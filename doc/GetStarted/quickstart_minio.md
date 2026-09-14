---
title: Quick start with MinIO
sidebar_label: Quick start — MinIO
sidebar_position: 2
description: Install a shared-data PhoenixAI cluster, a warehouse, and the Anywhere console with MinIO providing object storage inside the Kubernetes cluster.
---

# Quick Start With MinIO

Same environment as [Quick start — Amazon S3](./quickstart_s3.md), with MinIO providing the object
storage from inside the Kubernetes cluster instead of a cloud bucket. That suits two cases:

- a self-contained demo or evaluation, with no cloud account and no bucket to create;
- an air-gapped installation, where an external S3 endpoint is not reachable at all.

:::note New to Kubernetes or Helm?
This page assumes you can fill in the gaps — it names commands without explaining what a pod, a
StorageClass or a Helm release is. If that is not you, use
[Deploy step by step](../Deploy/install_with_helm.md) instead: the same install, in order,
with a check after every step and nothing assumed. It installs against Amazon S3; come back here for
the MinIO deltas.
:::

Everything MinIO changes is object storage configuration. The two differences from the S3 guide are
worth understanding before you start:

1. **Path-style addressing is required**, and it cannot be expressed in `fe.conf`. The FE
   configuration file has no path-style setting, so the cluster's storage is defined with SQL —
   `CREATE STORAGE VOLUME` — instead of being built from `fe.conf`.
2. **The S3 client must be told not to look for EC2 credentials.** Outside AWS there is nothing at
   the instance metadata address, and every request waits for that probe to time out first.

## Before you start

