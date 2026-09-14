---
title: Prerequisites
sidebar_label: Prerequisites
sidebar_position: 1
description: What you must have before installing PhoenixAI, and the five checks that catch the problems which otherwise surface much later as a failure that does not name its cause.
---

# Prerequisites

What to have in hand before you install, and the checks worth running first. It applies to both
ways in — [Install with Helm](./install_with_helm.md) and
[Install with kubectl](./install_with_kubectl.md). Helm is on the list either way: the kubectl
path applies manifests for the operator and the cluster, but the Anywhere console ships only as a
chart.

This is the whole list. Everything else — your license, monitoring, query insights — is set up once
the cluster is running, and none of it blocks an install.

## What you must have

Collect these first. Four of the five come from other people, so requesting them early is what
decides whether this takes an afternoon or a week.

| # | What | Who gives it to you |
| --- | --- | --- |
| 1 | A Kubernetes cluster you can reach with `kubectl`, and permission to create objects in it | your platform / Kubernetes administrator |
| 2 | The name of a **StorageClass** that works in that cluster | the same administrator — the checks below show how to confirm it yourself |
| 3 | **A key file for the PhoenixAI container image registry** | your [PhoenixAI team](https://www.phoenixdata.ai/contact-sales). This is the single most common reason a first install fails |
| 4 | An **S3-compatible bucket**, its region, and an access key / secret key that can read and write it | your cloud or storage administrator. The bucket you name is permanent — see [Decisions you cannot undo](./install_with_helm.md#decisions-you-cannot-undo) |
| 5 | `kubectl` and `helm` installed on your own machine | you |

:::caution Ask for the enterprise image tags, not just registry access
The coordinator and compute-node images must be the enterprise builds, which come from the private
registry your account team names — not the community StarRocks images. The tag alone does not tell
you which you have; what marks the build is the repository it came from. With community images the cluster starts and looks healthy, but **no warehouse compute pods
are ever created and nothing reports an error**. Ask your account team for the image tags that go
with your release at the same time as the key file.
:::

## Which image versions to use

Examples in these pages write versions as `<operator-image-tag>`, `<database-image-tag>` and
`<console-image-tag>`. Substitute the ones for your release. The three are not interchangeable, and
there is no floating tag that always means "the current one".

**If you have an account team**, use the versions they named — those are the builds your release was
qualified against.

**If you are evaluating PhoenixAI**, list what your registry access can see and take the newest
release build:

```bash
gcloud artifacts docker tags list \
  us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/fe-ubuntu
```

Repeat for `cn-ubuntu`, `operator` and `anywhere`. Authenticate first with the key file from
[Step 1](./install_with_helm.md#step-1--get-the-images-and-teach-kubernetes-to-pull-them).

<!-- WARNING: check before publish -- verify this command against the real Artifact Registry repo,
     with the service-account key file Step 1 creates rather than a developer's own gcloud session.
     A customer's key may be scoped to pull only, which is not necessarily enough to list tags. If
     it is not, name the route that does work here instead. -->

**Write the version down in either case.** Pinning it in your values file is what makes the install
reproducible, and what stops a later `helm upgrade` from moving the cluster onto a build you have
not qualified.

## Check your environment

Five things to confirm before you start. Each takes seconds, and each one corresponds to a way the
install fails later with a message that does not name the real cause.

**1. `kubectl` reaches the cluster, and the nodes are healthy.**

```bash
kubectl get nodes
```

Every node should say `Ready`. On a cluster that was just created, a node can report `NotReady` for
the first minute while its networking starts — re-run the command until it turns `Ready` rather than
reading it as a fault. If the command fails outright instead of printing nodes, your `kubectl` is not
configured for the cluster yet — that is your administrator's side, not this page's.

**2. Helm is installed and recent enough.**

```bash
helm version
```

Helm 3.8 or newer. If the command is not found, install Helm from
[helm.sh](https://helm.sh/docs/intro/quickstart/).

**3. Your `kubectl` has enough permission.**

Installing creates a namespace, custom resource definitions, StatefulSets, Deployments, Services,
Secrets, ConfigMaps, PersistentVolumeClaims, a ServiceAccount and its roles. A cluster administrator
already has all of it. If you are working with a restricted account, hand your administrator
[Least privilege to deploy](./least_permission_to_deploy_phoenixai_howto.md), which lists
exactly what to grant.

**4. Pick the StorageClass to use.**

```bash
kubectl get storageclass
```

Note the name — it goes into the values file as `<storage-class>`. A class marked `(default)` is the
one Kubernetes uses when nothing asks for a class by name, but the install pages always name it
explicitly, because an empty setting is *rejected* by PhoenixAI's configuration schema rather than
silently defaulted.

If the list is empty, stop here: no PhoenixAI pod can start, and the failure will show up later as
pods stuck in `Pending`. Your administrator has to install a storage driver first — on managed
Kubernetes this is usually a one-click add-on.

**5. The cluster has room.** The values file in [Install with Helm](./install_with_helm.md)
requests roughly **2.5 CPU cores and 9 GiB of memory** in total, and allows bursting to about
**9 cores and 18 GiB**:

| Pods | Requests each | Limits each |
| --- | --- | --- |
| 3 coordinators | 500m CPU / 2 GiB | 2 CPU / 4 GiB |
| 1 compute node | 500m CPU / 2 GiB | 2 CPU / 4 GiB |
| 1 operator | chart default | chart default |
| 1 console | chart default | chart default |

One large node is enough to start: this shape came up on a single 8-core / 32 GiB node with room to
spare. Two or three worker nodes are still the better arrangement, because the three coordinators can
then sit on different nodes and survive one of them failing. Requests that no node can satisfy appear
as pods in `Pending` with an `Insufficient cpu` or `Insufficient memory` event.
