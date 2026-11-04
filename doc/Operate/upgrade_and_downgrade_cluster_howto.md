# Upgrade and Downgrade a Cluster

PhoenixAI requires its components to change version in a fixed order:

- **Upgrade: CN first, then FE.** CN is backward compatible with an older FE; an FE that is newer than
  its CN is not supported.
- **Downgrade: FE first, then CN.** The mirror image of the rule above.

The operator enforces this order for you. You change the image versions in the `PhoenixAICluster`
(and in any `PhoenixAIWarehouse` or `PhoenixAICnGroup`) in one apply, and the operator rolls the
components in the right sequence, waiting for one to finish before it starts the other.

## What the operator does

Before it writes a StatefulSet whose image **version** changed, the operator asks FE which version
every node is actually running (`SHOW FRONTENDS` and `SHOW COMPUTE NODES`) and checks one rule:

| Component being written | Rule                                                                  |
|-------------------------|-----------------------------------------------------------------------|
| FE                      | the new FE version must not be **higher** than any running compute node |
| CN (cluster, warehouse or CN group) | the new CN version must not be **lower** than any running FE  |

If the rule does not hold yet, the write is postponed and retried on the next reconcile. Services,
configuration and the autoscaler object keep being reconciled. The postponed write is the whole
StatefulSet, though, so a replica count that changes in the meantime (from an autoscaler or from your
own edit) waits with it and is applied together with the new image.

Put together, the two rules produce the required order without you doing anything:

- **Upgrade FE and CN together**: CN rolls first. FE waits until every compute node reports the new
  version, then rolls.
- **Downgrade FE and CN together**: FE rolls first. CN waits until every FE reports the old version.
- **Resume an interrupted upgrade** (CN already new, FE still old): FE rolls right away.
- **Roll back the FE change while CN is still rolling**: allowed at once; nothing to wait for.

The rule is also applied to the spec itself, before anything runs: the FE image version must not be
higher than the CN image version of the cluster, of any warehouse attached to it, or of any CN group
attached to it. **This includes CN groups scaled to 0 replicas.** A parked group with an old image
would register old nodes into a new FE the moment you scale it out, so raise its image together with
the others (this rolls nothing, there are no pods).

The operator compares the **version** in the image tag (`4.1.16`, `4.1.16-ee`, `4.1.16-ee-4a26e40` are
all version 4.1.16). Changes that keep the image tag, such as environment variables, resources or
configuration, roll FE and CN in parallel exactly as before. Scaling FE in or out by hand, or CN by
hand or through its autoscaler, is not checked against the other side either. It pauses only while
that StatefulSet also has an image version change that is being held: when CN waits for FE during a
downgrade, when FE waits for the compute nodes during an upgrade, or on either side when the
operator cannot reach FE or log in to it. While it pauses, any change to that StatefulSet's replica
count waits too, scaling in as well as out, and is applied together with the version change once it
is let through. If you need to change capacity around an upgrade or a downgrade, do it before you
start or after it finishes.

When the tag changes but the versions cannot tell which way it goes, the change is ordered **like an
upgrade: CN first, then FE**. This covers another build of the same version (`4.1.0-0712` →
`4.1.0-0710`) and a tag without a version on either side (`latest`, `main`, a digest, a private build
name such as `4.1.0.0712`): a change to such a tag, and a change from one back to a versioned tag
(`main` → `4.1.0`). If the build you move away from is in fact newer than the target, that step is
really a downgrade and CN-first is the wrong order; use the override annotation for it. CN is written
right away, except that a CN moving from a tag without a version to a versioned one is still held while
FE runs a higher version. FE waits until the StatefulSet of the cluster's CN, of every attached
warehouse and of every attached CN group carries its new image and has finished rolling (all pods
ready, rollout complete). When the new FE tag has a version (`4.1.0-0710`, or `main` → `4.1.0`),
the spec rule above is checked first, so a compute owner whose image is below it, parked groups
included, is reported as `InvalidImageOrder:` rather than waited for.

In a version change, a version that cannot be read (a node FE reports as `main-…`, or a compute owner
whose tag has no version) is simply not compared.

## What you see while it waits

The wait is reported in the **component** status of the object whose write is postponed, under a
`RolloutOrderBlocked:` prefix, and the component phase is `reconciling`:

```bash
kubectl get pac <cluster> -n <namespace> -o jsonpath='{.status.phoenixAIFeStatus.reason}{"\n"}'
# RolloutOrderBlocked: FE target 4.2.0 must not be higher than any running compute node; waiting for cn-1.…=4.1.16
# RolloutOrderBlocked: the image versions cannot order this change, so it is ordered like an upgrade: FE waits until the compute nodes of this cluster have rolled out

kubectl get paw <warehouse> -n <namespace> -o jsonpath='{.status.reason}{"\n"}'
kubectl get pacg <cngroup>  -n <namespace> -o jsonpath='{.status.reason}{"\n"}'
```

The second FE reason above, for a change ordered like an upgrade, is the same text for the whole
wait. To see how far the compute nodes are, look at their StatefulSets
(`kubectl get sts -n <namespace>`).

A spec that breaks the rule is reported the same way with an `InvalidImageOrder:` prefix. On FE it
names the compute owner whose image is too low:

```text
InvalidImageOrder: FE target 4.2.0 is higher than the image of PhoenixAICnGroup az-a=4.1.16; FE must never be newer than any compute node, raise those images first (an owner with 0 replicas must be raised too)
```

