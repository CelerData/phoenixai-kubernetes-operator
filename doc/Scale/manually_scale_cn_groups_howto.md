---
sidebar_position: 1
sidebar_label: Manually scale CN groups
---

# Manually scale CN groups

This page was [part of the CN Groups guide](../Deploy/deploy_cn_group_howto.md), which covers what a
group is and how to create one.

Each group scales on its own, and `replicas` is a scale subresource, so an HPA can target the group
directly:

```bash
kubectl scale pacg wh-prod-az-a -n phoenixai --replicas=5
```

```yaml
    autoScalingPolicy:
      minReplicas: 2
      maxReplicas: 6
```

Scaling a group in removes only that group's nodes from the FE. The cluster, the warehouse and the
other groups are untouched even though they all share one warehouse.

If you let an HPA own the replica count, leave `replicas` out of your manifest and your Helm values
from the start. The operator never writes the CR's spec, so what an HPA sets survives a re-apply
only as long as your manifest does not mention the field. Pin it and an apply that carries the value
resets the count to what you pinned. More surprisingly, removing it from a manifest that used to
carry it resets the group to one replica: `kubectl apply` and Helm 3 both send a null for a field
they stop mentioning, and the field's default comes back. (Helm 4 applies server-side and leaves the
field to whoever set it last, so there the group keeps its count; do not build on that.) The charts ship without the
key for exactly this reason.

Helm 4 has one more consequence when your values **do** set `replicas`: once the count was changed
with `kubectl scale` (or by an HPA), the next `helm upgrade` fails with a conflict on the field
(`conflict with "kubectl" with subresource "scale"`). Either remove `replicas` from your values, or
pass `--force-conflicts` to let Helm take the field back — which resets the count to the value in
your values file.

`replicas: 0` is allowed and parks the group: its pods go away, its CN Group stays in the FE, and
the FE stops sending queries to it because it has no live nodes. Set it back to bring the group
home. The same works on a `PhoenixAIWarehouse`, which is how you hand a warehouse's capacity over to
its groups entirely. Leaving `replicas` out is not the same thing: an omitted value means one
replica, because that is the field's default.

Adding nodes to an existing group redistributes that group's shards and invalidates much of its
cache. Adding a whole new group leaves the existing groups alone, which is why capacity growth is
often better expressed as another group.
