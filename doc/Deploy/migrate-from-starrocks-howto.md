---
sidebar_label: Migrate from the StarRocks operator
sidebar_position: 5
---
# Migrating from the open-source StarRocks operator to PhoenixAI

## What this does

This is the upgrade path from the open-source
[`starrocks-kubernetes-operator`](https://github.com/StarRocks/starrocks-kubernetes-operator) to
PhoenixAI Anywhere. PhoenixAI releases start at v2.0.0 under a different API group, so there is no
in-place upgrade: this procedure is how you get there.

It swaps the operator that manages your cluster. **Your data stays where it is** (the volumes are
retained and reused), the cluster keeps its name and its pods keep their addresses, and the FE and
CN images keep running exactly what they ran before. Moving those to the enterprise images is a
separate step you can take afterwards.

The cost is **a short downtime**, because the old workloads have to be deleted and recreated rather
than adopted in place. [How it works](#how-it-works) explains why.

## Does this apply to you

Three things decide it, and the first is disqualifying.

- **Shared-data clusters only.** PhoenixAI supports FE + CN clusters. A cluster running BE nodes is
  shared-nothing and cannot be migrated: the converter refuses any input carrying a BE spec
  (`starRocksBeSpec` / `starrocksBeSpec`). In values mode it also refuses input that does not state
  `enabledBe: false` explicitly, because the kube-starrocks chart defaults it to `true`. If your
  values never mention `enabledBe` but the cluster genuinely runs without BE, add `enabledBe: false`
  to the input and rerun the converter.
- **Volumes must be set to be retained.** The migration deletes the old workloads, so their volumes
  have to survive that. `Retain` is the default; [Before you start](#before-you-start) checks it.
- **The community operator must be v1.11.0 through v1.11.8.** If you run warehouses, v1.11.8 saves
  manual steps. See the version prerequisite below.

**CelerData-era clusters are covered by the same procedure and the same converter.** If your cluster
still uses the previous enterprise branding (`celerdata.com/v1` CRs, `CelerDataCluster` /
`CelerDataWarehouse`, or `kube-celerdata` Helm values), every command below applies unchanged: the
converter auto-detects the source dialect per document and maps `celerData*` keys, the
`celerdata.com` API group, and the CelerData operator image to their PhoenixAI equivalents.
Data-plane images are never touched, whichever dialect you start from. The annotation that keeps
warehouses needs the CelerData-era operator at **v1.11.8**, the enterprise release that matches
community v1.11.8; older CelerData-era operators do not understand it, so with one of those keep the
warehouses by stopping the old operator instead; see [Warehouses](#warehouses).

### Version prerequisite: community operator v1.11.0 through v1.11.8

PhoenixAI releases start at **v2.0.0** under a new API group (`phoenixdata.ai`), so there is no
in-place upgrade from either the community operator or a CelerData-era enterprise operator; this
migration is the upgrade path. You can migrate straight to any PhoenixAI release; there is no need
to go through v2.0.0 first.

The converter supports clusters managed by any community operator release from **v1.11.0** through
**v1.11.8**. Every field those releases define exists in the PhoenixAI CRDs and charts under the same
name, so nothing is dropped, and none of them names its StatefulSets, Services or volumes
differently, so the volumes are reused whichever one you run. A field your release does not have
yet (for example `waitForFullRollout`, added in v1.11.5) keeps the behavior your cluster has today.
**For the cluster itself, you do not need to upgrade the community operator first.** If you run a
release older than v1.11.0, upgrade it to a release in that range before migrating; see
[Upgrade the Operator](../Deploy/upgrade_operator_howto.md). Community releases newer than v1.11.8
have not been checked against PhoenixAI yet; do not migrate from one before they are.

**If you run warehouses and want to keep them, migrate to PhoenixAI v2.0.2 or later.** Deleting a
warehouse CR makes the operator that owns it run `DROP WAREHOUSE`, which loses the warehouse's
properties and the privileges granted on it. v2.0.2 is the first PhoenixAI release that can be told
not to, which is what keeps the warehouses if you roll back. On the old side you have two options:

- Upgrade the old operator to **v1.11.8** first: community v1.11.8 for a `StarRocksWarehouse`, the
  CelerData-era enterprise v1.11.8 for a `CelerDataWarehouse`. These are the first releases that can
  be told not to drop a warehouse. Then no manual step is needed.
- Stay on an older release. The warehouses are kept as long as the old operator is not running when
  you delete each old warehouse CR: on the Helm path it is already gone by then, and on the kubectl
  path you stop it. You then clear a finalizer by hand.

With v1.11.8, prepare the warehouses **before the old operator goes away**: on the Helm path, that is
before the first `helm uninstall`. See [Warehouses](#warehouses).

Whatever your version, check the `storageVolumes` of your cluster **before the cutover**. PhoenixAI
expects stricter values than the community CRD accepts, and do not count on the API server to stop
you: the CRDs of the 2.0.x releases (v2.0.0 through v2.0.3) still accept the values below, and
v2.1.0 and later reject them only when the converted CR is applied. Either way the cutover fails
after the old workloads are gone.

- Each `storageSize` must be a size in binary units such as `10Gi` or `512Mi`: not `10G`, and a
  positive size must not begin with `0` (write `512Mi`, not `0.5Gi`). Rewrite such a value as the
  same size in the converted output; that is safe.
- Each `name` must be a plain DNS label: lowercase letters, digits and `-`, no dots. A volume name
  is part of its PVC names, so it **cannot** be changed without losing the volume. If a name does
  not fit, do not migrate that cluster; contact support.

## The flow

1. **Check it qualifies.** Shared-data only, volumes set to be retained, community operator
   v1.11.0 through v1.11.8 (v1.11.8 saves manual steps for warehouses), `storageVolumes` values
   PhoenixAI accepts.
2. **Convert.** A converter rewrites your CR or Helm values into the PhoenixAI equivalent, keeping
   the cluster name, namespace and volume names identical. That is what makes the rest work.
3. **Put the PhoenixAI operator in place.** Back up the old operator and the old CR or values
   first: those are your rollback artifacts. If you keep warehouses with the annotation (old
   operator at v1.11.8), annotate them before this step, while the old operator still runs (see [Warehouses](#warehouses)); on the
   Helm path this step removes the old operator.
4. **Delete the old cluster object.** Downtime starts here. The volumes survive.
5. **Apply the converted CR, or install the new chart.** The new operator recreates the workloads
   under the same names, binds them to the same volumes, and the pods come back with the same
   addresses. The FE metadata recognises them and the cluster heals.
6. **Verify.** Then migrate any warehouses, and switch to the enterprise images if you want to.

**Where step 3 falls depends on your path.** On the kubectl path you install the PhoenixAI operator
alongside the old one first, so steps 3 and 4 are separate and only step 4 costs downtime. With a
single Helm release they are one action: `helm uninstall` removes the old operator and cluster
together, and installing `kube-anywhere` brings both back. With separate operator and cluster
releases you swap the operator release once, before cutting over any cluster.

There are two paths through this, depending on how the cluster is managed today. They share the
pre-flight checks, the mechanics and the verification; only the cutover differs.

- **[Path A](#path-a--kubectl--cr)** — you `kubectl apply` a `StarRocksCluster` CR directly.
- **[Path B](#path-b--helm-kube-starrocks--kube-anywhere)** — you manage the cluster with a Helm release.

## How it works

The two operators are functionally close, but their CRDs are **not** compatible and there
is **no backward compatibility**:

|             | open source                                                | PhoenixAI                                 |
| ------------- | ------------------------------------------------------------ | ------------------------------------------- |
| API group   | `starrocks.com/v1`                                         | `phoenixdata.ai/v1`                        |
| Kinds       | `StarRocksCluster` / `StarRocksWarehouse`                  | `PhoenixAICluster` / `PhoenixAIWarehouse` |
| spec fields | `starRocksFeSpec` / `…CnSpec` / `…FeProxySpec`             | `phoenixAIFeSpec` / `…`                   |
| owner label | `app.starrocks.ownerreference/name`                        | `app.phoenixai.ownerreference/name`       |

What makes a safe migration possible is that **both operators generate identical Kubernetes
object names** — they depend only on the CR name plus a component suffix:

- StatefulSet: `<cluster>-fe` / `<cluster>-cn`
- Headless (search) service: `<cluster>-fe-search` / `<cluster>-cn-search`
- PVC: `<storageVolume.name>-<statefulset>-<ordinal>` (e.g. `fe-meta-mycluster-fe-0`)
- FE-proxy: a **Deployment** `<cluster>-fe-proxy` plus an external Service — **no PVC, service** (it
  is a stateless nginx proxy). It is recreated like the StatefulSets but has nothing to preserve.

So if the PhoenixAI CR keeps the **same name, same namespace and same `storageVolume` names**,
the PhoenixAI operator recreates StatefulSets that **reuse the existing PVCs** and bring pods
back with the **same FQDNs** — the FE metadata still recognises every FE/CN and the cluster heals.

### What this migration actually changes: only the operator

This is an **operator swap**, not a data-plane upgrade. Neither operator is tied to a particular
data-plane image — the community StarRocks operator and the PhoenixAI operator both run whatever
FE/CN image the CR (or Helm values) point at. So the supported, lowest-risk migration **keeps your
existing StarRocks data-plane images** and only replaces the controlling operator (and the CRD / CR
group it reconciles). The FE/CN pods keep running the same `starrocks/*` images they ran before;
only the thing managing them changes.

Switching the FE/CN images to the PhoenixAI (enterprise) images is a **separate, optional upgrade**
you can do afterward. The converter reflects this: it **never** rewrites the data-plane images (it only
rewrites the operator image), so the migration keeps your data plane exactly as-is.

### The one hard constraint: delete-and-recreate

A StatefulSet's `.spec.selector` is **immutable**, and the two operators put a different
owner-reference label key into it (`app.starrocks.…` vs `app.phoenixai.…`). Therefore, the
PhoenixAI operator **cannot adopt the old StatefulSet in place** — the old StatefulSets must be
deleted and recreated. Deleting a StatefulSet does **not** delete its PVCs (the default PVC
retention policy is `Retain`), so data survives. **There is a short downtime** while pods are
recreated.

### Side effect: reused PVCs keep the old owner-reference label

Because the two operators put a different owner-label key into the StatefulSet selector, the reused
PVCs end up with a label that does not match the new operator's key. This is **cosmetic as far as
the operator is concerned** — it identifies a component's PVCs by name, exactly as the StatefulSet
does — but it can matter to **your own** tooling, and you may clean it up.

When a StatefulSet creates a PVC from its `volumeClaimTemplate`, Kubernetes stamps the STS's
`.spec.selector.matchLabels` onto that PVC. It does this **only when it creates the PVC** — it never
relabels a PVC it merely reuses. So after the cutover:

- PVCs that already existed (every FE/CN ordinal present before migration) keep the **old**
  `app.starrocks.ownerreference/name=<cluster>-<component>` label and never gain the
  `app.phoenixai.ownerreference/name` one.
- PVCs created **after** migration (e.g. ordinals added by a later scale-out) get the **new**
  `app.phoenixai.ownerreference/name` label.

**The migration is unaffected, and so is the operator**: a StatefulSet binds a pod to its PVC
**by name**, not by label, so PVC reuse, data preservation, pod startup and PVC retention never
depend on the label. The operator identifies a component's PVCs the same way — by the
`<volume>-<statefulset>-<ordinal>` name convention — so volume expansion, scaling, and the PVC
entries the Anywhere console shows all work on a reused PVC regardless of which owner label it
carries.

The thing to watch is **your own tooling**: backup jobs, scripts or dashboards that select PVCs by
`app.starrocks.ownerreference/name` keep matching the pre-migration PVCs but miss any created
afterward — and the reverse for anything keyed on the PhoenixAI label. We deliberately leave the
labels untouched rather than mutate your live PVCs. If you want them uniform, relabel the reused
PVCs yourself **after the cluster is healthy** — this is metadata-only and does not disturb running
pods:

```bash
# Add the PhoenixAI owner-reference label to the reused PVCs.
# Keep the original app.starrocks.ownerreference/name label in place (do NOT remove it): if you ever
# roll back, the open-source operator's StatefulSet selector still references it.
for c in fe cn; do
  kubectl -n "$NS" label pvc -l "app.starrocks.ownerreference/name=$NAME-$c" \
    "app.phoenixai.ownerreference/name=$NAME-$c" --overwrite
done
kubectl -n "$NS" get pvc --show-labels
```

## Get the converter

Pick the PhoenixAI release you are migrating to, and take everything from that one release: the
converter, the operator manifest and CRDs (Path A), and the Helm charts (Path B). The commands below
use it as `$VERSION`:

```bash
VERSION=<X.Y.Z>   # the PhoenixAI release you are migrating to, e.g. 2.1.0
```

Each release publishes prebuilt `migrate-from-starrocks` binaries (under its
`migrate-from-starrocks/` release assets, one per OS/arch). Download the one for your platform **from
release `v$VERSION`**, `chmod +x` it, put it somewhere on your `PATH`, and check that it belongs to that
release:

```bash
migrate-from-starrocks --version   # prints: migrate-from-starrocks v$VERSION
```

The converter is tied to its release: in values mode it writes that release's operator image,
`us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/anywhere-operator:v$VERSION`, whatever operator
tag your input named. A converter from another release would install another operator. Every
command below assumes the converter is on the `PATH`.

The converter does a structured, key-only rename and never touches the cluster. It is safe to run
repeatedly. Its subcommands cover both paths:

```text
migrate-from-starrocks cr       [--input FILE] [--output FILE]                        # Path A — CR
migrate-from-starrocks operator [--input FILE] [--output FILE] --namespace NS         # Path A — operator.yaml
migrate-from-starrocks values   [--input FILE] [--output FILE] [--cluster-name NAME]  # Path B — Helm values
```

`--cluster-name NAME` (used by `values` for Path B) must be the **existing** cluster's name — the
same value as `$NAME` in [Before you start](#before-you-start). It is the `metadata.name` of the live
`StarRocksCluster`; find it with:

```bash
kubectl -n "$NS" get starrockscluster -o jsonpath='{.items[0].metadata.name}{"\n"}'
```

The migrated release must keep this exact name — every StatefulSet/PVC name derives from it, so a
different name would break PVC reuse (see the rule under [Path B](#path-b--helm-kube-starrocks--kube-anywhere)).

The converter **preserves the FE/CN data-plane images unchanged** — this migration only swaps the
operator (see "What this migration actually changes" above). It rewrites just the **operator** image
to the PhoenixAI registry (`us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/*`), since a StarRocks
operator cannot manage PhoenixAI CRs; make sure the namespace has `imagePullSecrets` able to pull that operator image.

**If your operator image comes from your own registry or mirror**, the converter cannot know the
path the PhoenixAI operator has there, so it leaves that image exactly as it found it — tag included
— and says so twice: a warning on stderr, and a `NOT CONVERTED` comment above the `image` key in the
output. **That field is then yours to fix**: point it at the operator image of the release you are
migrating to, `anywhere-operator:v$VERSION`, mirroring
`us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/anywhere-operator` into your registry first if
you need to. The converter also writes no `imagePullSecrets` in this case — the
`phoenixai-registry` secret it would otherwise add is for the upstream registry, and it cannot know
what yours needs — so set that alongside the image if your registry requires one. Installing with
the image left as-is runs a StarRocks operator against PhoenixAI CRs, which reconciles nothing — the
operator pod comes up and the cluster never does.

The converter also **pins the pods' timezone**. The kube-starrocks / kube-celerdata charts default
`timeZone` to `Asia/Shanghai`, while kube-anywhere defaults it to `UTC`. So when your values.yaml
never mentioned `timeZone`, the converter writes `timeZone: Asia/Shanghai` into the converted file —
otherwise the migrated pods would silently switch to UTC. That is not cosmetic: `TZ` only sets the
container's OS timezone, while StarRocks persists its `time_zone` variable in the FE metadata at
bootstrap, so the pods would keep answering SQL in `Asia/Shanghai` while writing logs in UTC. A
`timeZone` you set yourself (including an explicit `""`) is preserved exactly as-is. If you *want*
the cluster on UTC, that is a deliberate, separate change — edit the converted values and expect an
FE/CN rollout. (Path A needs nothing here: a CR created by the old chart already carries its `TZ`
env var explicitly, and the `cr` subcommand leaves it untouched.)

On the same behavior-preserving principle, the converter **pins every chart default that
kube-anywhere deliberately flips** relative to the source charts, whenever your values never set the
key (a value you set yourself always wins). Each pin carries a comment in the converted file:

| Pinned key | kube-anywhere default | Pinned to | Why the source behavior must be kept |
|---|---|---|---|
| `phoenixAICluster.enabledCn` | `true` | `false` | the source charts default CN off; migrating must not suddenly deploy a CN StatefulSet |
| `phoenixAICluster.waitForFullRollout` | `true` | `false` | keeps the rollout orchestration the cluster had |
| `phoenixAICluster.componentValues.runAsNonRoot` | `true` | `false` | a cluster that ran as root has root-owned files a non-root user cannot access |
| `phoenixAIFeSpec.storageSpec.name` | `"fe"` (PVC-backed FE metadata) | `""` (emptyDir) | a StatefulSet's volume set is fixed at creation — an existing FE cannot gain PVCs in place |
| `datadog.log.enableMultilineLogParsing` (only when `datadog.log.enabled: true`) | `true` | `false` | the multiline rule changes the pod log annotation, which would roll every FE/CN pod |
| `phoenixAIOperator.enablePVCExpansion` | `true` | `false` | with the feature on, a live PVC larger than the declared `storageSize` fails the reconcile; enable it deliberately once the declared sizes match the live PVCs |

The operator's other flipped defaults (`enableApiServer`, `enablePVCExpansionRBAC`) are **not**
pinned: they only add a read-only gRPC API Service and pre-provisioned RBAC and never touch the data
plane. In Path A the `operator` subcommand applies the same idea to the released manifest: it strips
the `--enable-pvc-expansion` arg from the operator Deployment (the feature's RBAC stays, so it can be
enabled later by adding the arg back). Path A CRs need none of this — the CRD defaults are unchanged,
only the chart defaults moved.

---

## Before you start

```bash
NS=namespace_where_starrocks_runs              # the namespace the cluster lives in
# The cluster's name. Every generated resource name derives from it, so the migrated CR/release
# MUST keep this exact name. NOTE: this picks the FIRST StarRocksCluster in the
# namespace; if you have several, set NAME explicitly instead of relying on items[0]:
NAME=$(kubectl -n "$NS" get starrockscluster -o jsonpath='{.items[0].metadata.name}')
echo "$NAME"                                   # e.g. starrockscluster-sample / kube-starrocks

# IMPORTANT: the PhoenixAI operator only supports shared-data clusters. A BE StatefulSet means the
# cluster is shared-nothing and CANNOT be migrated — stop here if this prints anything.
kubectl -n "$NS" get statefulset "$NAME-be" 2>/dev/null && echo "shared-nothing cluster: NOT migratable"

# IMPORTANT: confirm the StatefulSets will NOT delete their PVCs on deletion. The default is Retain;
# if anyone set whenDeleted: Delete, change it back to Retain first.
for c in fe cn; do
  kubectl -n "$NS" get statefulset "$NAME-$c" >/dev/null 2>&1 || continue
  echo -n "$NAME-$c: "
  kubectl -n "$NS" get statefulset "$NAME-$c" \
    -o jsonpath='{.spec.persistentVolumeClaimRetentionPolicy}{"\n"}'
done
kubectl -n "$NS" get pvc                       # eyeball the PVCs that must survive (fe-meta, cn storage, ...)
```

> Do not proceed if the meta/data PVCs are not `Retain` — you would lose data when the StatefulSet
> is deleted.

---

## Path A — kubectl / CR

Use this when you `kubectl apply` a `StarRocksCluster` CR directly (no Helm).

### A1 — Back up and convert the CR

Back up the live CR — it is both the converter input and your rollback artifact (see
[Rollback](#rollback)) — then convert it:

```bash
kubectl -n "$NS" get starrockscluster "$NAME" -o yaml > sr-backup.yaml
migrate-from-starrocks cr --input sr-backup.yaml > phoenixai-cr.yaml
```

Open the result and **verify the name, namespace and every `storageVolume.name` are unchanged**
from the originals — this is what makes PVC reuse work.

### A2 — Install the PhoenixAI operator (before any downtime)

Install the operator **first** and confirm it is healthy, so the only downtime is the cluster cutover
in A3 — not a botched operator install. The released `operator.yaml` installs into its own
`phoenixai` namespace, which differs from where your StarRocks operator runs; rewrite it to that
namespace with the converter (which also drops the bundled `Namespace` object, since the target
namespace already exists):

```bash
OPERATOR_NS="$NS"   # the namespace your StarRocks operator runs in (often the cluster's namespace)
# Back up the running StarRocks operator deployment FIRST — this is your rollback artifact (see Rollback).
kubectl -n "$OPERATOR_NS" get deploy -l app.kubernetes.io/name=kube-starrocks -o yaml > operator-backup.yaml
curl -fsSLO https://github.com/CelerData/phoenixai-kubernetes-operator/releases/download/v${VERSION}/operator.yaml
migrate-from-starrocks operator --input operator.yaml --namespace "$OPERATOR_NS" \
  --output phoenixai-operator.yaml
```

The converter only repoints namespaces — it does **not** carry over any customizations you made to your
StarRocks operator. **Diff `phoenixai-operator.yaml` against your running operator** and backfill anything
it can't know about — e.g. resource requests/limits, env vars, extra args/flags, replicas, nodeSelector,
tolerations, affinity, imagePullSecrets, etc.:

Apply it and wait for the operator to be Running before continuing:

```bash
# Install the CRDs first. Use `create`, not `apply`: `apply` copies the whole object into the
# kubectl.kubernetes.io/last-applied-configuration annotation, and the PhoenixAICluster CRD sits at
# ~242 KB against that annotation's 262144-byte limit (see the FAQ in
# install_with_kubectl.md). `create` does not write that annotation at all.
# This is a first-time install of the phoenixdata.ai CRDs (the cluster only had starrocks.com ones), so
# `create` fits; on a later operator upgrade you would use `kubectl replace` instead.
kubectl create \
  -f https://github.com/CelerData/phoenixai-kubernetes-operator/releases/download/v${VERSION}/phoenixdata.ai_phoenixaiclusters.yaml \
  -f https://github.com/CelerData/phoenixai-kubernetes-operator/releases/download/v${VERSION}/phoenixdata.ai_phoenixaiwarehouses.yaml \
  -f https://github.com/CelerData/phoenixai-kubernetes-operator/releases/download/v${VERSION}/phoenixdata.ai_phoenixaicngroups.yaml
kubectl get crd phoenixaiclusters.phoenixdata.ai phoenixaiwarehouses.phoenixdata.ai phoenixaicngroups.phoenixdata.ai

# apply the operator
kubectl apply -f phoenixai-operator.yaml
kubectl -n "$OPERATOR_NS" rollout status deploy/kube-anywhere-operator --timeout=120s
```

### A3 — Delete the old cluster (downtime starts here)

Deleting the `StarRocksCluster` garbage-collects its StatefulSets, Services and the fe-proxy
Deployment (they are owned by the CR); the PVCs survive because their retention policy is `Retain`
(verified in pre-flight). This is the only unavoidable downtime window.

```bash
kubectl -n "$NS" delete starrockscluster "$NAME"
# GC is asynchronous; make sure the old StatefulSets are gone before the PhoenixAI operator recreates
# them under the same names (a no-op if GC already removed them):
kubectl -n "$NS" delete statefulset "$NAME-fe" "$NAME-cn" --ignore-not-found
kubectl -n "$NS" wait --for=delete pod --all --timeout=180s 2>/dev/null || true
kubectl -n "$NS" get pvc            # confirm the PVCs survived
```

### A4 — Apply the PhoenixAI CR (reuses the existing PVCs)

```bash
kubectl -n "$NS" apply -f phoenixai-cr.yaml
```

The operator creates `…-fe` / `…-cn` StatefulSets with the **same** names and
`volumeClaimTemplate` names, so each pod binds the **existing** PVC. Pods come up with
the same FQDN, and the FE metadata recognises them.

---

## Path B — Helm (kube-starrocks → kube-anywhere)

Use this when the cluster was installed with the open-source Helm Chart.

Both `kube-starrocks` and `kube-anywhere` are a **parent chart wrapping two subcharts** — `operator`
and the cluster (`starrocks` → `phoenixai`). (`kube-anywhere` also carries an optional third
subchart, `anywhere` — the PhoenixAI Anywhere console, disabled by default — which plays no part in
the migration.) There are two deployment models; pick the one that
matches how you installed:

- **B-combined** — one `kube-starrocks` release deploys the operator **and** the cluster together.
  Migrate it as a single release swap.
- **B-split** — the `operator` subchart is deployed **once** (often cluster-wide) and the cluster
  (`starrocks`) subchart is deployed **separately, one release per namespace**. Migrate the operator
  once, then each cluster release independently. This preserves the "one operator, many clusters
  across namespaces" topology.

The converter handles: `migrate-from-starrocks values` detects whether the input is a combined
parent values, an operator-only values, or a cluster-only values, and converts only the blocks that
are present. It **never rewrites data-plane images**; it rewrites only the operator image, and only
when the values actually contain the operator block.

> **The single most important rule:** the migrated cluster name must equal the original. The chart
> derives it as `phoenixAICluster.name` > `nameOverride` > chart name. kube-starrocks defaults
> `nameOverride: kube-starrocks` and kube-anywhere defaults `kube-anywhere` — **different**, which
> would change the StatefulSet/PVC names and break reuse. The converter therefore pins
> `phoenixAICluster.name`. Always pass `--cluster-name "$NAME"` when converting cluster values.

Before you start, list the releases you will migrate. Each path below begins by backing up that
release's values with `helm get values -o yaml … > …-values-backup.yaml` — that file is **both the converter
input and your rollback artifact** (see [Rollback](#rollback)), so keep it.

```bash
helm list -n "$NS"                                          # note release names + chart versions
```

The `helm` commands below pull from the PhoenixAI chart repo; add them once:

```bash
helm repo add phoenixai https://celerdata.github.io/phoenixai-kubernetes-operator
helm repo add starrocks-community https://starrocks.github.io/starrocks-kubernetes-operator  # rollback only
helm repo update
```

### B-combined — one kube-starrocks release (operator + cluster together)

#### Convert the values

```bash
helm get values <oss-release> -n "$NS" -o yaml > kube-starrocks-values-backup.yaml   # back up + converter input
migrate-from-starrocks values \
  --input kube-starrocks-values-backup.yaml \
  --cluster-name "$NAME" \
  --output kube-anywhere-values.yaml
```

Then **review `kube-anywhere-values.yaml`**:

- `phoenixai.phoenixAICluster.name` is pinned to `$NAME` (the comment marks it).
- Every `storageSpec.name` (FE/CN) is unchanged — this is what makes the PVCs line up.
- The data-plane (FE/CN) images are kept as-is; only the **operator** image is rewritten to the
  PhoenixAI registry (a StarRocks operator can't manage PhoenixAI CRs).
- The flipped chart defaults are pinned back to the source behavior (see the pin table under
  [Get the converter](#get-the-converter)) — each pin carries a comment.

#### Stop the old release (downtime starts here)

> **Warehouses first.** If you keep warehouses with the annotation (old operator at v1.11.8),
> annotate each `StarRocksWarehouse` and check that it took effect **before** this step, as described in
> [Warehouses](#warehouses). This step removes the old operator, and once it is gone nothing acts on
> the annotation any more.

`helm uninstall` removes the whole OSS release — its operator **and** the StarRocksCluster CR.
Deleting the CR garbage-collects its StatefulSets and Services; the cluster CR carries no
finalizer, so this does not hang. The PVCs have a `Retain` policy (confirmed in pre-flight), so they
survive. **Downtime starts here.**

```bash
helm uninstall <oss-release> -n "$NS"
# StatefulSet GC is asynchronous; make sure the old ones are gone before the new release recreates
# them under the same names (a no-op if GC already removed them):
kubectl -n "$NS" delete statefulset "$NAME-fe" "$NAME-cn" --ignore-not-found
kubectl -n "$NS" wait --for=delete pod --all --timeout=180s 2>/dev/null || true
kubectl -n "$NS" get pvc            # confirm the PVCs survived
```

#### Install kube-anywhere (reuses the existing PVCs)

```bash
helm install <cd-release> phoenixai/kube-anywhere --version "$VERSION" -n "$NS" -f kube-anywhere-values.yaml
```

This release's operator creates `$NAME-fe`/`$NAME-cn` with the same names and
`volumeClaimTemplate` names, so the pods re-bind the existing PVCs and come up with the same FQDN.

### B-split — separate operator and cluster releases

You deployed the `operator` subchart and the `starrocks` subchart as **separate Helm releases**.
Migrate the operator **once**, then each cluster release. The data-plane mechanics are identical to
B-combined (PVC reuse, FQDN identity); the difference is you do it as two independent release swaps,
and only the cluster swap incurs downtime.

#### Swap the operator release (once)

> **Warehouses first.** If you keep warehouses with the annotation (old operator at v1.11.8),
> annotate each `StarRocksWarehouse`, in every namespace this operator manages, and check that it took effect
> **before** this step, as described in [Warehouses](#warehouses). This step removes the old
> operator, and once it is gone nothing acts on the annotation any more.

Convert the operator-only values and replace the operator release. The data plane keeps running while
the operator is briefly absent (an unmanaged FE/CN does not stop serving); only reconciliation
pauses.

```bash
helm get values <oss-operator-release> -n <operator-ns> -o yaml > operator-values-backup.yaml  # back up + converter input
migrate-from-starrocks values \
  --input operator-values-backup.yaml \
  --output phoenixai-operator-values.yaml

helm uninstall <oss-operator-release> -n <operator-ns>
helm install  <cd-operator-release> phoenixai/anywhere-operator --version "$VERSION" -n <operator-ns> -f phoenixai-operator-values.yaml
```

Make sure the PhoenixAI operator **watches the namespaces your clusters live in** — cluster-wide, or
one operator scoped per namespace (`phoenixAIOperator.watchNamespace`). The operator subchart bundles
the PhoenixAI CRDs, so installing it also installs `phoenixaiclusters` / `phoenixaiwarehouses`.

#### Migrate each cluster release (downtime per cluster)

For **each** cluster release, convert its cluster-only values (pass `--cluster-name`), uninstall the
old cluster release, and install the `phoenixai` cluster subchart. Repeat per namespace.

```bash
# `storageSpec.name` unchanged, `phoenixAICluster.name` pinned, data-plane images kept
NAME=$(kubectl -n "$NS" get starrockscluster -o jsonpath='{.items[0].metadata.name}')
helm get values <oss-cluster-release> -n "$NS" -o yaml > cluster-values-backup.yaml   # back up + converter input
migrate-from-starrocks values \
  --input cluster-values-backup.yaml \
  --cluster-name "$NAME" \
  --output phoenixai-cluster-values.yaml
```

Install the new release.

```bash
helm uninstall <oss-cluster-release> -n "$NS"
kubectl -n "$NS" delete statefulset "$NAME-fe" "$NAME-cn" --ignore-not-found
kubectl -n "$NS" wait --for=delete pod --all --timeout=180s 2>/dev/null || true
kubectl -n "$NS" get pvc            # confirm the PVCs survived

helm install <cd-cluster-release> phoenixai/phoenixai --version "$VERSION" -n "$NS" -f phoenixai-cluster-values.yaml
```

---

## Verify

```bash
kubectl -n "$NS" get phoenixaicluster "$NAME"
kubectl -n "$NS" get pods -w        # wait for FE/CN to become Ready
```

Then connect to the FE over the MySQL protocol. The query port is `9030` on the FE service
`<cluster>-fe-service` (use the cluster admin user — `root` by default, password empty unless you set one).
From inside the cluster, or via `kubectl port-forward`:

```bash
kubectl -n "$NS" port-forward svc/"$NAME-fe-service" 9030:9030 &
mysql -h 127.0.0.1 -P 9030 -u root      # add -p if a password is set
```

Confirm membership and data:

```sql
SHOW FRONTENDS;      -- all FEs present, Alive = true
SHOW COMPUTE NODES;  -- all CNs present, Alive = true (shared-data CNs also appear in SHOW BACKENDS)

-- spot-check a known table:
SELECT COUNT(*) FROM <your_db>.<your_table>;
```

If `SHOW COMPUTE NODES` lists the nodes by their old FQDN and `Alive = true`, the identity and data
were preserved successfully.

## Warehouses

A `StarRocksWarehouse` / `PhoenixAIWarehouse` is a CN-only compute warehouse attached to
an existing cluster. Migrate it **after the main cluster is healthy**. A warehouse holds no
authoritative data (it is computed only — data lives in the cluster's object storage), so this is
lower-risk than the cluster migration; just keep the **warehouse name** and the **cluster it points
at** unchanged so its CNs rejoin. The PhoenixAI operator from the main migration already reconciles it
— no extra operator needed.

**Deleting a warehouse CR drops the warehouse, unless you opt out.** Both operators clean up after a
deleted warehouse CR: before they release the warehouse's CN StatefulSet, they run `DROP WAREHOUSE` in
the FE. The migration deletes each `StarRocksWarehouse` and applies a same-named `PhoenixAIWarehouse`,
and a rollback does the reverse. Whenever the drop runs, the CNs of the new CR create the warehouse
again, but with default properties and without the privileges granted on it, and queries on that
warehouse fail in between.

Whether the drop runs depends on whether the operator that owns the deleted CR is still running:

| When | Owner of the deleted CR | Without the annotation below |
|---|---|---|
| Migrating on Path A | the community operator, still running | it drops the warehouse, unless you stop it first (see below) |
| Migrating on Path B | the community operator, already removed with its release | no drop, but the CN StatefulSet stays in `Terminating` until you clear its finalizer by hand |
| Rolling back | the PhoenixAI operator, running | it drops the warehouse |

**To keep the warehouse, its properties and its grants**, annotate the warehouse CR with
`starrocks.com/skip-fe-cleanup: "true"` on both sides. An operator that understands the annotation
holds no protection finalizer on the warehouse's CN StatefulSet and never drops the warehouse, so
deleting the CR is an ordinary Kubernetes delete and nothing is left in `Terminating`. That takes:

- the old operator at **v1.11.8 or later** for the old warehouse CR: community v1.11.8 for a
  `StarRocksWarehouse`, the CelerData-era enterprise v1.11.8 for a `CelerDataWarehouse`, if you want
  to avoid the manual steps under "Without the annotation" below. Upgrade to v1.11.8 before you
  migrate (see [Upgrade the Operator](../Deploy/upgrade_operator_howto.md)); older operators of either
  kind do not understand it.
- PhoenixAI operator **v2.0.2 or later** (2.1 and later included) for the `PhoenixAIWarehouse`. v2.0.0
  and v2.0.1 do not understand it and drop the warehouse on rollback.

An operator that does not understand the annotation ignores it without any error, so always check
that it has taken effect instead of assuming it did.

**Annotate the old warehouses while the old operator still runs.** It has to see the annotation
to release its own finalizer. On Path B that means before you uninstall the old operator's
release: before the cutover in B-combined, before the operator swap in B-split. For each warehouse:

```bash
WH=<warehouse-name>   # on the Helm path, the warehouse is named after its Helm release
kubectl -n "$NS" annotate starrockswarehouse "$WH" starrocks.com/skip-fe-cleanup=true
# CelerData-era cluster: same key, on the celerdatawarehouse instead
# kubectl -n "$NS" annotate celerdatawarehouse "$WH" starrocks.com/skip-fe-cleanup=true
kubectl -n "$NS" get sts "$WH-warehouse-cn" \
  -o jsonpath='{.metadata.finalizers}{"\n"}{.metadata.annotations.starrocks\.com/skip-fe-cleanup}{"\n"}'
```

It has taken effect when the first line does not list `starrocks.com.starrockswarehouse/protection`
(CelerData-era: `celerdata.com.celerdatawarehouse/protection`) and the second line prints `true`.
Only the StatefulSet's metadata changes, so no CN pod restarts.

**Without the annotation** (a community or CelerData-era operator older than v1.11.8, or a
warehouse you did not annotate), the old warehouse is kept only if the old operator is **not
running** when you delete its CR. On Path B it is already gone. On Path A, stop it first, after the
cluster cutover; if it still manages clusters you have not migrated yet, their reconciliation pauses
until you scale it back up, while their pods keep serving:

```bash
# The community operator's Deployment: kube-starrocks-operator unless you renamed it.
kubectl -n "$OPERATOR_NS" scale deploy kube-starrocks-operator --replicas=0
```

The CN StatefulSet then keeps its finalizer after you delete the old warehouse CR
(`starrocks.com.starrockswarehouse/protection`; CelerData-era clusters:
`celerdata.com.celerdatawarehouse/protection`), because only the old operator removes it. The
same-named replacement cannot be created until you clear it yourself:

```bash
kubectl -n "$NS" patch sts "$WH-warehouse-cn" --type=merge -p '{"metadata":{"finalizers":null}}'
```

The PVCs are unaffected: they have their own retain semantics and are reused by the recreated
warehouse.

**kubectl / CR** — the `cr` converter rewrites the kind and `spec.starRocksCluster` →
`spec.phoenixAICluster`. It keeps your annotations, so a `StarRocksWarehouse` annotated above yields
an annotated `PhoenixAIWarehouse`; if you did not annotate the old one, add the annotation to
`phoenixai-wh.yaml` before applying it, so that a rollback keeps the warehouse:

```bash
kubectl -n "$NS" get starrockswarehouse "$WH" -o yaml > wh-backup.yaml   # back up + converter input
migrate-from-starrocks cr --input wh-backup.yaml > phoenixai-wh.yaml   # verify spec.phoenixAICluster == "$NAME"
kubectl -n "$NS" delete starrockswarehouse "$WH"                         # GC removes its CN StatefulSet; PVCs survive
kubectl -n "$NS" apply -f phoenixai-wh.yaml                              # recreated by the PhoenixAI operator
```

**Helm (`warehouse` chart)** — `migrate-from-starrocks values` also converts warehouse values (it
renames `spec.starRocksClusterName` → `spec.phoenixAIClusterName`, keeping its value and the CN
image). The chart names the `PhoenixAIWarehouse` after the **Helm release name** (there is no
`nameOverride`), and that name drives the CN StatefulSet/PVC names — so the PhoenixAI release **must
reuse the original release name**, or the warehouse comes back renamed and does not reuse its PVCs.
Convert, then swap the release in place under the same name:

```bash
WH=<oss-warehouse-release>          # the warehouse name; reuse this exact name for the PhoenixAI release
helm get values "$WH" -n "$NS" -o yaml > wh-values-backup.yaml
migrate-from-starrocks values --input wh-values-backup.yaml --output phoenixai-wh-values.yaml
helm uninstall "$WH" -n "$NS"
helm install "$WH" phoenixai/warehouse --version "$VERSION" -n "$NS" -f phoenixai-wh-values.yaml
```

The chart does not set annotations on the `PhoenixAIWarehouse`, so add the annotation after the
install (`helm upgrade` leaves it in place):

```bash
kubectl -n "$NS" annotate phoenixaiwarehouse "$WH" starrocks.com/skip-fe-cleanup=true
```

If a recreate races the asynchronous GC of the old CN StatefulSet (a same-name clash), wait for the
old warehouse pods to terminate before applying/installing.

**Check the new warehouse before you rely on a rollback.** Run the same check against the PhoenixAI
StatefulSet: the first line must not list `phoenixdata.ai.phoenixaiwarehouse/protection`, and the
second line must print `true`. See "Delete the CR but keep the warehouse in the cluster" in
[deploy_warehouse_howto.md](deploy_warehouse_howto.md) for what the annotation does afterwards.

**Remove the annotation once you no longer plan to roll back**, so that deleting the warehouse later
drops it from the FE again. Before you delete such a warehouse, wait until the operator has put
`phoenixdata.ai.phoenixaiwarehouse/protection` back on its StatefulSet; deleted earlier, the warehouse
stays in the FE.

## Rollback

If verification fails, you can return to the open-source operator (PVCs are reused the same way).
Roll back with the **same path** you migrated with. Roll back each warehouse the same way, in reverse:
delete the `PhoenixAIWarehouse` and re-apply the backed-up `StarRocksWarehouse` (or reinstall its OSS
release). With the annotation in effect on the `PhoenixAIWarehouse`, the warehouse keeps its properties
and grants; without it, the PhoenixAI operator drops the warehouse (see [Warehouses](#warehouses)).

On the kubectl path, the backed-up `StarRocksWarehouse` was saved after you annotated it, so the
re-applied one still opts out. Once you no longer plan to migrate again, remove the annotation, so
that deleting the warehouse later drops it from the FE again:

```bash
kubectl -n "$NS" annotate starrockswarehouse "$WH" starrocks.com/skip-fe-cleanup-
```

Then wait until `starrocks.com.starrockswarehouse/protection` is back on the `$WH-warehouse-cn`
StatefulSet, with the same check as in [Warehouses](#warehouses), before you ever delete that warehouse;
deleted earlier, it stays in the FE. A reinstalled Helm release carries no annotation, so there is
nothing to remove.

### Rollback — Path A (kubectl / CR)

```bash
# Remove the PhoenixAI CR; GC deletes its StatefulSets + Services. PVCs survive (Retain).
kubectl -n "$NS" delete phoenixaicluster "$NAME"
# Make sure the old StatefulSets are gone before the OSS operator recreates them under the same names:
kubectl -n "$NS" delete statefulset "$NAME-fe" "$NAME-cn" --ignore-not-found
kubectl -n "$NS" wait --for=delete pod --all --timeout=180s 2>/dev/null || true
# Reinstall the open-source operator + CRDs (all-in-one manifest), then re-apply the backed-up CR:
kubectl apply -f operator-backup.yaml
kubectl -n "$NS" apply -f sr-backup.yaml
```

### Rollback — Path B (Helm)

Reinstall the original OSS chart with the values you backed up before the cutover. PVCs survive
(Retain), so the reinstalled release re-binds them.

```bash
helm uninstall <cd-release> -n "$NS"
kubectl -n "$NS" delete statefulset "$NAME-fe" "$NAME-cn" --ignore-not-found
kubectl -n "$NS" wait --for=delete pod --all --timeout=180s 2>/dev/null || true
# Reinstall the OSS chart from the backed-up values:
helm install <oss-release> starrocks-community/kube-starrocks -n "$NS" -f kube-starrocks-values-backup.yaml
# B-split: reinstall the cluster release(s) from cluster-values-backup.yaml and the operator release
# from operator-values-backup.yaml, the same way.
```

## Checklist

- [ ] PVC retention policy is `Retain` on **every** component with PVCs (FE **and** CN)
- [ ] Converted CR/values keep the **same** name / namespace / `storageVolume` (or `storageSpec`) names
- [ ] (Path A) live CR backed up to `sr-backup.yaml`
- [ ] (Path A) live operator.yaml backed up to `operator-backup.yaml`
- [ ] (Path A) `operator.yaml` rewritten to your operator namespace (`migrate-from-starrocks operator
  --namespace`), and finished comparing the diff.
- [ ] (Path B) each release's values backed up to a `*-values-backup.yaml` (converter input + rollback artifact)
- [ ] (Path B) `--cluster-name` set to the live cluster's actual name; `phoenixAICluster.name` pinned
- [ ] (Path B) the flipped-default pins are present in the converted values (`waitForFullRollout`,
  `componentValues.runAsNonRoot`, FE `storageSpec.name: ""`, `enablePVCExpansion`) unless you set
  those keys yourself
- [ ] `SHOW FRONTENDS` / `SHOW COMPUTE NODES` all `Alive = true` after cutover
- [ ] (Warehouses, to keep them) old operator at v1.11.8 (community or CelerData-era), every
  `StarRocksWarehouse` / `CelerDataWarehouse` annotated with `starrocks.com/skip-fe-cleanup: "true"`
  and checked **before** the old operator goes away
  (or, without the annotation, the old operator stopped before any old warehouse CR is deleted);
  PhoenixAI v2.0.2 or later, every `PhoenixAIWarehouse` annotated and checked
- [ ] (Optional) reused PVCs relabeled to `app.phoenixai.ownerreference/name`, or your PVC tooling
  updated to account for the mixed owner-reference labels (see "reused PVCs keep the old
  owner-reference label")
