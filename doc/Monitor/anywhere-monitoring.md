# Point the Anywhere Console at Prometheus

The Anywhere console's System Monitoring pages read their time series from Prometheus. Anywhere
never runs its own time-series database — it only queries one you already have, so the monitoring
pages stay empty until you tell it where that is.

This page assumes Prometheus is already scraping your cluster. If it is not, do
[deploy-prometheus-grafana.md](./deploy-prometheus-grafana.md) and
[integration-prometheus-grafana.md](./integration-prometheus-grafana.md) first — in particular the
`release` label warning, which is the usual reason a correctly configured Anywhere still shows
nothing.

## Configure the dependency

In the `kube-anywhere` chart's values, under the `anywhere` key (the console subchart):

```yaml
anywhere:
  dependencies:
    prometheus:
      enabled: true
      # Full base URL. The scheme is required, and a path prefix is kept, so this
      # also works behind a reverse proxy or against a Prometheus-compatible
      # backend such as Mimir or Thanos.
      endpoint: http://prometheus-kube-prometheus-prometheus.monitoring:9090
```

That is the whole of the required configuration. The optional settings are worth knowing about
before you need them:

| Setting | Use it when |
| --- | --- |
| `username` + `password`, or `bearerToken` | Prometheus is behind basic auth or a bearer token. Configure at most one of the two modes |
| `headers` | A multi-tenant backend needs an org header, e.g. `X-Scope-OrgID: tenant-1` |
| `tls.caCert` | The endpoint is HTTPS with a private CA. `tls.insecureSkipVerify` exists but the dependency check flags it |
| `metricPrefix` | Your pipeline renames PhoenixAI's `starrocks_*` metrics. Leave empty for the canonical names |
| `clusterLabel` | Your metrics locate clusters under a label other than `cluster` |

The last two exist because Anywhere queries metrics by name and locates clusters by label. The
`kube-anywhere` chart's ServiceMonitors emit exactly what Anywhere expects, so with the standard
install both stay empty.

## Verify it, rather than guessing

Anywhere ships a dependency check that reports each part of the wiring separately. It is the
fastest way to find out which piece is wrong, and much more useful than an empty chart:

It needs an admin session, so sign in first and keep the cookie:

```bash
kubectl -n phoenixai port-forward svc/kube-anywhere-console 8090:8090

curl -s -c cookies.txt -X POST localhost:8090/api/v1/auth/admin/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"<password>"}'

curl -s -b cookies.txt -X POST \
  localhost:8090/api/v1/admin/dependencies/prometheus/check
```

Admin passwords live in the `kube-anywhere-console-admin` Secret, one key per username.

A correctly wired installation reports every probe `ok`:

```text
summary            ok           prometheusVersion 3.14.0
config             ok           endpoint configured
connectivity       ok           query API reachable
auth               ok           credentials accepted
metric-present     ok           3 series for starrocks_fe_query_total in the last 15m
metric-rename      skipped      metric found under its expected name
cluster-label      ok           series carry the cluster label
container-metrics  ok  (opt)    79 series for container_cpu_usage_seconds_total
resource-metrics   ok  (opt)    26 series for kube_pod_container_resource_limits
```

Read the failures by which probe reports them:

- **`connectivity`** — the endpoint is wrong or unreachable from the Anywhere pod. Remember it is
  resolved inside the cluster, so it needs the in-cluster service address, not a `localhost` port-forward.
- **`metric-present`** — Anywhere can reach Prometheus, but Prometheus holds no PhoenixAI metrics.
  The scrape is the problem, not Anywhere. This is what a missing `release` label looks like from here.
- **`metric-rename`** — the metrics exist under a different prefix. The finding suggests the
  `metricPrefix` value to set.
- **`cluster-label`** — the series are there but carry no `cluster` label, so Anywhere cannot tell
  which cluster they belong to. Check the ServiceMonitor relabelings.

The last two probes are advisory. `container-metrics` and `resource-metrics` come from
kubelet/cAdvisor and kube-state-metrics, which `kube-prometheus-stack` scrapes by default. When they
are present, the resource topology and Instance State pages additionally show per-pod CPU and memory
usage and utilization. When they are absent, everything else still works — those particular charts
degrade rather than break.

If you are not running `kube-prometheus-stack`: cAdvisor metrics come from the kubelet, so they only
need to be scraped, while kube-state-metrics is a separate component to install and scrape. Running
without either is a supported setup.

## It also checks itself

The same probes run per cluster as the `prometheus-dependency-unusable` health-check rule, at
warning severity. So a Prometheus that was configured correctly and later broke — an endpoint that
moved, a scrape that stopped — surfaces on its own, without anyone opening the monitoring pages.

If an installation deliberately runs without Prometheus, silence the rule rather than living with a
standing warning:

```yaml
inspection:
  disabledRules:
    - prometheus-dependency-unusable
```

## Warehouses

Compute nodes belonging to a warehouse carry the same `cluster` label as the cluster they are
attached to, plus a `warehouse` label holding the warehouse name. Anywhere uses this to attribute
them correctly — the monitoring instance list shows each warehouse's compute nodes tagged with the
warehouse they belong to, alongside the cluster's own.

This requires the warehouse chart to have its ServiceMonitor enabled too; the cluster's
ServiceMonitors do not select a warehouse's Services. See
[integration-prometheus-grafana.md](./integration-prometheus-grafana.md#22-turn-on-the-prometheus-metrics-scrape-by-using-servicemonitor-crd).
