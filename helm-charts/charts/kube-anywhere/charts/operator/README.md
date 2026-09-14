# Deploy Operator by operator Chart

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0) [![Release Charts](https://img.shields.io/badge/Release-helmcharts-green.svg)](https://github.com/CelerData/phoenixai-kubernetes-operator/releases)

[Helm](https://helm.sh/) is a package manager for Kubernetes. A [Helm Chart](https://helm.sh/docs/topics/charts/) is a Helm package and contains all of the resource definitions necessary to run an application on a Kubernetes cluster. This topic describes how to use Helm to automatically deploy a PhoenixAI operator on a Kubernetes cluster.

## Before you begin

- [Create a Kubernetes cluster](https://kubernetes.io/).
- [Install Helm](https://helm.sh/docs/intro/quickstart/).


## Install operator Chart

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
      phoenixai/kube-anywhere       2.0.0            4.1.5-ee     kube-anywhere includes three subcharts, operator, phoenixai and anywhere
      phoenixai/operator            2.0.0            2.0.0        A Helm chart for PhoenixAI operator
      phoenixai/phoenixai           2.0.0            4.1.5-ee     A Helm chart for PhoenixAI cluster
      ```

2. Install the operator Chart.

   ```Bash
   helm install phoenixai-operator phoenixai/operator
   ```

   Please see [values.yaml](./values.yaml) for more details.

## Uninstall operator Chart

```Bash
helm uninstall phoenixai-operator
```
