# Collect query history for Query insights

The Cluster Console's **Query insights** page lists the queries a cluster ran — their SQL, how long
they took, what they scanned, whether they failed, and for the slow ones the query profile that
explains where the time went. It is the page a query author opens to tune a query, and the page a
platform operator opens to find out what hit the cluster last night.

A new installation shows nothing there. Collection is **off by default on both sides**, so the
page stays empty until you enable two settings in two different places. The page itself names
whichever one is still missing, so if you have already turned something on and the list is still
empty, read the banner first — it is more specific than this guide.

This page assumes the console is installed and signed in, as in
[Install with Helm](../Deploy/install_with_helm.md).

## How the page gets its data

Three things have to be true for a query to appear with its profile. Knowing them explains every
banner and every empty list below.

1. **The coordinator (FE) records query details.** With the FE configuration
   `enable_collect_query_detail_info` on, each coordinator keeps the details of its finished
   queries in a short in-memory queue — about 30 seconds, then they are gone. Each coordinator
   keeps its own queue. With the configuration off, the default, the queue is empty and there is
   nothing to collect.
2. **Anywhere collects and keeps them.** With `queryHistory.enabled` on in Anywhere's Helm
   values, Anywhere reads every coordinator's queue every 10 seconds and persists what matches its
   policy: the query's row in the console's data volume, and the SQL, execution plan and profile
   texts in the object storage you configured at install. With the switch off, the default,
   Anywhere sends no background requests to any cluster at all.
3. **The database generated a profile for that query.** A profile is produced only for queries
   the database considers expensive enough, governed by the global variable
   `big_query_profile_threshold` — 30 seconds by default — or by `enable_profile`, which profiles
   everything. A query that finished below the threshold is kept in history but has no profile to
   show.

Settings 1 and 3 are PhoenixAI Database settings; setting 2 is a console setting. That split is
why the banner on the page says which side to go to.

## Turn it on

### Step 1 — Anywhere: enable collection

In the `kube-anywhere` chart's values, under the `anywhere` key:

```yaml
anywhere:
  queryHistory:
    enabled: true
```

Re-run the `helm upgrade --install` command from the install guide. The console pod restarts
with the new configuration.

### Step 2 — PhoenixAI Database: record query details on every coordinator

Make it permanent in the same values file, in the coordinator configuration block you already
wrote when you installed the cluster:

```yaml
phoenixai:
  phoenixAIFeSpec:
    config: |
      # ... your existing coordinator configuration ...
      enable_collect_query_detail_info = true
```

The same `helm upgrade --install` applies it. The coordinators restart one at a time with the new
configuration.

If you cannot restart the coordinators right now, the setting also takes effect at runtime. One
statement, from any client connected to the cluster as `root`, is enough: the coordinator that
receives it applies it and forwards it to every other coordinator that is up.

```bash
kubectl -n phoenixai exec kube-anywhere-fe-0 -- env MYSQL_PWD='<root-password>' \
  mysql -h127.0.0.1 -P9030 -uroot \
  -e 'ADMIN SET FRONTEND CONFIG ("enable_collect_query_detail_info" = "true");'
```

A runtime change is not written to `fe.conf` — on Kubernetes the coordinator never persists
runtime configuration changes — so it is gone when a coordinator restarts, and a coordinator that
was down when the statement ran never received it. Still add the line to the values file. A
coordinator that comes back without it silently stops contributing queries; see
"Check it" below for how to spot which one.

With both sides on, the warning banner clears the next time Anywhere asks the cluster about the
setting — within a few minutes — or at once when the first query details arrive from a
coordinator. The next slow or failed query then shows up in the list.

### Step 3 — decide which queries to keep

