---
sidebar_position: 1
sidebar_label: Overview
description: What the PhoenixAI Anywhere console does, who signs in to each of its two consoles, and where each user goes.
---

# PhoenixAI Anywhere Console — UI guide

A high-level tour of the Anywhere web console: what it does, who signs in, and where each user
goes. What every page shows is on [Anywhere Console pages](./anywhere_console.md) and
[Cluster Console pages](./cluster_console.md).

## What the console does

PhoenixAI Anywhere is the self-managed web console for the PhoenixAI Database clusters the
PhoenixAI operator runs on Kubernetes. It observes them, and in the Cluster Console it runs SQL and
creates, edits and drops external catalogs — there always as the database user who signed in, and
never beyond that user's own privileges. **It does not
deploy, configure, scale or upgrade a cluster** — that is the operator's job, driven by the cluster
resource and the Helm values behind it.

Only shared-data ("elastic") clusters are supported. A shared-nothing ("classic") cluster may
still be listed with its type reported, but feature pages do not operate on it.

## The two kinds of users

The console is two consoles side by side, each with its own sign-in and its own account model.

### Anywhere Console

The platform operator's view. Covers every cluster the installation can see, plus the
install-level pages.

| Area | What you get |
| --- | --- |
| **Insight** | Cluster inventory, node and pod topology with each object's manifest, and CPU / memory / disk monitoring |
| **Troubleshooting** | Automated health checks across every cluster, recent Kubernetes events and live pod resource use, and saved diagnostic commands — read-only SQL, and shell commands such as `jstack` run inside a pod |
| **Support** | Support bundles — a scenario-driven collector that packages manifests, configs, logs, SQL output and diagnostics for support |
| **License** | Licenses registered on each cluster, effective-license rules, expiry and capacity tracking, license registration |
| **Metering** | CCU usage per cluster and per day, metering periods, and a full auditable record set with downloadable raw records |

- **Admin accounts live in a Kubernetes Secret**, managed with `kubectl` or Helm at install time.
  Several admin accounts may exist; they are added, removed and rotated by editing that Secret.
- Admins are not database users and need no database credential. For cluster SQL, Anywhere
  resolves the cluster's own database `root` identity automatically — no address or password is
  ever configurable in the console.
- In this release all admins are equivalent: any successful admin sign-in has full access to
  every admin page.

### Cluster Console

The view for the people who query one cluster — analysts and data engineers — bound to the single
cluster the session signed in to.

| Tab | What you get |
| --- | --- |
| **SQL editor** | Writing and running statements, with scripts saved per user and kept on the server |
| **Data catalog** | Browsing catalogs, databases, tables and their DDL, and creating, changing and dropping external catalogs |
| **Query insights** | What has already run — query history, profiling, and audit-log search |
| **System monitoring** | This cluster's own monitoring |

- **Accounts are PhoenixAI database users**, defined *inside each individual
  cluster*. Anywhere holds no user store for them — no create, delete or password reset; they
  are managed in the cluster with SQL (`CREATE USER`, `GRANT`, …).
- Sign-in selects a cluster, then takes that cluster's database username and password. They are
  checked against the cluster itself, and a rejected credential and an unreachable cluster are
  reported as different errors.
- The session is bound to that one cluster and passes the credentials through on every query, so
  **what a user can see is decided entirely by the cluster's own SQL privileges**, not by Anywhere.
- Accounts are per-cluster: the same username in two clusters is two unrelated accounts with
  independent passwords. That is why the sign-in form asks for the cluster first.
- `root` here is PhoenixAI Database's built-in superuser, which is a different thing from an
  Anywhere Console admin: the two account models share nothing, and signing in as one says nothing
  about the other. Any database user that can connect can sign in, but `root` is not merely a
  convenient example: **the Audit logs tab is visible only to `root`**, as
  [Cluster Console pages](./cluster_console.md) describes under Query insights.

## Where each user goes

Both consoles are served by the same installation, on the same host and port, distinguished by
path.

### Anywhere Console paths

