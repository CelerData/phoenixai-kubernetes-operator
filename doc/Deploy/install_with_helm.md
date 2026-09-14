---
sidebar_label: Install with Helm
sidebar_position: 3
title: Install with Helm
description: A complete, ordered install of the operator, a shared-data PhoenixAI cluster and the PhoenixAI Anywhere console with the kube-anywhere Helm chart — written so that no prior Kubernetes or Helm experience is assumed.
---

# Deploy PhoenixAI and the Anywhere console

This page walks through one complete installation, in order, with a check after every step. It
assumes you have **never used Helm** and know only that Kubernetes is "the thing our cluster runs
on". Every command can be copied as-is once you have filled in the values file in
[Step 3](#step-3--set-the-root-password-and-write-your-values-file).

**What you have at the end**

- a PhoenixAI cluster in elastic (shared-data) mode — 3 coordinators and 1 compute node — storing
  its data in your object-storage bucket;
- the PhoenixAI operator, which keeps that cluster running;
- the **PhoenixAI Anywhere console** in your browser, already showing that cluster.

**How long it takes.** About 45 minutes of reading and typing the first time, of which roughly 10
minutes is waiting for pods to start. Most of the elapsed time goes into gathering the
prerequisites and Step 1 — collecting credentials from other people. Nothing here is undone by
repeating it: a corrected values file is re-applied with the same command
(`helm upgrade --install`).

:::note Already comfortable with Kubernetes?
If you want the fastest possible end-to-end install on a laptop instead, use
[Quick start with Amazon S3](../GetStarted/quickstart_s3.md) or
[Quick start with MinIO](../GetStarted/quickstart_minio.md). They cover the same ground in fewer
words and assume you can fill in the gaps.
:::

:::note Before you start
[Prerequisites](./prerequisites.md) lists what you must have in hand and the five checks worth
running first. This page assumes you have been through it.
:::

## What you are installing

Four pieces, installed by **one** command. It is worth 60 seconds to get the picture straight,
because these names show up in every later step.

| Piece | What it does |
| --- | --- |
| **PhoenixAI operator** | A small program that runs inside Kubernetes and builds, repairs and scales PhoenixAI clusters for you. You never talk to it directly. |
| **PhoenixAI cluster** | The database itself: **coordinators** (FE — accept SQL, plan queries, hold metadata) and **compute nodes** (CN — do the work). In elastic mode the table data lives in your bucket, not on the nodes. |
| **PhoenixAI Anywhere console** | The web UI: cluster inventory, health checks, monitoring, license and usage, support bundles, plus a per-cluster view for the people who write queries. |
| **Warehouse** *(optional, later)* | An extra, separately scalable group of compute nodes. Not part of this page — see [Deploy a Warehouse](./deploy_warehouse_howto.md). |

**How those map to charts.** `kube-anywhere` is a single chart wrapping three subcharts —
`operator`, `phoenixai`, and `anywhere`, the console, which is included when you set
`anywhere.enabled=true`. Installing `kube-anywhere` installs all of them, and uninstalling it
removes what it installed. If you would rather manage the operator and the cluster on their own
schedules, `operator` and `phoenixai` can be installed separately instead. Warehouses come from a
chart of their own, `phoenixai/warehouse`. The chart has been split this way since v1.8.0.

And the four words from Helm and Kubernetes that this page uses:

| Word | Meaning here |
| --- | --- |
| **namespace** | A folder inside the Kubernetes cluster that keeps one installation's objects together. This page uses `phoenixai`. |
| **pod** | One running container (or a small group of them). A coordinator is a pod; the console is a pod. |
| **StorageClass** | The cluster's recipe for handing out disks. Coordinators, compute nodes and the console each ask for one. If the recipe does not work, pods sit in `Pending` forever, so the [prerequisites](./prerequisites.md) have you pick a working one. |
| **chart / values file / release** | A **chart** is a package (`kube-anywhere` is ours). A **values file** is your settings for it — one YAML file you keep and reuse. A **release** is one installation of a chart, under a name you pick. |

:::caution Object names do not follow your release name
The objects created below are called `kube-anywhere-fe-0`, `kube-anywhere-console`, and so on, no
matter what you name the release. The prefix comes from the chart, not from your `helm install`
command. [Step 4](#step-4--install) has a table of every name, so you can always find things.
:::

## Decisions you cannot undo

Four of the settings you write in [Step 3](#step-3--set-the-root-password-and-write-your-values-file)
are fixed when the cluster is created. Changing any of them afterwards means building a new cluster
and moving the data across, so they are worth deciding now rather than meeting later.

| Decision | Written as | Why it is fixed |
| --- | --- | --- |
| **The database root password** | `initPassword` | The chart can set it on a first install only, and the job that sets it belongs to that install — an upgrade started while it is still retrying removes it, leaving `root` open **and** compute nodes unable to register. Re-running the Step 4 command a minute after installing is enough to lose it, so let Step 4 finish before touching anything. |
| **The bucket, its region and path** | `phoenixAIFeSpec.config` | `cloud_native_storage_type` and the `aws_s3_*` settings are immutable coordinator configuration. A different bucket is a different cluster. |
| **The StorageClass for the node disks** | `storageSpec.storageClassName` | A StatefulSet's volume claims cannot be edited after it is created. Disk *sizes* can still be grown later — but only if the class you pick sets `allowVolumeExpansion: true`, so this choice decides whether growing is possible at all. |
| **Whether names are case-sensitive** | `phoenixAIFeSpec.config` | `enable_table_name_case_insensitive` is, in the product's own words, *"Only configurable during cluster initialization, immutable once set."* Left alone, catalog, database and table names are case-**sensitive**. |

`run_mode = shared_data` is fixed at creation too, but it is not a decision: Anywhere operates
elastic clusters only, so leave that line as Step 3 writes it.

## Step 1 — Get the images, and teach Kubernetes to pull them

The operator, coordinator, compute-node and console images are **enterprise builds in a private
registry**. Kubernetes therefore needs credentials, stored as a Kubernetes *secret*. Without them
every pod fails with `ImagePullBackOff` — the most common first-install failure of all.

**1. Request access.** Ask your [PhoenixAI team](https://www.phoenixdata.ai/contact-sales) for access to the PhoenixAI container image
registry, and for the image versions that match your release. The images live in **Google Artifact
Registry**, and access reaches you in one of two shapes. Ask which one you are getting — the answer
decides whether you touch Google Cloud at all.

**Shape A — they send you a key file.** The account that may read the registry belongs to PhoenixAI,
so only PhoenixAI can issue a key for it. You receive one JSON file and there is nothing for you to
do in Google Cloud. Save it somewhere your install machine can read, keep it out of version control,
and go to substep 2.

**Shape B — they grant an account of yours.** Use this when your organization would rather hold its
own credential. It needs a Google Cloud project of your own, and permission in that project to
create service-account keys (the Service Account Key Admin role). Create the account, send its
address to your account team, and issue the key yourself once they confirm the grant:

```bash
# 1. create a service account in YOUR project
gcloud iam service-accounts create phoenixai-puller \
  --project=<your-gcp-project> \
  --display-name="Pulls PhoenixAI images"

# 2. send this address to your PhoenixAI account team and wait for them to
#    confirm they granted it read access to the registry
echo "phoenixai-puller@<your-gcp-project>.iam.gserviceaccount.com"

# 3. issue the key file
gcloud iam service-accounts keys create phoenixai-puller.json \
  --iam-account=phoenixai-puller@<your-gcp-project>.iam.gserviceaccount.com
```

The read permission itself (Artifact Registry Reader, on PhoenixAI's registry) is granted on the
PhoenixAI side — you cannot grant it to yourself, which is why step 2 above is a wait.

Either way, what you hold at the end is one JSON key file, and the rest of this page is identical.

**2. Create the namespace:**

```bash
kubectl create namespace phoenixai
```

**3. Create the secret.** For Google Artifact Registry two of the three fields are fixed, so only the
path to your key file changes:

```bash
kubectl -n phoenixai create secret docker-registry phoenixai-registry \
  --docker-server=us-west1-docker.pkg.dev \
  --docker-username=_json_key \
  --docker-password="$(cat <path-to-your-key-file>.json)"
```

- `us-west1-docker.pkg.dev` is the registry host — the part before the first `/` in the
  `image.repository` values this chart ships. If your account team points you at a different region,
  use the host they give you.
- `_json_key` is **not** a placeholder. It is the literal user name Google Artifact Registry expects
  when the password is the contents of a service-account key file. Type it exactly.
- The password is the **whole JSON file**, which is what `$(cat ...)` passes in — not a field from
  inside it.

**4. Confirm it exists:**

```bash
kubectl -n phoenixai get secret phoenixai-registry
```

:::caution Two things people get wrong here
**The secret is per namespace.** It must live in the same namespace as the install. A secret in
`default` does nothing for pods in `phoenixai`.

**You must reference it in three places** in the values file — once for the operator, once for the
cluster's components, once for the console. They are separate components with separate settings, so
naming it once is not enough. Step 3 marks all three. A warehouse, added later, needs a fourth
reference in its own values file.
:::

:::note The credentials have to keep working, not just work once
The operator's image is re-fetched every time its pod starts, so an expired or deleted secret
breaks a restart weeks after a successful install. Rotate the secret in place — `kubectl -n
phoenixai delete secret phoenixai-registry` followed by the same `create secret` command — rather
than letting it lapse.
:::

### Why a key file, and not a user name and password

Google Artifact Registry has **no user name and password credential of its own**. It accepts exactly
four things, and only one of them suits a long-running Kubernetes cluster:

| What Google accepts | Docker user name | Password | Usable here? |
| --- | --- | --- | --- |
| Service-account key file | `_json_key` | the whole JSON file | **Yes** — what this page uses |
| The same file, base64-encoded | `_json_key_base64` | that base64 text | Yes, if that is the form you were given |
| Short-lived access token | `oauth2accesstoken` | `gcloud auth print-access-token` output | Only with automation — it expires after 60 minutes |
| gcloud credential helpers | — | — | No — they authenticate `docker` on a workstation; Kubernetes reads a Secret, not your gcloud session |

So the fixed strings above are not our convention, they are Google's: `_json_key` is what tells
Artifact Registry that the password is a key file.

If your security policy forbids long-lived keys, there are two ways out:

- **Short-lived tokens.** Same command with `--docker-username=oauth2accesstoken` and
  `--docker-password="$(gcloud auth print-access-token)"`. The token dies after an hour, so something
  has to recreate the Secret on a schedule — reasonable if you already run such automation, painful
  otherwise, and a pod that restarts after the token expired cannot pull.
- **Mirror the images into a registry you already run** — what most organizations with a strict policy
  end up doing. Pull the four images once, push them to your own registry, then in your values file
  override `image.repository` for the operator, the cluster components and the console, and create the
  pull secret for **your** registry instead. That registry may well accept a plain user name and
  password, in which case `create secret docker-registry` takes exactly that:

  ```bash
  kubectl -n phoenixai create secret docker-registry phoenixai-registry \
    --docker-server='<your-registry-host>' \
    --docker-username='<user-name>' \
    --docker-password='<password>'
  ```

  Mirroring also removes the install's dependency on reaching the internet, which matters in a
  restricted network.

## Step 2 — Get the chart

The chart reaches you one of two ways, and the next step is the same either way. Look first:

```bash
helm repo add phoenixai https://celerdata.github.io/phoenixai-kubernetes-operator
helm repo update phoenixai
helm search repo phoenixai
```

A repository that carries your release prints five charts — `kube-anywhere` and the subcharts it is
built from:

```text
NAME                       CHART VERSION    APP VERSION  DESCRIPTION
phoenixai/kube-anywhere    2.0.0            4.1.5-ee     kube-anywhere includes three subcharts, operato...
phoenixai/operator         2.0.0            2.0.0        A Helm chart for PhoenixAI operator
phoenixai/phoenixai        2.0.0            4.1.5-ee     A Helm chart for PhoenixAI cluster
phoenixai/anywhere         2.0.0            v2.0.0       A Helm chart for PhoenixAI Anywhere — a read-on...
phoenixai/warehouse        2.0.0            4.1.5-ee     Warehouse is currently a feature of the Phoenix...
```

The versions above are only an example. Use whichever your own command prints, and name them
explicitly in Step 4 — that is what makes the install reproducible.

**If the list includes `phoenixai/kube-anywhere`**, you are done with this step and you install from
the repository in Step 4.

**If it does not**, your release has not been published to that repository yet, and your account team
gives you the chart as a package file (`kube-anywhere-<version>.tgz`) instead. Save it next to your
values file; Step 4 shows the one line that differs.

What each of those five is:

| Chart | Installs |
| --- | --- |
| `phoenixai/kube-anywhere` | The operator and a cluster, plus the console when `anywhere.enabled=true`. What this page uses |
| `phoenixai/operator` | The operator on its own |
| `phoenixai/phoenixai` | A cluster on its own |
| `phoenixai/anywhere` | The console on its own, alongside an operator you install and manage separately. It is the same chart `kube-anywhere` pulls in, so through `kube-anywhere` its values carry the `anywhere.` prefix and here they do not |
| `phoenixai/warehouse` | A warehouse for an existing cluster |

Every value each of them accepts is documented in a `README.md` that travels inside the chart, so
you can read it without leaving the terminal: `helm show readme phoenixai/kube-anywhere` prints it,
and `helm show values phoenixai/kube-anywhere` prints the annotated defaults. Both work for any of
the five names above.

:::caution Do not substitute a chart that merely looks similar
The repository also carries older charts from the previous product generation, with names like
`celerdata` and `kube-celerdata`. They are a different, earlier product — not this one under another
name, and not a fallback. If `kube-anywhere` is absent, ask your account team for the package file;
do not install `kube-celerdata` instead.
:::

## Step 3 — Set the root password, and write your values file

**First, decide the database root password.** PhoenixAI's `root` user starts with **no password**,
and the chart can set one for you — but only during this first install. A later `helm upgrade`
cannot, so a cluster installed without it keeps an open `root` account until someone changes it by
hand.

Put the password in a Secret rather than in your values file, so it stays out of the file and out of
what `helm get values` prints:

```bash
kubectl -n phoenixai create secret generic phoenixai-root-password \
  --from-literal=password='<root-password>'
```

The values file below then points at that Secret. (Plaintext in the values file also works — see
[Initialize Root Password When First Deploy](../Configure/initialize_root_password_howto.md) for
both forms.)

**Then write the values file.** This is the only file you author, and the only step that needs
thought. Save it as `my-values.yaml`, keep it — you will reuse it for every upgrade — and treat it as
sensitive, since it holds your storage keys.

Replace every `<...>` placeholder; the table after the file says where each one comes from.

```yaml
# my-values.yaml

# ----------------------------------------------------------------------------
# The operator
# ----------------------------------------------------------------------------
operator:
  phoenixAIOperator:
    # (1 of 3) Pull the operator image.
    imagePullSecrets:
      - name: phoenixai-registry
    # The version your account team named. See the note under this file.
    image:
      tag: "<operator-image-tag>"
    # The console reads everything through this API. Leave it on, or the console
    # installs successfully and then shows no clusters at all.
    enableApiServer: true
    # Manage only this namespace. Also keeps the install's permissions
    # namespace-scoped instead of cluster-wide.
    watchNamespace: "phoenixai"

# ----------------------------------------------------------------------------
# The PhoenixAI cluster
# ----------------------------------------------------------------------------
phoenixai:
  # Set the database root password from the Secret created above. This works on
  # a first install only — a later helm upgrade cannot set it, so leaving it off
  # now means the cluster keeps an open root account.
  initPassword:
    enabled: true
    passwordSecret: phoenixai-root-password

  phoenixAICluster:
    enabledCn: true
    # Report the release as ready only once the cluster has fully rolled out.
    waitForFullRollout: true
    componentValues:
      # (2 of 3) Pull the coordinator and compute-node images.
      imagePullSecrets:
        - name: phoenixai-registry
      # The database version your account team named. Setting it here covers
      # both coordinators and compute nodes. If you ever set an `image` block
      # inside phoenixAIFeSpec or phoenixAICnSpec instead, give repository and
      # tag together there: a component's own image block replaces this one
      # wholesale rather than merging into it.
      image:
        tag: "<database-image-tag>"

  # Coordinators (FE)
  phoenixAIFeSpec:
    replicas: 3
    resources:
      requests: { cpu: 500m, memory: 2Gi }
      limits: { cpu: 2, memory: 4Gi }
    storageSpec:
      name: fe-storage
      # Always name a class explicitly. An empty value is rejected by the
      # configuration schema, not defaulted.
      storageClassName: "<storage-class>"
      storageSize: 20Gi
      logStorageSize: 5Gi
    config: |
      LOG_DIR = ${STARROCKS_HOME}/log
      JAVA_OPTS="-Dlog4j2.formatMsgNoLookups=true -Xmx3072m -XX:+UseG1GC"
      http_port = 8030
      rpc_port = 9020
      query_port = 9030
      edit_log_port = 9010
      # ---- These lines are what make it an elastic (shared-data) cluster. ----
      # The Anywhere console operates elastic clusters only, and the mode cannot
      # be changed after the cluster is created. Do not remove them.
      run_mode = shared_data
      cloud_native_meta_port = 6090
      cloud_native_storage_type = S3
      enable_load_volume_from_conf = true
      aws_s3_path = <bucket>/data
      aws_s3_region = <region>
      aws_s3_endpoint = s3.<region>.amazonaws.com
      aws_s3_access_key = <access-key>
      aws_s3_secret_key = <secret-key>
      aws_s3_use_aws_sdk_default_behavior = false
      # Catalog, database and table names are case-sensitive unless this is turned
      # on, and it can only be set now — see "Decisions you cannot undo" above.
      # enable_table_name_case_insensitive = true

  # Compute nodes (CN)
  phoenixAICnSpec:
    replicas: 1
    resources:
      requests: { cpu: 500m, memory: 2Gi }
      limits: { cpu: 2, memory: 4Gi }
    storageSpec:
      name: cn-storage
      storageClassName: "<storage-class>"
      storageSize: 20Gi
      logStorageSize: 5Gi
    config: |
      sys_log_level = INFO
      thrift_port = 9060
      webserver_port = 8040
      heartbeat_service_port = 9050
      brpc_port = 8060
      datacache_enable = true
      datacache_mem_size = 5%
      # Must be greater than zero in elastic mode, or CREATE TABLE fails with
      # "no valid cache space".
      datacache_disk_size = 4294967296

# ----------------------------------------------------------------------------
# The Anywhere console
# ----------------------------------------------------------------------------
anywhere:
  # The console is off by default, because it needs object storage of its own.
  enabled: true
  # (3 of 3) Pull the console image.
  imagePullSecrets:
    - name: phoenixai-registry
  # The console version your account team named.
  image:
    tag: "<console-image-tag>"

  # Where the operator's API lives. This default matches the install above; it
  # needs changing only if you renamed the operator's resources.
  operatorApiAddrs:
    - "kube-anywhere-operator-api:9090"
  # The namespaces holding the clusters this console serves. Must include the
  # namespace above; also keeps the console's permissions namespace-scoped.
  watchNamespaces:
    - "phoenixai"

  persistence:
    storageClass: "<storage-class>"
    size: 10Gi

  dependencies:
    # The console keeps large artifacts — query profiles and support bundles —
    # in object storage. It verifies this at startup with a write, a read and a
    # delete, so a wrong value here stops the console from starting instead of
    # failing quietly much later.
    s3:
      bucket: "<bucket>"
      # A key prefix of its own, so one bucket can hold both the cluster's data
      # (under data/ above) and the console's artifacts.
      path: "anywhere"
      region: "<region>"
      endpoint: "https://s3.<region>.amazonaws.com"
      accessKey: "<access-key>"
      secretKey: "<secret-key>"
      # Leave false for Amazon S3. Self-hosted S3-compatible storage such as
      # MinIO usually needs true.
      usePathStyle: false
```

| Placeholder | Where it comes from |
| --- | --- |
| `<storage-class>` | `kubectl get storageclass` — see [Prerequisites](./prerequisites.md) |
| `<bucket>`, `<region>` | your bucket. The same bucket serves the cluster (`data/`) and the console (`anywhere/`); nothing else in it is touched |
| `<access-key>`, `<secret-key>` | a key pair that can **read and write** that bucket |
| `<operator-image-tag>`, `<database-image-tag>`, `<console-image-tag>` | the three versions your account team named — see the note below |
| `phoenixai-registry` | the secret from Step 1. If you named it differently, change all three references |
| `phoenixai-root-password` | the Secret created at the start of this step |

:::caution Ask for the three image tags, and set them
The chart carries a default tag for each component, but a default only resolves once that exact
version has been published to the registry. Ask your account team for the operator, database and
console versions that go with your release, and write all three into the file. If a tag names an
image the registry does not hold, the pod fails with `ImagePullBackOff` **even though your
credentials are correct** — and the message says nothing about a missing version, so it is easy to
spend an hour re-checking the pull secret instead.

Naming the versions you were given is also what makes the install reproducible: the same values file
brings up the same cluster next month.
:::

:::caution Elastic mode is decided now, not later
`run_mode = shared_data` and the `aws_s3_*` lines under it are what create an elastic cluster. A
cluster created without them is a **classic** cluster: the console will list it, but every console
feature refuses to operate on it, and the mode cannot be switched afterwards — the cluster has to be
recreated. If you change nothing else in this file, keep that block.
:::

The `dependencies:` block above has a `prometheus:` section beside `s3:`, left out here to keep the
path short. It is worth adding: until it is wired, the console's monitoring views stay empty and a
support bundle's metrics snapshot comes back with no data — [Step 7](#step-7--what-to-set-up-next)
says what else that costs. Adding it later is an edit to this same file and the Step 4 command
again, not a reinstall. See [Deploy Prometheus and Grafana](../Monitor/deploy-prometheus-grafana.md)
and [Anywhere Console monitoring](../Monitor/anywhere-monitoring.md).

## Step 4 — Install

From the chart repository:

```bash
helm upgrade --install kube-anywhere phoenixai/kube-anywhere \
  --namespace phoenixai -f my-values.yaml
```

Or, if Step 2 left you with a package file, point at the file instead — nothing else changes:

```bash
helm upgrade --install kube-anywhere ./kube-anywhere-<version>.tgz \
  --namespace phoenixai -f my-values.yaml
```

`upgrade --install` is deliberate: the same command installs the first time and applies every later
change, so there is only one command to remember.

Watch the pods appear:

```bash
kubectl -n phoenixai get pods -w
```

Expect the operator, the console and a short-lived password job within seconds, then the coordinators
one at a time (`kube-anywhere-fe-0`, `-1`, `-2`), then the compute node once a coordinator can accept
it. Measured on an idle single-node cluster pulling the database images over the network for the first
time: everything settled in **five minutes**, of which about 20 seconds was the image download. Press
`Ctrl+C` to stop watching. The finished state:

```text
NAME                                      READY   STATUS      RESTARTS        AGE
kube-anywhere-cn-0                        1/1     Running     0               2m41s
kube-anywhere-console-0                   1/1     Running     0               4m55s
kube-anywhere-fe-0                        1/1     Running     0               4m53s
kube-anywhere-fe-1                        1/1     Running     0               3m43s
kube-anywhere-fe-2                        1/1     Running     0               2m54s
kube-anywhere-initpwd-gr8n6               0/1     Completed   4 (3m53s ago)   4m55s
kube-anywhere-operator-6d554cb5b9-8c648   1/1     Running     0               4m55s
```

:::note `kube-anywhere-initpwd-...` looks broken before it succeeds
That pod is the one-off job that sets the root password from Step 3. It starts immediately, while the
coordinators are still booting, so its first attempts cannot connect and it shows `Error` with a
climbing restart count for a minute or two. That is the retry working, not a failure. It ends as
`Completed` — the run above took four attempts — and `kubectl -n phoenixai get job` then reports
`COMPLETIONS 1/1`.

Let it get that far before you re-run the command above. The job belongs to this install only, so an
upgrade started while it is still retrying removes it and the password is never set — see
[the compute node never joins](#the-compute-node-never-joins) if that happens.
:::

Anything not `Running` after a few minutes has a reason worth reading rather than waiting out:

```bash
kubectl -n phoenixai get pods
kubectl -n phoenixai describe pod <pod-name> | tail -25
```

Take the `Events` at the bottom to [Troubleshooting](#troubleshooting).

Here is what everything is called — remember that the names come from the chart, not from your
release name:

| What | Kubernetes object |
| --- | --- |
| operator | Deployment `kube-anywhere-operator` |
| the API the console reads | Service `kube-anywhere-operator-api` |
| the cluster, as one object | `phoenixaicluster/kube-anywhere` |
| coordinators | pods `kube-anywhere-fe-0` … `-2` |
| compute node | pod `kube-anywhere-cn-0` |
| console | pod `kube-anywhere-console-0`, Service `kube-anywhere-console` |
| console sign-in accounts | Secret `kube-anywhere-console-admin` |
| the console's own disk | PersistentVolumeClaim `data-kube-anywhere-console-0` |

## Step 5 — Check the cluster is really up

Ask the operator for its own summary:

```bash
kubectl -n phoenixai get phoenixaicluster
```

```text
NAME            PHASE     FESTATUS   CNSTATUS   FEPROXYSTATUS
kube-anywhere   running   running    running
```

`FEPROXYSTATUS` stays empty — the optional FE proxy is not part of this install.

Then ask the database itself. This runs a MySQL client inside a coordinator, so you need nothing
installed locally. Use the root password you set in Step 3 — the password follows `-p` with no
space between them:

```bash
kubectl -n phoenixai exec -it kube-anywhere-fe-0 -- \
  mysql -h127.0.0.1 -P9030 -uroot -p'<root-password>' -e "SHOW FRONTENDS\G SHOW COMPUTE NODES\G SHOW WAREHOUSES\G"
```

Three things to confirm:

- `SHOW FRONTENDS` lists three rows with `Alive: true`;
- `SHOW COMPUTE NODES` lists your compute node with `Alive: true`;
- `SHOW WAREHOUSES` lists `default_warehouse`. **This is also your proof that the cluster is
  elastic**, because warehouses exist only in elastic mode. If the statement errors instead, the
  `run_mode` block did not take effect — see
  [the console lists the cluster but every page says it is not supported](#the-console-lists-the-cluster-but-every-page-says-it-is-not-supported).

:::note If that command works with no password at all, Step 3 did not take effect
`root` is authenticated the same way over `127.0.0.1` inside a coordinator as it is over the
cluster's Service — there is no loopback exemption. With a password set, dropping the `-p` is refused
on both:

```text
ERROR 1045 (28000): Access denied for user 'root' (using password: NO)
```

So if you *can* connect with no password, the password from Step 3 was never applied: `root` is open
to anything on the cluster network, and compute nodes cannot register either.
[The compute node never joins](#the-compute-node-never-joins) has the check and the fix.
:::

## Step 6 — Open the console

The console is an ordinary web service inside the cluster. The quickest way to reach it from your
own machine is to forward its port:

```bash
kubectl -n phoenixai port-forward svc/kube-anywhere-console 8090:8090
```

Leave that running, and in a second terminal confirm the service answers:

```bash
curl -s localhost:8090/api/v1/health
# {"code":20000,"data":{"status":"ok"}}
```

Read the administrator password the chart installed:

```bash
kubectl -n phoenixai get secret kube-anywhere-console-admin \
  -o jsonpath='{.data.admin}' | base64 -d; echo
```

Open **http://localhost:8090** and sign in as `admin` with that password. The cluster list should
show `kube-anywhere` in the `phoenixai` namespace, reported as elastic. If the list is empty, see
[the console shows no clusters](#the-console-shows-no-clusters).

:::caution Change this password before anyone else can reach the console
If the command above printed a long random string, that password was generated for your
installation alone and is already private to it.

If it printed something short and guessable — `admin`, for instance — your chart version installed a
**well-known default**, and anyone who can reach the console can sign in as an administrator.
Replace it now, before you put an Ingress or a load balancer in front of the console. An
administrator session is what gates the console's most sensitive actions, so treat this as the last
required step of the install rather than as hardening you will get to later.

**Set it in `my-values.yaml`, not with `kubectl`.** The chart renders this Secret from
`anywhere.admin.users` on every install *and every upgrade*, so a password written straight into the
Secret is put back to the chart's value the next time you run the Step 4 command:

```yaml
anywhere:
  admin:
    users:
      admin: "<a long random password>"
```

Then re-run the Step 4 command. To keep passwords out of the values file altogether, point
`anywhere.admin.existingSecret` at a Secret you manage yourself and the chart renders none.

Patching the Secret directly takes effect within about a minute, which is useful for locking the
console down right now — but follow it with the values change above, or the next upgrade restores
the well-known default:

```bash
kubectl -n phoenixai patch secret kube-anywhere-console-admin \
  --type merge -p "{\"stringData\":{\"admin\":\"$(openssl rand -base64 24)\"}}"
```
:::

Accounts live in that one Secret — one entry per user name. Add, remove or rotate them by editing
it; changes take effect within about a minute and need no restart:

```bash
kubectl -n phoenixai edit secret kube-anywhere-console-admin
```

Mirror anything you want to keep in `anywhere.admin.users`, or the next `helm upgrade` re-renders it
away.

There is a second sign-in page, for the people who **query** the cluster rather than operate it, at
**http://localhost:8090/cluster-console/login**. It takes a database user of the cluster itself —
created with SQL inside PhoenixAI — not a console account. The two sign-ins are independent, and one
browser can hold both at once.

:::note Port forwarding is for you, not for your users
`kubectl port-forward` lasts only as long as the command runs, and only for the machine running it.
To let colleagues reach the console, ask your Kubernetes administrator to put an Ingress or a
load-balancing Service in front of the `kube-anywhere-console` Service. Terminate TLS there — inside
the cluster the console speaks plain HTTP — and do not expose it to the public internet.
:::

## Step 7 — What to set up next

- **Register your license.** The console's health checks report a cluster that has no valid
  PhoenixAI Database license, so do this before judging a red result.
- **Add a warehouse**, if you want compute you can scale on its own:
  [Deploy a Warehouse](./deploy_warehouse_howto.md). The `PhoenixAIWarehouse` CRD ships with the
  operator chart you just installed, so no operator restart is involved. If you set a root
  password in Step 3, the warehouse needs it too: its compute nodes register themselves as `root`,
  and the warehouse chart does not inherit the cluster's `initPassword` setting. That guide's
  section on giving the warehouse the cluster's root password has the three lines to add.
- **Turn on monitoring.** Nothing breaks without a Prometheus wired to Anywhere — a deployment
  that never has one is supported — but three things quietly stop working: the System Monitoring
  charts and the pod-utilization view stay empty, every cluster carries a standing warning in its
  health checks, and a support bundle's metrics snapshot comes back with no data in it. None of
  that announces itself at the time, which is the reason to do it early rather than when you next
  need a bundle. See [Deploy Prometheus and Grafana](../Monitor/deploy-prometheus-grafana.md), then
  [Anywhere Console monitoring](../Monitor/anywhere-monitoring.md).
- **Turn on query insights.** Two switches, both in `my-values.yaml`: set
  `anywhere.queryHistory.enabled: true`, and add `enable_collect_query_detail_info = true` to the
  coordinator configuration — the same `phoenixai.phoenixAIFeSpec.config` block you already wrote.
  Then re-run the Step 4 command; the coordinators restart with the new configuration. The console's
  query-insights page names whichever of the two is still missing.
- **Keep `my-values.yaml`.** Every later change — a bigger disk, more compute nodes, a different
  password source — is an edit to that file followed by the same `helm upgrade --install` command
  from Step 4.

## Troubleshooting

Match the symptom you actually see. `kubectl -n phoenixai describe pod <pod-name>` and
`kubectl -n phoenixai logs <pod-name>` are the two commands behind nearly all of these; add
`--previous` to `logs` when a pod has already restarted.

### `ImagePullBackOff` or `ErrImagePull`

Kubernetes cannot download an image. In order of likelihood:

1. there is no pull secret in this namespace — go back to
   [Step 1](#step-1--get-the-images-and-teach-kubernetes-to-pull-them);
2. the secret exists, but in a **different namespace**:
   `kubectl get secret --all-namespaces | grep phoenixai-registry`;
3. the name in the values file does not match the secret's name;
4. it was referenced in only some of the three places, so some pods pull and others do not — which
   is why this often affects only part of the install;
5. the credentials are expired or lack read access — ask your account team to confirm.

`kubectl -n phoenixai describe pod <pod-name> | tail -20` prints the registry's own refusal, which
is what distinguishes "no credentials" from "credentials rejected".

### A pod stays `Pending`

Nothing has started it yet. `kubectl -n phoenixai describe pod <pod-name> | tail -25` names one of
two causes:

- **`pod has unbound immediate PersistentVolumeClaims`** — a disk problem. Check
  `kubectl -n phoenixai get pvc` and `kubectl -n phoenixai describe pvc <claim>`. Usually the
  `storageClassName` does not exist (compare it against `kubectl get storageclass`), or the cluster
  has no working storage driver, which your administrator has to install.
- **`Insufficient cpu` / `Insufficient memory`** — no node has room. Lower `replicas` or the
  `requests` in your values file, or add capacity.

### The compute node never joins

```bash
kubectl -n phoenixai logs kube-anywhere-cn-0 | tail -20
```

```text
[...] Add myself (kube-anywhere-cn-0...:9050) into FE ...
ERROR 1045 (28000): Access denied for user 'root' (using password: YES)
```

A compute node registers itself in a coordinator over SQL as `root`, with the password from Step 3.
`using password: YES` rarely means the password in your values file is wrong. It usually means the
password was never applied to the cluster, so the coordinator still expects no password at all.

That is what happens when the `kube-anywhere-initpwd` job never finished. The job belongs to the
install that created it and nothing recreates it, so an upgrade started while it was still retrying
removes it — re-running the Step 4 command a minute after installing is enough to lose it. `root` is
then left open **and** the compute nodes cannot join.

Confirm it by connecting as `root` with no password at all:

```bash
kubectl -n phoenixai exec kube-anywhere-fe-0 -- env MYSQL_PWD= \
  mysql -hkube-anywhere-fe-service -P9030 -uroot -e "SELECT user();"
```

If that **succeeds**, set the password by hand — the compute node registers within seconds:

```bash
kubectl -n phoenixai exec kube-anywhere-fe-0 -- env MYSQL_PWD= \
  mysql -h127.0.0.1 -P9030 -uroot -e "SET PASSWORD FOR 'root' = PASSWORD('<root-password>');"
```

Use the password your values file already points at, so the two agree;
[Change Root Password](../Configure/change_root_password_howto.md) covers the standing procedure.

If the connection is instead **refused**, the password is set and the mismatch is elsewhere: check
that the Secret named by `phoenixai.initPassword.passwordSecret` holds the password you think it does.

:::note `COMPLETIONS 1/1` does not always mean the same thing
On a first install it means the password was set. On a reinstall over volumes that already hold a
cluster whose `root` has a password, the job cannot authenticate, treats that as already done and
exits successfully — so `1/1` there means "assumed already set", not "verified".
:::

### The console pod restarts over and over (`CrashLoopBackOff`)

Almost always object storage. The console verifies its bucket at startup by writing, reading and
deleting one small object, and refuses to serve if that fails:

```bash
kubectl -n phoenixai logs kube-anywhere-console-0 --previous | tail -30
```

Check the bucket name, region, endpoint, keys, and `usePathStyle` — false for Amazon S3, usually
true for self-hosted S3-compatible storage. Fix `my-values.yaml` and rerun the Step 4 command; the
console restarts by itself when its settings change.

### The console shows no clusters

The console reads clusters through the operator's API, so one of these three is wrong:

1. `operator.phoenixAIOperator.enableApiServer` is not `true`;
2. `anywhere.operatorApiAddrs` does not match the operator's API Service — confirm the Service
   exists with `kubectl -n phoenixai get svc kube-anywhere-operator-api`;
3. `anywhere.watchNamespaces` does not include the namespace the cluster is in.

### The console lists the cluster but every page says it is not supported

The cluster is a **classic** cluster, not an elastic one. Confirm from the database side:

```bash
kubectl -n phoenixai exec -it kube-anywhere-fe-0 -- \
  mysql -h127.0.0.1 -P9030 -uroot -p'<root-password>' -e "ADMIN SHOW FRONTEND CONFIG LIKE 'run_mode'"
```

If that is not `shared_data`, the `run_mode` block in `phoenixAIFeSpec.config` was missing or edited
away when the cluster was **first created**. The mode cannot be changed on an existing cluster: fix
the values file, then uninstall and reinstall. Note that the coordinators' disks are deliberately
kept on uninstall, so delete those claims too before reinstalling — see
[Uninstall and clean up](#uninstall-and-clean-up).

### `CREATE TABLE` fails with "no valid cache space"

`datacache_disk_size` is zero or missing on the compute nodes. It must be greater than zero in
elastic mode.

### The install fails on a `CustomResourceDefinition` conflict

A message like `failed to install CRD ...: Apply failed with 1 conflict: conflict with "kubectl"`
means PhoenixAI's custom resource definitions are already in this Kubernetes cluster and were put
there by something other than Helm — usually an earlier install from the YAML manifests, or another
Helm release. The definitions are shared by the whole Kubernetes cluster, so the safe move is to
leave them alone and tell Helm not to manage them:

```bash
helm upgrade --install kube-anywhere phoenixai/kube-anywhere \
  --namespace phoenixai -f my-values.yaml --skip-crds
```

Do this only when you know the existing definitions come from the same release version. If they are
older, upgrade them deliberately first — see
[Upgrade the Operator](./upgrade_operator_howto.md).

### `helm upgrade` fails on a field-manager conflict in a workload (Helm 4)

Helm 4 applies changes server-side by default (`--server-side=auto`), so an object that something
else edited in place is reported as a conflict rather than silently overwritten. Any chart-managed
object touched with `kubectl set image`, `kubectl patch` or `kubectl edit` fails the next upgrade:

```text
Apply failed with 1 conflict: conflict with "kubectl-set" using apps/v1:
.spec.template.spec.containers[name="anywhere"].image
```

This is the workload version of the CRD conflict above. `kubectl -n phoenixai get statefulset
kube-anywhere-console -o yaml --show-managed-fields` names every manager that owns a field. Let the
chart win — `my-values.yaml` is the source of truth for these objects:

```bash
helm upgrade --install kube-anywhere phoenixai/kube-anywhere \
  --namespace phoenixai -f my-values.yaml --force-conflicts
```

Then make the change through `my-values.yaml` instead of with `kubectl`, or the next upgrade hits
the same wall.

Helm 3 applies client-side and does not reach this failure — nor does it have `--force-conflicts`.
If you are on Helm 3, a hot-edited field is silently overwritten by the next upgrade instead, which
is its own reason to keep changes in the values file.

### The install is rejected with "invalid ownership metadata"

An object that survives an uninstall — the coordinators' metadata volumes, and the console's
`data-kube-anywhere-console-0` — still carries the Helm annotations of the release that created it,
and object names come from the chart rather than from the release name. So reinstalling under a
*different* release name is refused:

```text
invalid ownership metadata; annotation validation error:
key "meta.helm.sh/release-name" must equal "kube-anywhere": current value is "phoenixai"
```

Either keep the original release name, or hand the existing objects to the new release by adding
`--take-ownership` to the Step 4 command. See
[The console data volume](./console_data_volume.md#it-survives-an-uninstall).

### A second install into the same Kubernetes cluster fails with "already exists"

Object names come from the chart, not from your release name, so a second `kube-anywhere` release in
the same Kubernetes cluster collides on the cluster-scoped objects even when it uses a different
namespace. Give the second install its own names with the `nameOverride` values, or see
[Deploy Multiple Clusters](./deploy_multiple_clusters_howto.md).

### The install is rejected with a `storageClassName` type error

An empty `storageClassName` is not accepted. Name a real class from `kubectl get storageclass`.

### Monitoring pages are empty

No Prometheus is configured. See
[Anywhere Console monitoring](../Monitor/anywhere-monitoring.md). The console also has an
administrator dependency check that reports exactly which part of the wiring is missing.

The same gap empties the pod-utilization view and the metrics snapshot in a support bundle, so fix
it before collecting a bundle for anything performance-related.

### You lost the console password

It cannot be read back in plain text anywhere else, but it can be replaced — set
`anywhere.admin.users` in `my-values.yaml` and re-run the Step 4 command, as
[Step 6](#step-6--open-the-console) describes.

Patching the `kube-anywhere-console-admin` Secret directly does apply within about a minute, which
is worth doing if you need the console locked down immediately. It is not a fix on its own: the
chart re-renders that Secret on every upgrade, so the next Step 4 run puts the old value back.
Follow the patch with the values change.

## Uninstall and clean up

```bash
helm uninstall kube-anywhere --namespace phoenixai
```

Disks are **kept on purpose**, so that an accidental uninstall does not destroy data: the
coordinators' metadata volumes, and the console's own volume `data-kube-anywhere-console-0`, which
holds your usage records. Reinstalling under the same names adopts them again.

Remove them only when you mean it:

```bash
kubectl -n phoenixai get pvc
kubectl -n phoenixai delete pvc <claim-name>
```

An uninstall never empties the bucket. Delete the `data/` and `anywhere/` prefixes yourself if you
are finished with the installation for good.

## Where to read next

- `helm show readme phoenixai/kube-anywhere` and `helm show values phoenixai/kube-anywhere` — every
  value the chart accepts, printed from the chart itself.
- [Console tour](../GetStarted/anywhere_console_ui_guide.md) — what each console page is for.
- [Deploy Multiple Clusters](./deploy_multiple_clusters_howto.md) — more than one cluster in one
  Kubernetes cluster.
- [Expand Persistent Volume](../Operate/expand_persistent_volume_howto.md) — growing disks after the
  fact.
