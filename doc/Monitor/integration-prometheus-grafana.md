# PhoenixAI Cluster Integration With Prometheus and Grafana Service

This document describes how to integrate PhoenixAI cluster with Prometheus and Grafana service in a Kubernetes
environment. From this document, you will learn,

* How to turn on Prometheus metrics scrape for the PhoenixAI cluster
* How to import PhoenixAI Grafana dashboard

## 1. Prerequisites

* Kubernetes: v1.23.0+
* PhoenixAI operator and helm chart: v2.0.0 (the ServiceMonitor route below needs v1.8.4 or later)
* `kube-prometheus-stack`, installed **before** the cluster — see
  [deploy-prometheus-grafana.md](./deploy-prometheus-grafana.md)

The chart renders ServiceMonitors only when the Prometheus operator's CRDs already exist. Install
the cluster first and they are skipped silently, with nothing on screen to say why.

## 2. Deploy PhoenixAI Cluster

There are two ways to turn on the Prometheus metrics scrape for the PhoenixAI cluster, and they are
**not** interchangeable — which one works depends on how Prometheus itself was deployed.

| Your Prometheus | Use | Why |
| --- | --- | --- |
| `kube-prometheus-stack` (the Prometheus operator) | [ServiceMonitor](#22-turn-on-the-prometheus-metrics-scrape-by-using-servicemonitor-crd) | Its Prometheus discovers targets **only** through ServiceMonitor and PodMonitor objects |
| The plain `prometheus-community/prometheus` chart | [Annotations](#21-turn-on-the-prometheus-metrics-scrape-by-adding-annotations) | That chart ships scrape configs that discover pods by annotation; it has no ServiceMonitor CRDs |

:::danger Annotations do nothing under `kube-prometheus-stack`
This is the combination that silently collects no PhoenixAI metrics at all. A Prometheus deployed by
the operator carries no annotation-based discovery — every job in its generated configuration is a
`serviceMonitor/…` job. You can confirm it on your own cluster:

```bash
kubectl -n monitoring get secret prometheus-<release>-kube-prometheus-prometheus \
    -o jsonpath='{.data.prometheus\.yaml\.gz}' | base64 -d | gunzip \
  | grep -c "prometheus_io_scrape"
# 0
```

Since ServiceMonitor support is the reason
[deploy-prometheus-grafana.md](./deploy-prometheus-grafana.md) recommends the operator install,
§2.2 is the route most readers want.
:::

### 2.1 Turn on the Prometheus metrics scrape by adding annotations

Follow the instructions from [PhoenixAI Helm Chart](https://github.com/CelerData/phoenixai-kubernetes-operator/tree/main/helm-charts/charts/kube-anywhere)
with some customized values.

Following is an example of the content of the `sr-values.yaml`.

* For chart v1.7.1 and below,

```yaml
# sr-values.yaml
phoenixAIFeSpec:
  service:
    annotations:
      prometheus.io/path: "/metrics"
      prometheus.io/port: "8030"
      prometheus.io/scrape: "true"
  resources:
    requests:
      cpu: 1
      memory: 2Gi
    limits:
      cpu: 4
      memory: 4Gi
phoenixAICnSpec:
  service:
    annotations:
      prometheus.io/path: "/metrics"
      prometheus.io/port: "8040"
      prometheus.io/scrape: "true"
  resources:
    requests:
      cpu: 1
      memory: 2Gi
    limits:
      cpu: 4
      memory: 4Gi
```

* For chart v1.8.0 and above,

```yaml
phoenixai:
  phoenixAIFeSpec:
    service:
      annotations:
        prometheus.io/path: "/metrics"
        prometheus.io/port: "8030"
        prometheus.io/scrape: "true"
    resources:
      requests:
        cpu: 1
        memory: 2Gi
      limits:
        cpu: 4
        memory: 4Gi
  phoenixAICnSpec:
    service:
      annotations:
        prometheus.io/path: "/metrics"
        prometheus.io/port: "8040"
        prometheus.io/scrape: "true"
    resources:
      requests:
        cpu: 1
        memory: 2Gi
      limits:
        cpu: 4
        memory: 4Gi
```

Note that `"prometheus.io/*` annotations are the must items to be added, this will allow Prometheus to auto discover
PhoenixAI PODs and to collect the metrics.
This method will restart the PhoenixAI cluster.

An equivalent PhoenixAI CRD may look like,

```yaml
apiVersion: phoenixdata.ai/v1
kind: PhoenixAICluster
metadata:
  name: kube-anywhere
  namespace: default
spec:
  phoenixAICnSpec:
    configMapInfo:
      configMapName: kube-anywhere-cn-cm
      resolveKey: cn.conf
    image: us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/cn-ubuntu:<database-image-tag>
    limits:
      cpu: 4
      memory: 4Gi
    replicas: 1
    requests:
      cpu: 1
      memory: 2Gi
    service:
      annotations:
        prometheus.io/path: /metrics
        prometheus.io/port: "8040"
        prometheus.io/scrape: "true"
  phoenixAIFeSpec:
    configMapInfo:
      configMapName: kube-anywhere-fe-cm
      resolveKey: fe.conf
    image: us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/fe-ubuntu:<database-image-tag>
    limits:
      cpu: 4
      memory: 4Gi
    replicas: 1
    requests:
      cpu: 1
      memory: 2Gi
    service:
      annotations:
        prometheus.io/path: /metrics
        prometheus.io/port: "8030"
        prometheus.io/scrape: "true"
```

Run the following commands to deploy PhoenixAI operator and PhoenixAI cluster,

```shell
helm repo add phoenixai https://celerdata.github.io/phoenixai-kubernetes-operator
helm repo update phoenixai
helm install kube-anywhere -f sr-values.yaml phoenixai/kube-anywhere
```

### 2.2 Turn on the Prometheus metrics scrape by using ServiceMonitor CRD

Compared to the annotation approach, ServiceMonitor allows for more flexible definition of selector
and relabeling rules in the future. It requires
[installing kube-prometheus-stack](./deploy-prometheus-grafana.md#1-install-kube-prometheus-stack).

Add this to the cluster chart's values:

```yaml
phoenixai:
  metrics:
    serviceMonitor:
      enabled: true
      # Required. See the warning below.
      labels:
        release: prometheus
```

:::caution The ServiceMonitors must carry the label your Prometheus selects on
Enabling them is not enough. `kube-prometheus-stack` defaults its `serviceMonitorSelector` to
`matchLabels: {release: <helm release name>}`, and the PhoenixAI charts do not add that label on
their own. Without it the ServiceMonitor objects are created and **Prometheus ignores every one of
them** — it scrapes only its own stack, and both the Grafana dashboard and the Anywhere console's
monitoring pages stay empty with nothing on screen to explain it.

Set `release` to the name you installed `kube-prometheus-stack` under; the examples here assume
`prometheus`. Verify afterwards — the targets should be `up`, one per FE and per compute node:

```bash
kubectl -n <namespace> get servicemonitor --show-labels
# then, against Prometheus:
#   count(up{cluster="<your cluster name>"})
```

:::

Note: This only works for chart v1.8.4 and above.

The ServiceMonitors above cover the cluster's own FE / CN. A warehouse is installed as a
separate `warehouse` chart release with its own Services, which the cluster's ServiceMonitors do not
select, so turn the scrape on for each warehouse release too — including the same `release` label:

```yaml
metrics:
  serviceMonitor:
    enabled: true
    labels:
      release: prometheus
```

The warehouse CN series carry the same `cluster` label as the components of the PhoenixAICluster
they are attached to, plus a `warehouse` label holding the warehouse name — so a query for one
cluster returns all of its compute nodes, and the warehouses can still be told apart.

## 3. Import PhoenixAI Grafana Dashboard

A Grafana dashboard for Kubernetes deployments ships in this repository, at
[examples/grafana/PhoenixAI-Overview-kubernetes.json](../../examples/grafana/PhoenixAI-Overview-kubernetes.json).
It keys on the `cluster` and `group` labels the chart's ServiceMonitors apply, so the
ServiceMonitors must be enabled *and* selected by your Prometheus — see the `release`
label note in the quick starts.
[examples/grafana/README.md](../../examples/grafana/README.md) records
what it covers and how it differs from the upstream StarRocks dashboard.

Detailed instructions can be
found in [the Grafana dashboard reference](https://grafana.com/docs/grafana/latest/visualizations/dashboards/build-dashboards/import-dashboards/).

Importing over the API rather than through the UI? The dashboard's datasource input is named
`PhoenixAI_Prometheus`; pass it under that name or the import fails with
`missing dashboard input variable`.

Download the dashboard first — the file is about 700 KB, so use **Download raw file** on the
GitHub page rather than selecting the text in the browser. Then, in Grafana:

* Click **Dashboards** in the left-side menu.
* Click **New** and select **Import dashboard** in the dropdown menu.
* Click **Upload dashboard JSON file** and choose the file you downloaded.

Grafana also accepts the dashboard pasted into the **Import via dashboard JSON model** text area,
which is quicker if you are re-importing a dashboard you have just edited. At this size, uploading
the file is the easier of the two.

The import process enables you to change the name of the dashboard, pick the data source you want the dashboard to use,
and specify any metric prefixes (if the dashboard uses any).

## 4. The Anywhere Console

Prometheus also backs the Anywhere Console's System Monitoring pages, which are configured
separately from anything above — see
[Point the Anywhere Console at Prometheus](./anywhere-monitoring.md). That page also covers the
dependency check, which reports whether the scrape you set up here is actually reaching the console.
