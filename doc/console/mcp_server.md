---
sidebar_position: 4
sidebar_label: MCP Server
description: How to enable the PhoenixAI Anywhere MCP Server and connect an AI client, what the AI can do on each endpoint, and the security review checklist — permissions, routes, the command catalog, accounts and the audit record.
---

# PhoenixAI Anywhere MCP Server

This guide is for the people who run PhoenixAI Anywhere and want to connect an AI client to it:
a platform administrator who operates PhoenixAI clusters through the Anywhere Console, or a data
user who works in the Cluster Console. It answers two questions: how to enable the MCP Server
and connect a client, and what the AI can do once connected.

## Overview

PhoenixAI Anywhere exposes its consoles to AI clients over the Model Context Protocol (MCP).
Any client that speaks MCP over HTTP with OAuth 2.1 sign-in works: Claude Code, Claude Desktop,
Cursor, claude.ai, and others. The client signs in through the console in your browser, you
approve it once, and from then on it calls the console on your behalf with a token of its own.

There are two endpoints, and each carries a different identity:

| Endpoint | Path | Signs in as | What the AI acts as |
|---|---|---|---|
| Anywhere Console endpoint | `<publicURL>/mcp/anywhere` | An Anywhere Console account (admin or viewer) | Always the **viewer** role, even when an admin approved it |
| Cluster Console endpoint, one per cluster | `<publicURL>/mcp/clusters/<namespace>/<cluster>` | Your own PhoenixAI Database login for that cluster | **You**: every statement runs as your PhoenixAI Database user, and its privileges are the limit |

**Posture.** Both endpoints are read-oriented. On the Anywhere Console endpoint, the only
actions that change anything are creating or deleting a support bundle and running an exec
preset (a diagnostic command an administrator defined, run inside a pod). The AI never changes a
cluster's configuration, scales it, or runs free-form SQL under the console's own administrative
identity. On the Cluster Console endpoint, the AI runs read-only SQL by default; it can run
statements that change data or schema only if you grant the `sql:write` permission at the
consent screen, and even then only what your PhoenixAI Database user may run.

