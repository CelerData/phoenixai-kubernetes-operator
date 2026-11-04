---
sidebar_label: CN Groups
sidebar_position: 8
---

# Deploy CN Groups

A CN Group is a second layer inside a warehouse. One group is one complete, independent set of
compute nodes: it has its own mapping from data shards to CN, and its own local data cache. The FE
picks one group per query and runs that entire query inside it, so a query never shuffles across
groups.

The usual reason to create groups is availability-zone locality: put one group in each zone, and
every query stays inside one zone. If a whole zone goes down, the FE stops sending new queries to
the group that has no live nodes, and clients keep using the same warehouse name throughout.

Use a CN Group when you want several interchangeable copies of the same compute pool behind one
warehouse name. Use a separate warehouse instead when you want workload isolation, separate
privileges, or separate suspend and billing: groups share all of those with their warehouse.

## 1. Prerequisites

1. A shared-data PhoenixAI Enterprise cluster. CN Groups do not exist in the open-source version.
2. **A CN image >= `4.1.6-ee`** (or the `26.2.1` series), on the group **and** on the cluster or
   warehouse it attaches to. The group support lives in the image's `cn_entrypoint.sh`, so this is a
   separate requirement from the FE version below, and the two can drift apart.

   The operator refuses the group before it creates anything if either image tag shows a version
   older than that, and `status.reason` names the version it read and which image it came from. Both
   images matter: an old image on the group makes its pods register into the builtin group, so the
   group would run without ever serving its own queries; an old image on the cluster or warehouse is
   worse, because once a second group exists that object can no longer register any *new* CN pod, so
   scaling it out would fail.

   A tag the operator cannot read as a version (`latest`, a digest, your own build tag) is allowed
   through rather than guessed at, and so is any image on a spec that sets `command`, since that
   replaces the image's entrypoint and the tag no longer describes what runs. If such an image turns
   out to be too old, the group still comes up but its pods register into the builtin group instead
   of their own; `SHOW NODES FROM WAREHOUSE <warehouse>` shows where each pod landed in its
   `CNGroupName` column.
3. An FE that advertises the `multi-cngroup` feature. The operator checks this before it creates
   anything and reports `status.phase: failed` otherwise.
4. The `PhoenixAICnGroup` CRD, present **before the operator started**. The operator chart ships it
   next to the cluster and warehouse CRDs, but `helm upgrade` never installs a chart's `crds/`
   directory, so an upgraded operator needs the CRD applied by hand and then a restart.
   [Upgrade the operator](./upgrade_operator_howto.md) applies it before the new operator starts;
   if you skipped that, take the CRD from the release your operator runs (v2.1.0 below):

   ```bash
   kubectl get crd phoenixaicngroups.phoenixdata.ai
   # if missing:
   kubectl create -f https://github.com/CelerData/phoenixai-kubernetes-operator/releases/download/v2.1.0/phoenixdata.ai_phoenixaicngroups.yaml
   kubectl rollout restart deployment/kube-anywhere-operator -n <operator namespace>
   ```

5. If you are spreading groups across zones, your nodes need the standard
   `topology.kubernetes.io/zone` label.

## 2. What a group costs you

Creating a group does not restart anything. Not the FE, not the other groups, and not the CN pods of
the cluster or warehouse that owns the new group.

There is one lasting trace, and it arrives quietly. Once a warehouse has more than one CN group, its
owner's own CN pods have to name the builtin group explicitly, so the operator adds
`KUBE_STARROCKS_CNGROUP=_builtin_cngroup_0_` to their pod template. It does not add it straight
away, because that would roll every one of those pods for something you did not ask for. Instead it
waits for the next time that StatefulSet is written anyway and puts the variable in the same update.
That next write is whatever you would have done regardless: changing the CR, rolling out a new
image, an autoscaler moving the replica count, or the StatefulSet being recreated.

So the pods that are running right now keep running, and the ones that appear later are born with
the variable. Pods that were already registered do not need it in the meantime: they re-register
under their existing identity when they restart, whatever groups the warehouse has.

The variable is never taken away again, not when you delete the last group and not when the CN Group
CRD is uninstalled. Keeping it costs nothing, because naming the builtin group explicitly is correct
whatever groups the warehouse has. To get a pristine pod template back you would have to recreate
the workload.

