---
sidebar_label: Multiple availability zones
sidebar_position: 9
---

# Deploy Across Availability Zones

The operator has no zone-specific setting. You spread a cluster across availability zones with the
standard Kubernetes scheduling fields that every component spec already accepts —
`topologySpreadConstraints`, `nodeSelector` and `affinity` — and, for CN, optionally with
[CN Groups](./deploy_cn_group_howto.md). This page puts those pieces together.

## 1. Prerequisites

1. **Every node carries the standard zone label** `topology.kubernetes.io/zone`. Managed Kubernetes
   (EKS, GKE, AKS) sets it for you. Check it:

   ```bash
   kubectl get nodes -L topology.kubernetes.io/zone
   ```

2. **Every zone you plan to use has nodes with room for the pods**. If a node autoscaler
   (cluster-autoscaler, Karpenter) adds nodes for you, make sure it can add them in each zone, for
   example with one node group per zone.

3. **The StorageClass binds volumes late.** A cloud disk (EBS, Persistent Disk, Azure Disk) lives in
   one zone, and a pod can only run in the zone its disk is in. With
   `volumeBindingMode: WaitForFirstConsumer` the disk is created after the scheduler has picked a
   node, so it follows the pod's spread. With `Immediate` the disk is created first, in whatever zone
   the provisioner picks, and the pod has to follow the disk, which defeats the spread.

   This applies to **every** volume a pod mounts, not just the main one: FE has a metadata and a log
   volume, CN can have data, log and spill volumes, and each can name its own class
   (`storageClassName`, `logStorageClassName` and `spillStorageClassName` in the Helm values, or one
   entry per volume under `storageVolumes` in the CR). A volume that names no class uses the cluster
   default. A single `Immediate` volume is enough to pin the pod, and two of them can even land in
   different zones, leaving the pod nowhere to run. On a running cluster, list the class of every
   claim, then the binding mode of each class:

   ```bash
   kubectl get pvc -n phoenixai -o custom-columns=PVC:.metadata.name,CLASS:.spec.storageClassName
   kubectl get storageclass
   ```

   The `VOLUMEBINDINGMODE` column should read `WaitForFirstConsumer` for every class in use. The
   default classes on EKS, GKE and AKS already do.

   One consequence lasts for the life of the volume: once a pod's PVC exists, that pod stays in the
   zone of its disk, even after a restart or a node replacement.

## 2. Pick a layout

