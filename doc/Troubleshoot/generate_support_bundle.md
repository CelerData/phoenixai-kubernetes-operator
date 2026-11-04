---
title: Generating a support bundle
sidebar_label: Generating a bundle
sidebar_position: 3
description: What a support bundle collects, how to scope one, and what is and is not masked before you send it on.
---

# Generating a support bundle

A support bundle collects logs, configuration and diagnostics from one cluster into a single archive
you can hand to support. Collection is read-only, and one bundle is collected at a time.

## Estimate before you collect

A bundle can run to gigabytes. The estimate runs the same file selection the collector does, so the
size it reports is the size you will get. The duration is a lower bound; collection can take longer.
Estimate before committing to a wide time window.

## Start from a scenario

A scenario is a preset for a symptom. It selects the artifacts support usually asks for, so you do
not have to choose them one by one.

For example:

- **Compute node crash** gathers what it takes to triage a crash or a restart loop — output from
  the run before the crash, and the query that was in flight.
- **Query trace** follows a single query ID across the coordinator logs, and needs you to supply
  the ID.

Others exist, and the set grows over time. The console carries the current list with a description
of each; start there rather than from this page.

A scenario pre-selects a subset. It does not restrict what you can add, and everything it selects
can be changed.

## Reuse a selection with a bundle profile

A bundle profile is a selection saved to a file: the artifacts, the pods, the time window and the
search values. It carries no cluster name and no collection logic, so it is a way to hand someone
an exact selection instead of describing one. The usual sender is support. Bundle profiles are
available from v2.1.

**Bundle profile** sits at the top right of the Create support bundle page.

- **Save to file** writes the current selection, with an optional note shown to whoever opens it.
  A half-finished selection will not save: a category ticked in one part and left empty in another
  is named so you can finish or clear it, because collection would otherwise drop it without
  saying so.
- **Load from file** always opens a review step before anything changes. The review reports what
  the file asks for that this cluster does not have — a pod that is gone, a value not offered here
  — and names what needs a decision; a missing pod can be replaced with one of the same kind, or
  ignored. Applying replaces the whole selection, and collection still waits for **Create bundle**.

A profile holds a selection and nothing else, so loading one cannot collect anything the page could
not already collect.

A file is refused outright, before any review, when it is not a bundle profile at all or was saved
by a console too different from yours to read it. The message says which it is; where the answer is
the version, ask whoever sent it to save it again on yours.

## What gets collected

A bundle can include, among other things:

- **Cluster definition and configuration files** — how the cluster and its warehouses are set up
- **Log files and log search** — everything in the window, or only the lines matching a search
- **Diagnostic queries** — read-only queries describing cluster state, such as nodes and running jobs
- **Thread dumps and thread stacks** — what coordinators and compute nodes were doing at the moment
  of collection
- **Query audit analysis** — failed statements, and the heaviest queries in the window
- **Crash context and memory diagnostics** — evidence for one specific class of failure
- **Metrics snapshot** — the monitoring window, so support sees the same charts you do. It comes
  back empty if no Prometheus is wired to Anywhere, and nothing in the bundle says so — check
  the console's monitoring pages before collecting a bundle for anything performance-related

<!-- DOC NOTE: this list is an API contract, not a description of the console -- it comes from
     bundleCategories in the backend, served through bundle-options. Keep it in sync when an
     artifact is added or removed there.

     Two things to know if you extend it. The backend has no grouping or type field:
     BundleCategoryInfo is {Name, DisplayName, Description} and the list is flat, so any grouping
     is ours to maintain. And the API's list is not the console's -- the console shows logs and
     log-search as a single row where the API has two entries. Follow the API. -->

## Getting the archive

There are two ways to retrieve a finished bundle.

- **Download** — the archive comes back through your existing session. Use it when you want to look
  at the bundle yourself, or send it to support manually.
- **Export link** — a pre-signed URL with an expiry. Anyone holding the link can download the
  bundle, so treat it as a credential. Useful for sharing within your own network, or with support
  where outbound transfer is permitted by your policy.

Bundles are removed after 7 days.

## What is masked, and what is not

Credential values in manifests, in configuration files and in the coordinator configuration
listing (`commands/show-frontend-config.txt`) are masked irreversibly.

Every other command output under `commands/` is collected exactly as the cluster printed it. What
a statement prints is the cluster's decision: `DESC STORAGE VOLUME`, `SHOW CREATE CATALOG` and
`SHOW ROUTINE LOAD` mask their own secrets, and a custom command you saved yourself is never
rewritten.

> **Audit logs contain user SQL verbatim and are deliberately not masked.** Review a bundle before
> sending it outside your organisation.

Every bundle contains a `safety-report.txt` listing what ran and what the masking covered. It is
generated from the artifacts that executed, so it describes that bundle rather than the product in
general — see [Reading a support bundle](./read_support_bundle.md).
