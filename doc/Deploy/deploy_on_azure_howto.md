---
sidebar_label: Deploy on Azure
sidebar_position: 13
title: Deploy on Azure with AKS and ADLS Gen2
description: Run a PhoenixAI cluster and the Anywhere console on AKS with Azure Data Lake Storage Gen2 as the storage, authenticating with workload identity — no account key or SAS anywhere — on a storage account that admits only private endpoints.
---

# Deploy on Azure with AKS and ADLS Gen2

This page is the Azure variant of [Install with Helm](./install_with_helm.md). It changes two
things in that install and leaves everything else as it is:

- the **cluster's data** goes to an Azure Data Lake Storage Gen2 account instead of an S3 bucket;
- the **console's own artifacts** (support bundles, query profiles) go to an ADLS Gen2 account as
  well — the same account under a different directory, or a separate one.

Both are reached with **workload identity**: the pods present the token Kubernetes projects
into them, Microsoft Entra ID exchanges it for an access token, and no storage account key, SAS
or client secret exists in your values file, in a Kubernetes Secret or on a disk. The page also
covers a storage account whose **public network access is disabled**, reachable only through
private endpoints — the common enterprise policy — because that is where the details matter.

:::note What you already have
This page assumes an AKS cluster you can reach with `kubectl`, the `az` CLI signed in to the
subscription that holds it, and the rights to create a managed identity, role assignments and
(for the private-endpoint section) network resources. It also assumes you have read
[Install with Helm](./install_with_helm.md) once: the images, the pull secret, the root password
and the install command are the same here and are not repeated.
:::

## Requirements

| Requirement | Why |
|---|---|
| AKS with the **OIDC issuer** and **workload identity** enabled | Workload identity is an AKS feature: the cluster signs the pods' service-account tokens and Azure trusts them through the issuer. `az aks update --enable-oidc-issuer --enable-workload-identity` turns both on for an existing cluster |
| PhoenixAI Database **4.1.6-ee or later** | The first release in which a storage volume built from `azure_adls2_oauth2_token_file` works end to end on every FE and CN. Earlier 4.1.x releases accept the setting and silently fall back to managed identity |
| A storage account with the **hierarchical namespace enabled** (that is what makes it ADLS Gen2), and a container in it | The cluster writes under `<container>/<directory>`. The console can share the account and container under a directory of its own, or use a separate account |
| Outbound HTTPS from the pods to **Microsoft Entra ID** (`login.microsoftonline.com`) | Every token exchange goes there; a network that allows only the storage endpoint fails at the first token request |

:::tip Blob Storage instead of ADLS Gen2
An account with the hierarchical namespace **off** is Azure Blob Storage. PhoenixAI Database
supports it as a storage volume too (`cloud_native_storage_type = AZBLOB`, `azure_blob_*`
settings), but only with an account key or a SAS: the workload identity settings exist for
ADLS Gen2 alone. For a deployment that must not hold a static key, use an ADLS Gen2 account.
The console takes either kind — `anywhere.dependencies.adls2` or `anywhere.dependencies.azblob`
— with every identity on both.
:::

## Step 1 — One identity, trusted by two service accounts

Workload identity ties a Kubernetes service account to an Azure identity through a **federated
credential**: a rule on the identity saying "trust tokens this cluster issues to this service
account". Two service accounts are involved, so the identity gets two federated credentials:

| Service account | Who runs as it | Name |
|---|---|---|
| The cluster's | every FE and CN pod, including a warehouse's compute nodes | one you create, `phoenixai-storage` below |
| The console's | the Anywhere console pod | created by the chart: `kube-anywhere-console`, unless you set `anywhere.serviceAccount.name` |

