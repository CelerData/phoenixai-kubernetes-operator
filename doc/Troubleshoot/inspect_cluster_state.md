---
title: Inspect cluster state
sidebar_label: Inspect cluster state
sidebar_position: 2
description: Read-only SQL checks for nodes, jobs and configuration, and the shell diagnostics that are disabled by default.
---

# Inspect cluster state

There are two ways to see what a cluster is doing: read-only SQL run against the database, and
shell diagnostics run inside a pod. SQL is always available. Shell diagnostics are disabled by
default.

## Built-in SQL checks

A fixed catalogue of read-only statements ships with the product. Sixteen at present:

### Nodes and sessions

| Command | Answers |
|---|---|
| `show-frontends` | Coordinator nodes, their roles and liveness |
| `show-compute-nodes` | Compute nodes, their warehouse and liveness |
| `show-warehouses` | Warehouses on a shared-data cluster |
| `show-processlist` | Active client sessions |
| `show-running-queries` | Queries running right now |

### Jobs and profiles

| Command | Answers |
|---|---|
| `show-loads` | The most recent 100 load jobs |
| `show-routine-load` | Routine load jobs |
| `show-profilelist` | Recent query profiles |
| `show-proc-statistic` | Per-database tablet and replica health |

### Configuration and variables

| Command | Answers |
|---|---|
| `show-frontend-config` | Coordinator configuration items |
| `show-variables` | Session variables |
| `show-variables-changed` | Only the session variables that differ from their defaults |
| `show-time-zone` | The cluster's `time_zone` and `system_time_zone` |
| `show-resource-groups` | Resource groups |

### Catalogs

| Command | Answers |
|---|---|
| `show-databases` | Databases in the default catalog |
| `show-catalogs` | Internal and external catalogs |

Use `show-variables-changed` rather than `show-variables` when diagnosing. A full listing runs to
thousands of rows.

<!-- DOC NOTE: this catalogue is a code constant, BuiltinCommands in the backend, served through
     the commands endpoint. It is an API contract, so this page can be definitive about it -- keep
     it in sync when a command is added or removed there.

     Do not add a column for the statement each command runs. The API already returns it per
     command, as the `sql` field, and the console shows it. A copy here would duplicate that and
     would probably be wrong: `show-loads` and `show-routine-load` do not run `SHOW LOADS` and
     `SHOW ROUTINE LOAD`. Catalogue commands run with no database selected, where those two fail,
     so both read `information_schema` instead. -->

A request names a saved command rather than carrying a statement, so only catalogue entries run.

## Adding your own checks

Custom commands are validated when they are saved, not when they run. A statement must:

- begin with `SELECT` or `SHOW`
- be a single statement
- contain no comment markers
- not write to external storage

Only administrators can add, edit or remove catalogue entries, because entries run with elevated
credentials.

## Shell diagnostics

Disabled by default. When enabled, anyone who can reach Anywhere can run any command in any pod of
the cluster.

The setting is `enablePodExec`, in Anywhere's configuration file rather than in the Helm chart
values. Configuration is read once at startup, so changing it takes a restart to have any effect.

The built-in thread-dump preset works whether or not it is enabled, and is administrator-only.
