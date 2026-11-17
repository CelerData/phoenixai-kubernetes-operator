# Expand the Persistent Volumes of FE / CN

PhoenixAI FE / CN run as StatefulSets, and a StatefulSet's `volumeClaimTemplates` are immutable
after creation — so you cannot grow a component's disk just by editing its size and re-applying.
This feature lets the operator do it for you: it expands the underlying PersistentVolumeClaims (PVCs)
**in place**, online, without deleting or recreating the StatefulSet or restarting the pods.

## Prerequisites

1. **A StorageClass that supports expansion.** The volumes you want to grow must use a StorageClass
   with `allowVolumeExpansion: true`, and the CSI driver must support **online** resize. Check:

   ```bash
   kubectl get storageclass <name> -o jsonpath='{.allowVolumeExpansion}{"\n"}'   # must be true
   ```

2. **The feature must be enabled on the operator** (next section).

## Enable the feature

The feature is gated by a global operator switch (default `false`). Enable it via Helm:

```yaml
# values.yaml
operator:
  phoenixAIOperator:
    enablePVCExpansion: true
```

The switch is **global to the operator process** and takes effect after the operator restarts; it
cannot be toggled per cluster. While off, the operator behaves exactly as before (volume size changes
are rejected by the Kubernetes API server).

## Expand a volume

Increase the `storageSize` of the relevant volume in your `PhoenixAICluster` (or `PhoenixAIWarehouse`)
and apply. For example, growing the CN data volume:

```yaml
spec:
  phoenixAICnSpec:
    storageSpec:
      name: cn
      storageSize: 200Gi   # was 100Gi
```

What the operator does:

- expands the matching PVCs in place (`<volume>-<statefulset>-<ordinal>`, e.g. `cn-data-<cluster>-cn-0`);
- never deletes or recreates the StatefulSet, and (on online storage) never restarts the pods;
- applies the new size to **new** pods too, so scaling out (including HPA) gives correctly-sized disks.

> The StatefulSet's `volumeClaimTemplates` intentionally stay at the **original** size — the PVC is
> the source of truth. This mismatch is expected and is not a bug.

This covers FE, CN, and the CN of a `PhoenixAIWarehouse`. (`feProxy` is stateless and has no volume.)

## Watch the progress

Expansion has two phases (block device, then filesystem). Watch the PVC:

```bash
kubectl get pvc -n <namespace>
kubectl describe pvc <pvc-name> -n <namespace>     # conditions: Resizing / FileSystemResizePending
```

Expansion is complete when the PVC's `status.capacity` reaches the requested size. The operator also
summarizes in-progress expansion on the component status:

```bash
kubectl get phoenixaicluster <name> -n <namespace> \
  -o jsonpath='{.status.phoenixAICnStatus.reason}{"\n"}'
# e.g. "volume expansion in progress: cn-storage-data-...-cn-0 (expected 200Gi, current 100Gi, FileSystemResizePending)"
```

The `reason` clears automatically on the operator's **next periodic reconcile** after every volume
has caught up — within about two minutes (the operator resyncs watched resources every 2 minutes; it
does not watch PVCs directly, so the summary is not refreshed the instant `status.capacity` catches
up). A `reason` that still shows an in-progress expansion is stale, not stuck, as long as the PVC
itself already reports the new capacity.

## Rules and limitations

- **No shrinking.** Cloud disks cannot shrink. If the CR `storageSize` is **smaller** than the live
  PVC (including the case where you previously expanded a PVC by hand), the operator does not shrink
  it and the reconcile reports an error such as *"PVC X is 200Gi but the CR requests 100Gi; the
  operator does not shrink volumes — set the CR storageSize to at least 200Gi."* Fix it by setting the
  CR `storageSize` to at least the current PVC size.
- **Only size changes.** Changing `storageClassName` or `accessModes` on an existing volume is not
  supported and is rejected. Adding a **new** volume to a cluster that already exists is likewise
  rejected — a StatefulSet's volume set is fixed at creation, so the operator cannot attach it.
  (Removing a volume has no effect, for the same reason.) Only growing existing volumes is supported.
- **`storageClassName` left unset** means the cluster default StorageClass — that is fully supported.

## Storage that requires detach (offline expansion)

Some storage (e.g. older Azure Disk, vSphere) cannot expand while the volume is attached to a running
pod. There the PVC stays in `FileSystemResizePending` and `status.capacity` never catches up. **The
operator does nothing destructive** — it will not delete the pod or StatefulSet — so you must complete
the expansion with a planned, brief downtime of the affected component:

1. After editing the CR `storageSize`, confirm the PVC `spec` already shows the new size but
   `status.capacity` is stuck.
2. Take the volume's pod offline to trigger a detach — `kubectl delete pod` is not enough (the
   StatefulSet re-attaches immediately). Scale the component (or that ordinal) down.
3. While detached, the block-device expansion completes (`status.capacity` advances at the block level).
4. Scale the component back up; on mount the filesystem resize finishes and `status.capacity` fully
   catches up.

The operator never intervenes during this process; it only reflects the PVC status.