```bash
RG=<resource group of the AKS cluster>
AKS=<AKS cluster name>
NS=phoenixai                      # the namespace you install into
SA_ID=$(az storage account show -n <storage-account> --query id -o tsv)

# 1. A user-assigned managed identity
az identity create -g $RG -n phoenixai-storage
CLIENT_ID=$(az identity show -g $RG -n phoenixai-storage --query clientId -o tsv)
PRINCIPAL_ID=$(az identity show -g $RG -n phoenixai-storage --query principalId -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

# 2. The data-plane role, on the storage account
az role assignment create --assignee-object-id $PRINCIPAL_ID --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" --scope $SA_ID

# 3. Two federated credentials: issuer = this cluster, subject = each service account
ISSUER=$(az aks show -g $RG -n $AKS --query oidcIssuerProfile.issuerUrl -o tsv)
for sa in phoenixai-storage kube-anywhere-console; do
  az identity federated-credential create -g $RG --identity-name phoenixai-storage -n $sa \
    --issuer "$ISSUER" --subject system:serviceaccount:$NS:$sa --audiences api://AzureADTokenExchange
done
```

Three things people get wrong here:

- **The role must be a data-plane role, on the storage account.** Owner and Contributor are
  management roles and grant no access to blob data. The console also signs download links with
  a *user delegation key*, and the permission to obtain one can only be granted at the account
  scope — a role on the container alone lets it read and write but makes its startup check fail
  with `AuthorizationPermissionMismatch`. A new role assignment takes a minute or two to take
  effect.
- **The subject is `system:serviceaccount:<namespace>:<service account>`, verbatim.** The
  console's service account is named by the chart (`kube-anywhere-console`), not by your release
  name. A mismatch shows up as `AADSTS700213: No matching federated identity record found for
  presented assertion subject '…'` in the pod's log, and the subject in that message is the value
  to use.
- **The client id and tenant id go into the values file** (next step). Annotating the service
  account with `azure.workload.identity/client-id`, as Azure's own documentation shows, is
  harmless but not what PhoenixAI reads.

## Step 2 — The values file

Starting from the values file in [Install with Helm](./install_with_helm.md), replace the storage
settings as follows. `<account>`, `<container>`, `<tenant-id>` and `<client-id>` are the values
from Step 1; the token file path is fixed — it is where AKS mounts the projected token.

```yaml
phoenixai:
  # The service account the FE and CN pods run as (Step 1 trusts it). Any
  # extra object can be declared here; the chart applies it with the release.
  resources:
    - apiVersion: v1
      kind: ServiceAccount
      metadata:
        name: phoenixai-storage
        namespace: phoenixai

  phoenixAIFeSpec:
    serviceAccount: phoenixai-storage
    # This label is what makes AKS mount the token into the pod. Without it
    # the token file does not exist and the storage volume cannot be created.
    podLabels:
      azure.workload.identity/use: "true"
    config: |
      # ... the FE settings from the install guide, with the aws_s3_* lines
      # replaced by these:
      run_mode = shared_data
      cloud_native_meta_port = 6090
      cloud_native_storage_type = ADLS2
      enable_load_volume_from_conf = true
      azure_adls2_endpoint = https://<account>.dfs.core.windows.net
      azure_adls2_path = <container>/data
      azure_adls2_oauth2_use_managed_identity = false
      azure_adls2_oauth2_tenant_id = <tenant-id>
      azure_adls2_oauth2_client_id = <client-id>
      azure_adls2_oauth2_token_file = /var/run/secrets/azure/tokens/azure-identity-token

  phoenixAICnSpec:
    # The compute nodes read and write the same storage, so they need the same
    # identity and the same token mount. They take the storage settings from
    # the FE; nothing storage-related goes into the CN config.
    serviceAccount: phoenixai-storage
    podLabels:
      azure.workload.identity/use: "true"

anywhere:
  enabled: true
  podLabels:
    azure.workload.identity/use: "true"
  dependencies:
    # The console's own store. The same account is fine: a different directory
    # keeps its keys apart from the cluster's data.
    adls2:
      endpoint: https://<account>.dfs.core.windows.net
      container: <container>
      path: anywhere
      oauth2TokenFile: /var/run/secrets/azure/tokens/azure-identity-token
      oauth2TenantId: <tenant-id>
      oauth2ClientId: <client-id>
```