| Page | Path |
| --- | --- |
| Sign in | `/login` |
| Clusters (landing page; `/` redirects here) | `/clusters` — table view at `?layout=table` |
| Cluster detail | `/clusters/{namespace}/{name}` — tabs at `?tab=` |
| Warehouse detail | `/clusters/{namespace}/{name}/warehouses/{warehouse}` |
| Usage & Metering | `/usage` — tabs at `?tab=` |
| License | `/license` |
| Health checks | `/health-checks` |
| Support | `/support` |
| Create support bundle | `/support/create` |

The sidebar carries four destinations — Clusters, Usage & Metering, Health checks, Support — and
can be collapsed to icons. License has no sidebar entry: reach it from a cluster's License tab,
or by URL. Below the destinations sit a **Help document** link and the signed-in user's menu,
which holds a **Theme** selector (Light / Dark / System), **Sign out**, and the running version.

### Cluster Console paths

| Page | Path |
| --- | --- |
| Sign in | `/cluster-console/login` |
| SQL editor | `/cluster-console/sql` |
| Data catalog | `/cluster-console/catalog` |
| Databases in a catalog | `/cluster-console/catalog/{catalog}` |
| Database detail | `/cluster-console/catalog/{catalog}/{database}` — tabs at `?view=`, job kind at `?task=` |
| Table detail | `/cluster-console/catalog/{catalog}/{database}/tables/{table}` — tabs at `?tab=` |
| Query insights | `/cluster-console/query-insights` — audit sub-tab at `?view=audit` |
| Query detail | `/cluster-console/query-insights/{queryId}` |
| System monitoring | `/cluster-console/monitoring` |

Cluster Console URLs never name the cluster — the session supplies it. That is why the paths are
the same for every cluster, and why switching clusters means signing in again. The signed-in
cluster is shown in the header (`phoenixai/kube-anywhere` in the screenshots on
[Cluster Console pages](./cluster_console.md)), beside the four destinations and the user menu.

Pages that render times take a display timezone from the UI and put it in the URL (`?tz=UTC`), so
a link reproduces what the sender was looking at.

**Finding the other console.** Both paths render the same sign-in page, which carries two tabs —
**Platform administrator** and **Database user** — so neither audience has to be told a URL: the
path you arrive on simply preselects its tab. There is also a hand-off from a cluster's detail
page in the Anywhere Console (**Open cluster**), which opens that page on the **Database user** tab
with the cluster preselected; that is context only, credentials are still required.

The cluster picker is preselected from `?cluster=ns/name` (the admin hand-off, or a bounce
carrying an expired session's cluster) or, failing that, from the last cluster signed into from
that browser. It is not preselected just because the installation has only one cluster.

## Conventions worth knowing

- **Time zones.** Usage & Metering and License render in UTC and say so. Every other page renders
  in browser-local time with no zone label. Values the cluster itself formatted are shown
  verbatim and annotated with the cluster's own time zone (for example "times in cluster
  time_zone: UTC" above the catalog tables), because they carry no zone of their own. Monitoring
  and Query insights offer a display-timezone selector, which affects display only and defaults to
  UTC; charts state the zone they are drawn in.
- **Themes.** Both consoles carry a Light / Dark / System selector — in the user menu once signed
  in, and as an icon on each sign-in page.
- **What the console does not do.** It does not deploy, configure, scale or upgrade a cluster, and
  it holds no account store for database users. Both belong to the operator and to the cluster.
- **What SQL it runs.** The Cluster Console runs the SQL its user writes and makes the catalog
  changes that user requests, bounded by that user's own privileges. The Anywhere Console executes
  only the saved commands in its own catalog, never SQL composed in the browser.
- **Custom shell commands** are gated by configuration. When disabled, built-in read-only
  commands remain available and the console says custom presets are off.
- **Anywhere's own queries are tagged, and only the user-issued ones are kept.** Anywhere tags
  every statement it runs with `/* APP=PhoenixAI Anywhere - <page> */`, naming the page it came
  from. Statements a user issued through the console — from the SQL editor, a saved command or
  catalog management — appear in Query insights with that tag, subject to the same persist
  policy as any other query. Statements the console issues for itself — schema browsing,
  privilege checks, its own polling — are never kept there, whatever `queryHistory.slowQueryMs`
  is set to; they are visible only in the Audit logs sub-view, which reads the coordinator's
  audit log directly.
