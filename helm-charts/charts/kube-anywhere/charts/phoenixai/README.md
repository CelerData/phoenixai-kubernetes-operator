# Deploy PhoenixAI Cluster by phoenixai Chart

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0) [![Release Charts](https://img.shields.io/badge/Release-helmcharts-green.svg)](https://github.com/CelerData/phoenixai-kubernetes-operator/releases)

[Helm](https://helm.sh/) is a package manager for Kubernetes. A [Helm Chart](https://helm.sh/docs/topics/charts/) is a Helm package and contains all of the resource definitions necessary to run an application on a Kubernetes cluster. This topic describes how to use Helm to automatically deploy a PhoenixAI cluster on a Kubernetes cluster.

## Before you begin

- [Create a Kubernetes cluster](https://kubernetes.io/).
- [Install Helm](https://helm.sh/docs/intro/quickstart/).
- [Install PhoenixAI operator](../operator/README.md#install-operator-chart).

## Install phoenixai Chart

1. Add the PhoenixAI Helm repository.

    ```bash
    $ helm repo add phoenixai https://celerdata.github.io/phoenixai-kubernetes-operator
    $ helm repo update phoenixai
    $ helm search repo phoenixai
    NAME                          CHART VERSION    APP VERSION  DESCRIPTION
    phoenixai/kube-anywhere       2.0.0            4.1.5-ee     kube-anywhere includes three subcharts, operator, phoenixai and anywhere
    phoenixai/operator            2.0.0            2.0.0        A Helm chart for PhoenixAI operator
    phoenixai/phoenixai           2.0.0            4.1.5-ee     A Helm chart for PhoenixAI cluster
    ```

2. Install the phoenixai Chart.

    ```bash
    helm install phoenixai phoenixai/phoenixai
    ```

    Please see [values.yaml](./values.yaml) for more details.

## Uninstall phoenixai Chart

```bash
helm uninstall phoenixai
```
