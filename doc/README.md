# Documentation

Guides for deploying and operating PhoenixAI on Kubernetes, grouped by topic. They are part of the
[PhoenixAI Anywhere documentation](https://docs.phoenixdata.ai/Anywhere/), which also publishes
the PhoenixAI Database documentation. The directories here use the same section names as the site,
so a page sits in the section it appears in there.

Pages marked *(site)* are published on the documentation site only.

## Get started

- [Quick start with Amazon S3](https://docs.phoenixdata.ai/Anywhere/quick_start/quickstart_s3/) *(site)*
- [Quick start with MinIO](https://docs.phoenixdata.ai/Anywhere/quick_start/quickstart_minio/) *(site)*

## Deploy

- [Prerequisites](https://docs.phoenixdata.ai/Anywhere/deployment/prerequisites/) *(site)* — what
  to have in hand, and the checks to run first.
- [Least privilege to deploy](./deployment/least_permission_to_deploy_phoenixai_howto.md)
- [Install with Helm](./deployment/install_with_helm.md) — the complete
  step-by-step install, assuming no prior Kubernetes or Helm experience. Start here.
- [Install with kubectl](./deployment/install_with_kubectl.md)
- [Migrate from the StarRocks operator](./deployment/migrate-from-starrocks-howto.md)
- [Console data volume](https://docs.phoenixdata.ai/Anywhere/deployment/console_data_volume/) *(site)*
- [Use MinIO for shared data](https://docs.phoenixdata.ai/Anywhere/deployment/use_minio_for_shared_data_howto/) *(site)*
- [Multiple availability zones](./deployment/deploy_multi_az_howto.md)
- [Multiple clusters](./deployment/deploy_multiple_clusters_howto.md)
- [License a cluster](https://docs.phoenixdata.ai/Anywhere/deployment/license_cluster/) *(site)*
- [Upgrade the operator](./deployment/upgrade_operator_howto.md)
- [Deploy on Azure](./deployment/deploy_on_azure_howto.md) — AKS, ADLS Gen2 and workload identity:
  no account key anywhere, on a storage account that admits only private endpoints.

## Console

- [Overview](https://docs.phoenixdata.ai/Anywhere/console/overview/) *(site)*
- [Anywhere Console pages](https://docs.phoenixdata.ai/Anywhere/console/anywhere_console/) *(site)*
- [Cluster Console pages](https://docs.phoenixdata.ai/Anywhere/console/cluster_console/) *(site)*
- [MCP Server](./console/mcp_server.md) — connect an AI client to the consoles: enabling, sign-in,
  what the AI can do, and the security review checklist.

## Security

- [Init Root Password When First Deploy](./security/initialize_root_password_howto.md)
- [Change Root Password](./security/change_root_password_howto.md)
- [Connect the Operator to an SSL-Enabled FE](./security/connect_to_ssl_enabled_fe_howto.md)
- [Transparent Data Encryption](https://docs.phoenixdata.ai/Anywhere/security/tde/) *(site)*
- [Run With a Read-Only Root Filesystem](./security/setup-phoenixai-when-readOnlyRootFilesystem-is-true.md)
- [Restrict access to the operator API](./security/restrict_operator_api_access_howto.md) — a
  NetworkPolicy that lets only the Anywhere console reach the operator's gRPC query API.

## Warehouses and scaling

- [Warehouses](./cluster_management/warehouse/deploy_warehouse_howto.md)
- [CN Groups](./cluster_management/warehouse/deploy_cn_group_howto.md)
- [Manually scale CN groups](https://docs.phoenixdata.ai/Anywhere/cluster_management/warehouse/manually_scale_cn_groups_howto/) *(site)*
- [HPA Automatic Scaling For CN Nodes](./cluster_management/hpa_dynamic_scaling_with_helm_howto.md)
- [Queue-Based Autoscaling For CN Nodes](./cluster_management/queue_based_autoscaling_howto.md)
- [Scheduled Scaling For CN Nodes With KEDA](./cluster_management/scheduled_scaling_with_keda_howto.md) — run
  more CN nodes during business hours and fewer at night, with an introduction to KEDA.
- [Scale In FE Nodes](./cluster_management/scale_in_fe_nodes_howto.md)

## Administration

Configuration:

- [Mount Persistent Volume](./administration/configuration/mount_persistent_volume_howto.md)
- [Mount CSI Ephemeral Volumes](./administration/configuration/mount_csi_volumes_howto.md)
- [Mount External ConfigMaps Or Secrets](./administration/configuration/mount_external_configmaps_or_secrets_howto.md)

Management:

- [Deploy the FE Proxy](./administration/management/fe_proxy.md)
- [Logging and Related Configurations](./administration/management/logging_and_related_configurations_howto.md)
- [Expand Persistent Volume (FE/CN)](./administration/management/expand_persistent_volume_howto.md)
- [Kubernetes Node Maintenance and PodDisruptionBudget](./administration/management/node_maintenance_and_pdb_howto.md)
- [Cluster Snapshot & Restore](./administration/management/cluster_snapshot_and_restore.md)
- [Upgrade and Downgrade a Cluster](./administration/management/upgrade_and_downgrade_cluster_howto.md)

Monitoring:

- [Deploy Prometheus and Grafana](./administration/management/monitoring/deploy-prometheus-grafana.md)
- [Prometheus And Grafana](./administration/management/monitoring/integration-prometheus-grafana.md)
- [Anywhere Console monitoring](https://docs.phoenixdata.ai/Anywhere/administration/management/monitoring/anywhere-monitoring/) *(site)*
- [Query insights](./administration/management/monitoring/anywhere-query-insights.md)
- [Datadog](./administration/management/monitoring/integration-with-datadog.md)

Troubleshooting *(site)*:

- [Health checks](https://docs.phoenixdata.ai/Anywhere/administration/management/troubleshooting/health_checks/)
- [Inspect cluster state](https://docs.phoenixdata.ai/Anywhere/administration/management/troubleshooting/inspect_cluster_state/)
- [Generating a support bundle](https://docs.phoenixdata.ai/Anywhere/administration/management/troubleshooting/generate_support_bundle/)
- [Reading a support bundle](https://docs.phoenixdata.ai/Anywhere/administration/management/troubleshooting/read_support_bundle/)

## Reference

- [API Reference](./api.md) — every field of the `PhoenixAICluster` and
  `PhoenixAIWarehouse` CRDs.

## Also in this folder

- [`deprecated/`](./deprecated) — documents resources that are no longer shipped.