Anywhere does not keep every query. By default it keeps **every failed query** and every query
that took **5000 ms or longer**; faster, successful queries are read from the queue and dropped.
The page states the policy in force under the table ("Showing slow queries (≥ 5000 ms) and failed
queries only"), so an ordinary list that seems short is not missing data.

The bar is `queryHistory.slowQueryMs`, in milliseconds:

```yaml
anywhere:
  queryHistory:
    enabled: true
    slowQueryMs: 5000   # default; failed queries are always kept
```

Lower it when the queries you want to study are faster than that. `0` keeps every query, which is
fine for a proof of concept or a quiet cluster and unwise at high query rates: every kept query
costs about 1 KB in the data volume plus its texts in object storage, and at hundreds of queries
per second that grows without bound. There is no setting that keeps failed queries out.

### Step 4 — make sure slow queries carry a profile

Out of the box the database profiles only queries that run for **30 seconds or longer**:
`enable_profile` is off and `big_query_profile_threshold` is `30s`. With the default bar from
Step 3 that leaves a gap: a query that took between 5 and 30 seconds is kept in the list, but its
**Query profile** tab is empty, with a note naming the query's latency, the threshold that
excluded it, and a value to set — for example, for a 7-second query:

> no profile is stored for this query: its latency (7094ms) is below the current
> big_query_profile_threshold (30s), which does not profile queries this fast. To profile them,
> lower the threshold below that latency — e.g. SET GLOBAL big_query_profile_threshold = '7s';

Set the threshold to match the bar from Step 3, so that exactly the queries worth keeping are the
ones that get profiled:

```sql
SET GLOBAL big_query_profile_threshold = '5s';
```

This is a cluster-wide variable, so it is set once, from any client connected to the cluster as a
user allowed to set global variables. New sessions pick it up; a session that was already open
keeps the old value until it reconnects.

Leave `enable_profile` off. Turning it on globally profiles every query, including the fast ones
Anywhere throws away — the per-query overhead is not worth paying in production for records
nobody keeps. That, and a threshold of `0s` (which switches profiling off entirely), are the two
states the page flags with a second, dismissible banner above the list. The default threshold
does not raise the banner: the page reports the gap per record, as above, rather than for the
cluster.

Lowering `slowQueryMs` later means lowering the threshold too; the two answer different questions
("what is worth keeping" and "what is worth profiling") and nothing keeps them aligned for you.
The one value not to copy across is `0`: with `slowQueryMs: 0` every query is kept, but a
threshold of `0s` profiles none of them. Keep a positive threshold — the profiles you need are
still the slow queries' — and the page's own suggestion in that case is `30s`.

## Check it, rather than guessing

**On the page.** Open Query insights. The banner at the top, when present, names the side that is
still off and the exact command or setting to change. The note under the table states the
persist policy in force. Both come from a live probe of the cluster, not from a static default,
so what they say about this cluster is correct even when it differs from this guide.

**Through the API.** The same probe is exposed as a status endpoint, which is the fastest way to
see every part of the pipeline at once. It needs an admin session or a Cluster Console session;
with an admin session:

```bash
kubectl -n phoenixai port-forward svc/kube-anywhere-console 8090:8090

curl -s -c cookies.txt -X POST localhost:8090/api/v1/auth/admin/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"<password>"}'

curl -s -b cookies.txt \
  localhost:8090/api/v1/namespaces/phoenixai/clusters/kube-anywhere/query-history/status
```

Admin passwords live in the `kube-anywhere-console-admin` Secret, one key per username.

A working installation answers along these lines:

```json
{
  "code": 20000,
  "data": {
    "enabled": true,
    "collectEnabled": true,
    "lastCollectTime": "2026-10-28T09:46:40Z",
    "storage": "s3",
    "persistPolicy": { "slowQueryMs": 5000, "failedAlways": true },
    "profile": { "enabled": false, "bigQueryThreshold": "5s" },
    "disk": { "usedPercent": 12 },
    "fes": [
      { "name": "kube-anywhere-fe-0", "lastEventTime": 1793180799000000000 },
      { "name": "kube-anywhere-fe-1", "lastEventTime": 1793180799000000000 },
      { "name": "kube-anywhere-fe-2", "lastEventTime": 1793180799000000000 }
    ]
  }
}
```

Read it field by field:

- **`enabled`** — Anywhere's own switch (Step 1). `false` means the Helm value is off; nothing
  else in the response matters until it is on.
- **`collectEnabled`** — the coordinator configuration (Step 2), as the cluster reports it:
  `true`, `false`, or `null` when Anywhere could not ask the cluster yet. Anywhere asks through
  the cluster's service, so whichever coordinator takes the connection answers; it asks every few
  minutes, and treats records arriving from any coordinator as `true` without asking.
- **`hint`** — present only when something is off, and spells out what to change. This is the
  same text as the banner on the page.
- **`persistPolicy`** — Step 3 as configured.
- **`profile`** — the database's profile settings (Step 4). A `hint` inside it is the second
  banner's text.
- **`fes[]`** — one entry per coordinator Anywhere has collected from, with the time of the last
  record it read (`lastEventTime`, in nanoseconds since the epoch). This is the place to look when
  records seem to be missing from one node only. A coordinator Anywhere cannot reach is missing
  from the list or carries a `lastError`. A coordinator that is reachable but has the setting
  off looks healthier than it is: no error, but its `lastEventTime` stops moving while the
  others advance — that is what a coordinator that restarted without the `fe.conf` line looks
  like. A coordinator that simply received no connections looks the same, so before acting on a
  stale timestamp, confirm the setting on that pod:

  ```bash
  kubectl -n phoenixai exec kube-anywhere-fe-1 -- env MYSQL_PWD='<root-password>' \
    mysql -h127.0.0.1 -P9030 -uroot \
    -e "ADMIN SHOW FRONTEND CONFIG LIKE 'enable_collect_query_detail_info';"
  ```
- **`disk`** — how full the console's data volume is. See "What is kept, and for how long" below.

**In Health checks.** The `query-detail-collect-inconsistent` check reports, at info severity,
a cluster where one side is on and the other off: the coordinators doing the work of collecting
while Anywhere drops it, or the reverse. It reads the coordinator configuration as written in
the cluster definition (`fe.conf`), which is what survives a restart — not the runtime state. A
cluster enabled only with `ADMIN SET FRONTEND CONFIG` therefore still fails this check, and one
switched off at runtime still passes it. See [Health checks](../Troubleshoot/health_checks.md).

## What you will see, and what you will not

- **Who sees what.** Signed in as `root` or as a user holding an administrator role (`root`,
  `cluster_admin` or `db_admin`), the page shows every user's queries. Any other database user
  sees only their own.
- **Running queries** appear as `RUNNING` while they execute, regardless of how long they will
  take, and are replaced by their final record when they finish. A fast, successful query is then
  removed from the list by the persist policy; it was there only while it ran.
- **`UNKNOWN`** marks a query that was running when its coordinator restarted. The database never
  reported how it ended, so Anywhere says it does not know rather than calling it failed.
- **Failed queries** include queries that were killed. The error message column carries the
  database's reason.
- **Statements the console issued for itself** — schema browsing, privilege checks and the
  collector's own probes — are not listed, nor are a client's connection-management statements
  such as `USE` or `SET autocommit`. Statements from the console's SQL editor, saved commands and
  catalog management are listed, tagged in the SQL text with the page they came from. Statements
  from external clients carry no tag. The Audit logs sub-view, which reads the coordinator's audit
  log file and is shown to `root` only, still lists everything.
- **No profile on a kept query** — the note on its Query profile tab names the reason. For a
  query faster than `big_query_profile_threshold` that is the expected answer, not a fault; Step 4
  explains how to change it.

## What is kept, and for how long

- **Retention** is `queryHistory.retentionDays`, 7 days by default. Records older than that, and
  their texts in object storage, are removed every hour. `0` means the default, not keep-forever.
- **The data volume is protected** regardless of retention. When the console's data volume
  passes 85% usage, Anywhere trims the oldest records first until it is back under 70%, and
  deletes the texts those records referenced. The `disk` field of the status endpoint reports the
  current usage and the time of the last trim. A volume that stays above 85% with no history left
  to trim is being filled by something else — see
  [the console data volume](../Deploy/console_data_volume.md).
- **Collection can have gaps.** The coordinator's queue is in memory and holds about 30 seconds
  of queries; Anywhere reads it every 10 seconds. Two things lose queries, with no record that
  they ran. A coordinator restart — a crash, an out-of-memory kill, a rolling upgrade — empties
  its queue at once, so the queries that finished since Anywhere's last read (up to about 10
  seconds' worth) are gone even if the coordinator is back within seconds. And a coordinator
  that is up but that Anywhere cannot read for longer than the queue holds — a network
  partition, the console itself restarting — loses everything that finished in that window.
  The Audit logs sub-view (signed in as `root`) is the place to look for them: it reads the
  coordinator's audit log file, which has neither gap.

## Settings reference

Anywhere side, under `anywhere.queryHistory` in the Helm values:

| Setting | Default | What it does |
| --- | --- | --- |
| `enabled` | `false` | Collect query history at all. Off = no background requests to any cluster |
| `slowQueryMs` | `5000` | Keep successful queries at least this slow, in ms. Failed queries are always kept. `0` keeps every query |
| `retentionDays` | `7` | Days to keep records and their texts. `0` means the default; a negative value refuses to start |
| `collectInterval` | `10s` | How often each coordinator's queue is read. Raising it towards the queue's ~30 s risks losing queries; leave it alone |

PhoenixAI Database side:

| Setting | Where | What it does for this page |
| --- | --- | --- |
| `enable_collect_query_detail_info` | Coordinator configuration (`fe.conf`); at runtime, `ADMIN SET FRONTEND CONFIG`, applied to every coordinator that is up and lost on restart | Makes the coordinator record query details at all. Off by default |
| `big_query_profile_threshold` | Global variable (`SET GLOBAL`) | Profiles queries at least this slow. Default `30s`; `0s` profiles none. Match it to `slowQueryMs` |
| `enable_profile` | Global variable (`SET GLOBAL`) | Profiles every query. Leave it off in production |

The meaning of the database settings beyond this page — what a profile contains, what
`ADMIN SET FRONTEND CONFIG` accepts — is in the PhoenixAI Database reference, which is the
authority on them.
