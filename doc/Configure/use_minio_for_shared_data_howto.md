---
sidebar_position: 9
---

# Use MinIO For Shared-Data Storage

A shared-data PhoenixAI cluster keeps its data in object storage rather than on the compute nodes.
MinIO is an S3-compatible object store you run yourself, which makes it a good fit for two cases:

- a self-contained demo or evaluation environment, with no cloud account and no bucket to create;
- an air-gapped installation, where an external S3 endpoint is not reachable at all.

This guide deploys MinIO into the same Kubernetes cluster, points a shared-data PhoenixAI cluster at
it, and configures PhoenixAI Anywhere to use the same bucket for its own artifacts.

MinIO is used here for both jobs on purpose: one object store, one set of credentials, two prefixes.

## Before you start

You need:

- a Kubernetes cluster and `kubectl`, plus `helm` for the PhoenixAI charts;
- enterprise PhoenixAI FE and CN images (`-ee`). Warehouses are an enterprise data-plane feature:
  with community images the cluster starts but no warehouse compute pods are ever created, and
  nothing reports an error;
- a MySQL client, to configure storage and to check the result.

For an air-gapped installation, stage these images in your internal registry before you begin —
MinIO adds two to the list — and request the MinIO license file while you are still online
([step 1](#1-deploy-minio) says where it comes from). Change the two `image:` lines in the MinIO
manifests to your copies.

| Image | Why |
| --- | --- |
| `quay.io/minio/aistor/minio` | the object store |
| `quay.io/minio/aistor/mc` | creates the bucket |
| PhoenixAI FE / CN (`-ee`) | the cluster |
| PhoenixAI operator | reconciles the cluster |
| PhoenixAI Anywhere | the console |

## 1. Deploy MinIO

:::caution AIStor serves no S3 requests until a license is installed
MinIO's community edition was retired, so this page deploys **MinIO AIStor**, a commercial product.
Without a license the server starts in *offline mode*: its readiness check fails, so the
Deployment never becomes Ready, and every S3 request — including the bucket Job below — is
denied with `No license is installed`.

Get a license before you apply the manifest. The **Free** tier is enough for this page: it costs
nothing and is limited to a single node, which is all this manifest runs. Request it from
[min.io/pricing](https://www.min.io/pricing) (**Get Started** under *Free*); it comes from MinIO
SUBNET as a `minio.license` file holding one long token. The manifest below keeps that token in a
Secret, mounts it into the container and passes it to the server with `--license`. The license
has to be there at start-up: a pod that is not Ready has no Service endpoint, so installing it
afterwards with `mc license update` does not fit this manifest. MinIO's
[license documentation](https://docs.min.io/aistor/operations/licenses/) covers the details.
:::

This manifest is deliberately minimal: one replica, one volume, root credentials in a Secret. It is
enough for a demo or an evaluation, and is **not** a production MinIO topology — for that, see
MinIO's own documentation on distributed deployments.

Paste the contents of your `minio.license` file into the `minio-license` Secret, change the
credentials, and set `storageClassName` to a class your cluster provides
(`kubectl get storageclass`).

```yaml
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
kind: Secret
metadata:
  name: minio-license
  namespace: minio
stringData:
  minio.license: paste-the-contents-of-your-minio.license-file-here
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
          image: quay.io/minio/aistor/minio:RELEASE.2026-09-19T17-05-25Z
          args: ["server", "/data", "--console-address", ":9001",
                 "--license", "/license/minio.license"]
          envFrom:
            - secretRef: { name: minio-root }
          ports:
            - { containerPort: 9000, name: s3 }
            - { containerPort: 9001, name: console }
          volumeMounts:
            - { name: data, mountPath: /data }
            - { name: license, mountPath: /license, readOnly: true }
          readinessProbe:
            httpGet: { path: /minio/health/ready, port: 9000 }
            initialDelaySeconds: 5
          resources:
            limits: { cpu: 2, memory: 2Gi }
            requests: { cpu: 10m, memory: 64Mi }
      volumes:
        - name: data
          persistentVolumeClaim: { claimName: minio-data }
        - name: license
          secret: { secretName: minio-license }
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

Apply it and wait for the pod:

```bash
kubectl apply -f minio.yaml
kubectl -n minio rollout status deploy/minio
```

The S3 endpoint is now `http://minio.minio.svc.cluster.local:9000`, reachable from any pod in the
cluster — which is what the PhoenixAI cluster and Anywhere both need. Plain HTTP is fine here
because the traffic never leaves the cluster network.

## 2. Create the bucket

Neither PhoenixAI nor Anywhere creates a bucket; it has to exist first. This Job does it:

```yaml
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
          image: quay.io/minio/aistor/mc:RELEASE.2026-02-03T00-12-26Z
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

The log should list the `phoenixai` bucket. One bucket serves both the cluster and Anywhere: they are
kept apart by key prefix, so nothing is shared but the storage itself.

## 3. Point the PhoenixAI cluster at MinIO

MinIO requires **path-style** addressing — `http://endpoint/bucket/key` rather than
`http://bucket.endpoint/key` — because the virtual-hosted form needs a DNS entry per bucket, which
does not exist for an in-cluster Service.

This matters for how you configure storage. The FE configuration file has **no** path-style setting,
so the `aws_s3_*` entries in `fe.conf` cannot describe a MinIO endpoint. Path-style is a property of
a **storage volume**, so create one with SQL instead.

In the cluster's values file, keep shared-data mode but let the FE start without loading a storage
volume from its configuration file:

```yaml
phoenixAIFeSpec:
  config: |
    run_mode = shared_data
    cloud_native_storage_type = S3
    enable_load_volume_from_conf = false
    cloud_native_meta_port = 6090
  # The S3 client looks for credentials in the EC2 instance metadata service
  # before it uses the ones you supply. Outside AWS there is nothing at that
  # address, so every request waits for that probe to time out first.
  feEnvVars:
    - name: AWS_EC2_METADATA_DISABLED
      value: "true"

phoenixAICnSpec:
  cnEnvVars:
    - name: AWS_EC2_METADATA_DISABLED
      value: "true"
```

Set the same variable on **every warehouse** as well — a warehouse runs its own compute nodes,
and they talk to object storage independently of the cluster's. In the warehouse chart's values:

```yaml
spec:
  envVars:
    - name: AWS_EC2_METADATA_DISABLED
      value: "true"
```

Deploy the cluster as usual, then connect to the FE and create the volume:

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
  works; keep it consistent with what you give Anywhere.
- `LOCATIONS` sets the prefix inside the bucket. Using `data` here leaves the rest of the bucket free
  for Anywhere.

Confirm it took effect:

```sql
SHOW STORAGE VOLUMES;
DESC STORAGE VOLUME minio_volume;
```

The volume must be enabled and the default before you create a table — a shared-data cluster has
nowhere to put data otherwise.

## 4. Point Anywhere at the same bucket

Anywhere stores its own large artifacts — query profiles and support bundles — in object storage, and
supports MinIO directly. The console ships as the `anywhere` subchart of the same `kube-anywhere`
chart you installed the operator and cluster with, so there is no separate release: enable it with
`anywhere.enabled=true` and put its settings under the `anywhere:` block of the same values file
(its keys carry the `anywhere.` prefix on the parent chart):

```yaml
anywhere:
  enabled: true
  dependencies:
    s3:
      bucket: "phoenixai"
      # Prefix, kept separate from the cluster's "data" prefix above.
      path: "anywhere"
      region: "us-east-1"
      endpoint: "http://minio.minio.svc.cluster.local:9000"
      accessKey: "phoenixai"
      secretKey: "change-me-before-applying"
      # Required for MinIO.
      usePathStyle: true
```

Anywhere validates this at startup with a write/read/delete probe against the bucket, so a wrong
endpoint, credential or path-style setting is reported as an actionable error rather than failing
later when someone requests a support bundle.

## 5. Check the whole path

```sql
-- Storage is wired up: this table's data lands in MinIO.
CREATE DATABASE IF NOT EXISTS minio_check;
CREATE TABLE minio_check.t (k INT) PROPERTIES ("replication_num" = "1");
INSERT INTO minio_check.t VALUES (1), (2), (3);
SELECT count(*) FROM minio_check.t;
```

Then confirm the objects exist, and that both prefixes are in use:

```bash
kubectl -n minio exec deploy/minio -- \
  mc --no-color ls --recursive local/phoenixai/ | head
```

Finally, generate a support bundle from the Anywhere console (Support → Create support bundle) and
check that objects appear under the `anywhere` prefix. At that point the cluster and the console are
both storing to MinIO.

## Troubleshooting

**The FE cannot reach storage, or table creation fails with an S3 error.** Check that
`aws.s3.enable_path_style_access` is `true` on the storage volume (`DESC STORAGE VOLUME`). Without
it, the client resolves `phoenixai.minio.minio.svc.cluster.local`, which does not exist.

**The FE ignores your storage volume.** `enable_load_volume_from_conf = false` must be set, and the
volume must be the default (`SET ... AS DEFAULT STORAGE VOLUME`).

**Anywhere reports an object-storage error at startup.** The endpoint needs a scheme
(`http://…`), and `usePathStyle` must be `true`. The startup probe names which operation failed.

**The bucket does not exist.** Re-run the bucket Job; nothing else creates it.

**Queries and loads are slow, or time out, but storage is otherwise reachable.** Check that
`AWS_EC2_METADATA_DISABLED=true` is set on the FE, the cluster's compute nodes, **and** each
warehouse's compute nodes. Without it, the S3 client tries the EC2 instance metadata service at
`169.254.169.254` on the way to the credentials you configured, and outside AWS that probe has to
time out before anything proceeds. It fails quietly: storage works, everything is just slow.
