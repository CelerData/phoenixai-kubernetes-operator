# anywhere-console

The **only supported way to install PhoenixAI Anywhere** — an operations, usage and SQL console
for PhoenixAI deployments on Kubernetes. Anywhere deploys **standalone, next to the PhoenixAI
operator** (its own single-replica StatefulSet with a data PVC, Service and ServiceAccount).

This chart is a subchart of the parent `kube-anywhere` chart (which also installs the operator
and a PhoenixAI cluster), where it is addressed as `anywhere`. Two ways to install it:

1. **With the parent chart** (recommended): set `anywhere.enabled=true` and prefix every value
   below with `anywhere.` (e.g. `anywhere.dependencies.s3.bucket`).
2. **Standalone** — from the released `anywhere-console-<version>.tgz` package, or from the
   `charts/anywhere-console/` directory of an unpacked `kube-anywhere` chart; use this next to an
   operator that is installed and managed separately. The values below apply as-is (no
   `anywhere.` prefix) and `enabled` is ignored.

## Prerequisites

- The operator installed with its gRPC query API exposed (`phoenixAIOperator.enableApiServer`,
  **on by default**; through the parent chart the key is
  `operator.phoenixAIOperator.enableApiServer`). This renders the `kube-anywhere-operator-api` Service
  (`:9090`) that anywhere's ops data path talks to; the default `operatorApiAddrs` entry assumes
  the same namespace and the operator chart's default `nameOverride`.
- If the console is published through an Ingress or another HTTP proxy, that proxy must pass
  **WebSocket upgrades** through to the console Service, and its idle timeout for the connection
  must be longer than 15 seconds. The SQL Editor in the Cluster Console executes statements over a
  WebSocket (`GET /api/v1/namespaces/{ns}/clusters/{cluster}/editor/socket`) that the console keeps
  alive with a ping every 15 seconds; nginx-ingress, the AWS load balancer controller and Traefik
  pass upgrades by default, and nginx's default `proxy-read-timeout` (60s) is fine. A proxy that
  drops idle WebSockets sooner shows up as an editor whose Run button never answers.

## Install

