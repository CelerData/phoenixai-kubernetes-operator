---
title: Transparent Data Encryption
sidebar_label: Transparent Data Encryption
description: Encrypt a cluster's data at rest with a master key held in HashiCorp Vault or AWS KMS, configured when the cluster is created.
sidebar_position: 4
---

# Transparent Data Encryption

Transparent Data Encryption (TDE) encrypts data at the engine layer as it is written to storage, so
a copy of the files is worthless without the key. The master key stays in your key service: the
cluster encrypts each file with a key of its own and keeps those keys wrapped under the master key.

:::note This protects data at rest, not data in transit
A client's connection to the cluster is a separate concern, covered by
[Connect the operator to an SSL-enabled FE](./connect_to_ssl_enabled_fe_howto.md).
Encrypting one does nothing for the other, and a requirement that names encryption usually means
both.
:::

## Before you start

**TDE is decided when the cluster is created.** You cannot enable it on a cluster that already
exists, and you cannot change the master key afterwards. It belongs with the other
[decisions you cannot undo](../Deploy/install_with_helm.md#decisions-you-cannot-undo).

**It applies to shared-data clusters**, which is what Anywhere runs, so there is nothing to check.

**Choose a key service before you write the values file.** Two are supported, and which one fits
depends on what your network can reach:

| | Where it runs | Reaches |
| --- | --- | --- |
| **HashiCorp Vault** | Wherever you run it, including inside your own network | Works with no outbound connectivity |
| **AWS KMS** | Amazon's service | Needs a route to AWS |

On a restricted or air-gapped network, Vault is the option that works: AWS KMS cannot be reached at
all without outbound access.

**Keep the key service available for the life of the cluster.** Coordinators and compute nodes
read the master key again after every restart. A key service they cannot reach, or a key that is
gone, keeps the coordinators from starting and the compute nodes from reading or writing data.

## Store the master key in Vault

Skip this section if you use AWS KMS.

The cluster reads the key over Vault's HTTP API from a **KV version 2** secrets engine, in a field
named **`plain_key`**. The value is a formatted string, not a bare key:

```text
aes_128:<Base64 encoding of the 128 bit key>
```

For example, with a KV v2 engine mounted at `secret/`:

```bash
vault kv put secret/phoenixai/tde-master plain_key="aes_128:$(openssl rand -base64 16)"
```

Give the cluster a token that can only read that path. It has to be valid whenever a coordinator or
compute node starts, because the key is read again on every start, including the first start after
an outage. A periodic token stays valid only as long as something renews it within its period, so
keep the renewal running independently of the database cluster, for example Vault Agent or a
scheduled `vault token renew`, and choose a period longer than the longest outage you plan for. The
read-only policy:

```hcl
path "secret/data/phoenixai/tde-master" {
  capabilities = ["read"]
}
```

## Prepare the AWS KMS key

Skip this section if you use Vault.

Refer to the key by its **ARN**. The value is handed to KMS as the key ID, so a key ID or an alias
also resolves, but an alias can later be pointed at another key, and the cluster's data keys only
decrypt under the key that wrapped them.

The coordinators call `kms:GenerateDataKey` and the compute nodes call `kms:Decrypt` on the key.
Grant both to the identity the cluster uses, on that key only:

```json
{
  "Effect": "Allow",
  "Action": ["kms:GenerateDataKey", "kms:Decrypt"],
  "Resource": "<key-ARN>"
}
```

## What goes where

On Anywhere these are coordinator and compute-node configuration, so they go in the `config:` block
of your values file, the same block that carries `run_mode`. Two rules decide which setting goes
where:

- **Non-secret settings go in `config:`.** That block becomes a ConfigMap.
- **Secrets do not.** A ConfigMap is readable by anyone who can read the namespace, and a token set
  as `vault_token` is also echoed back by `ADMIN SHOW FRONTEND CONFIG` and served by each compute
  node's unauthenticated `/varz` page. Pass the Vault token as the `VAULT_TOKEN` environment
  variable, and AWS credentials as `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`, from a Kubernetes
  Secret; both the coordinators and the compute nodes read them there. Never put the token in the
  `default_master_key` value either: that string is stored in the cluster's metadata and cannot be
  changed.

### Create the Secret

```bash
# Vault
kubectl -n phoenixai create secret generic phoenixai-tde \
  --from-literal=vault-token='<vault-token>'

# or AWS KMS, if you authenticate with a key pair rather than an instance profile
kubectl -n phoenixai create secret generic phoenixai-tde \
  --from-literal=aws-access-key-id='<access-key>' \
  --from-literal=aws-secret-access-key='<secret-key>'
```

### Where the blocks go

`phoenixAIFeSpec` and `phoenixAICnSpec` sit directly under `phoenixai:`, next to
`phoenixAICluster`, not inside it. A block nested under `phoenixAICluster` is not an error: the chart
never reads it, and the cluster comes up unencrypted for good.

:::caution Add the TDE lines to your shared-data `config:`, not to the chart's default
A `config:` you set takes the place of the component's whole default configuration, and the chart's
default carries no `run_mode` or storage settings. Add the TDE lines to the `config:` blocks from
[Step 3 of the Helm install](../Deploy/install_with_helm.md#step-3--set-the-root-password-and-write-your-values-file):
the coordinator block with `run_mode = shared_data` and the `aws_s3_*` lines, and the compute-node
block with its data cache settings. Without `run_mode = shared_data` the cluster is created as a
classic cluster, which TDE does not apply to and which cannot be converted later.
:::

### Coordinators

```yaml
phoenixai:
  phoenixAIFeSpec:
    config: |
      # ... the rest of your fe configuration ...

      # Vault: the KV v2 API path of the secret, /v1/ and /data/ included
      vault_addr = <vault-address>
      default_master_key = vault:/v1/<kv-mount>/data/<secret-path>

      # or AWS KMS: the key's ARN, and the region it lives in
      # default_master_key = kms:<key-ARN>
      # aws_kms_region = <region>
    feEnvVars:
      - name: VAULT_TOKEN
        valueFrom:
          secretKeyRef:
            name: phoenixai-tde
            key: vault-token
```

`default_master_key` takes the secret's **HTTP API path**, not the path you give `vault kv`: for the
secret written above it is `vault:/v1/secret/data/phoenixai/tde-master`. The cluster requests
`vault_addr` followed by that path, so `vault_addr` must not end with a slash.

### Compute nodes

The flag that turns encryption on lives here, not on the coordinators, and so does a second copy of
the key service's location: `vault_addr` with Vault, `aws_kms_region` with AWS KMS.
`phoenixAICnSpec` goes next to `phoenixAIFeSpec`, under the one `phoenixai:` key; a second
`phoenixai:` key in the same file replaces the first and drops the coordinator settings:

```yaml
phoenixai:
  phoenixAIFeSpec:
    # ... the coordinator block above ...
  phoenixAICnSpec:
    config: |
      # ... the rest of your cn configuration ...
      enable_transparent_data_encryption = true
      # Vault: compute nodes fetch the master key themselves, so they need the address too
      vault_addr = <vault-address>

      # or AWS KMS: compute nodes call KMS themselves, so they need the region too
      # aws_kms_region = <region>
    cnEnvVars:
      - name: VAULT_TOKEN
        valueFrom:
          secretKeyRef:
            name: phoenixai-tde
            key: vault-token
```

:::caution Set `vault_addr` or `aws_kms_region` on the compute nodes as well
Each compute node unwraps keys itself, at the location in its own configuration:

- **Vault:** the coordinators store only the secret's path, and each compute node joins it to its
  own `vault_addr`. Without it, the compute node fails on the first write after the cluster is
  created.
- **AWS KMS:** the region is not taken from the key's ARN. A compute node without `aws_kms_region`
  asks KMS in the SDK's default region, and every write fails with
  `kms:Decrypt ... the resource does not exist in this Region`.
:::

With AWS KMS, pass the key pair as `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` in place of
`VAULT_TOKEN`, on both the coordinators and the compute nodes, from the Secret created above:

```yaml
    cnEnvVars:            # and the same two entries under feEnvVars
      - name: AWS_ACCESS_KEY_ID
        valueFrom:
          secretKeyRef:
            name: phoenixai-tde
            key: aws-access-key-id
      - name: AWS_SECRET_ACCESS_KEY
        valueFrom:
          secretKeyRef:
            name: phoenixai-tde
            key: aws-secret-access-key
```

With these unset, both components use the AWS SDK's default credential chain, so an instance
profile needs neither.

### Check the values before installing

Because TDE cannot be turned on later, render the chart first and count each setting in the
output. Commented-out lines are dropped first, so an alternative you left as a comment is not
counted as set. With Vault:

```bash
helm template <release> phoenixai/kube-anywhere -f your-values.yaml \
  | grep -v '^[[:space:]]*#' > rendered.yaml
for s in 'run_mode = shared_data' 'default_master_key = vault:' enable_transparent_data_encryption \
         vault_addr VAULT_TOKEN; do
  printf '%-36s %s\n' "$s" "$(grep -c "$s" rendered.yaml)"
done
```

Expect the first three once each, and `vault_addr` and `VAULT_TOKEN` twice each: once for the
coordinators and once for the compute nodes.

With AWS KMS, render the same way and use this list instead:

```bash
for s in 'run_mode = shared_data' 'default_master_key = kms:' enable_transparent_data_encryption \
         aws_kms_region AWS_ACCESS_KEY_ID; do
  printf '%-36s %s\n' "$s" "$(grep -c "$s" rendered.yaml)"
done
```

Expect the first three once each, `aws_kms_region` twice (coordinators and compute nodes), and
`AWS_ACCESS_KEY_ID` twice with a key pair, not at all with an instance profile.

A count of 0 where you expect a setting means its block is in the wrong place.

## The settings

**Coordinators (`phoenixAIFeSpec.config`)**

| Setting | For | What it is |
| --- | --- | --- |
| `default_master_key` | both | `vault:/v1/<kv-mount>/data/<secret-path>`, or `kms:<key-ARN>` |
| `vault_addr` | Vault | The Vault server address, with no trailing slash |
| `vault_token` | Vault | Leave unset: pass the token as `VAULT_TOKEN` instead |
| `aws_kms_region` | AWS KMS | The region the key lives in |
| `aws_kms_access_key`, `aws_kms_secret_key` | AWS KMS | Leave unset: pass the key pair as `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` instead. Unnecessary with an instance profile |
| `aws_kms_iam_role_arn`, `aws_kms_external_id` | AWS KMS | For assumed-role access |

**Compute nodes (`phoenixAICnSpec.config`)**

| Setting | For | What it is |
| --- | --- | --- |
| `enable_transparent_data_encryption` | both | `true` turns encryption on |
| `vault_addr` | Vault | The Vault server address, the same value as on the coordinators |
| `aws_kms_region` | AWS KMS | The region the key lives in, the same value as on the coordinators |

Credentials are not set here either: the compute nodes read the same environment variables as the
coordinators.

## Check it is working

These metrics are exported by the compute nodes, not the coordinators, once encryption is active:

| Metric | Reports |
| --- | --- |
| `starrocks_be_encryption_keys_created` | File encryption keys created |
| `starrocks_be_encryption_keys_unwrapped` | Decryption operations |
| `starrocks_be_encryption_keys_in_cache` | Keys currently held in the key cache |
| `encryption_bytes` | Bytes encrypted |
| `decryption_bytes` | Bytes decrypted |

`starrocks_be_encryption_keys_created` rising as you load data is the signal that files are being
encrypted. The coordinators report `starrocks_fe_encryption_key_num`, the number of keys in the key
hierarchy: 2 right after the cluster is created, the master key and the first key-encryption key.
See [Anywhere Console monitoring](../Monitor/anywhere-monitoring.md) for reading metrics.

## Limitations

- **Shared-data clusters only.** That is what Anywhere runs, so this is not a restriction here.
- **Cannot be enabled on an existing cluster**, and **the master key cannot be changed** once set.
  Removing or changing `default_master_key` later keeps the coordinators from starting. The
  key-encryption keys under the master key are rotated automatically (`key_rotation_days`, default
  7); only the master key itself is fixed.
- **Expect a performance cost of under 10%.**