One consequence worth knowing: between creating a group and that next write, the owner's CN pods
cannot be replaced by *new* ones outside of that write. In practice every way of producing a new pod
(scaling, recreating the StatefulSet) is itself a write and therefore carries the variable with it,
so this is not something you have to schedule around. If you would rather have it over with, change
anything on the owning CR and the variable lands with that rollout.

Nothing happens to the other groups, to the FE, or to any other warehouse.

## 3. Write a group as a custom resource

A group is a `PhoenixAICnGroup`. Its `metadata.name` is the group name: the operator converts `-` to
`_` to get the name the FE uses, so `wh-prod-az-a` becomes `wh_prod_az_a`.

```yaml
apiVersion: phoenixdata.ai/v1
kind: PhoenixAICnGroup
metadata:
  # At most 41 characters, starting with a lower-case letter. The operator derives the StatefulSet,
  # the services and the pod revision labels from this name, and those have their own length limits.
  name: wh-prod-az-a
  namespace: phoenixai
spec:
  # Required and immutable.
  phoenixAICluster: kube-anywhere
  # Optional and immutable. Leave it out to attach the group to the cluster's default_warehouse.
  phoenixAIWarehouse: wh-prod
  phoenixAICnSpec:
    image: us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/cn-ubuntu:4.1.6-ee
    replicas: 3
    nodeSelector:
      topology.kubernetes.io/zone: us-east-1a
    # Point at the same ConfigMap as the warehouse to share one cn.conf.
    configMapInfo:
      configMapName: wh-prod-cm
      resolveKey: cn.conf
```

**A group describes itself completely.** Nothing is inherited from the warehouse's
`spec.template` or the cluster's `spec.phoenixAICnSpec`: if the group needs a resource request, a
tolerations list, a root password or a particular `cn.conf`, write it in the group. Inheritance may
arrive as a later feature; for now the explicitness is the contract.

### A full two-zone example

Both groups below belong to the warehouse `wh-prod` and differ only in the zone they are pinned to.
Copy the pair as is and change the zones, the image and the replica count.

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
    image: us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/cn-ubuntu:4.1.6-ee
    replicas: 3
    nodeSelector:
      topology.kubernetes.io/zone: us-east-1a
    configMapInfo:
      configMapName: wh-prod-cm
      resolveKey: cn.conf
    resources:
      requests:
        cpu: 8
        memory: 32Gi
    cnEnvVars:
      # Needed whenever the cluster's root account has a password: the pod registers itself over SQL.
      - name: MYSQL_PWD
        valueFrom:
          secretKeyRef:
            name: phoenixai-root-password
            key: password
---
apiVersion: phoenixdata.ai/v1
kind: PhoenixAICnGroup
metadata:
  name: wh-prod-az-b
  namespace: phoenixai
spec:
  phoenixAICluster: kube-anywhere
  phoenixAIWarehouse: wh-prod
  phoenixAICnSpec:
    image: us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/cn-ubuntu:4.1.6-ee
    replicas: 3
    nodeSelector:
      topology.kubernetes.io/zone: us-east-1b
    configMapInfo:
      configMapName: wh-prod-cm
      resolveKey: cn.conf
    resources:
      requests:
        cpu: 8
        memory: 32Gi
    cnEnvVars:
      - name: MYSQL_PWD
        valueFrom:
          secretKeyRef:
            name: phoenixai-root-password
            key: password
```

Apply them and watch the group come up:

```bash
kubectl apply -f cn-groups.yaml
kubectl get pacg -n phoenixai
```

```text
NAME           CLUSTER         WAREHOUSE   CNGROUP        STATUS    REASON
wh-prod-az-a   kube-anywhere   wh-prod     wh_prod_az_a   running
wh-prod-az-b   kube-anywhere   wh-prod     wh_prod_az_b   running
```

Confirm in the FE that the nodes landed where you meant them to:

```sql
SHOW NODES FROM WAREHOUSE wh_prod;
```

## 4. Write a group in Helm values

Both charts take the same entry schema. In the `warehouse` chart, `cnGroups` attaches the groups to
that release's warehouse:

```yaml
x-cn-common: &cn-common
  image:
    repository: us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/cn-ubuntu
    tag: "4.1.6-ee"
  resources:
    requests:
      cpu: 8
      memory: 32Gi
  envVars:
    - name: MYSQL_PWD
      valueFrom:
        secretKeyRef:
          name: phoenixai-root-password
          key: password

