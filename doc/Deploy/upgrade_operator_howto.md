---
sidebar_label: Upgrade the operator
sidebar_position: 12
---

# Upgrade the Operator

This guide explains how to upgrade **only the operator** — the controller that reconciles the CRDs —
to a newer version. There are two paths, depending on how the operator was installed:

- **Path A — raw manifest / `kubectl`**: you `kubectl apply`-ed an `operator.yaml`.
  → apply the new CRDs, then re-apply the new `operator.yaml`.
- **Path B — Helm**: you manage the operator through a Helm release.
  → apply the new CRDs, then `helm upgrade`.

It is **not** a data-plane (FE/CN) upgrade. To upgrade the StarRocks/PhoenixAI engine images, see
the "Upgrade PhoenixAI Cluster" section of
[Deploy PhoenixAI With Operator](./install_with_kubectl.md) and
[Deploy Warehouse](./deploy_warehouse_howto.md) instead.

The same procedure applies to the **community StarRocks operator** and the **PhoenixAI operator** —
they are the same chart family; only the names, registries, and values keys differ:

| | Community (StarRocks) | PhoenixAI |
| --- | --- | --- |
| Helm chart | `kube-starrocks` (or the `operator` subchart) | `kube-anywhere` (or the `anywhere-operator` subchart) |
| Operator image | `starrocks/operator` | `…/enterprise/anywhere-operator` |
| Operator values key | `starrocksOperator.*` | `phoenixAIOperator.*` |
| `operator.yaml` | StarRocks release — **bundles the CRDs** | PhoenixAI release — **CRDs shipped separately** |
| Helm repo | `https://starrocks.github.io/starrocks-kubernetes-operator` | `https://celerdata.github.io/phoenixai-kubernetes-operator` |

