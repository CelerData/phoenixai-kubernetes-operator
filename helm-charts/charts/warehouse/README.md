# Deploy PhoenixAI Warehouse by warehouse Chart

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0) [![Release Charts](https://img.shields.io/badge/Release-helmcharts-green.svg)](https://github.com/CelerData/phoenixai-kubernetes-operator/releases)

[Helm](https://helm.sh/) is a package manager for Kubernetes. A [Helm Chart](https://helm.sh/docs/topics/charts/) is a
Helm package and contains all of the resource definitions necessary to run an application on a Kubernetes cluster. This
topic describes how to use Helm to automatically deploy a PhoenixAI warehouse on a Kubernetes cluster.

## Before you begin

- [Create a Kubernetes cluster](https://kubernetes.io/).
- [Install Helm](https://helm.sh/docs/intro/quickstart/).
- [Install PhoenixAI operator](../kube-anywhere/charts/operator/README.md).
- [Install PhoenixAI cluster](../kube-anywhere/charts/phoenixai/README.md).

> Note: Warehouse is an enterprise feature for PhoenixAI.

## Install Warehouse Chart

1. Add the PhoenixAI Helm repository.

    ```bash
    $ helm repo add phoenixai https://celerdata.github.io/phoenixai-kubernetes-operator
    $ helm repo update phoenixai
    $ helm search repo phoenixai
    NAME                          CHART VERSION    APP VERSION  DESCRIPTION
    phoenixai/kube-anywhere       2.0.0            4.1.5-ee     kube-anywhere includes three subcharts, operator, phoenixai and anywhere
    phoenixai/operator            2.0.0            2.0.0        A Helm chart for PhoenixAI operator
    phoenixai/phoenixai           2.0.0            4.1.5-ee     A Helm chart for PhoenixAI cluster
    phoenixai/warehouse           2.0.0            4.1.5-ee     Warehouse is a feature of the PhoenixAI Enterprise Edition
    ```

2. Prepare the values.yaml file.

   ```yaml
   # The name of warehouse in PhoenixAI. You can execute `show warehouses` command in SQL to see the created warehouse.
   nameOverride: "wh1"
   spec:
     # Make sure the PhoenixAI cluster exists in the same namespace.
     # You can check it by running `kubectl -n phoenixai get phoenixaiclusters.phoenixdata.ai`.
     phoenixAIClusterName: kube-anywhere
     replicas: 1
     image: your-enterprise-image-version-for-cn
     resources:
       limits:
         cpu: 8
         memory: 8Gi
       requests:
         cpu: 8
         memory: 8Gi
   ```

3. Install the warehouse Chart.

    ```bash
    # Use the above values.yaml to deploy a warehouse in namespace phoenixai
    helm -n phoenixai install warehouse phoenixai/warehouse -f values.yaml
    ```

   This chart does not install the `PhoenixAIWarehouse` CRD — the **operator** chart does, because
   the operator registers its warehouse controller only if the CRD exists when it starts, which is
   before this chart runs. If the CRD is missing the install fails with
   `no matches for kind "PhoenixAIWarehouse"`; install it and restart the operator, as described in
   [Deploy Warehouse](../../../doc/Deploy/deploy_warehouse_howto.md).

   Please see [values.yaml](./values.yaml) for more details.

## Uninstall Warehouse

```bash
helm uninstall warehouse
```