**Audit.** Every tool call and every sign-in event is recorded in an audit file on the console's
data volume (see [Audit log](#audit-log)).

## Prerequisites

- PhoenixAI Anywhere installed through the Helm chart, reachable from your browser (to sign in)
  and from the machine the AI client runs on (to call tools).
- An account to approve the client with:
  - Anywhere Console endpoint: any Anywhere Console account. A viewer account is enough, since
    the AI is limited to the viewer role whoever approves it.
  - Cluster Console endpoint: a PhoenixAI Database user on that cluster. A read-only user is
    enough for troubleshooting. If an administrator is creating one for you, PhoenixAI Database
    keeps SELECT on tables, views and materialized views as three separate grants:

    ```sql
    CREATE USER '<name>'@'%' IDENTIFIED BY '<password>';
    GRANT SELECT ON ALL TABLES IN ALL DATABASES TO USER '<name>'@'%';
    GRANT SELECT ON ALL VIEWS IN ALL DATABASES TO USER '<name>'@'%';
    GRANT SELECT ON ALL MATERIALIZED VIEWS IN ALL DATABASES TO USER '<name>'@'%';
    ```

- An MCP client. Claude Code is used in the examples; the JSON form for other clients is below.
- Optional: query history enabled (for the query history tools) and Prometheus configured (for
  the metrics tools). See [Dependencies](#dependencies).

## Enable the MCP Server

MCP access is off by default. Nothing MCP-related exists until `mcp.enabled` is `true`: the
endpoints answer HTTP 404, and the MCP access page does not appear in either console.

Set the values in your Helm values file, then `helm upgrade` the release. The pod restarts with
the new configuration.

With the parent `kube-anywhere` chart (values prefixed with `anywhere.`):

```yaml
anywhere:
  enabled: true
  mcp:
    enabled: true
    publicURL: "https://anywhere.example.com"
```

With the standalone `anywhere-console` chart (no prefix):

```yaml
mcp:
  enabled: true
  publicURL: "https://anywhere.example.com"
```

| Key | Default | Meaning |
|---|---|---|
| `mcp.enabled` | `false` | Turns MCP access on. |
| `mcp.publicURL` | unset | The HTTPS address AI clients reach the console at, with no path (`https://anywhere.example.com`). It must be `https://`: AI clients refuse to sign in over plain http to any host but localhost (Claude Code stops with `Refusing to send credentials to non-https token endpoint`), so the console refuses to start on an `http://` address of any other host. Unset means clients can connect only through `kubectl port-forward`. |
| `mcp.accessTokenTTL` | `1h` | How long an access token lasts. The client refreshes it silently. |
| `mcp.refreshTokenTTL` | `720h` (30 days) | How long an unused sign-in stays valid. Each use renews it, so an active client never has to sign in again. Must not be shorter than `accessTokenTTL`. |

**Reachability.** The AI client must be able to open `publicURL`. Two ways:

- **Ingress or load balancer** terminating TLS in front of the console: set `publicURL` to that
  address. If the certificate comes from a private CA, the client must trust it; for Claude
  Code, export `NODE_EXTRA_CA_CERTS=/path/to/ca.pem` in the shell you start it from.
- **Port-forward** from the machine running the client:

  ```bash
  kubectl -n <namespace> port-forward svc/kube-anywhere-console 8090:8090
  ```

  Then use `http://localhost:8090` as the address. A loopback address works without setting
  `publicURL` at all. A client is bound to the address it signed in through, so switching
  between the Ingress address and a port-forward needs one more sign-in.

## Connect a client

The easiest path is the console's own **MCP access** page (the last sidebar item at `/mcp-access`
in the Anywhere Console; the first item of the user menu at `/cluster-console/mcp-access` in the
Cluster Console).
It prints the exact commands for the endpoint you are signed in to, with the right address
filled in, and lists your authorizations.

### Claude Code

1. Add the server. For the Anywhere Console endpoint:

   ```bash
   claude mcp add --transport http -s user phoenixai-anywhere https://anywhere.example.com/mcp/anywhere
   ```

   For a cluster's Cluster Console endpoint:

   ```bash
   claude mcp add --transport http -s user phoenixai-<cluster> https://anywhere.example.com/mcp/clusters/<namespace>/<cluster>
   ```

   `-s user` keeps the server across all your projects; `-s local` keeps it in the current one.
   The server name (`phoenixai-anywhere`, `phoenixai-<cluster>`) is yours to choose.

2. Sign in:

   ```bash
   claude mcp login phoenixai-anywhere
   ```

   This opens the console's consent page in your browser. On a machine without a browser, add
   `--no-browser` to print the address and open it elsewhere. If you skip this step, the first
   tool call opens the same page.

3. On the consent page, sign in to the console if you are not already (Anywhere Console account
   for the Anywhere endpoint; the cluster's PhoenixAI Database login for a cluster endpoint),
   review the permissions, and click **Approve**. The browser returns to the client, and the
   client is connected.

4. Check with `claude mcp list`, or in a Claude Code session with `/mcp`.

To stop using it, open `/mcp` in a Claude Code session, pick the server and choose **Clear
authentication** (`claude mcp logout phoenixai-anywhere` does the same from a shell). **Reconnect**
is not a sign-out: it reopens the connection with the sign-in the client already holds. The
authorization can also be ended from the console, with **Revoke** on the **MCP access** page.

### Other clients

Clients that take a configuration file (Claude Desktop, Cursor, and others) use the generic
shape below; where exactly it goes is each client's own documentation. The client discovers the
OAuth sign-in on its own, registers itself, and opens the consent page the first time it
connects.

```json
{
  "mcpServers": {
    "phoenixai-anywhere": {
      "type": "http",
      "url": "https://anywhere.example.com/mcp/anywhere"
    },
    "phoenixai-<cluster>": {
      "type": "http",
      "url": "https://anywhere.example.com/mcp/clusters/<namespace>/<cluster>"
    }
  }
}
```

### The consent screen

The page shows which client is asking, which console or cluster it wants, and which account it
will act as. The permissions are:

| Permission | Endpoint | Granted |
|---|---|---|
| Read with the viewer role (`anywhere:viewer`) | Anywhere Console | Always; cannot be unchecked |
| Read-only SQL (`sql:read`) | Cluster Console | Always; cannot be unchecked |
| Any SQL statement (`sql:write`) | Cluster Console | Only if you tick it; a confirmation dialog explains it lets the client run any statement your user may run, DDL, DML and GRANT included |

Whatever the client asked for, only what you tick is granted: a client that requests `sql:write`
gets it only when you check the box. **Deny** sends the client an error and grants nothing.

If you are signed in to a different cluster's Cluster Console, the page says so and offers to
sign in to the requested cluster; the browser holds one Cluster Console session at a time, so
that ends the other one.

### Seeing and revoking authorizations

The MCP access page lists **My authorizations**: client, permissions, when it was authorized and
last used, when the sign-in expires, and a status. An administrator additionally sees **All
authorizations** across every user. Every row but a revoked one carries a **Revoke** button; the
client's next request then fails and it has to sign in again.

| Status | What it means | What to do |
|---|---|---|
| Active | Working: the client can connect and its sign-in is current. | Nothing, or revoke it. |
| Needs sign-in | Cluster Console authorizations only. The database password is held in the console's memory, never on disk, and it is gone: an unclean restart lost it, or the database refused it after a password change or a dropped user. A clean restart such as `helm upgrade` keeps it. | The owner runs `claude mcp login <name>` and approves again. That creates a new authorization and ends this one as replaced. An administrator can only revoke it. |
| Sign-in expired | The client went unused for the sign-in's lifetime (`mcp.refreshTokenTTL`, 30 days by default) and its sign-in ran out. | The owner authorizes the client again, which creates a new authorization; or revoke this one. |
| Revoked | Ended, with the reason: by its owner, by an administrator, by the client, refresh-token reuse detected, the database password rejected, its cluster deleted, or replaced when the client signed in again. It cannot be undone. | Nothing. Authorizing again creates a new one. |

Authorizing again never revives a row; it always adds a new one. Ended authorizations stay visible
for 30 days. An administrator can end access but never grant or restore it: an authorization exists
only because its owner approved it in their own browser.

## Capabilities

### Anywhere Console endpoint: tools

All tools take the cluster's `namespace` and `cluster` (from `list_clusters`) unless noted. All
are read-only except the three marked **changes state**. Every result is a JSON object; errors
come back as tool errors with the same message the console would show.

#### Cluster inventory

| Tool | What it does |
|---|---|
| `list_clusters` | Every cluster the console operates: phase, type, version, warehouse count, license summary. Also returns the console's clock (`serverTime`), which the AI uses to build time windows. No parameters. |
| `get_cluster` | One cluster's overview: phase and reason, FE connection, per-component node counts, license, warehouses and their CN groups. |
| `run_health_checks` | The console's health checks on a cluster or one warehouse, with severity and rule id per finding. |
| `get_license` | The PhoenixAI Database licenses the FE reports, with expiry and an expiring-soon flag. |
| `get_resource` | One Kubernetes object of the cluster as a credential-masked JSON manifest, optionally with its recent Events. Served kinds: PhoenixAICluster, PhoenixAIWarehouse, StatefulSet, Deployment, Service, ConfigMap, Pod, PersistentVolumeClaim, PodDisruptionBudget, HorizontalPodAutoscaler. Secrets are refused. |
| `get_component_config` | The rendered `fe.conf` or `cn.conf` a component runs with (per warehouse and CN group for CN), credentials masked. |

#### Pods, logs and events

| Tool | What it does |
|---|---|
| `list_pods` | Every pod of the cluster, its warehouses and CN groups: phase, ready status, restarts, reason, last termination (reason, exit code, time), node. Filter by component or warehouse. |
| `get_pod_logs` | A container's stdout/stderr (like `kubectl logs`), newest lines first, with `previous` for the crashed instance. Credentials masked. |
| `list_log_files` | The log files in an FE or CN pod's log directory with sizes and times. |
| `read_log_file` | One log file's tail (32 KiB by default, up to 512 KiB) or the lines matching up to 8 search terms. Search terms that name a credential are refused; lines come back masked. |
| `search_audit_log` | The PhoenixAI Database audit log (`fe.audit.log`): one line per statement with user, state, time, scanned rows and the SQL. Requires a start time. Searches every FE at once unless a pod is named. |

**Metrics** (need Prometheus configured; see [Dependencies](#dependencies))

| Tool | What it does |
|---|---|
| `list_metric_templates` | The system monitoring charts the console can evaluate, with units and how to read them. |
| `query_metrics` | One chart over a time window of at most 30 days, about 60 points by default (`step` sets the resolution). Series longer than 200 points are downsampled. |

**Query history and profiles** (history tools need query history enabled; see [Dependencies](#dependencies))

| Tool | What it does |
|---|---|
| `list_query_history` | The queries the console collected, newest first, filterable by time, user, warehouse, state and duration. Up to 100 per page. An empty list says why (`emptyReason`). |
| `get_query_detail` | One collected query: full SQL, plan, metrics, and whether a profile exists. |
| `get_query_profile` | A query's runtime profile. With `analyzed: true` the operator tree with each operator's time, rows and memory, laid out by whichever FE still holds the profile (every FE is asked). Without it, the raw text, from query history when it kept one. Paged by bytes, 48 KiB per page at most. Does not need query history for profiles an FE still holds. |

#### Commands and configuration

| Tool | What it does |
|---|---|
| `list_commands` | The read-only SQL commands that can run on a cluster: the built-in catalog plus the custom commands an administrator created. |
| `run_command` | Run one command from that list by name, under the console's own administrative identity, and return the result table. Only catalog names are accepted, never SQL text; a command with `params` takes its parameters by name. A result of at most 1000 rows that fits one result comes back as rows; a larger one comes back rendered as text (`content`, one field per line), its first page (`maxBytes`, 32 KiB by default, at most 48 KiB) with an `outputId` — page on with `read_command_output`. |
| `read_command_output` | The rest of a `run_command` result that did not fit one result: the page from `offset` of the rendering `outputId` names, at most `maxBytes`. Page on from `nextOffset` while `truncated` is true. Outputs are kept for 15 minutes in the console process, only for the grant that ran the command; an unknown or expired id is not found — run the command again. |

#### Support bundles

| Tool | What it does |
|---|---|
| `list_support_bundles` | A cluster's bundles with status, progress, size and who created them. |
| `get_support_bundle` | One bundle's status and progress. |
| `get_support_bundle_options` | Everything a bundle request may ask for on this cluster: categories, pods, log types, commands, and ready-made scenarios (`cn-crash`, `query-trace`, `high-load-sql`, `fe-lock`). |
| `estimate_support_bundle` | Size and collection time of a bundle before creating it (logs only; uncompressed bytes). |
| `create_support_bundle` | **Changes state.** Start collecting a bundle. One bundle at a time across the whole console; collection runs in the background. Download and export stay in the console. |
| `delete_support_bundle` | **Changes state.** Delete a bundle (cancels one still collecting). Clients that honor the destructive hint ask you first. |

#### Exec presets

| Tool | What it does |
|---|---|
| `list_exec_presets` | The exec presets that can run in a cluster's pods: built-in diagnostics (jstack, process and socket listings, local status pages) plus custom presets an administrator created. |
| `run_exec_preset` | **Changes state.** Run one preset in a pod of its component and return stdout, stderr and the exit code. Custom presets run only when the console has pod exec enabled; built-in ones always. A stdout longer than one page (`maxBytes`, 32 KiB by default, at most 48 KiB) comes back as its first page with an `outputId`, `stdoutTotalBytes`, `nextOffset` and `truncated: true`; the rest is read with `read_exec_output`. Bytes that were not UTF-8 are replaced with U+FFFD before paging (`stdoutNotUTF8: true` says so). |
| `read_exec_output` | The rest of a `run_exec_preset` stdout that did not fit one result: the page from `offset` of the output `outputId` names, at most `maxBytes`. Page on from `nextOffset` while `truncated` is true. Outputs are kept for 15 minutes in the console process, only for the grant that ran the preset; an unknown or expired id is not found — run the preset again. |

### Cluster Console endpoint: tools

No namespace or cluster parameters: the endpoint is bound to one cluster. Every statement runs
as the PhoenixAI Database user who approved the client, on a dedicated session that ends with
the call, so `USE` and `SET` do not carry over; pass `catalogName`, `databaseName` and
`warehouse` instead.

| Tool | Needs | What it does |
|---|---|---|
| `get_cluster_info` | `sql:read` | Version, run mode, the user and its effective roles, the cluster's time zone, the warehouses the user can see, the granted permissions, and the console's clock. The AI is told to call it first. |
| `execute_sql_read_only` | `sql:read` | One read statement: `SELECT`, `SHOW`, `DESC`, `EXPLAIN`, `WITH … SELECT`, `HELP`, `ADMIN SHOW`, `ADMIN CHECK`, `ANALYZE PROFILE`. Refuses `INTO OUTFILE`, `SET`, transactions, and more than one statement. `EXPLAIN ANALYZE` is accepted but re-runs the query; the AI is instructed not to use it without your explicit agreement. |
| `execute_sql` | `sql:write` | One statement of any kind: DML, DDL, GRANT, ADMIN. Not listed to clients without `sql:write`. PhoenixAI Database RBAC decides whether it succeeds. |
| `get_query_profile` | `sql:read` | A query's profile read as your user, asking every FE, as on the Anywhere endpoint. Does not read query history. |

Both SQL tools accept `maxRows` (1–1000, default 200) and `timeoutSeconds` (1–300, default 60).
The statement is limited to 64 KiB. Results are the FE's own text, cell by cell, never masked.
The read-only check is a guardrail for the person who granted read access, not the security
boundary: that is your PhoenixAI Database privileges.

### Prompts

Prompts are troubleshooting playbooks you call up yourself in the client. In Claude Code they
appear as slash commands, `/mcp__<server>__<prompt>` (for example
`/mcp__phoenixai-anywhere__troubleshoot_slow_query`). A prompt is a fixed text with your
arguments filled in; it reads nothing and changes nothing by itself, and the tools the AI then
calls are audited as usual.

Anywhere Console endpoint (every prompt takes `namespace` and `cluster`):

| Prompt | Optional arguments | Walks through |
|---|---|---|
| `troubleshoot_slow_query` | `queryId`, `when` | Find the query in history, read its detail and profile, name the bottleneck operator, rule out cluster load and stale statistics. |
| `troubleshoot_pod_not_ready` | `pod` | Pod status and Events, previous-instance logs, log files, configuration, the FE/CN view, health checks. |
| `troubleshoot_cn_memory` | `pod`, `when` | What used a CN's memory and which limit was hit: Kubernetes OOM kill, refused allocation, or crash. |
| `troubleshoot_cluster_health` | `warehouse` | Why a cluster or warehouse is reconciling, failed or not scaling: CR status, PhoenixAI Database view, autoscaler. |
| `collect_support_bundle` | `symptom`, `when` | Choose categories, pods and window for a symptom, estimate, collect, report. |
| `troubleshoot_failing_loads` | `label` | Classify failing or slow loads from their errors, then check compaction, CN health and logs. |

Cluster Console endpoint (SQL-only variants, no cluster arguments):

| Prompt | Optional arguments | Walks through |
|---|---|---|
| `troubleshoot_slow_query` | `sql`, `queryId` | `SHOW PROFILELIST`, the analyzed profile, the raw profile, then `EXPLAIN`. |
| `troubleshoot_failing_loads` | `label`, `databaseName` | `information_schema.loads`, classified by error message. |

## Limits and operational notes

### Result size and truncation

- A tool result is at most 64 KiB. Logs keep the newest lines; metrics are downsampled to at
  most 200 points per series; profiles are paged; other results drop rows from the largest list
  and then shorten the longest text. A cut result carries `resultTruncated` so the AI knows to
  narrow its request.
- Profiles are paged by bytes with `offset`, `maxBytes` (at most 48 KiB) and `nextOffset`.
- `list_query_history` returns at most 100 records per page; `search_audit_log` at most 100
  entries; `run_command` at most 1000 rows; the SQL tools at most 1000 rows and 8 KiB per cell.
- Claude Code saves tool results above about 50,000 characters to a file and shows the model a
  preview. The endpoints declare a 100,000-character limit so that a full page of profile or log
  reaches the model as text.

### Tokens and sign-ins

- An access token lasts `accessTokenTTL` (1 hour by default); the client refreshes it on its own.
- A sign-in stays valid for `refreshTokenTTL` (30 days by default) of **inactivity**; each use
  renews it. An idle client past that has to sign in again.
- A refresh token presented twice is treated as stolen and the whole authorization is revoked
  (status "Revoked: a sign-in it had already used was presented again"). Sign in again.
- Cluster Console authorizations keep your password only in the console's memory (never on
  disk). After an unclean restart of the console the status shows **Re-authorize**, and the
  client's next call asks you to sign in again. A clean restart (rolling upgrade, `helm upgrade`)
  keeps it.
- If your password changes or your PhoenixAI Database user is dropped, the next call fails and
  the authorization is marked for re-authorization.
- If a cluster is deleted, its Cluster Console authorizations are revoked within an hour.

### Rate limits

The public discovery and registration endpoints are rate-limited per connecting address (120
and 20 requests per minute); the sign-in page is limited per registered client (60 per
minute). Over the limit the console answers HTTP 429 with `Retry-After`. Tool calls and token
refreshes are not rate-limited.

### Dependencies

| Capability | Needs | Otherwise |
|---|---|---|
| `list_query_history`, `get_query_detail`, raw profiles from history | `queryHistory.enabled: true` in the chart values **and** `enable_collect_query_detail_info = true` on the FE | The history tools return an empty list with `emptyReason` saying which switch is off |
| `list_metric_templates`, `query_metrics` | `dependencies.prometheus.enabled: true` with its `endpoint` | `query_metrics` fails with a message saying Prometheus is not configured |
| Custom exec presets in `run_exec_preset` | Pod exec enabled on the console | Built-in presets still run; custom ones are refused |

### Audit log

Every tool call (including refused and unknown ones) and every sign-in event (consent, denial,
token issue and refresh, revocation, reuse detection, lost credential, cluster removal) is one
JSON line in a file per UTC day on the console's data volume:

```text
/var/lib/phoenixai-anywhere/audit/mcp-<YYYY-MM-DD>.jsonl
```

Each line records who (account and role), through which client and authorization, what
(`action`, target, parameters with credentials removed and strings cut at 4 KiB), the outcome
and business code, duration, bytes returned, row count for tabular results, and the request id
that the console's own log carries for the same request. Files older than 90 days are deleted
daily. The console has no page for it.

An administrator reads it through the console's API, newest first:

```bash
curl -s -H "Authorization: Bearer <admin session token>" \
  "https://anywhere.example.com/api/v1/admin/mcp/audit-events?action=mcp.tool.&limit=100"
```

`from` / `to` (RFC3339) bound the window (the last 24 hours by default, 31 days at most), `limit`
is 1 to 500, `actor`, `clientName`, `namespace`, `cluster`, `via` and `outcome` match exactly and
`action` by prefix. While there is more to read the answer carries `nextCursor`; pass it back as
`cursor` for the next page, and stop when an answer has none (a page can be shorter than `limit`
and still have one).
Your SREs and support engineers can also take the files themselves.

The console image has no shell, so `kubectl exec … cat` and `kubectl cp` do not work. Read the
file from an ephemeral debug container that runs as the console's user and reaches its
filesystem through `/proc/1/root`:

```bash
cat > as-console.json <<'EOF'
{"securityContext":{"runAsUser":65532,"runAsGroup":65532,"runAsNonRoot":true}}
EOF
kubectl -n <namespace> debug kube-anywhere-console-0 --image=busybox:1.36 \
  --target=anywhere --profile=general --custom=as-console.json -c audit-reader -- sleep 600
kubectl -n <namespace> exec kube-anywhere-console-0 -c audit-reader -- \
  cat /proc/1/root/var/lib/phoenixai-anywhere/audit/mcp-2026-11-05.jsonl > mcp-2026-11-05.jsonl
jq -c 'select(.clientName=="Claude Code")' mcp-2026-11-05.jsonl
```

`--custom` needs a recent `kubectl` (the procedure was verified with 1.35). The debug container
exits by itself when `sleep` ends.

### Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `claude mcp login` ends with **Authentication timeout** and no browser page, or the page says the console does not recognize the client | The console no longer knows the client's registration: `publicURL` changed, the console was reinstalled on a fresh data volume, or the registration was cleaned up after 90 days without an authorization | `claude mcp logout <name>`, `claude mcp remove <name>`, then `claude mcp add` and `claude mcp login` again. Retrying the login alone does not help. |
| The client cannot reach the server at all | `publicURL` is not reachable from the client's machine, or TLS is from a private CA the client does not trust | Check the address in a browser from the same machine; set `NODE_EXTRA_CA_CERTS` for a private CA; or use `kubectl port-forward` with the localhost address. |
| The consent page asks you to sign in although you are signed in | The Anywhere endpoint needs an Anywhere Console session and a cluster endpoint needs a Cluster Console session **on that cluster**; the other console's session does not count | Sign in where the page points you; it returns to the consent page afterwards. |
| Tool error: the connection to the FE of the cluster failed, check that the cluster is running | The Cluster Console endpoint could not open a SQL connection to any FE | Check the cluster's phase and FE pods (in the console or with the Anywhere endpoint), then retry. |
| Tool error: no FE of the cluster holds this query's profile | The FE keeps profiles only for queries with `enable_profile` on or slower than `big_query_profile_threshold`, and only its most recent ones | Re-run the query with `enable_profile = true`, or read the raw profile from query history if the console kept it. |
| Tool error: "no FE answered with the profile", or "n of m FEs do not hold the profile and k could not answer … retry later" | At least one FE could not be asked (connection refused, HTTP error, or the 20-second search budget ran out) and the FEs that did answer do not hold the profile; the one that failed may be the holder | Check the FE pods, then retry; the message quotes the last failure. |
| `list_query_history` is empty with `emptyReason`, or the window reaches back before `collectingSince` | Collection is off in the console or on the FE, has not run yet, is failing (the reason is given), or nothing in the window met the keep rule (slower than 5 s by default, or failed). `collectingSince` is when this console process started collecting; queries before it are listed only if an earlier process kept them | Enable both switches (see [Dependencies](#dependencies)), widen the window, or ask for the query id directly. |
| A client that worked stops with "re-authorize" | The console restarted uncleanly and lost the in-memory password of a Cluster Console authorization, or the password was changed | Sign in again with `claude mcp login <name>`. |
| HTTP 429 during sign-in | Rate limit hit on discovery, registration or the sign-in page | Wait for the `Retry-After` interval (60 seconds). |

## Security model

| | Anywhere Console endpoint | Cluster Console endpoint |
|---|---|---|
| Who approves | Any Anywhere Console account (admin or viewer) | The cluster's PhoenixAI Database user |
| Identity the AI runs as | The viewer role, always, even when an admin approved it | Your PhoenixAI Database user, with your roles active |
| Reaches the cluster as | The console's own administrative identity, but only through the command catalog (the built-in read-only commands plus any an administrator added) and the exec preset catalog | A plain MySQL client with your credentials, one dedicated session per call |
| Permission boundary | The viewer role plus the command and preset catalogs | PhoenixAI Database RBAC |

What the AI can never do, on either endpoint:

- Act as an Anywhere Console admin: change accounts, configuration or custom commands, download
  or export a support bundle, or see other users' authorizations.
- Run free-form SQL under the console's administrative identity. On the Anywhere endpoint it
  can only run commands by name from the catalog; SQL text in a request is refused.
- Change a cluster's resources: it reads Kubernetes objects as masked manifests, and cannot
  create, edit or delete them. Secrets and CN group custom resources are not even readable.
- Run arbitrary shell in a pod. Only presets from the catalog run, and custom presets only when
  the console has pod exec enabled.
- Read your password or any object-storage credential: manifests, configuration files and log
  lines are masked before they reach the AI, log searches for credential terms are refused, and
  the audit file strips credential-named parameters.
- Use a console session token, or use an MCP token on the console's REST API: the two are not
  interchangeable, and a token for one endpoint is refused by the other.
- Carry state between SQL calls: every statement runs on its own session, so `SET`, `USE` and
  transactions are refused and nothing persists.
- Exceed what you approved: a client that asked for `sql:write` gets it only if you ticked the
  box, and you can revoke any authorization at any time from the MCP access page.

Two facts to be aware of on the Cluster Console endpoint, inherited from PhoenixAI Database
itself: on PhoenixAI Database 4.1.6-ee, a non-root user can read other users' query profiles
(including their SQL text) through `get_query_profile` and `ANALYZE PROFILE`, and newer versions
may refuse this; and
`get_query_profile` reads the raw profile over the FE's HTTP port inside the cluster network
without TLS, sending your password as HTTP basic authentication. Anyone who can capture traffic
on the cluster network could see it.

## Security review checklist

This chapter is for a security team deciding whether to enable MCP access. Each section answers
one question a review asks and states where the answer is enforced; it does not repeat the
narrative above. Everything here describes the console as shipped; where a behavior depends on a
setting, the setting is named.

### Nothing new is granted to the console

The two MCP endpoints are routes of the same process that serves the consoles: the same pod, the
same ServiceAccount, the same configuration file. Setting `mcp.enabled: true` adds no Kubernetes
permission, opens no new connection to any upstream, and makes no outbound call anywhere. The
console never connects to an LLM or to any vendor service; the only new traffic is inbound, from
the AI client to the console.

The console's Kubernetes permissions are the four rules below, rendered by the chart as a
ClusterRole when the operator runs in global mode and as one Role per namespace in
`watchNamespaces` otherwise. There is no `rbac.create` switch: the console cannot function
without them, and it needs nothing else.

| Resource | Verbs | Why |
|---|---|---|
| `secrets` | `get` | Reads the one Secret a cluster's custom resource names for its root password, to open the console's own SQL connection to that cluster. Secrets are never listed, and `get_resource` refuses the kind. |
| `pods/exec` | `create` | Runs an exec preset, lists and reads log files (`list_log_files`, `read_log_file`), searches the audit log, and collects a support bundle. The target pod is checked against the operator's pod tree, the container is the component's, and the command is the catalog entry, never text from the request. One exec runs per pod at a time, with a 60-second limit. |
| `pods/log` | `get` | `get_pod_logs`: one pod, one container, a bounded number of lines and bytes, no follow. |
| `events` | `get`, `list` | `get_resource` with Events: filtered to the object's UID by the API server, with a limit. |

The console opens no watches and runs no informers; every Kubernetes read is a request a person
or an AI client triggered. Cluster topology comes from the PhoenixAI operator's gRPC API, which
answers from its own cache.

The other connections the console holds, none of which MCP changes:

| To | Protocol | Identity | What for |
|---|---|---|---|
| PhoenixAI operator | gRPC, `operatorApiAddrs` | none (the API has no authentication of its own and is reachable only inside the cluster network) | clusters, warehouses, CN groups, pods, manifests |
| FE | MySQL protocol, port 9030, TLS when the FE offers it | the cluster's root password from its Secret (Anywhere Console endpoint); the approving user's own login (Cluster Console endpoint) | catalog commands as root; free-form SQL only as the user |
| FE | HTTP, port 8030, inside the cluster network, no TLS | the same identity, as HTTP basic authentication | licenses, query detail, query profile |
| CN | HTTP, ports 8040 and 8060, from inside the pod through exec | none | the `cn-*` exec presets (`curl` to `127.0.0.1`); the support bundle's CN memory diagnostics reach port 8040 over the pod IP |
| Prometheus | HTTP, `dependencies.prometheus.endpoint` | as configured | `query_metrics`, pod utilization; optional |
| Object storage | S3, Azure or GCS API | as configured | support bundles and query history texts; optional |

### Routes that exist once MCP is enabled

`mcp.enabled: true` registers the routes below; with it `false`, every one of them answers
HTTP 404 and the consoles show no MCP entry.

| Route | Who may call it | What it does |
|---|---|---|
| `GET /.well-known/oauth-authorization-server`, `GET /.well-known/oauth-protected-resource/mcp/anywhere`, `GET /.well-known/oauth-protected-resource/mcp/clusters/{ns}/{cluster}` | anyone | OAuth discovery metadata (RFC 8414, RFC 9728): addresses and supported scopes, no secrets |
| `POST /oauth/register` | anyone | Dynamic client registration (RFC 7591): a client names itself and its redirect URIs. Rate-limited to 20 per minute per address, at most 10,000 registrations kept, unused ones removed after 10 minutes |
| `GET /oauth/authorize` | anyone, but it only proceeds for a signed-in console session | Starts a consent; the person signs in to the console and approves. Errors are shown, never redirected. 60 per minute per registered client |
| `POST /oauth/token`, `POST /oauth/revoke` | the holder of an authorization code or a refresh token | Issues, refreshes and revokes tokens. Nothing is issued without a prior consent |
| `/api/v1/auth/mcp/authorize-requests/{rid}`, `/api/v1/auth/mcp/consent`, `/api/v1/auth/mcp/grants`, `/api/v1/auth/mcp/setup` | a signed-in console session (cookie) | The consent page and the MCP access page: what the client asked for, approve or deny, one's own authorizations |
| `/api/v1/admin/mcp/grants` | an admin console session | Everyone's authorizations; revoke any |
| `GET /api/v1/admin/mcp/audit-events` | an admin console session | The MCP audit trail, newest first, filtered and paged (see "Audit log") |
| `POST /mcp/anywhere`, `POST /mcp/clusters/{ns}/{cluster}` | the holder of an MCP access token for that endpoint | The MCP endpoints. `GET` and `DELETE` answer 405; a token for the other endpoint is refused |

What a peer on the network can do without a console login: read the metadata, register a
client, and run into the rate limits. What it cannot do: obtain a token, call a tool, or see an
authorization, because every token is issued only after a person signed in to the console and
clicked Approve. An MCP token is refused by every REST route, and a console session is refused by
the MCP endpoints.

### Which console code a tool runs

A tool is a thin wrapper over the service method behind a REST route, in the same process; there
is no HTTP hop and no second implementation of any rule. The permission, the masking and the
bounds a REST route applies are therefore the ones the tool applies. The table maps each tool to
the route a reviewer may already have assessed; `…` stands for
`/api/v1/admin/namespaces/{ns}/clusters/{cluster}`.

| Tool | Same code as |
|---|---|
| `list_clusters` | `GET /api/v1/admin/clusters` |
| `get_cluster` | `GET …/overview`, `GET …/warehouses` |
| `list_pods` | `GET …/pods` |
| `get_resource` | `GET /api/v1/admin/namespaces/{ns}/resources/{group}/{version}/{kind}/{name}` and `…/events` |
| `run_health_checks` | `GET …/inspections`, `GET …/warehouses/{name}/inspections` |
| `get_license` | `GET …/licenses`, `GET …/licenses/system-info` |
| `get_component_config` | `GET …/components/{component}/config` |
| `get_pod_logs` | `GET …/pods/{pod}/logs` |
| `list_log_files`, `read_log_file` | `GET …/pods/{pod}/log-files`, `GET …/pods/{pod}/log-files/{file}` |
| `search_audit_log` | `POST …/audit-logs/search` |
| `list_metric_templates`, `query_metrics` | `GET …/monitoring/cluster-templates`, `GET …/monitoring/instance-templates`, `POST …/monitoring/query` |
| `list_query_history`, `get_query_detail` | `GET …/query-history/records`, `GET …/query-history/records/{queryId}`, `…/texts`, `GET …/query-history/status` |
| `get_query_profile` | `GET …/query-history/records/{queryId}/texts` for a stored profile; otherwise a read from the FEs' HTTP profile API that has no REST route of its own |
| `list_commands`, `run_command` | `GET …/commands`, `POST …/commands/{name}/execute` |
| `list_support_bundles`, `get_support_bundle`, `get_support_bundle_options`, `estimate_support_bundle`, `create_support_bundle`, `delete_support_bundle` | `GET …/support/bundles`, `GET …/support/bundles/{id}`, `GET …/support/bundle-options`, `POST …/support/bundles/estimate`, `POST …/support/bundles`, `DELETE …/support/bundles/{id}` |
| `list_exec_presets`, `run_exec_preset` | `GET …/exec-presets`, `POST …/pods/{pod}/exec-presets/{name}/execute` |

The routes that need the admin role have no tool, and the AI's viewer role would be refused on
them anyway: creating, editing or deleting a command or an exec preset, running an arbitrary
command in a pod, uploading a license, downloading or exporting a support bundle, and the
all-users authorization list.

### The command catalog is a catalog, not a fixed list

Only entries of the catalog ever reach a cluster under the console's administrative identity:
`run_command` and `run_exec_preset` take a name, and a request that carries SQL or a shell command
is refused. What the catalog holds on a given deployment:

- The **built-in** entries ship with the product and cannot be edited: 33 read-only SQL commands
  and 20 exec presets, listed in full in the [Command catalog](#appendix-command-catalog)
  appendix. Every built-in SQL command is a `SHOW`, an `ADMIN SHOW` or a `SELECT` from
  `information_schema`; every built-in preset is a listing, a `jstack`, or a `curl` to the
  component's own status page on `127.0.0.1`.
- An **administrator** can add custom SQL commands and, when `enablePodExec` is on, custom exec
  presets, from the Diagnostics tab with an admin console session. A custom SQL command must be a
  single `SELECT` or `SHOW` statement without comments and without `INTO`, checked when it is
  saved; that check is a guardrail on what an administrator writes, not a boundary against one.
  Custom entries show `builtin: false` in `list_commands` and `list_exec_presets`, and run under
  the same identity as the built-ins.
- **Through MCP** nothing can be added or changed: the AI runs what the catalog holds at the
  moment of the call, and the administrator's additions are the administrator's decision.

There is no per-deployment allow or deny list for the built-ins in this version. A deployment
that wants the narrowest catalog keeps `enablePodExec` off, creates no custom entries, and keeps
the set of admin accounts small; what a cluster can actually run is what `list_commands` and
`list_exec_presets` return for it, or what the Diagnostics tab's **Browse** dialog lists.

### What the AI can see of your data

**Anywhere Console endpoint.** The AI sees the metadata of clusters, pods and warehouses,
configuration files and manifests with credentials masked, container and log file lines with
credentials masked, metrics, health findings, and the result tables of the catalog commands
(node, session, variable, job and statistics metadata, with the two configuration commands
masked by column). It sees **the SQL text of statements any user ran**: `show-processlist` and
`show-running-queries` carry the statements in flight, `search_audit_log` the statements the FE
logged, `list_query_history` and `get_query_detail` the collected ones, and a query profile names
its tables and predicates. It sees no table rows: no catalog command selects from user tables, and
the endpoint has no tool that takes SQL. On a cluster holding sensitive data, treat log, audit
log and query history access as access to query text, which can contain literal values.

**Cluster Console endpoint.** The AI runs SQL as the PhoenixAI Database user who approved it and
sees exactly what that user's privileges allow, with no masking: result cells are the FE's own
text. On PhoenixAI Database 4.1.6-ee, a non-root user can also read other users' query profiles,
SQL text included, through `get_query_profile` and `ANALYZE PROFILE`. For a sensitive cluster,
approve the client with a user created for it, grant that user only what the task needs, and do
not tick `sql:write`.

### Accounts, rotation and revocation

- **Use a dedicated viewer account for AI access.** Put it in `viewer.users` (or your own viewer
  Secret) under a name a reader recognizes in the audit file, for example `ai-support`. A viewer
  cannot be made an admin by anything the AI does, a viewer's password never opens the admin
  role, and every audit line and access log line names the account.
- **Rotation.** Edit the account's Secret; the console reads it at the next login, no restart.
  Rotating the password does not end the authorizations that account already approved: an
  authorization is tied to the account's name, not its password. To end them, revoke them on the
  MCP access page.
- **Removal.** Delete the account's key from its Secret. Every tool call under an authorization
  it approved is then refused at once with "the account that authorized this client no longer
  exists", because each call checks that the account still exists; no restart and no wait for a
  token to expire.
- **One client.** Revoke it on the MCP access page (the person's own, or an admin from **All
  authorizations**); its next request fails and it has to be approved again.
- **Everything.** Set `mcp.enabled: false` and upgrade the release: the routes disappear and no
  token is accepted. Authorizations stay in the database and resume if it is turned on again;
  revoke them first if that is not wanted.
- **The default account.** The chart ships `admin` / `admin` in `admin.users`. Replace it before
  the console is reachable (set `admin.users` or `admin.existingSecret`, or clear `users` to have
  a random password generated), and say so in the review: a reviewer reading the chart will find
  it.
- **Cluster Console endpoint.** The approving identity is a PhoenixAI Database user; its password
  is held only in the console's memory. Changing the password or dropping the user makes the
  client's next call fail and marks the authorization for re-authorization. Deleting the cluster
  revokes its authorizations within an hour.

### Audit record and SIEM forwarding

Each line of `/var/lib/phoenixai-anywhere/audit/mcp-<YYYY-MM-DD>.jsonl` is one JSON object with
these fields:

| Field | Meaning |
|---|---|
| `at` | time of the event, RFC 3339, UTC |
| `requestId` | the request id the console's own log carries for the same request |
| `actorKind`, `actor`, `role` | who acted: `admin` for an Anywhere Console account with its role (`viewer` through MCP), or the cluster's PhoenixAI Database user |
| `via` | `mcp` for a tool call, `session` for an action a person took on a console page (consent, revocation), `system` for the console's own cleanup |
| `clientName`, `grantId` | the AI client and the authorization it acted through |
| `action` | the tool name, a sign-in event (`oauth.consent`, `oauth.deny`, `oauth.token`, `oauth.refresh`, `oauth.revoke`, `oauth.reuse_detected`, `oauth.credential_lost`, `oauth.cluster_removed`, `oauth.superseded`), or `grant.revoke` for a revoke on the MCP access page |
| `namespace`, `cluster`, `target` | the cluster and the object acted on (a pod, a bundle id, a command name) |
| `params` | the tool's arguments after sanitizing: credential-named arguments removed, strings masked and cut at 4 KiB |
| `outcome`, `code`, `error` | `ok`, `error` or `denied`; the business code; the error text the client received |
| `durationMs`, `resultBytes`, `rowCount` | how long the call took, how much it returned, and the row count of a tabular result |
| `remoteAddr` | the address the request came from |

An illustrative line (one call, wrapped here for reading):

```json
{"at":"2026-11-05T09:52:10Z","requestId":"5f1c…","actorKind":"admin","actor":"ai-support",
 "role":"viewer","via":"mcp","clientName":"Claude Code","grantId":"wmVNYxa2…",
 "action":"run_command","namespace":"demo","cluster":"demo","target":"show-frontends",
 "params":{"name":"show-frontends"},"outcome":"ok","code":20000,"durationMs":41,
 "rowCount":3,"resultBytes":1480,"remoteAddr":"10.0.3.17:51844"}
```

The file is append-only JSON Lines, one file per UTC day, owned by the console's user with mode
0600, deleted after 90 days. An administrator can read it through
`GET /api/v1/admin/mcp/audit-events`; the console has no page for it. To feed
a SIEM, read the data volume with the log agent you already run, from a sidecar you add to the
console's StatefulSet or from the node, or copy the day's file as shown under
[Audit log](#audit-log). Independently of the file, the console's own log, which your log
pipeline already collects from the pod's stdout, carries one access line per MCP request with
`via=mcp`, the client name, the grant id and the tool name, so the request rate and the callers
are visible there without the file.

### Network path

Two connections exist, and both are inbound to the console:

1. **AI client to `publicURL`**, HTTPS terminated at your Ingress or load balancer, then plain
   HTTP to the console pod's port (8090 by default) inside the cluster. The client calls
   `/.well-known/*` and `/oauth/*` to sign in and `/mcp/*` to work. When the AI runs behind a
   gateway of yours, the gateway, or whatever host the MCP client process runs on, is what has to
   reach `publicURL`.
2. **The person's browser to the same `publicURL`**, once, to approve the client on the consent
   page; the browser then returns to the client's own redirect address (a loopback port for a
   local client, the client's own site for a hosted one).

The console connects to nothing on the client's side and to no address outside the cluster that
it did not already use before MCP was enabled. A request that carries an `Origin` header from a
site other than `publicURL` is refused, which blocks a web
page from driving the console through the user's browser (DNS rebinding); desktop, command-line
and server-hosted clients send no `Origin`. Without an Ingress, `kubectl port-forward` to the
console Service gives the same path over the Kubernetes API server's tunnel, with `localhost` as
the address.

## Appendix: command catalog

The built-in entries of the two catalogs as shipped, in the order the console lists them. Custom
entries an administrator adds appear beside them with `builtin: false`.

### Built-in SQL commands

All run as the cluster's root identity on one FE, read at most 10,000 rows (1,000 through
`run_command`), and return the FE's result as is, except the two configuration commands, whose
credential-named rows are masked in the `Value` / `VALUE` column.

| Name | Statement |
|---|---|
| `show-frontends` | `SHOW FRONTENDS;` |
| `show-compute-nodes` | `SHOW COMPUTE NODES;` |
| `show-processlist` | `SHOW PROCESSLIST;` |
| `show-running-queries` | `SHOW RUNNING QUERIES;` |
| `show-databases` | `SHOW DATABASES;` |
| `show-catalogs` | `SHOW CATALOGS;` |
| `show-variables` | `SHOW VARIABLES;` |
| `show-time-zone` | `SHOW GLOBAL VARIABLES LIKE '%time_zone%';` |
| `show-frontend-config` | `ADMIN SHOW FRONTEND CONFIG;` (credential values masked) |
| `show-resource-groups` | `SHOW RESOURCE GROUPS ALL;` |
| `show-loads` | `SELECT * FROM information_schema.loads ORDER BY CREATE_TIME DESC LIMIT 100;` |
| `show-routine-load` | `SELECT * FROM information_schema.routine_load_jobs;` |
| `show-warehouses` | `SHOW WAREHOUSES;` |
| `show-profilelist` | `SHOW PROFILELIST;` |
| `show-variables-changed` | `SHOW VERBOSE VARIABLES WHERE Is_changed = true;` |
| `show-proc-statistic` | `SHOW PROC '/statistic';` |
| `show-partitions-meta` | `SELECT * FROM information_schema.partitions_meta ORDER BY MAX_CS DESC LIMIT 500;` |
| `show-be-tablets` | `SELECT * FROM information_schema.be_tablets ORDER BY NUM_VERSION DESC LIMIT 500;` |
| `show-compactions` | `SELECT * FROM information_schema.be_cloud_native_compactions ORDER BY START_TIME DESC LIMIT 500;` |
| `show-be-configs` | `SELECT * FROM information_schema.be_configs;` (credential values masked) |
| `show-materialized-views` | `SELECT * FROM information_schema.materialized_views;` |
| `show-task-runs` | `SELECT * FROM information_schema.task_runs ORDER BY CREATE_TIME DESC LIMIT 100;` |
| `show-analyze-status` | `SELECT * FROM information_schema.analyze_status;` |
| `show-analyze-job` | `SHOW ANALYZE JOB;` |
| `show-stats-meta` | `SHOW STATS META;` |
| `show-histogram-meta` | `SHOW HISTOGRAM META;` |
| `show-plan-advisor` | `SHOW PLAN ADVISOR;` |
| `show-pipes` | `SELECT * FROM information_schema.pipes;` |
| `show-storage-volumes` | `SHOW STORAGE VOLUMES;` |
| `show-security-integrations` | `SHOW SECURITY INTEGRATIONS;` |
| `show-role-mappings` | `SHOW ROLE MAPPINGS;` |
| `show-automated-cluster-snapshot` | `ADMIN SHOW AUTOMATED CLUSTER SNAPSHOT;` |
| `show-cluster-snapshot-jobs` | `SELECT * FROM information_schema.cluster_snapshot_jobs ORDER BY JOB_ID DESC LIMIT 100;` |

### Built-in exec presets

Each runs as `bash -lc '<command>'` in the component's container of the chosen pod (the `fe`
container of an FE pod, the `cn` container of a CN pod of the cluster, a warehouse or a CN
group), with a 60-second limit and one run per pod at a time. The commands take no input from
the request. `<fe-pid>` stands for
`$(cat /opt/starrocks/fe/bin/fe.pid 2>/dev/null || pgrep -f StarRocksFE | head -1)`.

| Name | Component | Command |
|---|---|---|
| `jstack` | FE | `jstack <fe-pid>` |
| `jstack-locks` | FE | `jstack -l <fe-pid>` (pauses the FE for a few seconds on a large heap) |
| `fe-metrics` | FE | `curl -sS --fail-with-body -m 5 http://127.0.0.1:8030/metrics` |
| `fe-health` | FE | `curl -sS --fail-with-body -m 3 http://127.0.0.1:8030/api/health` |
| `fe-process` | FE | `ps -o pid,etime,rss,pcpu,args -C java` |
| `fe-profiles` | FE | lists the files under `<sys_log_dir>/proc_profile` (the directory resolved from `fe.conf`), newest first; a listing only |
| `fe-system-overview` | FE | `uptime; date -Is; df -h -x tmpfs -x overlay; free -m; cat /proc/loadavg` |
| `fe-tcp-counters` | FE | `grep -h '^Tcp' /proc/net/snmp /proc/net/netstat` |
| `fe-tcp-connections` | FE | counts the connections in `/proc/net/tcp` and `/proc/net/tcp6` by state (an `awk` one-liner) |
| `cn-metrics` | CN | `curl -sS --fail-with-body -m 5 http://127.0.0.1:8040/metrics` |
| `cn-health` | CN | `curl -sS --fail-with-body -m 3 http://127.0.0.1:8040/api/health` |
| `cn-mem-tracker` | CN | `curl -sS --fail-with-body -m 5 http://127.0.0.1:8040/mem_tracker` |
| `cn-memz` | CN | `curl -sS --fail-with-body -m 5 http://127.0.0.1:8040/memz` |
| `cn-datacache-stat` | CN | `curl -sS --fail-with-body -m 5 http://127.0.0.1:8040/api/datacache/stat` |
| `cn-pipeline-blocking-drivers` | CN | `curl -sS --fail-with-body -m 5 http://127.0.0.1:8040/api/pipeline_blocking_drivers/stat` |
| `cn-brpc-vars` | CN | `curl -sS --fail-with-body -m 5 http://127.0.0.1:8060/vars` |
| `cn-process` | CN | `ps -o pid,etime,rss,pcpu,args -C starrocks_be` |
| `cn-system-overview` | CN | `uptime; date -Is; df -h -x tmpfs -x overlay; free -m; cat /proc/loadavg` |
| `cn-tcp-counters` | CN | `grep -h '^Tcp' /proc/net/snmp /proc/net/netstat` |
| `cn-tcp-connections` | CN | counts the connections in `/proc/net/tcp` and `/proc/net/tcp6` by state (an `awk` one-liner) |

The ports are the components' defaults (`http_port` 8030, `be_http_port` 8040, `brpc_port`
8060); a cluster configured with other ports gets an HTTP error from the `curl` presets rather
than a different target.