| You want | Use | Section |
|---|---|---|
| FE that survives the loss of one zone | Spread 3 FE replicas over 3 zones | [3](#3-spread-fe-across-zones) |
| CN in every zone, simplest setup | Spread the CN pods over the zones | [4](#4-spread-cn-across-zones) |
| CN in every zone, each query kept inside one zone | One CN Group per zone (operator 2.1.0+) | [5](#5-one-cn-group-per-zone) |
| Everything in one zone | Pin the components to that zone | [6](#6-pin-a-component-to-one-zone) |

FE and CN are independent: spread FE across three zones and run one CN Group per zone, for example.

## 3. Spread FE across zones

The FE stays available as long as a majority of its replicas is up. Three replicas in three zones
survive the loss of any one zone. Two zones are not enough: whichever zone holds two of the three
replicas takes the majority down with it.

```yaml
apiVersion: phoenixdata.ai/v1
kind: PhoenixAICluster
metadata:
  name: kube-anywhere
  namespace: phoenixai
spec:
  phoenixAIFeSpec:
    replicas: 3
    topologySpreadConstraints:
      - maxSkew: 1
        minDomains: 3
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            # The value is the FE StatefulSet name, <cluster>-fe.
            app.phoenixai.ownerreference/name: kube-anywhere-fe
```

In the `kube-anywhere` Helm chart, the same list goes under
`phoenixai.phoenixAIFeSpec.topologySpreadConstraints`.

**Select the pods by StatefulSet, not by component.** The operator labels every pod with
`app.phoenixai.ownerreference/name: <StatefulSet name>`, which belongs to exactly one component of
one cluster. The `app.kubernetes.io/component: fe` label alone also matches the FE pods of any other
cluster in the same namespace, and the scheduler would then balance the two clusters together.

**`DoNotSchedule` or `ScheduleAnyway`.** `DoNotSchedule` guarantees the spread: a pod stays `Pending`
rather than land in a zone that already has more than its share. `ScheduleAnyway` never leaves a pod
`Pending`, but when one zone is full it quietly puts two FE in the same zone, and that zone then takes
the majority with it. For FE, use `DoNotSchedule` once all three zones have nodes, and check the
placement after the pods come up:

```bash
kubectl get pods -n phoenixai -l app.phoenixai.ownerreference/name=kube-anywhere-fe -o wide
kubectl get nodes -L topology.kubernetes.io/zone
```

**Keep `minDomains: 3`.** Without it, the scheduler counts only the zones that have a node it can use
right now. If one zone has none at that moment (its node group is empty, the autoscaler has not added
a node yet, or its nodes are cordoned), two zones and a 2+1 placement satisfy `maxSkew: 1`, and nothing
stays `Pending` to tell you. With `minDomains: 3` the scheduler counts the missing zone as empty, so
the third FE stays `Pending` until that zone has room. `minDomains` requires
`whenUnsatisfiable: DoNotSchedule` (the API server rejects it together with `ScheduleAnyway`) and is
honoured from Kubernetes 1.27 on.

The spread applies when a pod is scheduled. On a running cluster whose FE pods already share a zone,
read the next section first: adding the constraint does not move them.

### Move the FE pods of an existing cluster

Adding the constraint to a running cluster rolls the FE pods, but each pod comes back in the zone of
its disk, so FE pods that share a zone keep sharing it. Worse, with `DoNotSchedule` the rollout gets
stuck: a pod restarting in a zone that already holds more than its share has no node it may use, and
stays `Pending`. Moving an FE pod to another zone means giving it a new, empty disk there: the pod
then rejoins the FE group under its existing member name and copies the metadata from the leader.
The procedure below does that one pod at a time.

The commands use these variables; set them for your cluster:

```bash
NS=phoenixai
CLUSTER=kube-anywhere
```

#### Before you start

1. **The cluster runs an odd number of FE, three or more.** The procedure takes one FE out at a time,
   so the rest must keep a majority meanwhile. A group of two stops as soon as one member is down,
   and a group of one has nothing to fall back on. An even count buys nothing: four FE tolerate the
   loss of one, exactly like three, and spread over three zones they leave one zone holding two.

   If the cluster runs one or two FE, raise `replicas` to 3 first; with a larger even number, add one
   more. Make it a change of its own, and wait until `SHOW FRONTENDS` lists every FE as healthy. Then
   check where the pods are (step 2): the new pods may already have landed in the empty zones, leaving
   less to move.

2. **All FE are healthy.** Every row of `SHOW FRONTENDS` must show `Alive: true` and `Join: true`:

   ```bash
   kubectl exec -n $NS $CLUSTER-fe-0 -c fe -- mysql -h 127.0.0.1 -P 9030 -uroot \
     -e 'SHOW FRONTENDS\G' | grep -E ' IP:|Role:|Join:|Alive:|ReplayedJournalId:'
   ```

3. **The FE pods carry the root password, if root has one.** A pod that starts with an empty disk
   logs in as `root` to find the leader and add itself to the group. Without the password it cannot.
   The other pods then give up and restart, but `<cluster>-fe-0` treats an FE it cannot reach as no FE
   at all: after 30 seconds it starts a new, empty cluster of its own. Check the variable:

   ```bash
   kubectl exec -n $NS $CLUSTER-fe-0 -c fe -- sh -c 'test -n "$MYSQL_PWD" && echo set || echo missing'
   ```

   If root has a password and this prints `missing`, add `MYSQL_PWD` to the FE first, as described in
   [Change root user password](../Configure/change_root_password_howto.md). Helm installs that set
   `initPassword.enabled` already have it.

4. **The prerequisites at the top of this page hold**, in particular nodes in the zone the pod moves
   to and a StorageClass with `WaitForFirstConsumer`.

5. **Nothing else changes the FE meanwhile**: no upgrade, no configuration change, no node drain.
   While one FE is being replaced the group runs one member short; with three FE, a second one going
   down then stops it.

#### Step 1: add the constraint as `ScheduleAnyway`

Add the spread from the section above, but with `whenUnsatisfiable: ScheduleAnyway` and without
`minDomains` (which only works with `DoNotSchedule`), through the same channel you manage the
cluster with (`helm upgrade` with the new values, or the CR). The FE pods roll once, each back in its
current zone, and the leader moves at least once along the way. Wait until the rollout has finished
and `SHOW FRONTENDS` is healthy again.

`ScheduleAnyway` is what lets this rollout finish. It is also enough for the move: a pod with a new
disk goes to the emptiest zone unless that zone has no room.

If you already added the constraint as `DoNotSchedule` and an FE pod is stuck `Pending` with
`didn't match pod topology spread constraints`, change it to `ScheduleAnyway` and remove
`minDomains`. The StatefulSet replaces the stuck pod and the rollout carries on by itself.

#### Step 2: pick the pod to move

List which zone each FE pod is in:

```bash
kubectl get pods -n $NS -l app.phoenixai.ownerreference/name=$CLUSTER-fe \
  -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName
kubectl get nodes -L topology.kubernetes.io/zone
```

Pick one pod in a zone that holds more than one FE, and prefer a **follower** (the `Role` column of
`SHOW FRONTENDS`): a zone with two FE always has at least one, and moving a follower spares the
cluster a leader election.

**Avoid `<cluster>-fe-0` when the zone has another follower.** As noted in
[Before you start](#before-you-start), `fe-0` starts a new, empty cluster of its own when it cannot
reach an FE for 30 seconds, and a pod starting on an empty disk is exactly when that can happen: its
DNS record is still being published, and the leader may have only just moved. Move `fe-0` only when
it is the sole follower in the zone; then make sure `SHOW FRONTENDS` shows a stable leader right
before step 3, and watch the new pod's log in step 4 until it has rejoined.

Also pick a second FE, one that stays where it is, to run `SHOW FRONTENDS` on while the moved pod
comes back:

```bash
MOVE=$CLUSTER-fe-1     # the follower to move
CHECK=$CLUSTER-fe-2    # any other FE; never the same pod as $MOVE
```

List the pod's PVCs (FE has one for metadata and, by default, one for logs):

```bash
kubectl get pod -n $NS $MOVE \
  -o jsonpath='{range .spec.volumes[*]}{.persistentVolumeClaim.claimName}{"\n"}{end}'
```

If clients reach the FE through a load balancer that does not follow the Kubernetes Service, for
example one whose targets you maintain by hand, take the pod out of it now.

#### Step 3: replace the pod

Delete the PVCs, then the pod:

```bash
# Mark the PVCs for deletion. They stay until the pod is gone.
kubectl delete pvc -n $NS <metadata PVC> <log PVC> --wait=false

# Delete the pod. It leaves the FE Service at once and shuts down.
kubectl delete pod -n $NS $MOVE --wait=false
```

That is the whole change. **Do not run `ALTER SYSTEM DROP FOLLOWER` or `ADD FOLLOWER` for this
pod.** The pod keeps its name and so its place in the FE group: when it starts on the new, empty
disk, it rejoins as the same member and copies the metadata from the leader. A `DROP` would remove a
member that is about to come back, and if it lands after the new pod has started, it leaves a
running FE outside the group that still receives connections from the Service and fails every query
that needs the leader.

#### Step 4: wait for the new member

Once the old pod is gone, the StatefulSet creates new PVCs and a new pod, and the scheduler places it
by the spread constraint, normally in the zone that has no FE. When it starts, its log shows it
finding the leader and rejoining:

```text
first start fe with meta not exist.
Find leader: kube-anywhere-fe-2.kube-anywhere-fe-search.phoenixai.svc.cluster.local!
Add myself(kube-anywhere-fe-1.kube-anywhere-fe-search.phoenixai.svc.cluster.local:9010) to leader as follower ...
ERROR 1064 (HY000) at line 1: FE with the same host: kube-anywhere-fe-1.kube-anywhere-fe-search.phoenixai.svc.cluster.local already exists
first start with no meta run start_fe.sh with additional options: ' --host_type FQDN --helper ...'
```

The `already exists` error is expected: the member is still in the group, and the pod goes on to
start against it. While the new pod's DNS name is still being published you may also see a few
`unknown fqdn host` errors, each followed by `Sleep a while and retry adding`; they stop on their
own.

The pod turns `Ready` before it has caught up, so do not go by the pod status. Run `SHOW FRONTENDS`
on `$CHECK`, not on the moved pod: while that pod restarts the query fails, and once it is up it
reports the state it has replayed so far, which can lag behind the leader's.

```bash
kubectl exec -n $NS $CHECK -c fe -- mysql -h 127.0.0.1 -P 9030 -uroot \
  -e 'SHOW FRONTENDS\G' | grep -E ' IP:|Role:|Join:|Alive:|ReplayedJournalId:'
```

Wait until it shows the moved FE with `Join: true`, `Alive: true` and a `ReplayedJournalId` close
to the leader's, then confirm the zone it landed in with the commands from step 2. If it landed in
the same zone again (the other zone had no room), make room there and repeat step 3 for it.

#### Step 5: repeat, then make the spread strict

Move the next pod only after the previous one has fully rejoined. When the FE are spread evenly (no
zone holds more than one FE more than another), switch the constraint to
`whenUnsatisfiable: DoNotSchedule` and add `minDomains: 3`, as in the section above. That rolls the
FE once more, now without getting stuck, and from then on keeps any pod that is rescheduled with a
new disk out of a zone that already has its share.

## 4. Spread CN across zones

The same constraint works for CN. Each query may then use CN in every zone, so data moves between
zones during the query; cloud providers bill that traffic, and it adds latency. If either matters,
use CN Groups instead (section 5).

For the cluster's own CN, under `spec.phoenixAICnSpec` (Helm: `phoenixai.phoenixAICnSpec`):

```yaml
    topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            # <cluster>-cn
            app.phoenixai.ownerreference/name: kube-anywhere-cn
```

For a warehouse, under `spec.template` of the `PhoenixAIWarehouse` (the `warehouse` chart's
`spec.topologySpreadConstraints`), with the warehouse's StatefulSet name,
`<warehouse>-warehouse-cn`:

```yaml
        labelSelector:
          matchLabels:
            app.phoenixai.ownerreference/name: wh-prod-warehouse-cn
```

`ScheduleAnyway` is usually the right choice for CN: an uneven spread costs some capacity in one
zone, which is better than CN pods left `Pending`.

The spread is best effort as the CN count changes. Pods an autoscaler adds are scheduled with the
constraint, but under `ScheduleAnyway` it is only a preference. Scaling in ignores it entirely: the
StatefulSet removes the highest-numbered pods wherever they run, and the remaining pods are not moved.
After scaling, check the placement with the commands from section 3 if the balance matters to you.

## 5. One CN Group per zone

A [CN Group](./deploy_cn_group_howto.md) is a complete set of CN inside a warehouse, and the FE runs
each query entirely inside one group. Pin one group to each zone and every query stays inside one
zone: no cross-zone traffic during the query. If a zone goes down, the FE stops sending new queries to
the group that has no live nodes, and clients keep using the same warehouse name.

> **CN Groups need operator 2.1.0 or later.** Earlier operators do not reconcile `PhoenixAICnGroup`
> resources. On an older operator, spread the CN pods instead (section 4).

Each group is pinned with a `nodeSelector`:

```yaml
apiVersion: phoenixdata.ai/v1
kind: PhoenixAICnGroup
metadata:
  name: wh-prod-az-a
  namespace: phoenixai
spec:
  phoenixAICluster: kube-anywhere
  phoenixAIWarehouse: wh-prod
  phoenixAICnSpec:
    replicas: 3
    nodeSelector:
      topology.kubernetes.io/zone: us-east-1a
    # image, resources, configMapInfo, ... as in the CN Groups guide
```

Create one such group per zone, differing only in the name and the zone. CN Groups need the
Enterprise edition and a recent enough CN image and FE; the
[CN Groups guide](./deploy_cn_group_howto.md) lists the requirements and has a complete two-zone
example, in both CR and Helm form.

**The owner's own CN form one more group.** The CN pods of the warehouse (or, for the
`default_warehouse`, of the cluster) the groups attach to stay in the builtin group
`_builtin_cngroup_0_`, and the FE can send queries to that group too. If those pods are spread over
several zones, a query sent to the builtin group crosses zones. To keep every query inside one zone,
pin the owner's CN to a single zone as well (section 6, minding its warning about existing PVCs), so
the builtin group becomes one more single-zone group.

Size each group so that the groups left after losing one zone can carry the load: with two zones,
each group alone must be able to serve the warehouse.

## 6. Pin a component to one zone

To keep a component in a single zone, set a `nodeSelector` on its spec:

```yaml
  phoenixAICnSpec:
    nodeSelector:
      topology.kubernetes.io/zone: us-east-1a
```

Use `affinity.nodeAffinity` instead when a pod may run in any one of several zones.

**On a running component, check its PVCs first.** Adding the selector rolls the pods, and a pod whose
disk is in another zone can then run nowhere: its volume requires the old zone and the selector the
new one, so it stays `Pending`, and a one-replica FE is down until you revert. Before adding the
selector, confirm that every PVC of the component is bound in the target zone:

```bash
kubectl get pv -o custom-columns='CLAIM:.spec.claimRef.name,PINNED-TO:.spec.nodeAffinity.required.nodeSelectorTerms[*].matchExpressions[*].values'
```

For a cloud disk, `PINNED-TO` shows its zone. A local disk shows the node it lives on instead.

If some are not, move those pods first: for FE, with the procedure in
[Move the FE pods of an existing cluster](#move-the-fe-pods-of-an-existing-cluster); for CN, by
deleting the pod's PVCs and then the pod, so that it comes back on a new disk.

## 7. When a zone goes down

- **Pods with PVCs stay there.** Their disks are in that zone, so Kubernetes cannot start them
  anywhere else. They come back when the zone does. Do not force-delete them expecting them to move:
  a new pod would still need the same disk. This covers FE pods, whose metadata is on a PVC by
  default, and CN pods that have persistent volumes.
- **Pods without PVCs can move, but not on their own.** CN runs without a PVC unless you configure
  one (by default its log is an `emptyDir`), so a replacement could run in a zone that is still up.
  The StatefulSet only creates that replacement once the old pod object is gone, and Kubernetes keeps
  a pod on an unreachable node until the node is deleted or the pod is force-deleted. Force-delete
  only when you are sure the node is down rather than just cut off: otherwise two CN with the same
  identity can end up running.
- **FE** keeps serving as long as a majority of its replicas is in the zones that are still up.
- **Spread CN** (section 4): the CN in the other zones keep serving. Queries that were running on
  the lost CN at that moment can fail and need retrying.
- **CN Groups** (section 5): the FE sends new queries to the groups whose nodes are alive.

The PodDisruptionBudgets the operator creates limit voluntary evictions such as node drains; they do
not prevent a zone outage. See
[Kubernetes Node Maintenance and PodDisruptionBudget](../Operate/node_maintenance_and_pdb_howto.md).
