---
sidebar_position: 3
sidebar_label: Queue-based autoscaling for CN nodes
---

# Queue-based autoscaling for CN nodes

This guide scales the CN nodes of a warehouse on its **query queue**: when queries start to wait for
compute, more CN nodes are added; when the warehouse goes quiet, CN nodes are removed. It works for
the CN nodes of a `PhoenixAICluster` (the `default_warehouse`) and for a `PhoenixAIWarehouse`.

No operator setting is involved. The pieces are:

```
FE (leader) /metrics ──ServiceMonitor──▶ Prometheus ◀──PromQL── KEDA ScaledObject
                                                                     │ creates and drives an HPA
  PhoenixAICluster / PhoenixAIWarehouse (scale subresource) ◀────────┘
          │
          ▼
  the operator resizes the CN StatefulSet and removes dropped CN nodes from the FE
```

1. The FE keeps a query queue per warehouse once you turn it on, and reports it as the metric
   `starrocks_fe_warehouse_query_queue`.
2. Prometheus scrapes that metric from the FE pods.
3. [KEDA](https://keda.sh) queries Prometheus and creates a Horizontal Pod Autoscaler (HPA) that
   resizes the `PhoenixAICluster` or `PhoenixAIWarehouse` through its scale subresource.
4. The operator applies the new replica count to the CN StatefulSet. After a scale-in it drops the
   removed CN nodes from the FE (`ALTER SYSTEM DROP COMPUTE NODE`).

## Prerequisites

- A PhoenixAI cluster in **shared-data** mode (`run_mode = shared_data`).
- A kernel that supports warehouse query queues: 3.5.6-ee or later on the 3.5 line, or any 4.x. To
  check, look for `warehouse-query-queue` in the FE feature list:

  ```bash
  kubectl -n <namespace> exec <cluster>-fe-0 -- \
    curl -s -u root: http://127.0.0.1:8030/api/v2/feature | grep -o '"warehouse-query-queue"'
  ```

  Pass the root password after `root:` if one is set.
- [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator), for example
  installed with the [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
  chart. The cluster chart creates a `ServiceMonitor`, which needs Prometheus Operator.
- KEDA v2. If it is not installed yet:

  ```bash
  helm repo add kedacore https://kedacore.github.io/charts
  helm repo update
  helm install keda kedacore/keda --namespace keda --create-namespace

  # All three deployments should be ready, and KEDA should serve the external metrics API.
  kubectl -n keda get deploy
  kubectl get apiservice v1beta1.external.metrics.k8s.io
  ```

## Step 1: Turn on the query queue for the warehouse

The queue is a property of a warehouse, set with SQL. It is not an `fe.conf` setting. Connect to
the FE with a MySQL client and run:

```sql
-- the CN nodes of a PhoenixAICluster belong to default_warehouse
ALTER WAREHOUSE default_warehouse SET ("enable_query_queue" = "true");

-- for a PhoenixAIWarehouse, use its name, for example:
-- ALTER WAREHOUSE wh1 SET ("enable_query_queue" = "true");
```

The property is stored in the FE metadata, so it survives FE restarts. Check it with
`SHOW WAREHOUSES`: the `Property` column should contain `"enable_query_queue":true`.

From now on queries that scan tables can wait in the queue when the warehouse is out of
capacity. The queue manages capacity in **slots**. By default a warehouse has one slot per CPU core
of its CN nodes, and a query takes up to one slot per CN node it runs on.

Once the queue is on, the leader FE reports the metric:

```bash
kubectl -n <namespace> exec <cluster>-fe-0 -- \
  curl -s http://127.0.0.1:8030/metrics | grep starrocks_fe_warehouse_query_queue
```

```
starrocks_fe_warehouse_query_queue{field="query_pending_length", warehouse_id="0", warehouse_name="default_warehouse"} 0
starrocks_fe_warehouse_query_queue{field="query_running_length", warehouse_id="0", warehouse_name="default_warehouse"} 0
starrocks_fe_warehouse_query_queue{field="earliest_query_wait_time", warehouse_id="0", warehouse_name="default_warehouse"} 0.0
starrocks_fe_warehouse_query_queue{field="sum_required_slots", warehouse_id="0", warehouse_name="default_warehouse"} 0
starrocks_fe_warehouse_query_queue{field="remain_slots", warehouse_id="0", warehouse_name="default_warehouse"} 4
starrocks_fe_warehouse_query_queue{field="max_slots", warehouse_id="0", warehouse_name="default_warehouse"} 4
...
```

| `field` | Meaning |
|---|---|
| `max_slots` | Total slots of the warehouse |
| `remain_slots` | Slots not in use |
| `sum_required_slots` | Slots that the queued queries are waiting for |
| `query_pending_length` | Number of queued queries |
| `earliest_query_wait_time` | Seconds the oldest queued query has waited |

Two things to know:

- Only the **leader** FE reports this metric. In a cluster with several FE nodes, run the `curl`
  above against each FE; one of them prints the series.
- A warehouse whose queue is off reports no series at all, not zeros.

## Step 2: Let Prometheus scrape the FE

Turn on the ServiceMonitor in the cluster's values file and apply it with `helm upgrade`:

```yaml
phoenixai:
  metrics:
    serviceMonitor:
      enabled: true
      labels: {}   # labels your Prometheus selects ServiceMonitors by, if any
```

Prometheus only scrapes the ServiceMonitors that its `serviceMonitorSelector` matches. Check it:

```bash
kubectl -n <prometheus-namespace> get prometheus -o jsonpath='{.items[*].spec.serviceMonitorSelector}'
```

`{}` matches every ServiceMonitor. If it prints labels instead, for example
`{"matchLabels":{"release":"prometheus"}}`, put the same labels under `serviceMonitor.labels`.

Prometheus needs a minute or two to pick up a new ServiceMonitor. After that, the series should be
in Prometheus. The ServiceMonitor adds the labels `namespace`
and `cluster` (the cluster name), which the query in step 4 filters on:

```promql
starrocks_fe_warehouse_query_queue{namespace="<namespace>", cluster="<cluster>", field="max_slots"}
```

## Step 3: Hand the CN replica count over to KEDA

KEDA must be the only thing that sets the CN replica count:

- **Remove `autoScalingPolicy`** from the CN spec (`phoenixAICnSpec.autoScalingPolicy` for a cluster,
  `spec.autoScalingPolicy` for a warehouse). With it, the operator creates its own HPA, and KEDA
  refuses to create a second one for the same object.
- **Remove `replicas`** from the CN spec in your values file. Otherwise every `helm upgrade` writes
  that number back, the CN nodes are resized to it, and KEDA then resizes them again.

Apply the change with `helm upgrade` before creating the ScaledObject.

## Step 4: Create the ScaledObject

The example below autoscales the CN nodes of the cluster `kube-anywhere` in the namespace
`phoenixai`, whose CN nodes have 8 CPU cores each:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: kube-anywhere-cn-queue
  namespace: phoenixai
spec:
  scaleTargetRef:
    apiVersion: phoenixdata.ai/v1
    kind: PhoenixAICluster        # PhoenixAIWarehouse for a warehouse
    name: kube-anywhere           # the cluster or warehouse name
  minReplicaCount: 2              # required: KEDA's default is 0
  maxReplicaCount: 10
  advanced:
    horizontalPodAutoscalerConfig:
      behavior:
        scaleUp:
          stabilizationWindowSeconds: 60
          policies:
            - type: Pods
              value: 4            # add at most 4 CN nodes per minute
              periodSeconds: 60
        scaleDown:
          stabilizationWindowSeconds: 600
          policies:
            - type: Pods
              value: 1            # remove at most 1 CN node every 5 minutes
              periodSeconds: 300
  triggers:
    - type: prometheus
      metadata:
        serverAddress: http://prometheus-kube-prometheus-prometheus.monitoring:9090
        threshold: "8"            # slots per CN node = CPU cores per CN node
        ignoreNullValues: "false" # required: see below
        query: |
          max(starrocks_fe_warehouse_query_queue{namespace="phoenixai",cluster="kube-anywhere",warehouse_name="default_warehouse",field="max_slots"})
          - max(starrocks_fe_warehouse_query_queue{namespace="phoenixai",cluster="kube-anywhere",warehouse_name="default_warehouse",field="remain_slots"})
          + max(starrocks_fe_warehouse_query_queue{namespace="phoenixai",cluster="kube-anywhere",warehouse_name="default_warehouse",field="sum_required_slots"})
```

```bash
kubectl apply -f kube-anywhere-cn-queue.yaml
kubectl -n phoenixai get scaledobject,hpa
```

`READY` should be `True`, and the HPA `keda-hpa-kube-anywhere-cn-queue` should show a number under
`TARGETS`, not `<unknown>`.

### What the settings do

**The query** is the warehouse's slot demand: slots in use (`max_slots - remain_slots`) plus slots
the queued queries wait for (`sum_required_slots`). Keep all three filters:

- `namespace` and `cluster`: different clusters scraped by the same Prometheus all have a
  `default_warehouse`.
- `warehouse_name`: the warehouse this ScaledObject scales.

`max(...)` keeps the value correct if more than one series briefly exists for the warehouse, for
example around an FE leader change.

**`threshold`** is the number of slots one CN node adds: its CPU core count. KEDA sets the desired
number of CN nodes to `ceil(demand / threshold)`, which works out to
`current CN nodes × (demand / max_slots)`. In other words, the target is 100% slot usage, with
queued queries counted:

- queries are waiting → demand is above `max_slots` → scale out;
- all slots busy, nothing waiting → the count stays;
- slots sitting idle → scale in.

To keep headroom, use a smaller `threshold`. With 8-core CN nodes, `threshold: "6.4"` aims at 80% slot
usage.

The result is not an exact count of the CN nodes a burst needs. A query that scans a large table
takes one slot on every CN node, so adding CN nodes makes such queries faster rather than letting
more of them run at once. The queue then drains over several rounds of scale-out. Use
`behavior.scaleUp.policies` to bound how much each round adds.

**`ignoreNullValues: "false"`** matters for safety. The query returns nothing when Prometheus has no
data, for example because Prometheus is down, the FE leader is restarting, or the queue was turned
off. With KEDA's default (`"true"`), an empty result counts as 0, and the CN nodes are scaled in to
`minReplicaCount`. With `"false"`, KEDA reports an error instead, and the HPA keeps the current number
of CN nodes. For the same reason, do not configure KEDA's `fallback` unless you want a fixed replica
count during an outage.

**`minReplicaCount`** defaults to 0 in KEDA. Set it to the smallest number of CN nodes the warehouse
should keep.

**`behavior`**: the stabilization windows require a change to persist before KEDA acts on it, and
the policies cap how many CN nodes each period adds or removes. Keep `scaleUp.stabilizationWindowSeconds`
at 30 seconds or more: after new CN nodes become ready, the FE takes 15–30 seconds to count their slots
in `max_slots`, and a shorter window can trigger an extra scale-out on the old value.

### A warehouse

For a `PhoenixAIWarehouse`, change three things in the example:

```yaml
  scaleTargetRef:
    apiVersion: phoenixdata.ai/v1
    kind: PhoenixAIWarehouse
    name: wh1
  ...
        query: |
          max(starrocks_fe_warehouse_query_queue{namespace="phoenixai",cluster="kube-anywhere",warehouse_name="wh1",field="max_slots"})
          - max(starrocks_fe_warehouse_query_queue{namespace="phoenixai",cluster="kube-anywhere",warehouse_name="wh1",field="remain_slots"})
          + max(starrocks_fe_warehouse_query_queue{namespace="phoenixai",cluster="kube-anywhere",warehouse_name="wh1",field="sum_required_slots"})
```

`cluster` stays the name of the cluster the warehouse belongs to, because the metric comes from that
cluster's FE. Each warehouse needs its own `ALTER WAREHOUSE ... SET ("enable_query_queue" = "true")`
and its own ScaledObject; scaling one warehouse does not change the others.

### Combine with a schedule

A ScaledObject can carry several triggers, and KEDA follows whichever asks for the most CN nodes. To
keep at least 4 CN nodes during business hours and still scale on the queue, add a `cron` trigger:

```yaml
  triggers:
    - type: prometheus
      metadata:
        ...                       # as above
    - type: cron
      metadata:
        timezone: Asia/Shanghai
        start: "0 9 * * 1-5"      # 09:00 on weekdays
        end: "0 18 * * 1-5"       # 18:00 on weekdays
        desiredReplicas: "4"
```

During the window the CN count does not drop below 4, and queued queries can still push it higher.
After the window, the count follows the queue again.

For more on cron triggers — cron syntax, time zones, several windows, and when scale-up and
scale-down happen — see [Scheduled scaling for CN nodes with KEDA](./scheduled_scaling_with_keda_howto.md).

## Watch it work

```bash
# current value / threshold, and the replica count
kubectl -n phoenixai get hpa keda-hpa-kube-anywhere-cn-queue -w

# why the HPA scaled
kubectl -n phoenixai describe hpa keda-hpa-kube-anywhere-cn-queue

# the CN replica count the operator applies
kubectl -n phoenixai get phoenixaicluster kube-anywhere -o jsonpath='{.spec.phoenixAICnSpec.replicas}'
```

`TARGETS` shows the demand divided by the current number of CN nodes, against `threshold`, for example
`5334m/8 (avg)`.

## Troubleshooting

**The ScaledObject is rejected with `the workload '<name>' of type 'phoenixdata.ai/v1.PhoenixAICluster' is already managed by the hpa '<name>-cn-autoscaler'`.**
The CN spec still has `autoScalingPolicy`. Remove it as described in step 3.

**`TARGETS` stays `<unknown>`, or the KEDA operator logs `prometheus metrics 'prometheus' target may be lost, the result is empty`.**
The query returns nothing. In order, check:

1. The warehouse queue is on (`SHOW WAREHOUSES`).
2. The leader FE prints the series (`curl .../metrics`, step 1).
3. Prometheus has a target for the FE pods. If not, check the ServiceMonitor labels against the
   Prometheus `serviceMonitorSelector` (step 2).
4. The `namespace`, `cluster` and `warehouse_name` values in the query match the series in
   Prometheus.

While the query returns nothing, the HPA keeps the current number of CN nodes.

**CN nodes were scaled in to `minReplicaCount` although the warehouse was busy.**
Check that the trigger sets `ignoreNullValues: "false"`.

**CN nodes are resized right after every `helm upgrade`.**
The values file still sets the CN `replicas`. Remove it (step 3).

**Queries are not queued although the warehouse is busy.**
Only queries that scan tables go through the queue. Queries such as `SELECT ... FROM TABLE(generate_series(...))`
never wait in it.

## Notes

- When CN nodes are removed, queries still running on them fail, as with any CN scale-in. Long
  scale-down windows and small scale-down steps reduce how often that happens.
- CN groups are not covered by this guide.
