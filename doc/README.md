# Documentation

Guides for deploying and operating PhoenixAI on Kubernetes, grouped by topic.
These are the same guides that make up the PhoenixAI Anywhere documentation
site.

## Get started

- [Quick start with Amazon S3](./GetStarted/quickstart_s3.md)
- [Quick start with MinIO](./GetStarted/quickstart_minio.md)
- [Console tour](./GetStarted/anywhere_console_ui_guide.md)

## Deploy

- [Prerequisites](./Deploy/prerequisites.md) — what to have in hand, and the checks to run first.
- [Least privilege to deploy](./Deploy/least_permission_to_deploy_phoenixai_howto.md)
- [Install with Helm](./Deploy/install_with_helm.md) — the complete
  step-by-step install, assuming no prior Kubernetes or Helm experience. Start here.
- [Install with kubectl](./Deploy/install_with_kubectl.md)
- [Migrate from the StarRocks operator](./Deploy/migrate-from-starrocks-howto.md)
- [Console data volume](./Deploy/console_data_volume.md)
- [Warehouses](./Deploy/deploy_warehouse_howto.md)
- [Multiple clusters](./Deploy/deploy_multiple_clusters_howto.md)
- [License a cluster](./Deploy/license_cluster_howto.md)
- [Upgrade the operator](./Deploy/upgrade_operator_howto.md)

## Configure

- [Change Root Password](./Configure/change_root_password_howto.md)
- [Init Root Password When First Deploy](./Configure/initialize_root_password_howto.md)
- [Connect the Operator to an SSL-Enabled FE](./Configure/connect_to_ssl_enabled_fe_howto.md)
- [Mount Persistent Volume](./Configure/mount_persistent_volume_howto.md)
- [Mount CSI Ephemeral Volumes](./Configure/mount_csi_volumes_howto.md)
- [Mount External ConfigMaps Or Secrets](./Configure/mount_external_configmaps_or_secrets_howto.md)
- [Run With a Read-Only Root Filesystem](./Configure/setup-phoenixai-when-readOnlyRootFilesystem-is-true.md)
- [Use MinIO for Shared Data](./Configure/use_minio_for_shared_data_howto.md)

## Scale

- [HPA Automatic Scaling For CN Nodes](./Scale/hpa_dynamic_scaling_with_helm_howto.md)
- [Scale In FE Nodes](./Scale/scale_in_fe_nodes_howto.md)

## Operate

- [Deploy the FE Proxy](./Operate/fe_proxy.md)
- [Logging and Related Configurations](./Operate/logging_and_related_configurations_howto.md)
- [Expand Persistent Volume (FE/CN)](./Operate/expand_persistent_volume_howto.md)
- [Kubernetes Node Maintenance and PodDisruptionBudget](./Operate/node_maintenance_and_pdb_howto.md)
- [Cluster Snapshot & Restore](./Operate/cluster_snapshot_and_restore.md)

## Monitor

- [Deploy Prometheus and Grafana](./Monitor/deploy-prometheus-grafana.md)
- [Prometheus And Grafana](./Monitor/integration-prometheus-grafana.md)
- [Anywhere Console monitoring](./Monitor/anywhere-monitoring.md)
- [Datadog](./Monitor/integration-with-datadog.md)

## Troubleshoot

- [Health checks](./Troubleshoot/health_checks.md)
- [Inspect cluster state](./Troubleshoot/inspect_cluster_state.md)
- [Generating a support bundle](./Troubleshoot/generate_support_bundle.md)
- [Reading a support bundle](./Troubleshoot/read_support_bundle.md)

## Reference

- [API Reference](./api.md) — every field of the `PhoenixAICluster` and
  `PhoenixAIWarehouse` CRDs.

## Also in this folder

- [`deprecated/`](./deprecated) — documents resources that are no longer shipped.
