---
sidebar_position: 4
sidebar_label: Scheduled scaling for CN nodes
title: Scheduled scaling for CN nodes
description: Add and remove CN nodes on a calendar — more compute during business hours, less at night — using KEDA, an open-source autoscaler. Written for readers who have never used KEDA.
---

# Scheduled scaling for CN nodes

Many workloads follow the clock: reports run every weekday morning, dashboards are busy during
office hours, and almost nothing happens at night. **Scheduled scaling** lets you write that
pattern down once, like entries in a calendar, and have the number of CN (compute) nodes follow it:

> "From 08:00 to 20:00 on weekdays, run 10 CN nodes. The rest of the time, run 2."

The PhoenixAI operator does not have its own scheduler for this. Instead it works with
**[KEDA](https://keda.sh)**, a widely used open-source autoscaler for Kubernetes. If your
organization already runs KEDA, you can reuse it as is; if not, this page shows how to install it.

This page assumes you can run `kubectl` and `helm` against your cluster, and nothing more. You do
not need to have used KEDA or the Kubernetes HorizontalPodAutoscaler before.

## 1. How it works, in one minute

Four pieces take part. You only write the first one.

```text
 you write             KEDA creates            PhoenixAI CR               operator
┌──────────────┐     ┌──────────────────┐     ┌──────────────────┐      ┌──────────────┐
│ ScaledObject │ ──▶ │ HPA              │ ──▶ │ replicas: 10     │ ───▶ │ CN pods      │
│ (the         │     │ keda-hpa-<name>  │     │ (warehouse,      │      │ added to /   │
│  calendar)   │     │                  │     │  cluster, group) │      │ removed from │
└──────────────┘     └──────────────────┘     └──────────────────┘      │ the FE       │
                                                                        └──────────────┘
```

1. **ScaledObject** — a small YAML file you write. It says *what* to scale (for example the
   warehouse `wh-reports`) and *when* (a time window and a node count).
2. **HPA** — KEDA turns your ScaledObject into a standard Kubernetes
   HorizontalPodAutoscaler named `keda-hpa-<your ScaledObject name>`. You never edit it.
3. **The PhoenixAI custom resource (CR)** — the HPA changes the CN replica count on your
   `PhoenixAIWarehouse`, `PhoenixAICluster` or `PhoenixAICnGroup`, exactly as if you had edited it.
4. **The operator** — sees the new replica count and adds or removes CN pods the same way it does
   for any other scale operation, including registering and deregistering them with the FE.

Because KEDA only changes a replica count, nothing about how PhoenixAI itself runs changes.

### Words used on this page

| Term | Meaning |
|---|---|
| **Window** | A period with a start time and an end time, for example 08:00–20:00. |
| **`desiredReplicas`** | How many CN nodes to run *inside* a window. |
| **`minReplicaCount`** | How many CN nodes to run *outside* every window. Also the lowest count KEDA ever goes to. |
| **`maxReplicaCount`** | A safety ceiling. KEDA never scales above it. |
| **Cron expression** | A compact way to write a time, such as `0 8 * * 1-5` ("08:00, Monday to Friday"). See [Section 7](#7-cron-expressions-cheat-sheet). |

## 2. Before you begin

You need:

- A running PhoenixAI cluster managed by the PhoenixAI operator, with CN nodes (in the cluster, in a
  warehouse, or in a CN group).
- `kubectl` and [Helm](https://helm.sh/) v3 or later on your computer.
- Permission to install cluster-wide components (KEDA installs CRDs and a webhook), or a cluster
  administrator who can install KEDA for you.

> [!IMPORTANT]
> **One autoscaler per CR.** Do not set `autoScalingPolicy` on a CR that a ScaledObject scales.
> `autoScalingPolicy` makes the operator create its own HPA, and two HPAs cannot share one replica
> count. KEDA checks this only when you create or change the ScaledObject: if the CR already has
> `autoScalingPolicy`, KEDA refuses the ScaledObject (see [Troubleshooting](#10-troubleshooting)).
> The reverse order is **not** caught: if `autoScalingPolicy` comes back after the ScaledObject
> exists — a Helm rollback to old values, for example — the operator creates its HPA again. The two
> HPAs then either keep overwriting each other, so a CN pod is removed and re-added about every
> half minute, or Kubernetes notices and stops both, so the schedule silently stops working. The
> ScaledObject shows `READY True` either way (see [Troubleshooting](#10-troubleshooting)).
>
> If you want CPU-based scaling *and* a schedule, let KEDA do both — see
> [Recipe 8.4](#84-a-schedule-plus-cpu-based-scaling).

## 3. Install KEDA

If KEDA may already be installed, run the check in [Section 3.3](#33-check-that-keda-is-running)
first. Skip the rest of this section only if all three KEDA pods are `Running` — the
`scaledobjects.keda.sh` CRD alone is not enough, because it stays behind when KEDA is uninstalled,
and a ScaledObject created without a running KEDA is accepted but never does anything.

### 3.1 Pick a KEDA version

Each KEDA release supports a range of Kubernetes versions. Check yours:

```bash
kubectl version
# Server Version: v1.30.4   <- this is the number that matters
```

Then pick the newest KEDA version whose range includes it, from the official
[Kubernetes compatibility table](https://keda.sh/docs/latest/operate/cluster/#kubernetes-compatibility).
An excerpt:

| KEDA | Kubernetes |
|---|---|
| v2.21 | v1.34 – v1.36 |
| v2.18 | v1.31 – v1.33 |
| v2.17 | v1.30 – v1.32 |
| v2.15 | v1.28 – v1.30 |
| v2.14 | v1.27 – v1.29 |

For Kubernetes v1.30 the newest match is v2.17. The examples below use that version; replace it
with yours.

### 3.2 Install it with Helm

First tell Helm where the KEDA charts live, and download the list of versions:

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
```

Find the latest chart release for the KEDA version you picked (`~2.17` means "any 2.17.x"):

```bash
$ helm search repo kedacore/keda --versions --version '~2.17'
NAME            CHART VERSION   APP VERSION   DESCRIPTION
kedacore/keda   2.17.3          2.17.3        Event-based autoscaler for workloads on Kubernetes
kedacore/keda   2.17.2          2.17.2        Event-based autoscaler for workloads on Kubernetes
...
```

Use the top `CHART VERSION`. It always has the same first two numbers as the KEDA version; the last
number occasionally differs from `APP VERSION` (chart `2.14.3` installs KEDA `2.14.1`, for example),
which is normal.

Install KEDA into its own namespace:

```bash
helm install keda kedacore/keda \
  --version 2.17.3 \
  --namespace keda --create-namespace \
  --wait
```

### 3.3 Check that KEDA is running

```bash
kubectl get pods -n keda
```

You should see three pods, all `Running`:

```text
NAME                                               READY   STATUS    RESTARTS      AGE
keda-admission-webhooks-5f66d98774-7vpfm           1/1     Running   0             86s
keda-operator-54b8994449-l6fzf                     1/1     Running   1 (57s ago)   86s
keda-operator-metrics-apiserver-667c46c858-z46rs   1/1     Running   0             86s
```

A restart or two of `keda-operator` in the first minute is harmless as long as all three pods then
stay `Running`.

> [!NOTE]
> A cluster can have only **one** provider of the `external.metrics.k8s.io` API, and with KEDA
> installed it must be KEDA. If something else already serves that API (for example
> `prometheus-adapter` configured for external metrics), talk to your cluster administrator first.
> The ordinary metrics-server (`metrics.k8s.io`) is a different API and is fine.

## 4. Find what you want to scale

A ScaledObject points at one PhoenixAI CR. All three CR kinds that own CN nodes can be scaled:

| You want to scale… | `kind` | `name` is… | List them with |
|---|---|---|---|
| A warehouse's CN nodes | `PhoenixAIWarehouse` | the warehouse CR name | `kubectl get paw -n <ns>` |
| The CN nodes inside the cluster itself | `PhoenixAICluster` | the cluster CR name | `kubectl get pac -n <ns>` |
| One CN group | `PhoenixAICnGroup` | the group CR name | `kubectl get phoenixaicngroups -n <ns>` |

For all three, `apiVersion` is `phoenixdata.ai/v1`. The ScaledObject must be created in the **same
namespace** as the CR.

For example:

```bash
$ kubectl get paw -n phoenixai
NAME         STATUS    REASON
wh-reports   running
```

Before going further, make sure that CR has **no** `autoScalingPolicy`:

```bash
kubectl get paw wh-reports -n phoenixai -o jsonpath='{.spec.template.autoScalingPolicy}'
# (prints nothing) -> good
```

For a cluster, the field is `.spec.phoenixAICnSpec.autoScalingPolicy`; for a CN group, also
`.spec.phoenixAICnSpec.autoScalingPolicy`. If it prints something, remove `autoScalingPolicy` from
your Helm values (or the CR) first.

> [!WARNING]
> **KEDA must be the only thing that writes the replica count.** Whatever manages the CR
> declaratively — Helm, Argo CD, Flux, a `kubectl apply` in CI — must not set it. If it does, every
> upgrade or sync writes that number back onto the CR. KEDA corrects it within a few seconds, but in
> between the operator already starts removing (or adding) CN pods, so queries running on them fail;
> with a GitOps tool that syncs continuously, this repeats on every sync.
>
> - **Helm:** remove `replicas` from your values for the component KEDA will scale —
>   `spec.replicas` in the warehouse chart, `phoenixai.phoenixAICnSpec.replicas` in the
>   kube-anywhere chart. **Plan the one upgrade that removes the key:** Helm deletes the field from
>   the CR, and the CR then falls back to its default of **1** replica, so every CN pod above the
>   first is removed (KEDA scales back up afterwards, if a ScaledObject exists). Do that upgrade
>   while the component runs a single CN node, or in a maintenance window. Later upgrades no longer
>   touch the count.
> - **Argo CD / Flux / plain manifests:** leave the replica field out of the manifest you keep in
>   Git, or tell the tool to ignore it (Argo CD `ignoreDifferences` on `/spec/template/replicas`
>   for a warehouse, `/spec/phoenixAICnSpec/replicas` for a cluster or CN group).
> - **CN groups created by the charts** (`cnGroups` in the warehouse chart, `phoenixAICnGroups` in
>   the kube-anywhere chart): remove `replicas` from the entry of each group KEDA will scale. The key
>   is optional there, and the first bullet's caution about the one upgrade that removes it applies
>   to the group too ([Deploy CN Groups](../Deploy/deploy_cn_group_howto.md) shows the entries).

## 5. Your first schedule

This example runs **3 CN nodes from 08:00 to 20:00 every day**, and **1 CN node** the rest of the
time, for the warehouse `wh-reports`.

Save this as `wh-reports-schedule.yaml`:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: wh-reports-schedule      # any name you like
  namespace: phoenixai           # must be the namespace of the warehouse
spec:
  # WHAT to scale.
  scaleTargetRef:
    apiVersion: phoenixdata.ai/v1
    kind: PhoenixAIWarehouse
    name: wh-reports

  # Outside the window, run this many CN nodes. Keep it at 1 or more (see Section 9).
  minReplicaCount: 1
  # Never run more than this many, whatever the triggers say.
  maxReplicaCount: 5

  # WHEN to scale.
  triggers:
    - type: cron
      metadata:
        timezone: Asia/Shanghai  # an IANA time-zone name, e.g. America/New_York, Europe/Berlin, UTC
        start: "0 8 * * *"       # window opens at 08:00
        end: "0 20 * * *"        # window closes at 20:00
        desiredReplicas: "3"     # CN nodes inside the window (note the quotes: it is a string)
```

Apply it:

```bash
kubectl apply -f wh-reports-schedule.yaml
```

That is all. As soon as the ScaledObject exists, KEDA brings the warehouse to the right count for
*the current time*: 3 if you are inside the window, 1 if you are not.

## 6. Check that it works

### 6.1 The ScaledObject is ready

```bash
$ kubectl get scaledobject -n phoenixai
NAME                  SCALETARGETKIND                        SCALETARGETNAME   MIN   MAX   TRIGGERS   AUTHENTICATION   READY   ACTIVE   FALLBACK   PAUSED    AGE
wh-reports-schedule   phoenixdata.ai/v1.PhoenixAIWarehouse   wh-reports        1     5     cron                        True    True     False      Unknown   3m
```

- `READY True` — KEDA accepted the ScaledObject and can reach the warehouse.
- `ACTIVE True` — you are inside a window right now. `False` outside every window. Both are fine.

### 6.2 KEDA created an HPA

```bash
$ kubectl get hpa -n phoenixai
NAME                           REFERENCE                       TARGETS     MINPODS   MAXPODS   REPLICAS   AGE
keda-hpa-wh-reports-schedule   PhoenixAIWarehouse/wh-reports   1/1 (avg)   1         5         3          3m
```

`REPLICAS` is the number that matters. `TARGETS` looks odd but is expected: the cron trigger
reports the count it wants, averaged over the pods that exist, against a target of `1` per pod. For
a few seconds after a window opens you see something like `3/1 (avg)` (3 wanted, 1 pod running);
once the pods have been added it settles back to `1/1 (avg)`.

### 6.3 The warehouse and its pods follow

```bash
$ kubectl get paw wh-reports -n phoenixai -o jsonpath='{.spec.template.replicas}'
3

$ kubectl get pods -n phoenixai -l app.phoenixai.ownerreference/name=wh-reports-warehouse-cn
NAME                        READY   STATUS    RESTARTS   AGE
wh-reports-warehouse-cn-0   1/1     Running   0          3h
wh-reports-warehouse-cn-1   1/1     Running   0          40s
wh-reports-warehouse-cn-2   1/1     Running   0          40s
```

### 6.4 See *why* it scaled

The HPA records every change it makes as an event:

```bash
$ kubectl get events -n phoenixai --field-selector involvedObject.name=keda-hpa-wh-reports-schedule
LAST SEEN   TYPE     REASON              OBJECT                                                 MESSAGE
40s         Normal   SuccessfulRescale   horizontalpodautoscaler/keda-hpa-wh-reports-schedule   New size: 3; reason: external metric s0-cron-Asia-Shanghai-08xxx-020xxx(...) above target
```

`s0-cron-…` is the cron trigger, so this scale-up came from your schedule.

### 6.5 Timing — what to expect

- **Scale-up** happens within about 30 seconds after the window opens. New CN nodes also need a
  minute or two to start; if they must be ready at 08:00, open the window a few minutes earlier.
- **Scale-down** happens about **5 minutes** after the window closes, not immediately. This delay
  is a standard HPA safety rule (the *scale-down stabilization window*), meant to stop a workload
  from shrinking because of a short dip. If you want scale-down to happen earlier, end the window
  5 minutes earlier, or shorten the delay as shown in
  [Recipe 8.6](#86-scale-down-faster-or-more-gently).

> [!WARNING]
> **Scale-down does not wait for queries.** When the count drops, the operator removes CN nodes
> whether or not queries are running on them, and those queries fail — the 5-minute delay is not a
> drain. End windows after the work they serve has finished, and consider removing nodes one at a
> time ([Recipe 8.6](#86-scale-down-faster-or-more-gently)).

## 7. Cron expressions cheat sheet

A cron expression has five fields: `minute hour day-of-month month day-of-week`. `*` means "every".
Day of week runs from `0` (Sunday) to `6` (Saturday).

| Expression | Means |
|---|---|
| `0 8 * * *` | 08:00 every day |
| `30 7 * * *` | 07:30 every day |
| `0 8 * * 1-5` | 08:00 Monday to Friday |
| `0 20 * * 1-5` | 20:00 Monday to Friday |
| `0 0 * * 6` | 00:00 every Saturday |
| `0 9 1 * *` | 09:00 on the 1st of every month |
| `0 6 * 12 *` | 06:00 every day in December |

[crontab.guru](https://crontab.guru) explains any expression in plain English — paste yours there
to double-check.

Rules for the cron trigger:

- `start` and `end` must be different.
- The times are read in the `timezone` you give, so daylight-saving changes are handled for you.
  Use `UTC` if you prefer to think in UTC.
- A window may cross midnight (`start: "0 22 * * *"`, `end: "0 6 * * *"`).

## 8. Recipes

Recipes 8.1, 8.4 and 8.5 are complete ScaledObjects: change the names and apply them. Recipes 8.2,
8.3 and 8.6 show only the part that differs — a `triggers:` list or an `advanced:` block. Put that
part into a complete ScaledObject such as [8.1](#81-weekdays-only), in place of its own `triggers:`
(or next to it, for `advanced:`), and apply the result.

### 8.1 Weekdays only

More nodes during office hours on Monday to Friday; the minimum at night and all weekend.

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: wh-reports-schedule
  namespace: phoenixai
spec:
  scaleTargetRef:
    apiVersion: phoenixdata.ai/v1
    kind: PhoenixAIWarehouse
    name: wh-reports
  minReplicaCount: 2
  maxReplicaCount: 10
  triggers:
    - type: cron
      metadata:
        timezone: America/New_York
        start: "0 8 * * 1-5"
        end: "0 19 * * 1-5"
        desiredReplicas: "10"
```

### 8.2 Several windows in one day

List one trigger per window. When several windows are active at the same time, the **largest**
`desiredReplicas` wins, so overlapping windows are safe.

```yaml
  triggers:
    # Morning reports: 6 nodes from 07:00 to 10:00.
    - type: cron
      metadata:
        timezone: Europe/Berlin
        start: "0 7 * * *"
        end: "0 10 * * *"
        desiredReplicas: "6"
    # Nightly batch: 8 nodes from 01:00 to 03:00.
    - type: cron
      metadata:
        timezone: Europe/Berlin
        start: "0 1 * * *"
        end: "0 3 * * *"
        desiredReplicas: "8"
```

### 8.3 A one-off busy period

For a single campaign or month-end close, combine a day-of-month or month field with a window, and
delete the ScaledObject (or the trigger) once the period is over.

```yaml
  triggers:
    # 12 nodes from 09:00 to 18:00 on the last three days of October.
    - type: cron
      metadata:
        timezone: UTC
        start: "0 9 29-31 10 *"
        end: "0 18 29-31 10 *"
        desiredReplicas: "12"
```

### 8.4 A schedule plus CPU-based scaling

This is the replacement for `autoScalingPolicy` when you also want a schedule. Add a `cpu` trigger
next to the cron trigger: inside the window the cron trigger keeps **at least** `desiredReplicas`
nodes, and the CPU trigger can add more on top when the nodes are busy. Outside the window the CPU
trigger alone decides, between `minReplicaCount` and `maxReplicaCount`.

The `cpu` trigger needs [metrics-server](https://github.com/kubernetes-sigs/metrics-server)
(`kubectl top pods` must work) and a CPU **request** on **every container** of the CN pods,
because utilization is measured against the request. That includes any sidecars you added
(`sidecars` / `sidecarsMap`): if one container has no CPU request, the HPA cannot compute CPU
utilization at all, and only the cron trigger keeps working.

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: wh-reports-schedule
  namespace: phoenixai
spec:
  scaleTargetRef:
    apiVersion: phoenixdata.ai/v1
    kind: PhoenixAIWarehouse
    name: wh-reports
  minReplicaCount: 1
  maxReplicaCount: 10
  triggers:
    - type: cron
      metadata:
        timezone: Asia/Shanghai
        start: "0 8 * * 1-5"
        end: "0 20 * * 1-5"
        desiredReplicas: "4"
    - type: cpu
      metricType: Utilization
      metadata:
        value: "60"      # add nodes when average CPU use is above 60% of the request
```

The HPA now shows both metrics — first the cron trigger, then CPU — and its events tell you which
trigger caused each change. Here the window opened (4 nodes), then a busy period pushed it to 6:

```text
$ kubectl get hpa keda-hpa-wh-reports-schedule -n phoenixai
NAME                           REFERENCE                       TARGETS                 MINPODS   MAXPODS   REPLICAS   AGE
keda-hpa-wh-reports-schedule   PhoenixAIWarehouse/wh-reports   667m/1 (avg), 55%/60%   1         10        6          2h

$ kubectl get events -n phoenixai --field-selector involvedObject.name=keda-hpa-wh-reports-schedule
... New size: 4; reason: external metric s0-cron-Asia-Shanghai-...(...) above target
... New size: 6; reason: cpu resource utilization (percentage of request) above target
```

(`667m/1` is the cron trigger's 4 wanted nodes averaged over 6 pods: it is below target, so the
schedule alone would keep 4, and CPU is what holds the count at 6.)

To scale on the warehouse **query queue** instead of CPU — add CN nodes when queries start to wait —
use a `prometheus` trigger next to the cron trigger, as described in
[Queue-based autoscaling for CN nodes](./queue_based_autoscaling_howto.md#combine-with-a-schedule).

> [!TIP]
> Set a realistic CPU **request** on the CN pods. Utilization is CPU used divided by the request,
> so with a tiny request (say `10m`) even idle CN nodes read several hundred percent and KEDA
> scales straight to `maxReplicaCount`.

### 8.5 CN groups

Each CN group is its own CR with its own replica count, so give each group its own ScaledObject.
A warehouse with groups `wh-prod-az-a` and `wh-prod-az-b` needs two:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: wh-prod-az-a-schedule
  namespace: phoenixai
spec:
  scaleTargetRef:
    apiVersion: phoenixdata.ai/v1
    kind: PhoenixAICnGroup
    name: wh-prod-az-a
  minReplicaCount: 1
  maxReplicaCount: 6
  triggers:
    - type: cron
      metadata:
        timezone: UTC
        start: "0 8 * * 1-5"
        end: "0 20 * * 1-5"
        desiredReplicas: "3"
---
# The same again for wh-prod-az-b: change metadata.name and scaleTargetRef.name.
```

`desiredReplicas` is per group: with two groups and `desiredReplicas: "3"`, the two groups run 6 CN
nodes inside the window. The warehouse's (or cluster's) own CN nodes come on top of that — they
form the builtin group — unless you park them at `replicas: 0`, as
[Deploy CN Groups](../Deploy/deploy_cn_group_howto.md) describes.

`scaleTargetRef.name` is the name of the `PhoenixAICnGroup` resource (`kubectl get pacg -n phoenixai`
lists them). If the groups come from a chart's `cnGroups` / `phoenixAICnGroups` list, leave
`replicas` out of their entries, or every `helm upgrade` writes it back (see the warning in
[Section 4](#4-find-what-you-want-to-scale)).

### 8.6 Scale down faster, or more gently

The HPA that KEDA creates accepts the standard HPA `behavior` settings. This example removes the
5-minute delay and takes nodes away one at a time, one per minute:

```yaml
spec:
  # ... scaleTargetRef, minReplicaCount, maxReplicaCount, triggers as before ...
  advanced:
    horizontalPodAutoscalerConfig:
      behavior:
        scaleDown:
          stabilizationWindowSeconds: 0
          policies:
            - type: Pods
              value: 1
              periodSeconds: 60
```

Without this block, the HPA scales down to the **highest** count it wanted at any time in the last
5 minutes. Two consequences are worth knowing:

- After you lower a schedule (or apply one whose window is not active), expect the old count to
  stay for up to 5 minutes.
- If you remove this block again, the count can briefly go back **up** — to the highest value of
  the last 5 minutes — before it settles. The HPA event then reads `New size: N; reason: All
  metrics below target`, which looks odd but is this rule at work.

## 9. Day-2 operations

### Change the schedule

Edit the YAML file and run `kubectl apply -f` again. KEDA picks up the change within seconds.

### Pause the schedule

To freeze the current node count — for example during maintenance — annotate the ScaledObject:

```bash
kubectl annotate scaledobject wh-reports-schedule -n phoenixai autoscaling.keda.sh/paused="true"
```

While paused, `kubectl get scaledobject` shows `PAUSED True`, KEDA removes its
`keda-hpa-<name>` HPA, and the replica count stays where it is — even if a window opens meanwhile.
You can change the count by hand during the pause; `kubectl scale` works on all three CR kinds:

```bash
kubectl scale paw wh-reports -n phoenixai --replicas=2
```

To resume:

```bash
kubectl annotate scaledobject wh-reports-schedule -n phoenixai autoscaling.keda.sh/paused-
```

KEDA recreates the HPA and brings the count in line with the schedule: within about 30 seconds if
that means adding nodes, after the usual 5-minute delay if it means removing nodes you added by hand
(see [Timing](#65-timing--what-to-expect)).

### Remove the schedule

```bash
kubectl delete scaledobject wh-reports-schedule -n phoenixai
```

KEDA deletes its HPA. The warehouse **keeps the replica count it had at that moment** — it does
not go back to any earlier value. Set the count you want afterwards (in your Helm values or on the
CR). If you prefer KEDA to restore the count the CR had *before* the ScaledObject was created, add
this to the ScaledObject before deleting it:

```yaml
spec:
  advanced:
    restoreToOriginalReplicaCount: true
```

### Do not scale to zero

Keep `minReplicaCount` at 1 or more. KEDA can technically scale a target to 0, but a warehouse or
group with no CN nodes cannot run queries, and scaling PhoenixAI CN nodes to zero and back with
KEDA has not been validated. For the same reason, never set `desiredReplicas: "0"`.

## 10. Troubleshooting

**`kubectl apply` fails with `... is already managed by the hpa '<name>-cn-autoscaler'`**

```text
admission webhook "vscaledobject.kb.io" denied the request: the workload 'kube-anywhere' of type
'phoenixdata.ai/v1.PhoenixAICluster' is already managed by the hpa 'kube-anywhere-cn-autoscaler'
```

The CR still has an `autoScalingPolicy`, so the operator runs its own HPA for it. Remove
`autoScalingPolicy` from the CR (or your Helm values), wait until `kubectl get hpa` no longer lists
`<name>-cn-autoscaler`, then apply the ScaledObject again. If you want CPU scaling as well, use
[Recipe 8.4](#84-a-schedule-plus-cpu-based-scaling).

**`READY` is `False`**

Run `kubectl describe scaledobject <name> -n <ns>` and read the `Conditions` and `Events` at the
bottom.

- `Target resource doesn't exist` — a typo in `scaleTargetRef`: the `kind`, the `name`, or a
  ScaledObject in a different namespace from the CR.
- `failed to ensure HPA is correctly created for ScaledObject` — usually an invalid cron
  expression. The HPA events name the exact problem (next entry).

**The count does not follow the schedule (`ACTIVE` stays `Unknown`, or the HPA shows `<unknown>`)**

Read the HPA's events — they carry the error KEDA hit while evaluating your triggers:

```bash
$ kubectl get events -n phoenixai --field-selector involvedObject.name=keda-hpa-wh-reports-schedule
... FailedGetExternalMetric ... error parsing start schedule: end of range (25) above maximum (23): 25
```

A misspelled `timezone` is the one mistake that shows up **only** in KEDA's own log, while `READY`
stays `True`:

```bash
$ kubectl logs -n keda deploy/keda-operator | grep -i error
... error getting scale decision ... "error": "unable to load timezone. Error: unknown time zone Asia/Shangai"
```

Use the exact IANA name (`Asia/Shanghai`, `America/New_York`, `Europe/Berlin`, `UTC`); the list is
at [Wikipedia: tz database time zones](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones).

**The window opened but nothing happened**

- Check `timezone`. A window written for `Asia/Shanghai` but meant for `UTC` opens eight hours off.
- Check `maxReplicaCount`: it caps `desiredReplicas`.
- Look at the HPA events (Section 6.4) and the CR status:
  `kubectl get paw <name> -n <ns> -o jsonpath='{.status.phase} {.status.reason}'`. If the HPA did
  raise the replica count but pods do not start, the problem is in scheduling the pods (CPU, memory,
  image pull), not in KEDA — `kubectl describe pod` on a pending pod tells you which.

**The window closed but the nodes are still there**

With only a cron trigger, wait 5 minutes — see [Timing](#65-timing--what-to-expect). If the
ScaledObject has other triggers (CPU, or the
[query queue](./queue_based_autoscaling_howto.md)), closing the window only removes the cron
trigger's floor; the other triggers may still ask for those nodes, for as long as the load lasts.
`kubectl describe hpa keda-hpa-<name> -n <ns>` lists every metric with its current value, and the
HPA events name the trigger behind each change.

**A CN pod keeps being removed and re-added, or the schedule stopped working**

Check whether a second HPA targets the same CR:

```text
$ kubectl get hpa -n phoenixai
NAME                                REFERENCE                       TARGETS         MINPODS   MAXPODS   REPLICAS
keda-hpa-wh-reports-schedule        PhoenixAIWarehouse/wh-reports   1500m/1 (avg)   1         5         2
wh-reports-warehouse-cn-autoscaler  PhoenixAIWarehouse/wh-reports   <unknown>/80%   1         2         3
```

`autoScalingPolicy` came back on the CR after the ScaledObject was created (a Helm rollback, an old
values file), so the operator created its own `<name>-cn-autoscaler` HPA again. The two HPAs either
keep overwriting each other — their events alternate between `New size: 3` and `New size: 2` — or
Kubernetes stops both and reports `AmbiguousSelector ... are controlled by multiple HPAs` in their
events. The ScaledObject keeps showing `READY True`. Remove `autoScalingPolicy` again: the operator
deletes its HPA, and KEDA's takes over on its next pass.

**The node count jumps down and back up after a `helm upgrade`**

Your Helm values still set `replicas`. Remove it — see the warning in
[Section 4](#4-find-what-you-want-to-scale).

## 11. Further reading

- [KEDA cron scaler](https://keda.sh/docs/latest/scalers/cron/)
- [ScaledObject reference](https://keda.sh/docs/latest/reference/scaledobject-spec/) — every field,
  including `pollingInterval`, `cooldownPeriod` and `advanced`
- [HPA Automatic Scaling for CN Nodes](./hpa_dynamic_scaling_with_helm_howto.md) — CPU and memory
  based scaling with `autoScalingPolicy`, for when you do not need a schedule
- [Queue-based autoscaling for CN nodes](./queue_based_autoscaling_howto.md) — scaling on the
  warehouse query queue with KEDA and Prometheus