| You need | Notes |
| --- | --- |
| `kubectl`, `helm` | Any recent version; Helm 3.8 or newer |
| A Kubernetes cluster | `kind create cluster` is enough. Measured on this environment: **3.9 GB** of memory and under one CPU core at rest, with 3 coordinators, 2 compute nodes and MinIO running. 8 GB available to Docker leaves comfortable headroom; the chart values cap each coordinator and compute node at 2 GiB, so a cluster under query load can use more |
| Access to the PhoenixAI image registry | A key file from your PhoenixAI account team, plus the operator, database and console image tags that go with your release — see [Get the images](#get-the-images) |
| Enterprise PhoenixAI images | The FE and CN images must be the enterprise (`-ee`) builds. With community images the cluster starts but **no warehouse compute pods are ever created, and nothing reports an error** |
| A MySQL client | To check the cluster and to run SQL |
| A PhoenixAI Database license | Not needed to install, but the console's health checks report a cluster without one — see [Register the license](#register-the-license) |

Add the chart repository and see what it offers:

```bash
helm repo add phoenixai https://celerdata.github.io/phoenixai-kubernetes-operator
helm repo update phoenixai
helm search repo phoenixai
```

Use the chart names and versions that command lists. One chart — `kube-anywhere` — installs the
operator, a PhoenixAI cluster, and (with `anywhere.enabled=true`) the Anywhere console. It is also
distributed as a release archive, so if you do not see it in the repository, install it from the
`.tgz` for your release — ask your account team for `kube-anywhere-<version>.tgz`.

:::caution Do not substitute a chart that merely looks similar
The repository also carries older charts from the previous product generation, named `celerdata` and
`kube-celerdata`. They are a different, earlier product — not this one under another name, and not a
fallback.
:::

## Get the images

The operator, coordinator (FE), compute-node (CN) and console images are enterprise builds in a
**private registry**, so Kubernetes needs credentials for it. Without them every pod fails with
`ImagePullBackOff`.

Ask your [PhoenixAI team](https://www.phoenixdata.ai/contact-sales) for two things:

1. **Access to the registry.** The images live in Google Artifact Registry, and access arrives either
   as a JSON key file they issue for you, or as a grant on a service account of your own that you
   then issue a key for. Either way you end up holding one JSON key file.
2. **The image tags for your release** — one each for the operator, the database (FE and CN) and the
   console. Name all three yourself rather than relying on a chart default: a tag the registry does
   not hold fails with `ImagePullBackOff` **even though your credentials are correct**, and the
   message says nothing about a missing version. If nobody has named versions for you, you can
   [list what the registry holds](../Deploy/prerequisites.md#which-image-versions-to-use) and take
   the newest release build.

The pull secret is created in [Create the namespace and the pull secret](#create-the-namespace-and-the-pull-secret),
once the namespace exists. For the longer version — why Artifact Registry has no user name and
password, how to use short-lived tokens instead, and how to mirror the images into a registry you
already run — see
[Deploy step by step, Step 1](../Deploy/install_with_helm.md#step-1--get-the-images-and-teach-kubernetes-to-pull-them).

For an air-gapped installation, stage **five** images in your internal registry: the FE, CN,
operator and console images, plus `minio/minio` and `minio/mc`. Mirroring is also what removes the
install's dependence on reaching Artifact Registry at all — create the pull secret for **your**
registry instead, with whatever user name and password it takes, and point `image.repository` at it
for the operator, the FE, the CN, the console and any warehouse.

:::tip Loading image archives into kind
`kind load docker-image` fails on the multi-platform archives the `-ee` images ship as, because it
passes `--all-platforms` and containerd rejects the result:

```text
ctr: content digest sha256:e90f77…: not found
```

It is worth knowing that this failure is easy to miss — piping the command through `tail` or `grep`
masks its exit status, so it appears to succeed and the pods only fail minutes later with
`ErrImagePull`. Import into the node's containerd directly instead:

```bash
docker exec --privileged -i <kind-node> \
  ctr --namespace=k8s.io images import --digests --snapshotter=overlayfs - \
  < fe-ubuntu-<database-image-tag>.tar.gz
```

Then set `imagePullPolicy: IfNotPresent` in the chart values so the kubelet uses the imported copy.
:::

## Deploy MinIO

This is deliberately minimal — one replica, one volume, root credentials in a Secret. It is enough
for an evaluation and is **not** a production MinIO topology; for that, see MinIO's own
documentation on distributed deployments.

Change the credentials before applying, and set `storageClassName` to a class your cluster provides.

```yaml
# minio.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: minio
---
apiVersion: v1
kind: Secret
metadata:
  name: minio-root
  namespace: minio
stringData:
  MINIO_ROOT_USER: phoenixai
  MINIO_ROOT_PASSWORD: change-me-before-applying
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: minio-data
  namespace: minio
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: standard
  resources:
    requests:
      storage: 20Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  namespace: minio
spec:
  replicas: 1
  selector:
    matchLabels: { app: minio }
  template:
    metadata:
      labels: { app: minio }
    spec:
      containers:
        - name: minio
          image: minio/minio:RELEASE.2025-09-07T16-13-09Z
          args: ["server", "/data", "--console-address", ":9001"]
          envFrom:
            - secretRef: { name: minio-root }
          ports:
            - { containerPort: 9000, name: s3 }
            - { containerPort: 9001, name: console }
          volumeMounts:
            - { name: data, mountPath: /data }
          readinessProbe:
            httpGet: { path: /minio/health/ready, port: 9000 }
            initialDelaySeconds: 5
          resources:
            limits: { cpu: 2, memory: 2Gi }
            requests: { cpu: 10m, memory: 64Mi }
      volumes:
        - name: data
          persistentVolumeClaim: { claimName: minio-data }
---
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: minio
spec:
  selector: { app: minio }
  ports:
    - { name: s3, port: 9000, targetPort: 9000 }
    - { name: console, port: 9001, targetPort: 9001 }
```

```bash
kubectl apply -f minio.yaml
kubectl -n minio rollout status deploy/minio
```

The S3 endpoint is now `http://minio.minio.svc.cluster.local:9000`, reachable from any pod in the
cluster — which is what the PhoenixAI cluster and the console both need. Plain HTTP is fine here
because the traffic never leaves the cluster network.

## Create the bucket

Nothing creates it for you:

```yaml
# minio-mkbucket.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: minio-mkbucket
  namespace: minio
spec:
  backoffLimit: 6
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: mc
          image: minio/mc:RELEASE.2025-08-13T08-35-41Z
          envFrom:
            - secretRef: { name: minio-root }
          command: ["/bin/sh", "-c"]
          args:
            - |
              set -e
              until mc alias set local http://minio.minio.svc.cluster.local:9000 \
                    "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"; do sleep 3; done
              mc mb --ignore-existing local/phoenixai
              mc ls local
```

```bash
kubectl apply -f minio-mkbucket.yaml
kubectl -n minio wait --for=condition=complete job/minio-mkbucket --timeout=120s
kubectl -n minio logs job/minio-mkbucket
```

The log ends with the `phoenixai` bucket listed. Expect a few `connection refused` lines first —
the job retries until MinIO is accepting requests.

## Create the namespace and the pull secret

```bash
kubectl create namespace phoenixai
```

Turn the key file from [Get the images](#get-the-images) into a pull secret. For Google Artifact
Registry two of the three fields are fixed, so only the path to your key file changes:

```bash
kubectl -n phoenixai create secret docker-registry phoenixai-registry \
  --docker-server=us-west1-docker.pkg.dev \
  --docker-username=_json_key \
  --docker-password="$(cat <path-to-your-key-file>.json)"
```

- `us-west1-docker.pkg.dev` is the registry host — the part before the first `/` in your image
  repositories. Use the host your account team gives you.
- `_json_key` is not a placeholder. It is the literal user name Artifact Registry expects when the
  password is a service-account key file.
- The password is the **whole JSON file**, which is what `$(cat …)` passes in.

The secret is per namespace — one in `default` does nothing for pods in `phoenixai` — and the values
files below reference it **three times**: once for the operator, once for the cluster's components,
once for the console. A warehouse needs a fourth reference in its own values file. Referencing it in
only some of them is why an install sometimes pulls half its images and stalls on the rest.

If you mirrored the images into a registry of your own, create the secret for that registry instead
(`--docker-server`, `--docker-username`, `--docker-password` take a plain user name and password);
in a kind cluster with the images imported directly and `imagePullPolicy: IfNotPresent`, skip the
secret and the `imagePullSecrets` lines altogether.

## Install Prometheus

Prometheus is optional, but without it the console's monitoring pages have no data. The
`kube-prometheus-stack` chart also scrapes kubelet/cAdvisor and kube-state-metrics by default,
which is what makes per-pod CPU and memory utilization appear.

Install it **before** the cluster. The cluster and warehouse charts render ServiceMonitors, and
those need the Prometheus operator's CRDs to already exist — install them the other way round and
the ServiceMonitors are skipped, with no error, leaving the monitoring pages empty for a reason
nothing on screen explains.

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update prometheus-community
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace
```

:::caution The ServiceMonitors must carry the label your Prometheus selects on
`kube-prometheus-stack` defaults `serviceMonitorSelector` to
`matchLabels: {release: <helm release name>}`. The cluster and warehouse charts do
not add that label, so with the install above and nothing else, **Prometheus
scrapes none of the PhoenixAI targets** — it collects only its own stack, and the
console's monitoring pages stay empty with nothing on screen to say why.

Add it through `metrics.serviceMonitor.labels` in the values below. If you
installed the stack under a different release name, use that name.
:::

## Install the operator, the cluster and the console

One `helm install` of the `kube-anywhere` chart deploys all three. Identical to the S3 guide
**except** the FE storage settings, the environment variables and the console's storage block. The
FE starts without loading a storage volume from its configuration file, because the volume is
created with SQL in the next step.

```yaml
operator:
  phoenixAIOperator:
    # (1 of 3) Pull the operator image.
    imagePullSecrets:
      - name: phoenixai-registry
    image:
      tag: "<operator-image-tag>"
    enableApiServer: true
    watchNamespace: "phoenixai"

phoenixai:
  metrics:
    serviceMonitor:
      enabled: true
      labels:
        release: prometheus
  phoenixAICluster:
    name: kube-anywhere
    enabledCn: true
    waitForFullRollout: true
    componentValues:
      # (2 of 3) Pull the FE and CN images. Set here, this covers both; the FE
      # proxy below is public nginx and needs no secret.
      imagePullSecrets:
        - name: phoenixai-registry

  phoenixAIFeSpec:
    replicas: 3
    image:
      repository: <your-registry>/fe-ubuntu
      tag: <database-image-tag>
    config: |
      LOG_DIR = ${STARROCKS_HOME}/log
      JAVA_OPTS="-Dlog4j2.formatMsgNoLookups=true -Xmx1024m -XX:+UseG1GC"
      http_port = 8030
      rpc_port = 9020
      query_port = 9030
      edit_log_port = 9010
      run_mode = shared_data
      cloud_native_meta_port = 6090
      cloud_native_storage_type = S3
      # DELTA vs S3: no aws_s3_* settings here. Path-style addressing cannot be
      # expressed in fe.conf, so the storage volume is created with SQL below.
      enable_load_volume_from_conf = false
    # DELTA vs S3: keep the S3 client away from the EC2 metadata service.
    feEnvVars:
      - name: AWS_EC2_METADATA_DISABLED
        value: "true"
    resources:
      limits: { cpu: 2, memory: 2Gi }
      requests: { cpu: 10m, memory: 10Mi }
    storageSpec:
      name: fe-storage
      storageClassName: standard
      storageSize: 10Gi
      logStorageSize: 1Gi

  phoenixAICnSpec:
    replicas: 1
    image:
      repository: <your-registry>/cn-ubuntu
      tag: <database-image-tag>
    config: |
      sys_log_level = INFO
      thrift_port = 9060
      webserver_port = 8040
      heartbeat_service_port = 9050
      brpc_port = 8060
      datacache_enable = true
      datacache_mem_size = 5%
      datacache_disk_size = 4294967296
    # DELTA vs S3
    cnEnvVars:
      - name: AWS_EC2_METADATA_DISABLED
        value: "true"
    resources:
      limits: { cpu: 4, memory: 2Gi }
      requests: { cpu: 10m, memory: 10Mi }
    storageSpec:
      name: cn-storage
      storageClassName: standard
      storageSize: 10Gi
      logStorageSize: 1Gi

  # The FE proxy (nginx) is what makes the "Load data and query it" step below
  # possible from your own machine: it follows the HTTP 307 a coordinator answers
  # a load with, which points at a compute node address only routable inside the
  # cluster. Leave it out if you will only ever load from inside the cluster.
  phoenixAIFeProxySpec:
    enabled: true
    replicas: 1
    resources:
      requests: { cpu: 10m, memory: 64Mi }
      limits: { cpu: 1, memory: 1Gi }

anywhere:
  # The console is opt-in because it needs object storage of its own.
  enabled: true
  # (3 of 3) Pull the console image.
  imagePullSecrets:
    - name: phoenixai-registry
  image:
    repository: <your-registry>/anywhere
    tag: <console-image-tag>

  # The operator's gRPC API Service, in this namespace.
  operatorApiAddrs:
    - "kube-anywhere-operator-api:9090"
  watchNamespaces:
    - "phoenixai"

  dependencies:
    s3:
      bucket: "phoenixai"
      # A prefix of its own, kept apart from the cluster's "data" prefix.
      path: "anywhere"
      region: "us-east-1"
      endpoint: "http://minio.minio.svc.cluster.local:9000"
      accessKey: "phoenixai"
      secretKey: "change-me-before-applying"
      # DELTA vs S3: required for MinIO.
      usePathStyle: true
    prometheus:
      enabled: true
      endpoint: http://prometheus-kube-prometheus-prometheus.monitoring:9090
```

```bash
helm install kube-anywhere phoenixai/kube-anywhere \
  --namespace phoenixai -f cluster-values.yaml
kubectl -n phoenixai get pods -w
```

The console validates its storage block at startup with a write, read and delete against its
prefix, so a wrong endpoint, credential or path-style setting is reported as an actionable error
rather than surfacing later when someone requests a support bundle.

:::note Keep FE logs as files
Do not set `LOG_CONSOLE=1` on the FE. The console's audit-log search and the support bundle's log
collection both read log **files** from the log volume; console-only logging leaves both empty.
:::

:::caution The root password can only be set on the first install
This quick start leaves `root` with no password, which is why every SQL command below passes
`-uroot` with nothing after it. That is fine on a laptop and wrong anywhere else — and a later
`helm upgrade` **cannot** set it, so a cluster installed without it keeps an open `root` account
until someone changes it by hand.

To set one now, create a Secret before installing and point the chart at it:

```bash
kubectl -n phoenixai create secret generic phoenixai-root-password \
  --from-literal=password='<root-password>'
```

```yaml
phoenixai:
  initPassword:
    enabled: true
    passwordSecret: phoenixai-root-password
```

Then add `-p'<root-password>'` to the `mysql` commands below and put the password after the colon in
`-u root:`. See [Initialize Root Password When First Deploy](../Configure/initialize_root_password_howto.md).
:::

## Create the storage volume

The cluster has nowhere to put data until this exists. `aws.s3.enable_path_style_access` is the
setting that makes MinIO reachable, and a storage volume is the only place it can be given.

```sql
CREATE STORAGE VOLUME minio_volume
TYPE = S3
LOCATIONS = ("s3://phoenixai/data")
PROPERTIES (
    "enabled" = "true",
    "aws.s3.region" = "us-east-1",
    "aws.s3.endpoint" = "http://minio.minio.svc.cluster.local:9000",
    "aws.s3.access_key" = "phoenixai",
    "aws.s3.secret_key" = "change-me-before-applying",
    "aws.s3.enable_path_style_access" = "true"
);

SET minio_volume AS DEFAULT STORAGE VOLUME;
```

Two notes on the properties:

- `aws.s3.region` is required by the S3 client even though MinIO ignores it. Any valid region name
  works; keep it consistent with what you give the console.
- `LOCATIONS` sets the prefix inside the bucket, leaving the rest of it for the console.

Confirm the volume is enabled and the default before creating any table:

```sql
SHOW STORAGE VOLUMES;
DESC STORAGE VOLUME minio_volume;
```

Check the cluster over SQL:

```bash
kubectl -n phoenixai exec -it kube-anywhere-fe-0 -- \
  mysql -h127.0.0.1 -P9030 -uroot -e "SHOW BACKENDS\G SHOW WAREHOUSES\G"
```

## Register the license

A cluster runs without a license, but the console's health checks report it as unlicensed — so do
this before reading a red result as a fault.

The license API is served by the **leader** coordinator, so find it first:

```bash
kubectl -n phoenixai exec kube-anywhere-fe-0 -- \
  mysql -h127.0.0.1 -P9030 -uroot -e "SHOW FRONTENDS\G" | grep -E 'Name|Role'
```

The `Name` on the `LEADER` row begins with the pod name. Forward that pod's HTTP port, and leave it
running:

```bash
kubectl -n phoenixai port-forward pod/kube-anywhere-fe-<leader> 8030:8030
```

Then, in a second terminal — send the system information to PhoenixAI Support, and register the
`license.txt` they return:

```bash
# system information to send to Support
curl -u root: localhost:8030/api/v1/license/system_info

# after Support returns license.txt
curl -u root: -XPOST --location-trusted --data-binary @license.txt \
  localhost:8030/api/v1/license/register

# confirm
curl -u root: localhost:8030/api/v1/license/list
```

`-u root:` ends in a colon because no root password was set; if you set one, it goes after the
colon. The user needs the `cluster_admin` role, which `root` has. Full detail, including the shape
of each response, is in [License Your PhoenixAI Cluster](../Deploy/license_cluster_howto.md).

In an air-gapped installation this is the one step that needs a way to move two small files in and
out — the system information string, and `license.txt`.

## Install a warehouse

As in the S3 guide, plus one addition: **a warehouse runs its own compute nodes**, and they reach
object storage independently of the cluster's. They need the same environment variable — and, since
they pull the CN image themselves, the fourth reference to the pull secret.

```yaml
# warehouse-values.yaml
metrics:
  serviceMonitor:
    enabled: true
    labels:
      release: prometheus
spec:
  phoenixAIClusterName: "kube-anywhere"
  replicas: 1
  # (4th reference) Pull the CN image for this warehouse's own compute nodes.
  imagePullSecrets:
    - name: phoenixai-registry
  image:
    repository: <your-registry>/cn-ubuntu
    tag: <database-image-tag>
  config: |
    sys_log_level = INFO
    thrift_port = 9060
    webserver_port = 8040
    heartbeat_service_port = 9050
    brpc_port = 8060
    datacache_enable = true
    datacache_mem_size = 5%
    datacache_disk_size = 4294967296
  # DELTA vs S3
  envVars:
    - name: AWS_EC2_METADATA_DISABLED
      value: "true"
  resources:
    limits: { cpu: 2, memory: 2Gi }
    requests: { cpu: 10m, memory: 10Mi }
  storageSpec:
    name: warehouse-cn-storage
    storageClassName: standard
    storageSize: 10Gi
    logStorageSize: 1Gi
```

```bash
helm install wh1 phoenixai/warehouse --namespace phoenixai -f warehouse-values.yaml
```

No operator restart is needed. The operator registers its warehouse controller only if the
`PhoenixAIWarehouse` CRD exists **when it starts**, and the operator chart you installed above ships
that CRD next to the cluster one, so the controller is already running.

```bash
kubectl -n phoenixai exec -it kube-anywhere-fe-0 -- \
  mysql -h127.0.0.1 -P9030 -uroot -e "SHOW WAREHOUSES\G"
```

## Load data and query it

Load your own data, or use these datasets and queries to see the system in action. These two datasets
— 423,725 New York City crash records and 22,931 hourly weather readings — are worth the
few minutes to work through the loading process.

**1. Reach the cluster over HTTP.** Loading is an HTTP request. Sent straight at a coordinator it is
answered with an HTTP 307 naming a compute node's *in-cluster* address, which your own machine
cannot resolve. The FE proxy follows that redirect for you, so send the request there instead — the
`phoenixAIFeProxySpec` block in the values file above is what created it.

```bash
kubectl -n phoenixai port-forward svc/kube-anywhere-fe-proxy-service 8080:8080
```

Leave that running, and use a second terminal for everything below.

:::note A port forward is for you, not for your users
It lasts only as long as the command runs, and only on the machine running it. To let colleagues
load data, ask your Kubernetes administrator to put an Ingress or a load-balancing Service in front
of `kube-anywhere-fe-proxy-service`. See
[Deploy the FE Proxy](../Operate/fe_proxy.md).
:::

**2. Create the database and the two tables:**

```bash
kubectl -n phoenixai exec -i kube-anywhere-fe-0 -- mysql -h127.0.0.1 -P9030 -uroot <<'SQL'
CREATE DATABASE IF NOT EXISTS quickstart;
USE quickstart;
CREATE TABLE IF NOT EXISTS crashdata (
    CRASH_DATE DATETIME, BOROUGH STRING, ZIP_CODE STRING, LATITUDE INT, LONGITUDE INT,
    LOCATION STRING, ON_STREET_NAME STRING, CROSS_STREET_NAME STRING, OFF_STREET_NAME STRING,
    CONTRIBUTING_FACTOR_VEHICLE_1 STRING, CONTRIBUTING_FACTOR_VEHICLE_2 STRING, COLLISION_ID INT,
    VEHICLE_TYPE_CODE_1 STRING, VEHICLE_TYPE_CODE_2 STRING);
CREATE TABLE IF NOT EXISTS weatherdata (
    DATE DATETIME, NAME STRING, HourlyDewPointTemperature STRING, HourlyDryBulbTemperature STRING,
    HourlyPrecipitation STRING, HourlyPresentWeatherType STRING, HourlyPressureChange STRING,
    HourlyPressureTendency STRING, HourlyRelativeHumidity STRING, HourlySkyConditions STRING,
    HourlyVisibility STRING, HourlyWetBulbTemperature STRING, HourlyWindDirection STRING,
    HourlyWindGustSpeed STRING, HourlyWindSpeed STRING);
SQL
```

**3. Download the two files:**

```bash
curl -O https://raw.githubusercontent.com/StarRocks/demo/master/documentation-samples/quickstart/datasets/NYPD_Crash_Data.csv
curl -O https://raw.githubusercontent.com/StarRocks/demo/master/documentation-samples/quickstart/datasets/72505394728.csv
```

**4. Load the crash data.** The `columns:` list names every column in the file, in order, so the
ones the table does not keep can be skipped; `CRASH_DATE` is assembled from the file's separate date
and time fields. `-u root:` ends in a colon because this quick start never set a root password — if
you set one, it goes after the colon.

```bash
curl --location-trusted -u root: \
    -T ./NYPD_Crash_Data.csv \
    -H "label:crashdata-0" \
    -H "column_separator:," \
    -H "skip_header:1" \
    -H "enclose:\"" \
    -H "max_filter_ratio:1" \
    -H "columns:tmp_CRASH_DATE, tmp_CRASH_TIME, CRASH_DATE=str_to_date(concat_ws(' ', tmp_CRASH_DATE, tmp_CRASH_TIME), '%m/%d/%Y %H:%i'),BOROUGH,ZIP_CODE,LATITUDE,LONGITUDE,LOCATION,ON_STREET_NAME,CROSS_STREET_NAME,OFF_STREET_NAME,NUMBER_OF_PERSONS_INJURED,NUMBER_OF_PERSONS_KILLED,NUMBER_OF_PEDESTRIANS_INJURED,NUMBER_OF_PEDESTRIANS_KILLED,NUMBER_OF_CYCLIST_INJURED,NUMBER_OF_CYCLIST_KILLED,NUMBER_OF_MOTORIST_INJURED,NUMBER_OF_MOTORIST_KILLED,CONTRIBUTING_FACTOR_VEHICLE_1,CONTRIBUTING_FACTOR_VEHICLE_2,CONTRIBUTING_FACTOR_VEHICLE_3,CONTRIBUTING_FACTOR_VEHICLE_4,CONTRIBUTING_FACTOR_VEHICLE_5,COLLISION_ID,VEHICLE_TYPE_CODE_1,VEHICLE_TYPE_CODE_2,VEHICLE_TYPE_CODE_3,VEHICLE_TYPE_CODE_4,VEHICLE_TYPE_CODE_5" \
    -XPUT http://localhost:8080/api/quickstart/crashdata/_stream_load
```

A successful load answers with `"Status": "Success"` and the rows it took. One row of this file is
rejected by the date conversion, which is why `max_filter_ratio` is set — expect
`"NumberLoadedRows": 423725` and `"NumberFilteredRows": 1`.

**5. Load the weather data.** The same shape, with this file's own (much longer) column list:

```bash
curl --location-trusted -u root: \
    -T ./72505394728.csv \
    -H "label:weather-0" \
    -H "column_separator:," \
    -H "skip_header:1" \
    -H "enclose:\"" \
    -H "max_filter_ratio:1" \
    -H "columns: STATION, DATE, LATITUDE, LONGITUDE, ELEVATION, NAME, REPORT_TYPE, SOURCE, HourlyAltimeterSetting, HourlyDewPointTemperature, HourlyDryBulbTemperature, HourlyPrecipitation, HourlyPresentWeatherType, HourlyPressureChange, HourlyPressureTendency, HourlyRelativeHumidity, HourlySkyConditions, HourlySeaLevelPressure, HourlyStationPressure, HourlyVisibility, HourlyWetBulbTemperature, HourlyWindDirection, HourlyWindGustSpeed, HourlyWindSpeed, Sunrise, Sunset, DailyAverageDewPointTemperature, DailyAverageDryBulbTemperature, DailyAverageRelativeHumidity, DailyAverageSeaLevelPressure, DailyAverageStationPressure, DailyAverageWetBulbTemperature, DailyAverageWindSpeed, DailyCoolingDegreeDays, DailyDepartureFromNormalAverageTemperature, DailyHeatingDegreeDays, DailyMaximumDryBulbTemperature, DailyMinimumDryBulbTemperature, DailyPeakWindDirection, DailyPeakWindSpeed, DailyPrecipitation, DailySnowDepth, DailySnowfall, DailySustainedWindDirection, DailySustainedWindSpeed, DailyWeather, MonthlyAverageRH, MonthlyDaysWithGT001Precip, MonthlyDaysWithGT010Precip, MonthlyDaysWithGT32Temp, MonthlyDaysWithGT90Temp, MonthlyDaysWithLT0Temp, MonthlyDaysWithLT32Temp, MonthlyDepartureFromNormalAverageTemperature, MonthlyDepartureFromNormalCoolingDegreeDays, MonthlyDepartureFromNormalHeatingDegreeDays, MonthlyDepartureFromNormalMaximumTemperature, MonthlyDepartureFromNormalMinimumTemperature, MonthlyDepartureFromNormalPrecipitation, MonthlyDewpointTemperature, MonthlyGreatestPrecip, MonthlyGreatestPrecipDate, MonthlyGreatestSnowDepth, MonthlyGreatestSnowDepthDate, MonthlyGreatestSnowfall, MonthlyGreatestSnowfallDate, MonthlyMaxSeaLevelPressureValue, MonthlyMaxSeaLevelPressureValueDate, MonthlyMaxSeaLevelPressureValueTime, MonthlyMaximumTemperature, MonthlyMeanTemperature, MonthlyMinSeaLevelPressureValue, MonthlyMinSeaLevelPressureValueDate, MonthlyMinSeaLevelPressureValueTime, MonthlyMinimumTemperature, MonthlySeaLevelPressure, MonthlyStationPressure, MonthlyTotalLiquidPrecipitation, MonthlyTotalSnowfall, MonthlyWetBulb, AWND, CDSD, CLDD, DSNW, HDSD, HTDD, NormalsCoolingDegreeDay, NormalsHeatingDegreeDay, ShortDurationEndDate005, ShortDurationEndDate010, ShortDurationEndDate015, ShortDurationEndDate020, ShortDurationEndDate030, ShortDurationEndDate045, ShortDurationEndDate060, ShortDurationEndDate080, ShortDurationEndDate100, ShortDurationEndDate120, ShortDurationEndDate150, ShortDurationEndDate180, ShortDurationPrecipitationValue005, ShortDurationPrecipitationValue010, ShortDurationPrecipitationValue015, ShortDurationPrecipitationValue020, ShortDurationPrecipitationValue030, ShortDurationPrecipitationValue045, ShortDurationPrecipitationValue060, ShortDurationPrecipitationValue080, ShortDurationPrecipitationValue100, ShortDurationPrecipitationValue120, ShortDurationPrecipitationValue150, ShortDurationPrecipitationValue180, REM, BackupDirection, BackupDistance, BackupDistanceUnit, BackupElements, BackupElevation, BackupEquipment, BackupLatitude, BackupLongitude, BackupName, WindEquipmentChangeDate" \
    -XPUT http://localhost:8080/api/quickstart/weatherdata/_stream_load
```

Expect `"NumberLoadedRows": 22931` and no filtered rows.

**6. Ask the data something.** Crashes per hour, and the average temperature per hour:

```bash
kubectl -n phoenixai exec -i kube-anywhere-fe-0 -- mysql -h127.0.0.1 -P9030 -uroot -D quickstart <<'SQL'
SELECT COUNT(*), date_trunc("hour", crashdata.CRASH_DATE) AS Time
FROM crashdata GROUP BY Time ORDER BY Time ASC LIMIT 200;

SELECT avg(HourlyDryBulbTemperature), date_trunc("hour", weatherdata.DATE) AS Time
FROM weatherdata GROUP BY Time ORDER BY Time ASC LIMIT 100;
SQL
```

Then the question neither table answers alone — how many crashes happened in the hours when
visibility was poor, and what the weather was:

```bash
kubectl -n phoenixai exec -i kube-anywhere-fe-0 -- mysql -h127.0.0.1 -P9030 -uroot -D quickstart <<'SQL'
SELECT COUNT(DISTINCT c.COLLISION_ID) AS Crashes,
       truncate(avg(w.HourlyDryBulbTemperature), 1) AS Temp_F,
       truncate(avg(w.HourlyVisibility), 2) AS Visibility,
       max(w.HourlyPrecipitation) AS Precipitation,
       date_format((date_trunc("hour", c.CRASH_DATE)), '%d %b %Y %H:%i') AS Hour
FROM crashdata c
LEFT JOIN weatherdata w ON date_trunc("hour", c.CRASH_DATE)=date_trunc("hour", w.DATE)
WHERE w.HourlyVisibility BETWEEN 0.0 AND 1.0
GROUP BY Hour ORDER BY Crashes DESC LIMIT 100;
SQL
```

Swap the `WHERE` clause for `w.HourlyDryBulbTemperature BETWEEN 0.0 AND 40.5` to ask the same
question about freezing hours instead.

## Sign in

The console was installed together with the cluster (the `anywhere:` block above). Wait for it:

```bash
kubectl -n phoenixai rollout status statefulset/kube-anywhere-console
kubectl -n phoenixai port-forward svc/kube-anywhere-console 8090:8090
```

Check the service answers, then open the console at `http://localhost:8090`:

```bash
curl -s localhost:8090/api/v1/health
# {"code":20000,"data":{"status":"ok"}}
```

Admin accounts live in the `kube-anywhere-console-admin` Secret — one key per username. If you did not
supply any, a single `admin` account was generated with a random password:

```bash
kubectl -n phoenixai get secret kube-anywhere-console-admin \
  -o jsonpath='{.data.admin}' | base64 -d; echo
```

Add, remove or rotate accounts by editing that Secret; changes take effect within about a minute
and need no restart.

:::caution Replace a short, guessable password before anyone else can reach the console
A long random string was generated for your installation alone. If the command printed something
short — `admin`, for instance — your chart version installed a **well-known default**, and anyone
who can reach the console can sign in as an administrator. Replace it before you put an Ingress or
a load balancer in front of the console:

```bash
kubectl -n phoenixai patch secret kube-anywhere-console-admin \
  --type merge -p "{\"stringData\":{\"admin\":\"$(openssl rand -base64 24)\"}}"
```
:::

To reach the **Cluster Console** — the per-cluster view, with the data catalog, query insights and
system monitoring — go to `http://localhost:8090/cluster-console/login` and sign in with a database
user from the cluster itself. That is a PhoenixAI database user, created in the cluster with SQL,
not an Anywhere account.

## Check the whole path

```sql
CREATE DATABASE IF NOT EXISTS minio_check;
CREATE TABLE minio_check.t (k INT) PROPERTIES ("replication_num" = "1");
INSERT INTO minio_check.t VALUES (1), (2), (3);
SELECT count(*) FROM minio_check.t;
```

Then confirm the cluster's objects are there:

```bash
kubectl -n minio run mc --rm -i --restart=Never \
  --image=minio/mc:RELEASE.2025-08-13T08-35-41Z \
  --env=U=<access-key> --env=P=<secret-key> --command -- /bin/sh -c \
  'mc alias set local http://minio.minio.svc.cluster.local:9000 "$U" "$P" >/dev/null &&
   mc du local/phoenixai/data/'
```

A few dozen small objects under `data/` is what a freshly created table looks like.

The console's own prefix stays **empty** until it has something to store: it validates the bucket at
startup with a write, read and delete, which leaves nothing behind. To see objects under `anywhere/`,
create a support bundle from the console (Support → Create support bundle) and list that prefix
afterwards.

## What to enable next

**Query insights is off by default.** The page needs two settings, in two different places:

1. `anywhere.queryHistory.enabled` in the chart values;
2. the FE configuration `enable_collect_query_detail_info` on every FE, either in `fe.conf` or with
   `ADMIN SET FRONTEND CONFIG`.

The page names both in its empty state, so you do not have to remember which is missing.

## Troubleshooting

**Pods stay in `ImagePullBackOff` or `ErrImagePull`.** In order of likelihood: there is no pull
secret in this namespace; the secret is in a different one
(`kubectl get secret --all-namespaces | grep phoenixai-registry`); the name in the values file does
not match; it was named in only some of the three places, which is why this often affects part of
the install and not the rest; the tag names a version the registry does not hold; or the credentials
are expired. On kind, it can also mean `kind load` reported success while importing nothing — see
the tip under [Get the images](#get-the-images). `kubectl -n phoenixai describe pod <pod> | tail -20`
prints the registry's own refusal, which separates "no credentials" from "credentials rejected".

**The FE cannot reach storage, or table creation fails with an S3 error.** Check that
`aws.s3.enable_path_style_access` is `true` on the storage volume (`DESC STORAGE VOLUME`). Without
it the client resolves `phoenixai.minio.minio.svc.cluster.local`, which does not exist. The
signature is a connection or DNS error naming a host with the bucket name in front of the endpoint.

**The FE ignores your storage volume.** `enable_load_volume_from_conf` must be `false`, and the
volume must be the default (`SET … AS DEFAULT STORAGE VOLUME`).

**Queries and loads are slow, or time out, but storage is otherwise reachable.** Check
`AWS_EC2_METADATA_DISABLED=true` on the FE, the cluster's compute nodes **and** each warehouse's
compute nodes. Without it, the S3 client tries the EC2 instance metadata service on the way to the
credentials you configured, and outside AWS that probe has to time out first. It fails quietly:
storage works, everything is just slow.

**The console reports an object-storage error at startup.** The endpoint needs a scheme
(`http://…`), and `usePathStyle` must be `true`. The startup probe names which operation failed.

**The bucket does not exist.** Re-run the bucket job; nothing else creates it.

**`CREATE TABLE` fails with "no valid cache space".** `datacache_disk_size` is zero on the compute
nodes. It must be greater than zero in shared-data mode.

**The CRD rejects the cluster with a `storageClassName` type error.** An empty `storageClassName`
renders as YAML null. Set it to a real class (`kubectl get storageclass`).

**`CREATE TABLE` times out with "unfinished replicas".** A compute node that started moments ago
can exceed the FE's `tablet_create_timeout_second` (10 seconds by default). Retry, or raise it with
`ADMIN SET FRONTEND CONFIG ("tablet_create_timeout_second" = "20")`.

**The console shows no clusters.** The operator was installed without
`phoenixAIOperator.enableApiServer=true`, so there is no gRPC API for Anywhere to read.

**A warehouse never gets compute pods, with no error anywhere.** Two causes, in the order worth
checking. First, the operator started before the `PhoenixAIWarehouse` CRD existed, so it holds no
warehouse controller. The operator chart installs that CRD on a fresh install, so this is the case
of an operator upgraded from an earlier version (`helm upgrade` never installs a chart's `crds/`) or
one installed with `--skip-crds`. `kubectl -n phoenixai logs deployment/kube-anywhere-operator | grep
PhoenixAIWarehouse` returns nothing, and `kubectl rollout restart deployment kube-anywhere-operator`
fixes it. Second, the images are community builds rather than enterprise `-ee`.

**Monitoring pages are empty.** Prometheus is not installed, `anywhere.dependencies.prometheus` is not set,
or the ServiceMonitors were not rendered (`metrics.serviceMonitor.enabled`).

