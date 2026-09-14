---
sidebar_label: Warehouses
sidebar_position: 7
---

# Deploy Warehouse

From PhoenixAI Operator v1.9.0, PhoenixAIWarehouse CRD is introduced to manage the warehouse. This document describes
how to deploy a warehouse.

## 1. Prerequisites

1. PhoenixAI Operator >= v1.9.0. The latest version of the operator is recommended.
2. An installed PhoenixAI Cluster.
   See [Install with kubectl](./install_with_kubectl.md)
   or [Install with Helm](./install_with_helm.md) for more details.
3. PhoenixAI enterprise version >= v3.2.0.
4. The `PhoenixAIWarehouse` CRD, present **before the operator started**. A fresh installation of
   the current charts satisfies this on its own: the operator chart ships the CRD next to the
   cluster one, and [Install with kubectl](./install_with_kubectl.md) applies both in step 1.1. No
   operator restart is needed there.

   :::caution An upgraded or older operator will not have it
   Operator charts only began shipping the warehouse CRD in v2.0.0, and **`helm upgrade` never
   installs a chart's `crds/` directory** — so an operator upgraded from an earlier version does not
   gain the CRD from the chart, whatever version it now runs. The same holds for an operator
   installed with `--skip-crds`, or from a manifest that applied only the cluster CRD.

   Check rather than assume:

   ```bash
   kubectl get crd phoenixaiwarehouses.phoenixdata.ai
   kubectl -n phoenixai logs deployment/kube-anywhere-operator | grep PhoenixAIWarehouse
   ```

   The operator decides whether to run the warehouse controller **once, at startup**. If it started
   without the CRD, warehouses are never reconciled and nothing reports it: `kubectl get paw` shows
   the object with an empty `STATUS`, there are no pods and no events, and the `grep` above returns
   nothing. Install the CRD, then restart the operator:

   ```bash
   kubectl apply -f https://raw.githubusercontent.com/celerdata/phoenixai-kubernetes-operator/main/deploy/phoenixdata.ai_phoenixaiwarehouses.yaml
   kubectl -n phoenixai rollout restart deployment kube-anywhere-operator
   ```

   The `grep` then reports `Starting Controller`.

   The warehouse chart does **not** carry the CRD — only the operator chart does, because that is
   the one installed early enough for the operator to see it. So a warehouse chart installed against
   an operator that lacks the CRD fails outright with `no matches for kind "PhoenixAIWarehouse"`,
   rather than appearing to succeed and then never producing pods.
   :::

## 2. Deploy Warehouse

You can choose one of the following methods to deploy a warehouse:

1. Deploy Warehouse by YAML Manifest
2. Deploy Warehouse by Helm Chart

> The CN nodes you deploy with a PhoenixAI cluster are added to the `default_warehouse` by default. You can
> also define a Warehouse CR named `default-warehouse` to add more CN nodes to that warehouse.

### 2.1 Deploy Warehouse by YAML Manifest

Deploy a warehouse by the following YAML manifest.

```yaml
# wh1.yaml
apiVersion: phoenixdata.ai/v1
kind: PhoenixAIWarehouse
metadata:
  # A warehouse will be created with this name in PhoenixAI Cluster. If you are using dash(-) in the name, the warehouse
  # name created by PhoenixAI will be replaced with underscore(_).
  name: wh1

spec:
  # Make sure the PhoenixAI cluster exists in the same namespace.
  # You can check it by running `kubectl -n phoenixai get phoenixaiclusters.phoenixdata.ai`.
  phoenixAICluster: kube-anywhere
  template:
    envVars:
      - name: TZ
        value: UTC
    image: us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/cn-ubuntu:<database-image-tag>
    replicas: 1
    limits:
      cpu: 8
      memory: 8Gi
    requests:
      cpu: 8
      memory: 8Gi
```

You can see [api.md](../api.md) for more details about the PhoenixAIWarehouse CRD fields. The spec part is very similar
to the PhoenixAICnSpec of PhoenixAICluster, so
see [deploy_a_phoenixai_cluster_with_cn.yaml](../../examples/phoenixai/deploy_a_phoenixai_cluster_with_cn.yaml) for more
fields.

Apply the YAML manifest:

```bash
kubectl -n phoenixai apply -f wh1.yaml
```

### 2.2. Deploy Warehouse by Helm Chart

We also support deploying a warehouse by Helm chart.
You can also see [Warehouse Chart](../../helm-charts/charts/warehouse/README.md) for how to deploy it.

First, prepare a values.yaml file for Warehouse chart.

```yaml
# wh1-values.yaml
spec:
  # Make sure the PhoenixAI cluster exists in the same namespace.
  # You can check it by running `kubectl -n phoenixai get phoenixaiclusters.phoenixdata.ai`.
  phoenixAIClusterName: kube-anywhere
  replicas: 1
  image:
    repository: us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/cn-ubuntu
    tag: "<database-image-tag>"
  resources:
    limits:
      cpu: 8
      memory: 8Gi
    requests:
      cpu: 8
      memory: 8Gi
```

Then deploy a warehouse by the following command:

```console
# Use the above values.yaml to deploy a warehouse in namespace phoenixai
helm -n phoenixai install wh1 phoenixai/warehouse -f wh1-values.yaml
```

### 2.3 Give the warehouse the cluster's root password

A warehouse's compute nodes register themselves in the cluster's coordinator over SQL as `root`. If
the cluster was installed with a root password, they need it, and **the warehouse chart does not
inherit the cluster chart's `initPassword` setting** — there is no warehouse value for it. Without
the password the compute node loops on:

```text
[...] Add myself (wh1-warehouse-cn-0...:9050) into FE ...
ERROR 1045 (28000): Access denied for user 'root' (using password: NO)
```

and the pod never becomes ready. Pass the password as an environment variable instead. Point it at
the same Secret the cluster used, so there is one copy of the password:

```yaml
# wh1-values.yaml
spec:
  # ... the rest of your warehouse values ...
  envVars:
    - name: MYSQL_PWD
      valueFrom:
        secretKeyRef:
          # The Secret named by phoenixai.initPassword.passwordSecret when the cluster
          # was installed.
          name: phoenixai-root-password
          key: password
```

Clusters whose `root` has no password need none of this — leave `envVars` unset.

If a warehouse is already stuck in this state, adding the block above and re-running
`helm upgrade` is enough; the compute node registers within seconds of restarting.

## 3. Manage Warehouse

### 3.1. Show the deployed warehouse

If you have deployed the above warehouse, you can see it by using the following SQL command:

```console
# A warehouse has been created with the name `wh1`.
mysql> show warehouses;
+-------+-------------------+-----------+-----------+---------------------+-----------------+-----------------+------------+-----------+-----------+---------------------+---------------------+----------------------------------------------+
| Id    | Name              | State     | NodeCount | CurrentClusterCount | MaxClusterCount | StartedClusters | RunningSql | QueuedSql | CreatedOn | ResumedOn           | UpdatedOn           | Comment                                      |
+-------+-------------------+-----------+-----------+---------------------+-----------------+-----------------+------------+-----------+-----------+---------------------+---------------------+----------------------------------------------+
| 0     | default_warehouse | AVAILABLE | 0         | 1                   | 1               | 1               | 0          | 0         | NULL      | 2024-05-11 16:49:37 | 2024-05-11 17:53:30 | An internal warehouse init after FE is ready |
| 35030 | wh1               | AVAILABLE | 1         | 1                   | 1               | 1               | 0          | 0         | NULL      | NULL                | NULL                | NULL                                         |
+-------+-------------------+-----------+-----------+---------------------+-----------------+-----------------+------------+-----------+-----------+---------------------+---------------------+----------------------------------------------+
2 rows in set (0.00 sec)
```

### 3.2 Upgrade Deployment

We strongly recommend you to upgrade deployment by modifying the YAML Manifest file or values.yaml file. For example,
you can update any fields in the file, e.g. the image version, replicas, and resources.

> We don't suggest you to modify the deployment of warehouse by `kubectl edit`.

#### 3.2.1 Update the YAML manifest

For example, upgrade the image version:

```yaml
apiVersion: phoenixdata.ai/v1
kind: PhoenixAIWarehouse
metadata:
  # A warehouse will be created with this name in PhoenixAI Cluster. If you are using dash(-) in the name, the warehouse
  # name created by PhoenixAI will be replaced with underscore(_).
  name: wh1

spec:
  # Make sure the PhoenixAI cluster exists in the same namespace.
  # You can check it by running `kubectl -n phoenixai get phoenixaiclusters.phoenixdata.ai`.
  phoenixAICluster: kube-anywhere
  template:
    envVars:
      - name: TZ
        value: UTC
    image: us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/cn-ubuntu:<new-database-image-tag>  # this line is updated
    replicas: 1
    limits:
      cpu: 8
      memory: 8Gi
    requests:
      cpu: 8
      memory: 8Gi
```

Apply the updated YAML manifest:

```console
kubectl -n phoenixai apply -f wh1.yaml
```

### 3.2.2 Update values.yaml for Helm chart

For example, upgrade the image version:

```yaml
# wh1-values.yaml
spec:
  # Make sure the PhoenixAI cluster exists in the same namespace.
  # You can check it by running `kubectl -n phoenixai get phoenixaiclusters.phoenixdata.ai`.
  phoenixAIClusterName: kube-anywhere
  replicas: 1
  image:
    repository: us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/cn-ubuntu
    tag: "<new-database-image-tag>" # this line is updated
  resources:
    limits:
      cpu: 8
      memory: 8Gi
    requests:
      cpu: 8
      memory: 8Gi
```

Then upgrade the warehouse by the following command:

```console
helm -n phoenixai upgrade wh1 phoenixai/warehouse -f wh1-values.yaml
```

## 4. Delete the Warehouse

If you deployed the warehouse by YAML manifest, you can delete it by running the following command:

```console
kubectl delete -f wh1.yaml
```

If you deployed the warehouse by Helm chart, you can delete it by running the following command:

```console
helm -n phoenixai uninstall wh1
```