> Migrating from the community operator to PhoenixAI? Community releases **v1.11.0 through v1.11.8**
> can migrate directly (v1.11.8 saves manual steps if you run warehouses); follow
> [Migrating from the open-source StarRocks operator to PhoenixAI](../Deploy/migrate-from-starrocks-howto.md).
> Only a community operator older than v1.11.0 has to be upgraded first, into that range, with this
> guide.
>
> Running a **CelerData-era enterprise** operator (`kube-celerdata` release or `celerdata.com/v1`
> CRs, up to v1.11.8)? The same applies: there is **no in-place `helm upgrade`** to v2.0.0 — the
> chart, CRD group, and kinds were all renamed. Follow the same
> [migration guide](../Deploy/migrate-from-starrocks-howto.md); its converter auto-detects CelerData-era
> input, and your data and cluster identity are preserved.
>
> Staying on v1.x for now? The v1.x `celerdata` and `kube-celerdata` charts are no longer listed in
> the Helm repository, so `phoenixai/kube-celerdata` does not resolve. Upgrade within v1.x from the
> release archive instead, for example
> `helm upgrade <release> https://github.com/CelerData/phoenixai-kubernetes-operator/releases/download/v1.11.8/kube-celerdata-1.11.8.tgz`.
> v1.11.8 is also the release to be on **before** migrating if you keep warehouses with the
> `starrocks.com/skip-fe-cleanup` annotation; see [Warehouses](../Deploy/migrate-from-starrocks-howto.md#warehouses).

## What an operator upgrade does (and does not do)

- It replaces only the **operator Deployment** — normally only the operator pod restarts.
- **In the common case it does not restart your FE/CN pods**: the data plane keeps serving and
  reconciliation only pauses for the few seconds the new operator takes to start.
- **It can, however, trigger a data-plane rolling restart.** If the new operator version renders the
  FE/CN StatefulSet pod template differently from the old one (e.g. a changed default, label,
  annotation, or env var), reconciliation updates the StatefulSet's pod template, and that rolls the
  affected FE/CN pods — a normal, one-pod-at-a-time StatefulSet rolling update. Check the release
  notes, and if a pod-template change is expected, plan the upgrade during a maintenance window.
- **Image version changes are ordered automatically.** Once the new operator runs, changing the FE and
  CN image versions in one apply no longer rolls both at the same time: the operator rolls CN before FE
  on an upgrade and FE before CN on a downgrade, and reports what it is waiting for in the component's
  `status.reason`. See [Upgrade and Downgrade a Cluster](../Operate/upgrade_and_downgrade_cluster_howto.md).
  The operator upgrade itself does not trigger this; it only applies to the next image change you make.
  If your warehouses are `warehouse` releases of their own and the new chart version also changes the
  default FE/CN image, upgrade those releases before the cluster's, raising each `cnGroups[].image.tag`
  yourself (CN groups do not follow chart defaults): see
  [Warehouses in their own Helm releases](../Operate/upgrade_and_downgrade_cluster_howto.md#warehouses-in-their-own-helm-releases).
- **You must apply the new CRDs yourself.** Each release usually adds new spec fields, but neither
  `helm upgrade` nor the PhoenixAI `operator.yaml` updates the CRDs — applying a newer operator without its CRDs
  leaves the new fields unrecognized. Applying a CRD is safe and does not disrupt running objects.
- You can **upgrade across versions directly** — there is no need to step through intermediate
  releases. Set `VERSION` to the target version and follow the path below.

The commands below use **upgrading to v2.1.0 as a concrete example** — replace `2.1.0` (and the
`VERSION` value) with your target version. Set these variables for your environment first:

```bash
VERSION=2.1.0              # the target operator version
OPNS=phoenixai             # the namespace the operator runs in
OP=kube-anywhere-operator  # operator Deployment name
                           # (older chart default: kube-phoenixai-operator;
                           #  community: kube-starrocks-operator)

# Not sure of the name/namespace? Find them:
kubectl get deploy -A | grep -E 'kube-(anywhere|phoenixai|starrocks)-operator'
helm list -A              # if Helm-managed, shows the release + its namespace
```

---

## Path A — raw `operator.yaml` / `kubectl`

Two steps: apply the new CRDs, then re-apply the new release's `operator.yaml`, which carries both
the new operator image and the RBAC the new version needs.

```bash
VERSION=2.1.0

# 1. Replace the CRDs (helm/kubectl never upgrade these automatically). Use `replace`, not `apply`:
#    `apply` copies the whole object into the kubectl.kubernetes.io/last-applied-configuration
#    annotation, which cannot exceed 262144 bytes. The PhoenixAICluster CRD is ~242 KB — under the
#    limit, but with less than 8% to spare, and only because these CRDs are generated with field
#    descriptions stripped (see the FAQ in install_with_kubectl.md). `replace` does
#    not write that annotation, so it never depends on that margin. The cluster CRD always exists
#    on an upgrade, so `replace` fits.
kubectl replace -f https://github.com/CelerData/phoenixai-kubernetes-operator/releases/download/v2.1.0/phoenixdata.ai_phoenixaiclusters.yaml

#    The warehouse and CN group CRDs are the exception: a release adds a CRD only once (the
#    warehouse CRD in v2.0.0, the CN group CRD in v2.1.0), and neither the `operator.yaml` nor
#    `helm upgrade` (which never installs a chart's crds/) creates it, so on an operator upgraded
#    from before that release it does not exist yet and `replace` alone fails with NotFound.
#    `create` first, fall back to `replace`. At ~114 KB each, both are well clear of the annotation
#    limit either way.
kubectl create -f https://github.com/CelerData/phoenixai-kubernetes-operator/releases/download/v2.1.0/phoenixdata.ai_phoenixaiwarehouses.yaml 2>/dev/null \
  || kubectl replace -f https://github.com/CelerData/phoenixai-kubernetes-operator/releases/download/v2.1.0/phoenixdata.ai_phoenixaiwarehouses.yaml
kubectl create -f https://github.com/CelerData/phoenixai-kubernetes-operator/releases/download/v2.1.0/phoenixdata.ai_phoenixaicngroups.yaml 2>/dev/null \
  || kubectl replace -f https://github.com/CelerData/phoenixai-kubernetes-operator/releases/download/v2.1.0/phoenixdata.ai_phoenixaicngroups.yaml

# 2. Re-apply the new release's operator.yaml: it updates the operator image AND its ClusterRole.
#    Download it first and carry over how your operator actually runs (namespace — the manifest
#    hardcodes `phoenixai` —, resources, args, imagePullSecrets, …); the released manifest carries
#    no customization.
curl -fLO https://github.com/CelerData/phoenixai-kubernetes-operator/releases/download/v${VERSION}/operator.yaml
kubectl apply -f operator.yaml
kubectl -n "$OPNS" rollout status deploy/"$OP"
```

> Do not upgrade on this path with `kubectl set image` alone. It changes only the image, and a new
> release can need RBAC the old ClusterRole does not grant. v2.1.0 does: it adds the
> `PhoenixAICnGroup` CRD and the rules to watch it, so a 2.0.x operator moved to the v2.1.0 image
> with `set image` keeps crash-looping with `unable to set up CN group reconciler … phoenixaicngroups
> … forbidden` (the old pod keeps serving, but the upgrade never completes). If you hit this,
> re-apply `operator.yaml` as in step 2.

---

## Path B — Helm

A Helm install of the operator is one of these two layouts — upgrade with the matching command:

```bash
# combined parent chart — operator + cluster in one release:
helm install <release> phoenixai/kube-anywhere -n <ns> ...
# or the operator subchart on its own (operator managed separately from clusters):
helm install <release> phoenixai/anywhere-operator -n <ns> ...
```

Then upgrade in two steps: apply the new CRDs (Helm will not), then `helm upgrade`.

```bash
VERSION=2.1.0
helm repo update phoenixai            # or: helm repo update starrocks-community

# 1. Replace the CRDs (helm upgrade does NOT touch CRDs from a chart's crds/ directory). Use `replace`,
#    not `apply` — `apply` copies the whole object into the 262144-byte
#    kubectl.kubernetes.io/last-applied-configuration annotation, and the PhoenixAICluster CRD sits
#    at ~242 KB against that limit (see the FAQ in install_with_kubectl.md).
#    `replace` does not write that annotation. The cluster CRD already exists, so `replace` fits.
kubectl replace -f https://github.com/CelerData/phoenixai-kubernetes-operator/releases/download/v2.1.0/phoenixdata.ai_phoenixaiclusters.yaml

#    The warehouse and CN group CRDs are the exception: a release adds a CRD only once (the
#    warehouse CRD in v2.0.0, the CN group CRD in v2.1.0), and neither the `operator.yaml` nor
#    `helm upgrade` (which never installs a chart's crds/) creates it, so on an operator upgraded
#    from before that release it does not exist yet and `replace` alone fails with NotFound.
#    `create` first, fall back to `replace`. At ~114 KB each, both are well clear of the annotation
#    limit either way.
kubectl create -f https://github.com/CelerData/phoenixai-kubernetes-operator/releases/download/v2.1.0/phoenixdata.ai_phoenixaiwarehouses.yaml 2>/dev/null \
  || kubectl replace -f https://github.com/CelerData/phoenixai-kubernetes-operator/releases/download/v2.1.0/phoenixdata.ai_phoenixaiwarehouses.yaml
kubectl create -f https://github.com/CelerData/phoenixai-kubernetes-operator/releases/download/v2.1.0/phoenixdata.ai_phoenixaicngroups.yaml 2>/dev/null \
  || kubectl replace -f https://github.com/CelerData/phoenixai-kubernetes-operator/releases/download/v2.1.0/phoenixdata.ai_phoenixaicngroups.yaml

# 2. helm upgrade to the new chart version, re-passing the same values file you installed with
#    (use the chart you installed: kube-anywhere for combined, operator for the subchart).
helm upgrade <release> phoenixai/kube-anywhere --version "$VERSION" -n "$OPNS" -f your-values.yaml
kubectl -n "$OPNS" rollout status deploy/"$OP"
```

---

## Verify

Confirm the operator is on the new version, then confirm the cluster is unaffected:

```bash
kubectl -n "$OPNS" get deploy "$OP" -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'  # new version
kubectl -n "$OPNS" rollout status deploy/"$OP"                                                     # operator Running
```

An operator upgrade does not change cluster membership. Confirm the data plane the same way as in the
migration guide's [Verify](../Deploy/migrate-from-starrocks-howto.md#verify) section (`SHOW FRONTENDS` / `SHOW BACKENDS` show the same nodes `Alive = true`).