Notes on the block:

- The FE settings are the storage volume's properties in `fe.conf` spelling: the same names the
  `CREATE STORAGE VOLUME` statement takes as `azure.adls2.*`. With
  `enable_load_volume_from_conf = true` the FE builds the default storage volume from them when
  the cluster first starts.
- `azure_adls2_endpoint` and the console's `endpoint` are the same value: the account's **DFS**
  endpoint, with `https://`.
- The console block carries no `sharedKey`, `sasToken` or `oauth2ClientSecret`: the three
  identity keys above are the whole credential. Configuring any of the others beside them is
  refused at startup rather than silently ignored.
- A **warehouse** adds compute nodes of its own, deployed with the `warehouse` chart. Give them
  the same two settings — `spec.serviceAccount: phoenixai-storage` and
  `spec.podLabels: {azure.workload.identity/use: "true"}` — or its CN pods have no token and
  every query that reads the storage fails on them.

Then install exactly as the install guide does:

```bash
helm upgrade --install kube-anywhere phoenixai/kube-anywhere \
  --namespace phoenixai --create-namespace -f my-values.yaml
```

## Step 3 — Check that it worked

**The cluster.** Once the FE is up, the storage volume it built from the settings is listed, and
a table can be created and queried:

```sql
SHOW STORAGE VOLUMES;
DESC STORAGE VOLUME builtin_storage_volume;      -- the azure.adls2.* properties, no key or SAS
CREATE DATABASE smoke; CREATE TABLE smoke.t (k INT) PROPERTIES ("replication_num" = "1");
INSERT INTO smoke.t VALUES (1); SELECT * FROM smoke.t;
```

