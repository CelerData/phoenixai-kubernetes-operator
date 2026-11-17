# Deploy Prometheus and Grafana

PhoenixAI's charts expose their metrics through **ServiceMonitor** objects, and those are only
understood by a Prometheus deployed with the Prometheus Operator. So there is really one
recommended path — `kube-prometheus-stack`, which installs the operator, Prometheus, and Grafana
together, and provisions Grafana's Prometheus data source for you.

A plain Prometheus install is covered at the end, for the case where you already have one and cannot
change it.

## 1. Install kube-prometheus-stack

Install it **before** the PhoenixAI cluster. The cluster and warehouse charts render their
ServiceMonitors only if the Prometheus Operator's CRDs already exist; install them the other way
round and the ServiceMonitors are skipped silently, leaving every dashboard empty for a reason
nothing on screen explains.

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update prometheus-community
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace
```

The release name matters beyond this command. `kube-prometheus-stack` defaults its
`serviceMonitorSelector` to `matchLabels: {release: <release name>}`, so the PhoenixAI charts must
label their ServiceMonitors to match — see
[the `release` label warning](./integration-prometheus-grafana.md#22-turn-on-the-prometheus-metrics-scrape-by-using-servicemonitor-crd).
Installing as `prometheus`, as above, means `release: prometheus`.

This also scrapes kubelet/cAdvisor and kube-state-metrics by default, which is what makes per-pod
CPU and memory utilization available to the Anywhere console's monitoring pages. Nothing to
configure — but if you trim the stack down, those two are worth keeping.

Check what came up:

```bash
kubectl --namespace monitoring get pods -l "release=prometheus"
```

## 2. Reach Grafana

The chart creates a `ClusterIP` service, so reach it with a port-forward:

```bash
kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80
```

Grafana is then at `http://localhost:3000`. To reach it from outside the cluster instead, set
`grafana.service.type=LoadBalancer` in the chart's values — but only where your cluster has a
load-balancer provider. On kind, minikube, or bare metal without MetalLB the external IP stays
`<pending>` forever, and the port-forward above is what you want.

The generated admin password is in a Secret:

```bash
kubectl --namespace monitoring get secret prometheus-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d ; echo
```

Sign in as `admin` with that password.

## 3. Confirm the Prometheus data source

`kube-prometheus-stack` provisions it automatically — there is nothing to add by hand. Confirm it
under **Connections → Data sources**, or over the API:

```bash
curl -s -u admin:<password> localhost:3000/api/datasources \
  | grep -o '"name":"Prometheus"[^}]*"url":"[^"]*"'
```

It should point at `http://prometheus-<release>-kube-prometheus-prometheus.monitoring:9090`.

With that in place, continue to
[Integration with Prometheus and Grafana](./integration-prometheus-grafana.md) to turn the scrape on
for your cluster and import the dashboard.

## Appendix: a plain Prometheus and Grafana

Use this only if you already run a Prometheus that is not managed by the Prometheus Operator. It
has no ServiceMonitor CRDs, so the ServiceMonitor route does not apply and you must use the
[annotation method](./integration-prometheus-grafana.md#21-turn-on-the-prometheus-metrics-scrape-by-adding-annotations)
instead.

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update prometheus-community
helm install prometheus prometheus-community/prometheus

helm repo add grafana https://grafana.github.io/helm-charts
helm repo update grafana
helm install grafana grafana/grafana
```

This Grafana has no data source provisioned. Add one under **Connections → Data sources**, of type
Prometheus, with the URL `http://prometheus-server.<namespace>` — `<namespace>` being wherever you
installed the Prometheus chart. Its admin password is in the `grafana` Secret:

```bash
kubectl get secret grafana -o jsonpath="{.data.admin-password}" | base64 -d ; echo
```

Be aware of what this path costs you: the Grafana dashboard that ships with this repository keys on
the `cluster` and `group` labels that the charts' ServiceMonitors apply through relabeling. Under
annotation-based discovery those labels are not set, so the dashboard's variables will not resolve
and its panels stay empty.
