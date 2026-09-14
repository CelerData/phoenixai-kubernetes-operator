# Deploy Operator, PhoenixAI Cluster and Anywhere Console by kube-anywhere Chart

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0) [![Release Charts](https://img.shields.io/badge/Release-helmcharts-green.svg)](https://github.com/CelerData/phoenixai-kubernetes-operator/releases)

[Helm](https://helm.sh/) is a package manager for Kubernetes. A [Helm Chart](https://helm.sh/docs/topics/charts/) is a Helm package and contains all of the resource definitions necessary to run an application on a Kubernetes cluster. This topic describes how to use Helm to automatically deploy a PhoenixAI operator and cluster on a Kubernetes cluster.

The kube-anywhere chart carries three subcharts:

- **operator** — the PhoenixAI operator;
- **phoenixai** — a PhoenixAI cluster (the PhoenixAICluster custom resource);
- **anywhere** — the PhoenixAI Anywhere console, an operations & usage console for the deployed
  clusters. It is **opt-in** (`anywhere.enabled=true`) because it requires S3-compatible object
  storage (`anywhere.dependencies.s3`); see its own
  [README](./charts/anywhere/README.md) for the values.

## Before you begin

- [Create a Kubernetes cluster](https://kubernetes.io/).
- [Install Helm](https://helm.sh/docs/intro/quickstart/).

## Install kube-anywhere Chart

1. Add the Helm Chart Repo for PhoenixAI. The Helm Chart contains the definitions of the PhoenixAI Operator and the custom resource PhoenixAICluster.
   1. Add the Helm Chart Repo.

      ```Bash
      helm repo add phoenixai https://celerdata.github.io/phoenixai-kubernetes-operator
      ```

   2. Update the Helm Chart Repo to the latest version.

      ```Bash
      helm repo update phoenixai
      ```

   3. View the Helm Chart Repo that you added.

      ```Bash
      $ helm search repo phoenixai
      NAME                          CHART VERSION    APP VERSION  DESCRIPTION
      phoenixai/anywhere            2.0.0            v2.0.0       A Helm chart for PhoenixAI Anywhere — a read-only operations & usage console
      phoenixai/kube-anywhere       2.0.0            4.1.5-ee     kube-anywhere includes three subcharts, operator, phoenixai and anywhere
      phoenixai/operator            2.0.0            2.0.0        A Helm chart for PhoenixAI operator
      phoenixai/phoenixai           2.0.0            4.1.5-ee     A Helm chart for PhoenixAI cluster
      phoenixai/warehouse           2.0.0            4.1.5-ee     Warehouse is a feature of the PhoenixAI Enterprise Edition
      ```

      `kube-anywhere` is the install path this guide follows: it carries the console as a
      subchart, enabled with `anywhere.enabled=true`. The separately listed
      `phoenixai/anywhere` is the same console packaged on its own, for installing it next
      to an operator that is managed separately — do not install both.

2. Use the default **[values.yaml](https://github.com/CelerData/phoenixai-kubernetes-operator/blob/main/helm-charts/charts/kube-anywhere/values.yaml)** of the Helm Chart to deploy the PhoenixAI Operator and PhoenixAI cluster, or create a YAML file to customize your deployment configurations.
   1. Deployment with default configurations

      Run the following command to deploy the PhoenixAI Operator and the PhoenixAI cluster:

      ```Bash
      $ helm install kube-anywhere phoenixai/kube-anywhere
      # If the following result is returned, the PhoenixAI Operator and PhoenixAI cluster are being deployed.
      NAME: kube-anywhere
      LAST DEPLOYED: Tue Aug 15 15:12:00 2023
      NAMESPACE: phoenixai
      STATUS: deployed
      REVISION: 1
      TEST SUITE: None
      ```

   2. Deployment with custom configurations
      - Create a YAML file, for example, **my-values.yaml**, and customize the configurations for the PhoenixAI Operator and PhoenixAI cluster in the YAML file. For the supported parameters and descriptions, see the comments in the default **[values.yaml](https://github.com/CelerData/phoenixai-kubernetes-operator/blob/main/helm-charts/charts/kube-anywhere/values.yaml)** of the Helm Chart.
      - Run the following command to deploy the PhoenixAI Operator and PhoenixAI cluster with the custom configurations in **my-values.yaml**.

        ```Bash
        helm install -f my-values.yaml kube-anywhere phoenixai/kube-anywhere
        ```

    Deployment takes a while. During this period, you can check the deployment status by using the prompt command in the returned result of the deployment command above. The default prompt command is as follows:

    ```Bash
    $ kubectl --namespace default get phoenixaicluster -l "cluster=kube-anywhere"
    # If the following result is returned, the deployment has been successfully completed.
    NAME            FESTATUS   CNSTATUS
    kube-anywhere   running    running
    ```

    You can also run `kubectl get pods` to check the deployment status. If all Pods are in the `Running` state and all containers within the Pods are `READY`, the deployment has been successfully completed.

    ```Bash
    $ kubectl get pods
    NAME                                       READY   STATUS    RESTARTS   AGE
    kube-anywhere-cn-0                         1/1     Running   0          2m50s
    kube-anywhere-fe-0                         1/1     Running   0          4m31s
    kube-anywhere-operator-69c5c64595-pc7fv    1/1     Running   0          4m50s
    ```

    Note: the `kube-anywhere` prefix on the resource names above comes from the operator and
    phoenixai subcharts' `nameOverride` (which also sets the cluster name), not from the chart
    name — the two just happen to match. A release installed with an older chart version, whose
    default was `kube-phoenixai`, keeps that prefix on upgrade unless you change `nameOverride`,
    which would rename every resource and recreate the cluster.

## Upgrade kube-anywhere Chart

If you need to upgrade the PhoenixAI Operator and PhoenixAI cluster, run the following command:
```bash
helm upgrade -f my-values.yaml kube-anywhere phoenixai/kube-anywhere
```

## Uninstall kube-anywhere Chart

If you need to uninstall the PhoenixAI Operator and PhoenixAI cluster, run the following command:
```bash
helm uninstall kube-anywhere
```

Search Helm Chart maintained by PhoenixAI on Artifact Hub. See [kube-anywhere](https://github.com/CelerData/phoenixai-kubernetes-operator/tree/main/helm-charts/charts/kube-anywhere).