**Object storage is required**: the chart refuses to render until exactly one of
`dependencies.s3`, `dependencies.azblob`, `dependencies.adls2` or `dependencies.gs` is configured
(see [External dependencies](#external-dependencies-object-storage--prometheus)).

Installation goes through a values file you author — `my-values.yaml` below — rather than `--set`
chains: the file is reviewable, reusable across upgrades, and the S3 block carries credentials
you do not want in shell history.

With the parent chart, in one install together with the operator and cluster:

```yaml
# my-values.yaml (the operator's gRPC query API is on by default)
anywhere:
  enabled: true
  dependencies:
    s3:
      bucket: <bucket>
      region: <region>
      accessKey: <ak>
      secretKey: <sk>
```

```bash
helm upgrade --install kube-anywhere phoenixai/kube-anywhere -n <namespace> -f my-values.yaml
```

Standalone, next to an operator you install and manage separately — the chart is published as its
own `anywhere` package, and the same keys apply without the `anywhere.` prefix:

```yaml
# my-values.yaml
dependencies:
  s3:
    bucket: <bucket>
    region: <region>
    accessKey: <ak>
    secretKey: <sk>
```

```bash
helm upgrade --install anywhere phoenixai/anywhere-console -n <namespace> -f my-values.yaml
```

The same chart also ships inside the parent package, so `helm pull phoenixai/kube-anywhere --untar`
followed by installing its `charts/anywhere-console/` directory is equivalent.

Then reach the console:

```bash
kubectl -n <namespace> port-forward svc/kube-anywhere-console 8090:8090
curl -s localhost:8090/api/v1/health
```

## Scope: pairing the operator's mode

One anywhere serves every operator it is pointed at:

| Operator mode | Install | RBAC rendered |
|---|---|---|
| Global (default) | one anywhere for the whole Kubernetes cluster | ClusterRole + ClusterRoleBinding |
| Namespaced | one anywhere for ALL operators: list every operator API in `operatorApiAddrs` and every namespace in `watchNamespaces` | Role + RoleBinding per entry of `watchNamespaces` |

```yaml
# in my-values.yaml — namespaced-mode pairing: one anywhere, two operators
# (prefix both keys with `anywhere.` when installing through the parent chart)
operatorApiAddrs:
  - kube-anywhere-operator-api.ns-a:9090
  - kube-anywhere-operator-api.ns-b:9090
watchNamespaces:
  - ns-a
  - ns-b
```

Both values are plain lists — a single namespaced-mode operator is just one entry in each (the
one-anywhere-per-namespace install remains possible, it is just no longer required).

The RBAC is minimal and read-oriented: `secrets: [get]` (per-cluster credential resolution) and
`pods/exec: [create]` (the exec feature). Pod topology comes from the operator API, so no other
Kubernetes verbs are granted. The ServiceAccount and (Cluster)Role/(Cluster)RoleBinding are
always rendered — anywhere cannot function without them, so there is no `rbac.create`-style
toggle; what IS configurable is the ServiceAccount's name/annotations/labels (`serviceAccount.*`,
e.g. for cloud IAM bindings).

## External dependencies (object storage / Prometheus)

Anywhere is stateless by design — persistence and metrics come from services **the user provides**:

| Dependency | Consumed by | Values block |
|---|---|---|
| Object storage (**required**, exactly one): S3-compatible, Azure Blob Storage, Azure Data Lake Storage Gen2 or Google Cloud Storage | large artifacts: query profiles (tens of KB–tens of MB) and support bundles (up to 100 GiB scale) | `dependencies.s3`, `dependencies.azblob`, `dependencies.adls2` or `dependencies.gs` |
| Prometheus (optional) | the System Monitoring pages (query-only, no own TSDB) | `dependencies.prometheus` |

There is deliberately no relational-database dependency: anywhere embeds its relational storage
(SQLite on the data PVC, sized by `persistence.size` — see [Persistence](#persistence)) — the
usage-metering ledger and future console state need no user-provided database.

The object-store blocks have no on/off switch — the chart refuses to render until exactly one of
them is configured (`s3.bucket`, `azblob.container`, `adls2.container` or `gs.bucket`, plus the
credentials your provider requires; two configured blocks are refused as well), and at startup
the backend re-enforces the same policy and additionally probes the store (a
write/read/list/presign/delete of `system/startup-probe`), so bad credentials, a missing
bucket/container, or a credential that can write but not list fail the pod immediately instead
of silently mis-storing data. The presign step runs only on a store that advertises support-bundle
export (S3, Azure with any credential but `sasToken`, GCS) and makes that claim honest: an identity
that claims to sign download URLs but cannot — a GCS identity without a private key that lacks the
IAM `signBlob` permission, or an Azure Entra ID identity that may not obtain a user delegation
key — fails the pod too. Azure with `sasToken` does not advertise export,
skips the step and starts normally (see the Azure blocks below). All four backends store the same key layout — one top-level
prefix per feature, optionally under the block's `path` (so a bucket or container can be shared
with other uses, e.g. the PhoenixAI cluster's own data store; bucket/container + `path` match the
cluster's `aws_s3_path` / `azure_blob_path` / `azure_adls2_path` / `gs://` location semantics). The configured block
is inlined into the `dependencies:` section of the rendered config-file Secret
(`templates/secret-config.yaml` — the reason the config is a Secret and not a ConfigMap). The whole
config is read once at startup; changing any of it via `helm upgrade` rolls the pod through the
config checksum annotation, which is also how rotated credentials take effect.

The `s3` block is AWS S3, or any S3-compatible store through `endpoint`:

```yaml
# in my-values.yaml — AWS S3 with a static access key
# (nest it under `anywhere:` when installing through the parent chart)
dependencies:
  s3:
    bucket: <bucket>
    path: anywhere
    region: <the bucket's region>
    accessKey: <access-key-id>
    secretKey: <secret-access-key>
```

| Identity | Values |
|---|---|
| Static access key (an IAM user's key) | `accessKey` + `secretKey` |
| The AWS SDK's default credential chain: IAM Roles for Service Accounts (IRSA), EKS Pod Identity, an EC2 instance profile | leave `accessKey` and `secretKey` empty — no secret in the values. For IRSA, annotate the console's Kubernetes ServiceAccount with the role through `serviceAccount.annotations` (`eks.amazonaws.com/role-arn: arn:aws:iam::<account>:role/<role>`); for EKS Pod Identity, associate the role with that ServiceAccount |

On AWS, `region` is required and must be the bucket's own region: a missing one, or another
region, fails the startup probe. Leave `endpoint` empty there (the regional endpoint follows from
`region`); an S3-compatible store (Alibaba OSS, MinIO, ...) takes its endpoint and usually accepts
any non-empty `region`. With no key in the values and no identity in the pod's environment, the
SDK ends its search at the EC2 instance metadata service, so the startup failure reads
`no EC2 IMDS role found` — it means no identity was configured.

The identity needs these five actions, and no others:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": "s3:ListBucket", "Resource": "arn:aws:s3:::<bucket>" },
    { "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:AbortMultipartUpload"],
      "Resource": "arn:aws:s3:::<bucket>/*" }
  ]
}
```

Without `s3:PutObject`, `s3:GetObject`, `s3:ListBucket` or `s3:DeleteObject` the startup probe
fails at the step that needs it (write, read back, list, delete) and names the action;
`s3:AbortMultipartUpload` lets a support-bundle upload that failed half-way clean up its parts.
Every key lies under `path`, so the object resource can be narrowed to
`arn:aws:s3:::<bucket>/<path>/*`. Encryption and export:

- **Bucket default encryption works as it is** — SSE-S3, or SSE-KMS with a customer-managed key,
  for which the identity also needs `kms:GenerateDataKey` (writes; without it the startup probe
  fails) and `kms:Decrypt` (reads, downloads and presigned export URLs).
- **A bucket policy that requires the `x-amz-server-side-encryption` header on every upload is not
  supported**: the console does not send that header, so every write is denied. Rely on the
  bucket's default encryption instead, which S3 applies without it.
- **Support-bundle export URLs are signed with the console's identity.** With a static key a URL
  lives for the lifetime the export asked for (up to 7 days). With temporary credentials (IRSA,
  EKS Pod Identity, an instance profile, an assumed role) S3 stops accepting the URL when the
  session that signed it expires — typically within hours, whatever lifetime was asked for. When
  a link must last longer, use a static key, or download the bundle through the console.

The two Azure blocks follow the PhoenixAI Database storage-volume vocabulary, so the values can be
copied from the cluster's own configuration:

| Block | Storage account | Storage volume `TYPE` / fe.conf keys | `endpoint` |
|---|---|---|---|
| `dependencies.azblob` | Azure Blob Storage — hierarchical namespace **disabled** | `AZBLOB` / `azure_blob_*` | `https://<account>.blob.core.windows.net` |
| `dependencies.adls2` | Azure Data Lake Storage Gen2 — hierarchical namespace **enabled** | `ADLS2` / `azure_adls2_*` | `https://<account>.dfs.core.windows.net` |

```yaml
# in my-values.yaml — ADLS Gen2 with the account's access key
dependencies:
  adls2:
    endpoint: https://<account>.dfs.core.windows.net
    container: <file-system>
    path: anywhere
    sharedKey: <account-key>
```

Both take exactly one credential — anything configured beyond the one chosen refuses startup
rather than being ignored:

| Credential | Values | ADLS2 storage-volume properties |
|---|---|---|
| Account key | `sharedKey` | `azure.adls2.shared_key` |
| SAS | `sasToken` (an account or container SAS with read, write, delete, list and create permissions on the Blob service) | `azure.adls2.sas_token` |
| Workload identity (AKS) | `oauth2TokenFile` + `oauth2TenantId` + `oauth2ClientId` | `azure.adls2.oauth2_token_file` + `_tenant_id` + `_client_id` |
| Managed identity (user-assigned) | `oauth2UseManagedIdentity: true` + `oauth2TenantId` + `oauth2ClientId` | `azure.adls2.oauth2_use_managed_identity` + `_tenant_id` + `_client_id` |
| Service principal | `oauth2ClientId` + `oauth2ClientSecret` + `oauth2ClientEndpoint` | `azure.adls2.oauth2_client_id` + `_client_secret` + `_client_endpoint` |

The `azblob` block takes the same keys with the same rules: a storage volume of `TYPE = AZBLOB`
has no OAuth2 form to copy from, so the ADLS2 one is used for both. Two things follow from the
credential choice and the endpoint:

- **Support-bundle export** (`POST .../support/bundles/{id}/export`, a presigned download URL for
  the vendor) works with every credential but `sasToken`: a SAS cannot sign a new SAS, so with
  `sasToken` a bundle's `exportSupported` is `false` and it is downloaded through the console
  instead. This is a supported, deployable mode — the startup probe skips its presign step for it.
  The account key signs a service SAS; the three Microsoft Entra ID identities sign a user
  delegation SAS, which Azure caps at 7 days — an export asking for the full 168 hours gets a link
  that expires a few minutes earlier, and the response's `expiresAt` says exactly when. S3 always
  supports export.
- **ADLS Gen2 is reached through the account's Blob endpoint**
  (`https://<account>.blob.core.windows.net`, derived from the DFS endpoint you configure — every
  storage account has both): a Private Endpoint for the account must therefore cover the `blob`
  sub-resource, not only `dfs` — with its own private DNS zone,
  `privatelink.blob.core.windows.net`, linked to the cluster's network — or the startup probe
  fails on the blob host, in whatever way the network fails it: `403 AuthorizationFailure` where
  the account's public endpoint can still be reached (public network access disabled), a
  resolution or connection failure where it cannot, or the probe's 30 s deadline — and the log
  line's `note` names the missing sub-resource in each case. The same reach applies to a
  **support-bundle export URL**: it points at the blob endpoint, so on an account that admits
  only private endpoints it downloads only from inside that network, and a vendor outside it is
  handed the bundle through the console's own download instead.

#### Authenticating with Microsoft Entra ID

The three Entra ID identities need no account key, so they work on an account whose shared-key
access is disabled (`allowSharedKeyAccess = false`, which the Azure Policy "Storage accounts should
prevent shared key access" enforces) — where an account key and every SAS signed with it are
refused. Whichever identity is used needs the **Storage Blob Data Contributor** role **on the
storage account** (Owner and Contributor are management roles and grant no access to blob data).
The account scope matters: support-bundle export signs with a user delegation key, and the
permission to obtain one (`generateUserDelegationKey`) can only be granted at the storage account
or above. With the role on the container alone the console can read and write, but the startup
probe — which obtains a key — fails with `AuthorizationPermissionMismatch`, and the log's `note`
says so. To keep the data role on one container, add **Storage Blob Delegator** on the account
beside it. A new role assignment takes a few minutes to take effect, and the startup probe fails
with `AuthorizationPermissionMismatch` until it has.

**Workload identity** is the one to use on AKS. It needs, once per install:

1. an AKS cluster with the OIDC issuer and workload identity enabled
   (`az aks update --enable-oidc-issuer --enable-workload-identity`);
2. a user-assigned managed identity, with Storage Blob Data Contributor on the account;
3. a federated credential on that identity: issuer = the cluster's OIDC issuer URL, subject =
   `system:serviceaccount:<release namespace>:<service account>`, audience =
   `api://AzureADTokenExchange`. The service account is `nameOverride` (default
   `kube-anywhere-console`) unless `serviceAccount.name` sets another;
4. the pod label the AKS webhook looks for, set through `podLabels` — without it no token is
   mounted, and the console refuses to start saying so.

```yaml
# in my-values.yaml — ADLS Gen2 with AKS workload identity
dependencies:
  adls2:
    endpoint: https://<account>.dfs.core.windows.net
    container: <file-system>
    oauth2TokenFile: /var/run/secrets/azure/tokens/azure-identity-token
    oauth2TenantId: <tenant-id>
    oauth2ClientId: <identity-client-id>
podLabels:
  azure.workload.identity/use: "true"
```

The console reads the client, the tenant and the token file from these values only. The
`AZURE_CLIENT_ID` / `AZURE_TENANT_ID` / `AZURE_FEDERATED_TOKEN_FILE` variables the webhook injects
are not read, and annotating the service account with `azure.workload.identity/client-id` (what
the Azure documentation shows) is harmless but not needed.

**Managed identity** suits a self-managed Kubernetes on Azure VMs or VM scale sets: the identity is
attached to the nodes and reached through the instance metadata service (`169.254.169.254`), which
a network policy must not block. Only a user-assigned identity, named by `oauth2ClientId`, is
supported. On AKS prefer workload identity — the node's kubelet identity is shared by every pod on
the node. Off Azure there is no metadata service, and the console refuses to start after its 30 s
startup budget, saying so.

**Service principal** works anywhere, including outside Azure: an app registration with a client
secret, and `oauth2ClientEndpoint` set to its token endpoint
`https://login.microsoftonline.com/<tenant-id>/oauth2/token` (the `/oauth2/v2.0/token` form is
accepted too). The client secret is a credential like an account key: it expires (at most two
years), and rotating it is a `helm upgrade` that rolls the pod.

Workload identity and service principal also need the pod to reach Microsoft Entra ID over HTTPS
(`login.microsoftonline.com`; `login.chinacloudapi.cn` / `login.microsoftonline.us` for an account
in Azure China / Azure Government, which the console derives from the account endpoint). A
firewall that allows only the storage endpoint makes the startup probe fail on the token request.

The `gs` block is Google Cloud Storage through its native API, with the identity options a
PhoenixAI Database storage volume of `TYPE = GS` takes (its `gcp.gcs.*` properties, in
camelCase), so the values can be copied from the cluster's `CREATE STORAGE VOLUME` statement:

| Identity | Values | Storage volume properties |
|---|---|---|
| Compute Engine service account (on GKE: Workload Identity) | `useComputeEngineServiceAccount: true` — no secret in the values; bind the console's Kubernetes ServiceAccount to the Google service account through `serviceAccount.annotations` (`iam.gke.io/gcp-service-account`) | `gcp.gcs.use_compute_engine_service_account` |
| Service-account key | `serviceAccountEmail` + `serviceAccountPrivateKeyId` + `serviceAccountPrivateKey` (the `client_email` / `private_key_id` / `private_key` of the JSON key, all three) | `gcp.gcs.service_account_email` / `_private_key_id` / `_private_key` |
| Impersonation | either identity above plus `impersonationServiceAccount`; the identity needs `roles/iam.serviceAccountTokenCreator` on the target | `gcp.gcs.impersonation_service_account` |

```yaml
# in my-values.yaml — Google Cloud Storage with a service-account key
dependencies:
  gs:
    bucket: <bucket>
    path: anywhere
    serviceAccountEmail: <sa>@<project>.iam.gserviceaccount.com
    serviceAccountPrivateKeyId: <key-id>
    serviceAccountPrivateKey: |
      <the PEM private key of the JSON key file, BEGIN and END lines included>
```

The identity needs object read, write, list and delete on the bucket (`roles/storage.objectAdmin`
covers it). Support-bundle export always works on `gs`: a service-account key signs the download
URL locally, and the other two identities sign through the IAM Credentials API, which needs
`roles/iam.serviceAccountTokenCreator` on the signing account itself (the Compute Engine account,
or the impersonated one) — the startup probe signs once and refuses to start without that role,
so a bundle never advertises an export that would then fail. `endpoint` is optional (the public
`https://storage.googleapis.com` when empty) and is for a Private Service Connect address or a
proxy; the IAM Credentials API is always reached at its public endpoint.

Google Cloud Storage can also be reached through its S3-compatible XML API with the `s3` block —
the same way a storage volume of `TYPE = S3` with `aws.s3.endpoint = https://storage.googleapis.com`
does — using an HMAC key generated for a service account (Cloud Storage → Settings →
Interoperability): `endpoint: https://storage.googleapis.com`, `accessKey` / `secretKey` set to the
HMAC pair, any non-empty `region`, and either addressing style. That path keeps an S3-shaped
credential in the stack; the `gs` block is the one that needs none.

`dependencies.prometheus` stays opt-in (`enabled: false` by default):

```yaml
# in my-values.yaml, next to the required s3 block
dependencies:
  prometheus:
    enabled: true
    endpoint: http://prometheus.monitoring:9090
```

The Prometheus block supports the common enterprise access shapes — base URL with a path prefix,
basic auth or `bearerToken`, extra `headers` (multi-tenant `X-Scope-OrgID`), self-signed CA via
`tls.caCert` — plus two rename-adaptation knobs (`metricPrefix`, `clusterLabel`); see the comments
in [values.yaml](values.yaml). Validate the wiring after install with
`POST /api/v1/admin/dependencies/prometheus/check` — it checks config → connectivity → auth → metric
presence → rename detection → cluster label and answers each failure with actionable fix guidance.
The same checks also run per cluster as the `prometheus-dependency-unusable` health-check rule
(warning), so a missing or misconfigured dependency surfaces in the health-check view without anyone
opening that endpoint; an installation that deliberately runs without Prometheus can silence it via
`inspection.disabledRules`.

The object store is consumed by Query Insights History — query profile/explain/SQL texts land
under the `profile/` key prefix — and by Support bundles: bundle archives stream under the
`support-bundle/` prefix (no local staging, sized for 100 GiB-scale log collections; a bundle
streams with a fixed upload geometry, so one archive can be at most about 312 GiB on `s3` and
S3-compatible stores — 32 MiB parts, 10,000 parts per upload — and 390 GiB on `azblob` / `adls2`
— 8 MiB blocks, 50,000 blocks per blob — while `gs` has no part limit), and can be
exported as presigned, expiring download URLs (`POST .../support/bundles/{id}/export`; see the
credential note above for Azure). Operational notes:

- **Two-sided opt-in**: query-history collection is off by default on BOTH sides. Anywhere's own
  switch is `queryHistory.enabled` (chart value; off = anywhere sends no background requests to
  any cluster), matching the FE config `enable_collect_query_detail_info`, which also defaults to
  `false` — enable it at runtime with
  `ADMIN SET FRONTEND CONFIG ("enable_collect_query_detail_info" = "true")` (must reach every FE),
  persisted by also setting it in `fe.conf`. The PhoenixAI Database-side cost is a small in-FE-memory queue
  (~30s of query details, cleaned every 5s). The status endpoint
  (`GET /api/v1/namespaces/{ns}/clusters/{cluster}/query-history/status`) probes the flag and
  reports side-specific guidance, and the configuration inspection flags a half-enabled state
  (rule `query-detail-collect-inconsistent`).
- **What gets persisted**: only queries at least `queryHistory.slowQueryMs` (default 5000 ms) slow,
  plus every failed query; `slowQueryMs: 0` keeps everything but is suitable only for low-traffic
  clusters — at high QPS full persistence grows the database and object store without bound. See
  the sizing comment in `values.yaml`.
- **Retention**: anywhere deletes expired records and objects itself
  (query-history `retentionDays`, default 7; `supportBundle.retentionDays` for bundles —
  time is the primary dimension). Independent of retention, anywhere trims the oldest
  query-history records when the data PVC passes 85% usage, down to 70%. Configuring bucket
  lifecycle rules is a recommended backstop for
  objects orphaned while anywhere is down — expiration on the `profile/` prefix (query-history
  retention + 7 days) and on the `support-bundle/` prefix (bundle retentionDays + 7 days), plus an
  abort-incomplete-multipart-upload rule (a bundle upload killed mid-flight can leave paid-for
  parts behind).

### Switching to another object store, and downgrading

Anywhere does **not** migrate objects between stores. A `helm upgrade` that changes the configured
block — another backend, or the same backend with another bucket, container, account or `path` —
starts the console on the new location only:

- support bundles created before the switch drop out of the bundle list; their archives stay in
  the old location until you delete them there (or lifecycle rules expire them);
- query-history records collected before the switch stay in the list, but their SQL / plan /
  profile texts can no longer be opened — the texts live in the old location, and the console
  answers that they could not be read;
- everything collected after the switch works as usual.

To keep old bundles reachable, download them before switching, or copy the `support-bundle/`
(and, for old query texts, `profile/`) prefixes into the new location under the same keys before
the upgrade — the key layout is identical on all four backends. One move keeps everything: an Azure
Data Lake Storage Gen2 account is also reachable through its Blob endpoint, so switching between
`dependencies.adls2` and `dependencies.azblob` on the **same** account, container and `path` sees the
same objects (`path` is the key prefix, so a different one starts from an empty tree).

A **downgrade** to a chart or image older than the Azure Blob Storage / ADLS Gen2 / Google Cloud
Storage support (the 2.0.x line) only knows `dependencies.s3`:

- the older chart refuses to render with an `azblob`, `adls2` or `gs` block (it asks for
  `dependencies.s3`), so `helm upgrade` to it with your current values fails and leaves the release
  where it is;
- the older backend refuses to start on a config that carries one of those blocks (`unknown field`).

Switch the release back to `dependencies.s3` before or while you downgrade —
`helm rollback` to a revision that ran on S3 does exactly that — and expect the effects of a store
switch above: what was written to Azure or GCS is invisible until you upgrade again, and reappears
then. The embedded database is not in the way: an older console starts on a data volume a newer
one has already migrated.

## Persistence

The embedded relational storage (SQLite: the usage-metering ledger, future console state) lives
on a **standalone chart-managed PVC** named `data-<nameOverride>-0` (`data-kube-anywhere-console-0` by default) —
deliberately not a StatefulSet `volumeClaimTemplate`, whose immutability would freeze the size at
install time:

- **Resize**: raise `persistence.size` in your values file and `helm upgrade -f my-values.yaml` to
  grow the volume in place, when the StorageClass has `allowVolumeExpansion: true`. Shrinking is
  rejected by Kubernetes. Some CSI drivers finish the filesystem expansion only on pod restart — if
  the PVC reports a `FileSystemResizePending` condition, `kubectl delete pod kube-anywhere-console-0` completes
  it.
- **Survives uninstall**: the PVC carries `helm.sh/resource-policy: keep` — usage records are the
  customer's bill, remove them deliberately (`kubectl delete pvc data-kube-anywhere-console-0`). A same-name
  reinstall adopts the kept PVC and its data.
- **Bring your own PVC**: set `persistence.existingClaim` to a pre-created claim in the release
  namespace; the chart then renders no PVC and `size`/`storageClass` are ignored.

## Upgrading from 2.0.x

Two names changed after 2.0.x. The chart handles both on `helm upgrade`, whether the release is
upgraded with `-f my-values.yaml` or with `--reuse-values`:

- **The console image** moved from `us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/anywhere`
  to `us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/anywhere-console`. The old repository
  receives no new versions. The 2.0.x chart and its example values set the old repository
  explicitly, and `--reuse-values` keeps it, so an upgraded release would otherwise pull a tag the
  old repository does not have and stay in `ImagePullBackOff`. When `image.repository` is exactly
  the old repository and `image.tag` is empty (the tag follows the chart), the chart pulls the new
  repository instead, and its install notes say so.
  - If you upgrade with `--reuse-values`, the 2.0.x default is reused from the previous release, not
    from your values, and later `--reuse-values` upgrades keep reusing it. To make the new
    repository explicit, upgrade once with your values file instead of `--reuse-values`, or add
    `--set image.repository=us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/anywhere-console`
    (`anywhere.image.repository` under the parent `kube-anywhere` chart).
  - If your own values pin the old repository and leave `image.tag` empty, drop the
    `image.repository` line.
  - If you also set `image.tag`, the old repository is used as written. Every tag it ever had is
    still served there, so the pinned pod keeps running. The old repository holds nothing newer
    than `v2.0.1`, though, so before you bump the tag, move the pin to the new repository.
    Change `image.repository` and `image.tag` together, in the same edit, to the new repository
    and a version published there. Do not drop the repository line alone, because that keeps your
    tag, and the new repository may not have it (`v2.0.0-rc1` exists only in the old one). Or
    keep the old repository with a tag it already has. The install notes remind you while the old
    repository is set.
  - A repository of your own, such as a mirror, is used exactly as given. Mirror the new image
    name into it before you upgrade.
- **The chart** was renamed from `anywhere` to `anywhere-console`. Resource names do not change
  with it. With the shipped `nameOverride` they keep the `kube-anywhere-console` prefix. A
  standalone install that set `nameOverride: ""` keeps the `anywhere` prefix it had in 2.0.x, so
  the upgrade mounts the same data PVC (`data-anywhere-0`) and keeps the same admin Secret.

## Notable values

Prefix each with `anywhere.` when installing through the parent `kube-anywhere` chart.

| Value | Default | Meaning |
|---|---|---|
| `enabled` | `false` | parent-chart condition: whether `kube-anywhere` installs the console (ignored standalone) |
| `nameOverride` | `kube-anywhere-console` | prefix of every resource this chart creates (StatefulSet, Services, Secrets, ServiceAccount, RBAC, PVC `data-<nameOverride>-0`). It does not follow the release name — change it to run a second console in a namespace that already has one. Empty means `anywhere` |
| `image.repository` / `.tag` | `us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/anywhere-console`, tag = chart appVersion | container image. The 2.0.x repository `.../enterprise/anywhere` with an empty tag is replaced with the current one (see [Upgrading from 2.0.x](#upgrading-from-20x)) |
| `operatorApiAddrs` | `["kube-anywhere-operator-api:9090"]` | ALL operator gRPC API Service addresses this anywhere serves — one entry per operator; order arbitrates ownership conflicts |
| `watchNamespaces` | `[]` (all namespaces, cluster-scoped RBAC) | the namespaces the PhoenixAI clusters live in when pairing namespaced-mode operators; one Role/RoleBinding each |
| `admin.users` / `admin.existingSecret` | `{admin: admin}` / `""` | Admin Console accounts. The chart ships a default **admin / admin** account, which a reachable install must replace; clear `users` to have a random password generated instead. See the comments in `values.yaml` for the three sources and the GitOps caveat |
| `auth.secureCookies` | `false` | marks both consoles' session cookies `Secure`. Off by default because the in-cluster deployment speaks plain HTTP, where the flag would stop every login from working; turn it on when TLS terminates in front of the console (an Ingress, a load balancer, a service mesh) |
| `auth.sessionTTL` | `""` (the service default, 24h) | sliding lifetime of a login — every request pushes the expiry back, so it bounds idle time rather than total session length. A Go duration (`"12h"`, `"90m"`), and it must be positive |
| `httpPort` | `8090` | HTTP listen/Service port |
| `logLevel` | `info` | debug/info/warn/error; an unknown level refuses startup |
| `dependencies.s3.bucket` / `.region` / `.accessKey` / `.secretKey` / ... | `""` | S3-compatible object storage for large artifacts — one of the four object-store blocks is required, see [External dependencies](#external-dependencies-object-storage--prometheus) |
| `dependencies.azblob.endpoint` / `.container` / `.path` / `.sharedKey` / `.sasToken` / `.oauth2TokenFile` / `.oauth2UseManagedIdentity` / `.oauth2TenantId` / `.oauth2ClientId` / `.oauth2ClientSecret` / `.oauth2ClientEndpoint` | `""` / `false` | Azure Blob Storage (hierarchical namespace disabled) as the object store; exactly one credential: `sharedKey`, `sasToken`, or a Microsoft Entra ID identity (see [Authenticating with Microsoft Entra ID](#authenticating-with-microsoft-entra-id)) |
| `dependencies.adls2.*` | `""` / `false` | Azure Data Lake Storage Gen2 (hierarchical namespace enabled) as the object store; the DFS endpoint, the same keys and credential rule as `azblob` |
| `dependencies.gs.bucket` / `.path` / `.endpoint` / `.useComputeEngineServiceAccount` / `.serviceAccountEmail` / `.serviceAccountPrivateKeyId` / `.serviceAccountPrivateKey` / `.impersonationServiceAccount` | `""` / `false` | Google Cloud Storage as the object store; exactly one of the Compute Engine identity or the three key fields, optionally impersonating another account |
| `queryHistory.enabled` | `false` | query-history collection switch — off by default, matching the PhoenixAI Database-side `enable_collect_query_detail_info` default; enable both to use the history page |
| `queryHistory.slowQueryMs` | `5000` | persist bar in ms: only queries at least this slow are kept (failed queries always are); `0` keeps every query |
| `queryHistory.profileBackfillLimit` | unset (`1000`) | how many records per FE may wait for a profile the FE builds after the record is collected; it is fetched from that FE for up to 5 minutes. Keep it at about twice the FEs' `profile_info_reserved_num` (default 500) |
| `queryHistory.collectInterval` / `.retentionDays` | `10s` / `7` | sampling period (the FE queue retains only ~30s) and days to keep records + profile objects (`0` means the default 7 days, not keep-forever; negative values refuse startup) |
| `license.expiryWarnWindow` | `720h` (30 days) | how far ahead of a license's expiry warnings fire — the `license-invalid` inspection rule and the cluster list/overview `expiringSoon` flag share this boundary |
| `license.cacheTTL` | `5m` | how long a cluster's registered-license list is served from anywhere's in-memory cache before its FE is asked again; `"0s"` disables the cache |
| `inspection.enabledRules` / `.disabledRules` | `[]` / `[]` (all rules run) | CR-inspection rule selection; rule ids and meanings are listed as comments in `values.yaml` |
| `env` | `[]` | extra container env vars, e.g. `GODEBUG` (anywhere's own configuration is not env-settable — it goes through the rendered config file) |
| `serviceAccount.name` / `.annotations` / `.labels` | `""` (the `nameOverride` prefix) / `{}` / `{}` | the always-created ServiceAccount the pod runs as (annotations e.g. for cloud IAM bindings) |
| `podLabels` | `{}` | extra labels on the console pod, e.g. `azure.workload.identity/use: "true"` for AKS workload identity; the chart's own `app` / `version` labels cannot be overridden (the render refuses) |
| `persistence.size` | `10Gi` | data PVC size; growable via `helm upgrade` (StorageClass must allow expansion), never shrinkable |
| `persistence.storageClass` | `""` (cluster default) | StorageClass of the chart-rendered PVC |
| `persistence.existingClaim` | `""` | use a pre-created PVC instead of rendering one (`size`/`storageClass` then ignored) |

See `values.yaml` for the full list. Configuration reaches the container as a rendered config
file (the `kube-anywhere-console-config` Secret — a Secret because the inlined `dependencies:` section
carries credentials — mounted and passed via `--config`); a checksum annotation on the pod
template rolls the pod whenever the rendered file changes. There are no `PHOENIXAI_ANYWHERE_*`
environment variables.