cnGroups:
  - name: az-a
    replicas: 3
    nodeSelector:
      topology.kubernetes.io/zone: us-east-1a
    <<: *cn-common
  - name: az-b
    replicas: 3
    nodeSelector:
      topology.kubernetes.io/zone: us-east-1b
    <<: *cn-common
```

The CR is named `<release>-<name>`, so the entries above become `wh-prod-az-a` and `wh-prod-az-b` in
a release called `wh-prod`. The YAML anchor is how you avoid repeating the shared fields; the chart
never merges an entry with the `spec` block above it.

In the `kube-anywhere` chart the key is `phoenixai.phoenixAICnGroups`, the entries are identical, and
the groups attach to the cluster's `default_warehouse`. The CR is named `<cluster>-<name>`.

An entry that sets `config` gets its own `cn.conf` ConfigMap. An entry without `config` (or with an
empty one) shares the warehouse's (or the cluster's) ConfigMap, and therefore restarts together with
it when that config changes.

`replicas` is optional in an entry. Leave it out when an HPA or `kubectl scale` should own the
count, as [Manually scale CN groups](../Scale/manually_scale_cn_groups_howto.md) explains: the group
then starts at one replica and keeps whatever count it is
scaled to across `helm upgrade`.

## 5. Delete a group

```bash
kubectl delete pacg wh-prod-az-a -n phoenixai
```

The operator drops the group in the FE and then releases the CR. Queries already running on those
nodes fail and have to be retried by the client: there is no graceful drain, because disabling a
group does not move traffic off it.

Two ordering rules are worth knowing:

- **Delete the groups before, or together with, their warehouse.** `helm uninstall` does both at
  once and is handled: the warehouse waits for its groups and then drops itself, leaving nothing
  behind in the FE.
- **If you delete only the warehouse**, the operator keeps the warehouse in the FE rather than
  taking the still-referenced groups down with it. Each remaining group reports this in its
  `status.reason` (`the PhoenixAIWarehouse this CN group belongs to does not exist`). Delete the
  groups and the warehouse is dropped immediately; there is nothing else to do. To clean up a
  warehouse you have already orphaned, recreate and delete it, or drop it by hand with
  `DROP WAREHOUSE`.

  The warehouse's own pods stop right away, as you asked: its StatefulSet and its compute nodes go
  immediately. Only the warehouse itself lingers in the FE, and only because dropping it would take
  the groups' own FE state with it.

Never drop the builtin group (`_builtin_cngroup_0_`) by hand. It is where the cluster's and the
warehouse's own CN pods register, and without it they cannot come back after a restart.

## 6. Troubleshooting

| Symptom | Cause |
|---|---|
| `status.reason` mentions `multi-cngroup` | The FE predates CN Group support, or the cluster is not shared-data. Upgrade the FE. |
| `status.reason` says the CN image does not support CN Group, and nothing was created | An image tag reads as older than `4.1.6-ee` / `26.2.1`. The reason names the version and whether it came from the group or from the cluster or warehouse. Upgrade that image; the operator re-checks it on its periodic resync, every two minutes. |
| The pods are running, but `SHOW NODES FROM WAREHOUSE` lists them in the builtin group | The image tag could not be read as a version, so the group was allowed through, and the image turned out to predate CN Group support. Upgrade the image. |
| The group is `failed` on the name | The name must match `^[a-z][a-z0-9-]*$` and be at most 41 characters. |
| The group is `failed` on immutability | `phoenixAICluster` and `phoenixAIWarehouse` cannot change once the group is running. Delete the group and create it again. |
| `status.reason` says `phoenixAIWarehouse` names a warehouse the operator rejects | That warehouse CR is itself `failed` on its name: it resolves to `default_warehouse`, or it has the cluster's name. Point the group at a valid warehouse, or leave `phoenixAIWarehouse` empty to use `default_warehouse`. |
| Nothing happens at all, and the operator log says the CRD was not found | The CRD was installed after the operator started. Restart the operator. |
