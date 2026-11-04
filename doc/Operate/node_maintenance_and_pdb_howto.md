# Kubernetes Node Maintenance and PodDisruptionBudget Howto

When a Kubernetes cluster's nodes are drained for maintenance (e.g. `kubectl drain`, cluster-autoscaler
node consolidation, or a managed node-group upgrade on EKS/GKE/AKS), the node's pods are evicted via the
Kubernetes [Eviction API](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/). Without any
protection, draining multiple nodes in parallel can evict multiple replicas of the same PhoenixAI component
(FE/CN/FE Proxy) at once, breaking FE quorum or dropping CN capacity and causing a service outage.

## What the operator does automatically

Starting from this version, the operator automatically creates a
[PodDisruptionBudget](https://kubernetes.io/docs/tasks/run-application/configure-pdb/) (PDB) for each of the
FE, CN, and FE Proxy components, named `<component-statefulset-or-deployment-name>-pdb`
(e.g. `phoenixaicluster-sample-fe-pdb`). The PDB sets `maxUnavailable: 1`, meaning the Kubernetes API server
will reject (and `kubectl drain` will retry/wait on) any voluntary eviction that would take down more than
one replica of that component at a time — regardless of how many nodes are being drained concurrently.

### Turning the feature on / off

The behavior is controlled by the operator flag `--enable-pod-disruption-budget`:

- **Helm chart users**: enabled by default via the operator value
  `phoenixAIOperator.enablePodDisruptionBudget: true` (the chart's RBAC already includes the required
  `policy/poddisruptionbudgets` permissions). Set it to `false` to turn the feature off; the change rolls
  only the operator pod, never FE/CN.
- **`operator.yaml` users**: the released `operator.yaml` ships with the flag enabled and the matching
  RBAC rule, so the default experience matches Helm.
- **Bare binary / custom deployments**: the flag defaults to **off**. When it is off, the operator never
  touches the PodDisruptionBudget API at all — neither creating nor deleting PDBs — so an operator running
  under hand-maintained RBAC *without* `policy/poddisruptionbudgets` permissions still reconciles cleanly.
  This is the recommended setting while migrating an installation whose RBAC has not been updated yet.

Note: turning the flag **off** after it has been on does not delete the PDBs the operator already created
(with the feature off it deliberately never touches that API). Remove them manually if you no longer want
them: `kubectl delete pdb <name>-fe-pdb <name>-cn-pdb -n <namespace>`.

This is created once and never overwritten: if a PDB with that name already exists — whether from a
previous reconcile, or supplied directly by you — the operator leaves it alone. This means:

- You don't need to configure anything to get this protection; it applies automatically.
- If you want different disruption tolerance (e.g. a larger `maxUnavailable` for a big CN cluster, or a
  quorum-aware `minAvailable` for FE), just create your own `PodDisruptionBudget` under the same name before
  the operator does (or edit the operator-created one afterwards) — the operator will never revert your
  changes. If you're using the Helm chart, the generic `resources: []` value
  (see [values.yaml](../../helm-charts/charts/kube-anywhere/values.yaml)) is a convenient place to declare a
  custom PDB alongside the rest of your release.

## Operational guidance for node drains

Because the PDB will make `kubectl drain` block/retry rather than immediately evict a pod that would
violate it, keep the following in mind during a Kubernetes node upgrade:

- **Drain nodes sequentially, not all at once**, when they host replicas of the same PhoenixAI component.
  This lets each evicted pod reschedule and become ready again before the next node is drained.
- Use a reasonable `kubectl drain --timeout=<N>` and treat a
  `Cannot evict pod as it would violate the pod's disruption budget` message as an expected signal to wait,
  not an error to work around.
- **Do not use `kubectl drain --disable-eviction`** (or otherwise force-delete pods) to "unblock" a drain —
  this bypasses the PDB entirely and reintroduces the exact simultaneous-eviction risk the PDB protects
  against.
- Managed node-group upgrade tools (e.g. Karpenter, cluster-autoscaler, EKS/GKE/AKS managed node group
  upgrades) generally respect PodDisruptionBudgets and will wait/requeue automatically — expect node upgrade
  windows to take longer with this protection in place, which is the intended trade-off for availability.

## Defense in depth: spreading replicas across nodes

A PDB limits how many replicas can be evicted *at once*, but it doesn't control where replicas are
scheduled in the first place. If multiple replicas of the same component happen to land on the same node,
draining that single node can still be as disruptive as the PDB allows. For additional protection, consider
setting a **soft** topology spread constraint (or pod anti-affinity) on components you want to spread across
nodes/zones, using the existing `topologySpreadConstraints` field already available on each component spec
(FE shown, the same field exists on `phoenixAICnSpec` and `phoenixAIFeProxySpec`):

```yaml
apiVersion: phoenixdata.ai/v1
kind: PhoenixAICluster
metadata:
  name: phoenixaicluster-sample
spec:
  phoenixAIFeSpec:
    replicas: 3
    topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        # ScheduleAnyway is a soft constraint: it's honored best-effort and never leaves pods
        # unschedulable, unlike DoNotSchedule, which can strand pods Pending on small clusters.
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            app.kubernetes.io/component: fe
```

The operator does not set this by default, because a hard topology constraint
(`whenUnsatisfiable: DoNotSchedule`) can make pods `Pending` forever on clusters with fewer nodes than
replicas (e.g. small trial or dev clusters) — a worse outcome than the problem it's meant to prevent. Using
`ScheduleAnyway` gets you the spreading benefit without that risk.

To spread across availability zones rather than nodes, see
[Deploy Across Availability Zones](../Deploy/deploy_multi_az_howto.md).
