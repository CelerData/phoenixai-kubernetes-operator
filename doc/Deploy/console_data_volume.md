---
sidebar_label: Console data volume
sidebar_position: 6
title: The console data volume
description: What the Anywhere console keeps on its own persistent volume, why it outlives an uninstall, and how to size it.
---

# The console data volume

The Anywhere console keeps its own state on a persistent volume of its own, separate from any
cluster it manages and from the disks those clusters run on.
Backup and restore, in the PhoenixAI Database documentation, covers the data in a PhoenixAI
cluster. It does not cover this volume.

## What is on it

| Holds | Why it matters |
|---|---|
| Usage ledger | Append-only, tamper-evident record of metered usage. The basis of billing |
| Saved SQL scripts | What people wrote in the Cluster Console's SQL editor, with the folders they arranged them in, kept per database user per cluster |
| Query history | One row per collected query, subject to the retention window |
| Saved commands and presets | Catalogue entries created in this deployment |
| Session snapshot | Written only during a graceful restart |

Two of these cannot be reconstructed from anywhere else: the usage ledger, and the saved SQL
scripts.
The ledger can be exported as a file and kept independently of the volume — see the Usage page in
the Anywhere Console. Scripts have no equivalent export, so a snapshot of the volume is the only
way to carry them across a replacement.

Query history ages out on its own. Scripts, saved commands and exec presets are never aged out or
trimmed: they stay until someone deletes them, and would have to be written again if the volume
were lost.

## It survives an uninstall

The volume is retained deliberately, so removing the release discards neither billing history nor
the SQL scripts people have saved.

Its name comes from the **chart**, not from your release name: `data-<anywhere.nameOverride>-0`,
which is `data-kube-anywhere-console-0` unless you override `anywhere.nameOverride`. Reinstalling
into the same namespace therefore reclaims it whatever you call the release. Setting
`persistence.existingClaim` points Anywhere at a volume you name yourself instead.

:::caution Reinstalling under a *different* release name needs `--take-ownership`
The claim is declared by the chart, so it carries Helm's ownership annotations from the release that
created it. Installing a release with a new name into a namespace that already holds the claim is
rejected before anything is applied:

```text
Error: unable to continue with install: PersistentVolumeClaim "data-kube-anywhere-console-0"
in namespace "phoenixai" exists and cannot be imported into the current release:
invalid ownership metadata; annotation validation error:
key "meta.helm.sh/release-name" must equal "kube-anywhere": current value is "phoenixai"
```

An installation made under an earlier release name — `phoenixai`, say — hits this the first time it
is reinstalled under the release name the current documentation uses, `kube-anywhere`. Hand the
existing claim to the new release:

```bash
helm upgrade --install kube-anywhere phoenixai/kube-anywhere \
  --namespace phoenixai -f my-values.yaml --take-ownership
```

Keeping the old release name works just as well, and changes nothing about the object names.
:::

## Sizing

The chart asks for 10Gi by default. Where the StorageClass allows expansion the volume can be
grown in place later; it cannot be shrunk.

Query history is what grows with workload. How many records are retained depends on the workload
and on the slow-query threshold in force.

Two things trim it: the retention period, and a watermark that prunes the oldest records when the
volume runs low on space. Both act on query history alone — neither touches the usage ledger or
saved SQL scripts, which are never removed automatically.

Capturing every query on a cluster serving 100 queries per second produces millions of rows here,
and hundreds of gigabytes of query text per day in the object store. At the default threshold only
slow and failed queries are kept, which is a small fraction of that. The threshold and the
retention period are the two controls, and they govern both.

Saved SQL scripts grow with the number of people instead, and nothing reclaims them: no retention
window, no watermark. The ceiling is small and countable — at most 50 scripts of 500,000 bytes for
each database user on each cluster, so roughly 25 MB per user per cluster at the absolute limit,
and far less in practice — but it only ever rises. Size for the people who will use the editor as
well as for the queries they run.

<!-- DOC NOTE: these figures are the current estimate, taken from the query-history feature notes
     rather than measured on a running deployment. Good enough to size against; worth revisiting
     once there is a real workload to check them with. -->