An `INSERT` that fails with an authorization error on a CN names the pod that has no token (see
[Troubleshooting](#troubleshooting)).

**The console.** Its pod writes, reads, lists and deletes a probe object in the store before it
serves anything, and logs the outcome in its first lines:

```bash
kubectl -n phoenixai logs kube-anywhere-console-0 | grep '"msg":"object storage'
# {"authMode":"workload-identity","clientId":"<client-id>","msg":"object storage: adls2",...}
```

A pod in `CrashLoopBackOff` instead failed that probe, and the same log line says why — see
[Troubleshooting](#troubleshooting). Nothing else about the console changes: the pages, the
support bundle and the query history work as on any other store.

## A storage account that admits only private endpoints

Many enterprise subscriptions set `publicNetworkAccess = Disabled` on every storage account and
reach them through **private endpoints**: a network interface in your virtual network with a
private IP, plus a private DNS zone that resolves the account's name to it from inside the
network. PhoenixAI works on such an account with two extra conditions.

**Private endpoints for both `dfs` and `blob`.** An ADLS Gen2 account has two sub-resources, and
PhoenixAI uses both: the FE and CN talk to the `dfs` endpoint, while the console reaches the
same account through its `blob` endpoint (`<account>.blob.core.windows.net`). Each sub-resource
is its own private endpoint with its own DNS zone, linked to the virtual network the AKS nodes
are in:

```bash
VNET=<virtual network of the AKS nodes>   # and its resource group
SUBNET=<a subnet in it for private endpoints>
for sub in dfs blob; do
  az network private-endpoint create -g $RG -n pe-$sub --vnet-name $VNET --subnet $SUBNET \
    --private-connection-resource-id $SA_ID --group-id $sub --connection-name $sub
  az network private-dns zone create -g $RG -n privatelink.$sub.core.windows.net
  az network private-dns link vnet create -g $RG -n link-$sub -z privatelink.$sub.core.windows.net -v $VNET -e false
  az network private-endpoint dns-zone-group create -g $RG --endpoint-name pe-$sub -n zg-$sub \
    --private-dns-zone privatelink.$sub.core.windows.net --zone-name $sub
done
```

Then disable public access on the account (`az storage account update --public-network-access
Disabled`) — and, since no key is used anywhere, disable shared-key access too
(`--allow-shared-key-access false`), which is what the Azure policy "Storage accounts should
prevent shared key access" enforces. Nothing in the values file changes: the account name
resolves to the private IP from inside the network and to the public IP from outside, and the
public endpoint refuses everyone.

With only the `dfs` private endpoint in place, the cluster works and the console does not: its
startup check fails on the `blob` host with `403 AuthorizationFailure`, and the log line's `note`
field says that the blob sub-resource is missing. Add the second endpoint and restart the pod.

**Entra ID stays reachable.** Private endpoints cover the storage account; the token exchange
still goes to `login.microsoftonline.com` over the public internet. An egress firewall must allow
that host (the `AzureActiveDirectory` service tag in a network security group), or every pod fails
at its first token request.

**Download links stay inside the network.** When a support bundle is handed to a vendor, the
console issues a time-limited download link to the account's blob endpoint. On an account that
admits only private endpoints that link works from inside your network and nowhere else — a
browser outside it gets `403 AuthorizationFailure`. Download the bundle through the console
instead and pass the file on.

## Other credentials

Workload identity is the recommended identity on AKS, and the only one with no secret to keep.
The alternatives, for the console and the cluster alike:

| Credential | Cluster (`fe.conf`) | Console (`anywhere.dependencies.adls2`) | When |
|---|---|---|---|
| Account key | `azure_adls2_shared_key` | `sharedKey` | a proof of concept, or an account whose policy allows shared-key access |
| SAS | `azure_adls2_sas_token` | `sasToken` — an account or container SAS with read, write, delete, list and create permissions | the same, with an expiry; the console then cannot issue download links of its own and offers the download through itself |
| Managed identity | `azure_adls2_oauth2_use_managed_identity = true` + tenant id + client id | `oauth2UseManagedIdentity: true` + `oauth2TenantId` + `oauth2ClientId` | self-managed Kubernetes on Azure virtual machines, where the identity is attached to the nodes. On AKS prefer workload identity: the node identity is shared by every pod on the node |
| Service principal | `azure_adls2_oauth2_client_id` + `_client_secret` + `_client_endpoint` | `oauth2ClientId` + `oauth2ClientSecret` + `oauth2ClientEndpoint` | outside Azure, or a policy that mandates an app registration; the secret expires and rotation is a `helm upgrade` |

Exactly one credential is configured on each side; the console refuses to start on a block that
carries two.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Console log: `oauth2TokenFile … cannot be read (no such file or directory); with AKS workload identity the pod needs the label azure.workload.identity/use` | The pod has no `azure.workload.identity/use: "true"` label, so AKS mounted no token. Set `anywhere.podLabels` (or `podLabels` on the FE / CN spec for the cluster) and let the pod restart |
| `AADSTS700213: No matching federated identity record found for presented assertion subject 'system:serviceaccount:<ns>:<sa>'` | The identity has no federated credential for that service account. Create one with exactly the subject in the message |
| Console log: `workload-identity authentication (oauth2TokenFile) also needs oauth2ClientId and oauth2TenantId` | The values file names the token file but not the identity. Both ids come from the values, never from the service account annotation |
| `AuthorizationPermissionMismatch` on the console's startup check, while the cluster works | The role is on the container, not the account, or was assigned less than a few minutes ago. Grant **Storage Blob Data Contributor** on the storage account and wait |
| Console: `403 AuthorizationFailure` on `PUT https://<account>.blob…` with a `note` about the blob sub-resource | Public access is disabled and the account has a private endpoint for `dfs` only. Add the `blob` one with its DNS zone |
| The cluster creates tables but every query on a warehouse's compute nodes fails on storage | The warehouse's CN pods run as the default service account without the label. Set `spec.serviceAccount` and `spec.podLabels` on the warehouse chart |
| Everything works for an hour, then fails | The projected token has a one-hour lifetime and Kubernetes rotates it in place, so a component must re-read the file at every token exchange rather than keep its first content. The console does; the cluster needs PhoenixAI Database 4.1.6-ee or later — check the image tags |