The same rule is checked from the compute side, against the FE image in the cluster spec rather than
the version FE runs right now. Taking CN, a warehouse or a CN group below the cluster's FE image, or
creating a warehouse or CN group below it, is reported on that object and its write is postponed, even
while FE is still rolling towards that image and reports the old version:

```text
InvalidImageOrder: CN target 4.1.5 is lower than the FE image 4.1.6 of PhoenixAICluster <cluster>; FE must never be newer than any compute node, so raise this image to at least 4.1.6, or take FE back first
```

A compute upgrade that is still below the FE image is not reported: it moves towards the rule.

The operator does **not** emit Kubernetes events for either state. Waiting is the normal, temporary
condition of a combined upgrade, not an error. The reason disappears as soon as the write goes through.

## Warehouses in their own Helm releases

Changing every image "in one apply" is not possible when a warehouse is a Helm release of its own:
the cluster comes from the `kube-anywhere` (or `phoenixai`) release, each warehouse from a `warehouse`
release, and each `helm upgrade` changes only its own. Then the order of the releases matters:

| Change                     | First                                                   | Then                                                    |
|----------------------------|---------------------------------------------------------|---------------------------------------------------------|
| Upgrade (higher version)   | every `warehouse` release, its `cnGroups` tags included | the cluster's release                                   |
| Downgrade (lower version)  | the cluster's release                                   | every `warehouse` release, its `cnGroups` tags included |

A CN group declared in a warehouse's `cnGroups` does not follow the warehouse's image: each entry
carries its own `image.tag`, inherits nothing from the warehouse's `spec`, and no chart default
moves it. Change every entry's tag in the warehouse step yourself, groups at 0 replicas included.

In that order no release is held up by another. Within the cluster's own release the usual order
still applies (on an upgrade FE waits until the cluster's CN has rolled), but FE never stops on an
`InvalidImageOrder` that names a warehouse or a CN group.

The other order is not refused, it waits. Upgrade the cluster's release first and its CN rolls, but FE
stays on the old version, reporting `InvalidImageOrder: FE target <version> is higher than the image of
PhoenixAIWarehouse <warehouse>=<version>`, until you upgrade that warehouse's release; FE then rolls by
itself. Downgrade a warehouse first and its write is held with `InvalidImageOrder: CN target <version>
is lower than the FE image <version>` until the cluster's FE has been taken back.

This also applies when you never set an image tag yourself: a new chart version that changes the
default image tag of both charts moves every release to its own chart's default, release by release,
as you run `helm upgrade` with your values file. CN group tags are the exception, since you always set
them: they stay where they are, and FE then waits on the group (`... the image of PhoenixAICnGroup
<group>=<version>`) until you raise it. To see whether FE is waiting:

```bash
kubectl -n <namespace> get pac <cluster> -o jsonpath='{.status.phoenixAIFeStatus.reason}{"\n"}'
```

## When the operator cannot ask FE

The check needs a working SQL connection to FE, using the root password in the FE spec (the `MYSQL_PWD`
entry of `spec.phoenixAIFeSpec.feEnvVars`, which the Helm chart injects when `initPassword` is enabled;
every operator login to FE uses it, see [change the root password](../Configure/change_root_password_howto.md)). When FE
cannot be reached, or the password is rejected, the operator cannot prove the rule and therefore
**postpones the write**, saying so in the reason:

```text
RolloutOrderBlocked: cannot verify runtime versions (dial tcp …: connection refused); fix FE first, or set annotation starrocks.com/skip-rollout-order-check="true" on PhoenixAICluster <name> to override
RolloutOrderBlocked: authentication to FE failed (Error 1045 …); the operator logs in with the MYSQL_PWD env var of the FE StatefulSet (spec.phoenixAIFeSpec.feEnvVars of the PhoenixAICluster), make sure it is the current root password, or set annotation …
```

If you changed the root password, update the `MYSQL_PWD` of the FE spec (or the Secret it references) first. If FE is down and
the fix is itself an FE image change (for example, rolling back an FE upgrade that failed to start),
use the override below.

## Overriding the check

Add this annotation to the object whose StatefulSet write you want to let through unchecked:

```bash
kubectl annotate pac <cluster> -n <namespace> starrocks.com/skip-rollout-order-check="true"
```

It works on `PhoenixAICluster`, `PhoenixAIWarehouse` and `PhoenixAICnGroup`, and only affects that
object's own writes. Remove it once the cluster is healthy again:

```bash
kubectl annotate pac <cluster> -n <namespace> starrocks.com/skip-rollout-order-check-
```

There is no operator-wide switch: the annotation is deliberately the only way to bypass the check.

## Notes

- **Changes to or from an image tag without a version, and another build of the same version**, are rolled CN first, then
  FE (see above). For these, FE waits on the compute StatefulSets themselves, so a CN StatefulSet that
  never finishes rolling (a pod that cannot start, or the `OnDelete` update strategy) holds FE until it
  does, or until you add the override annotation.
- **`spec.waitForFullRollout`** keeps its existing meaning: when set, BE/CN changes wait for the FE
  StatefulSet to finish rolling, for every kind of change. It is independent of the version ordering
  described here, and it now holds in the very reconcile that changes FE as well (it used to let a
  CN change through in that one pass).
- **Load on FE**: the operator queries FE only while a version change is pending (a change ordered
  like an upgrade reads the StatefulSets and sends no query at all), at most once every
  10 seconds per cluster, and marks its statements with `/* phoenixai-operator */` so they can be
  filtered in the FE audit log.
