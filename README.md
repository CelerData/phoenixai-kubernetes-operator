# PhoenixAI-Kubernetes-Operator

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

> English | [中文](README_ZH-CN.md)

## Overview

PhoenixAI Kubernetes Operator is a project that implements the deployment and operation of PhoenixAI, a next-generation
sub-second MPP OLAP database, on Kubernetes. It facilitates the deployment of PhoenixAI' Frontend (FE)
and Compute Node (CN) components within your Kubernetes environment. It also includes Helm chart for easy installation
and configuration. With PhoenixAI Kubernetes Operator, you can easily manage the lifecycle of PhoenixAI clusters, such
as installing, scaling, upgrading etc.

> [!NOTE]  
> The PhoenixAI k8s operator was designed to be a level 2 operator.   See https://sdk.operatorframework.io/docs/overview/operator-capabilities/ to understand more about the capabilities of a level 2 operator. 

## Prerequisites

1. Kubernetes version >= 1.23.0
2. Helm version >= 3.0

## Features

### Operator Features

- Support deploying PhoenixAI FE and CN components separately
  FE component is a must-have component, the CN component can be optionally deployed
- Support multiple PhoenixAI clusters in one Kubernetes cluster
- Support external clients outside the network of kubernetes to load data into PhoenixAI using STREAM LOAD
- Support automatic scaling for CN nodes based on CPU and memory usage
- Support mounting persistent volumes for PhoenixAI containers

### Helm Chart Features

- Support Helm Chart for easy installation and configuration
    - using kube-anywhere Helm chart to install both operator and PhoenixAI cluster, and optionally
      the PhoenixAI Anywhere console with `anywhere.enabled=true`
    - using operator Helm Chart to install operator, and using PhoenixAI Helm Chart to install phoenixai cluster
- Support initializing the password of root in your PhoenixAI cluster during installation.
- Support integration with other components in the Kubernetes ecosystem, such as Prometheus, Datadog, etc.

## Installation

In order to use PhoenixAI in Kubernetes, you need to install:

1. PhoenixAICluster CRD
2. PhoenixAI Operator
3. PhoenixAICluster CR

There are two ways to install Operator and PhoenixAI Cluster.

1. Install Operator and PhoenixAI Cluster by yaml Manifest.
2. Install Operator and PhoenixAI Cluster by Helm Chart.

> Note: In every release, we will provide the latest version of the yaml Manifest and Helm Chart. You can find them
> in https://github.com/CelerData/phoenixai-kubernetes-operator/releases

## Installation by yaml Manifest

Please see [Deploy PhoenixAI With Operator](./doc/Deploy/install_with_kubectl.md) document for more details.

### 1. Apply the PhoenixAICluster CRD

```console
kubectl apply -f https://raw.githubusercontent.com/celerdata/phoenixai-kubernetes-operator/main/deploy/phoenixdata.ai_phoenixaiclusters.yaml
```

### 2. Apply the Operator manifest

Apply the Operator manifest. By default, the Operator is configured to install in the PhoenixAI namespace. To use the
Operator in a custom namespace, download
the [Operator manifest](https://raw.githubusercontent.com/celerdata/phoenixai-kubernetes-operator/main/deploy/operator.yaml)
and edit all instances of namespace: PhoenixAI to specify your custom namespace.
Then apply this version of the manifest to the cluster with kubectl apply -f {local-file-path} instead of using the
command below.

```console
kubectl apply -f https://raw.githubusercontent.com/celerdata/phoenixai-kubernetes-operator/main/deploy/operator.yaml
```

### 3. Deploy the PhoenixAI cluster

You need to prepare a separate yaml file to deploy the PhoenixAI. The phoenixai cluster CRD fields explains
in [api.md](./doc/api.md). The [examples](./examples/phoenixai) directory contains some simple example for reference.

You can use any of the template yaml file as a starting point. You can further add more configurations into the template
yaml file following this deployment documentation.

For demonstration purpose, we use the
[deploy_a_phoenixai_cluster_running_in_shared_data_mode.yaml](./examples/phoenixai/deploy_a_phoenixai_cluster_running_in_shared_data_mode.yaml)
example template to start a shared-data PhoenixAI cluster with 3 FE nodes and CN nodes. Download and edit the
template first: the FE ConfigMap at the bottom of the file is where you specify your shared storage (S3, MinIO,
etc.) location and credentials.

Here's an example yaml (`phoenixai-shared-data.yaml`) for Docker Desktop with local desktop
access so you can upgrade in later steps.
```yaml
apiVersion: phoenixdata.ai/v1
kind: PhoenixAICluster
metadata:
  name: phoenixaicluster-sample
  namespace: phoenixai
spec:
  phoenixAIFeSpec:
    image: us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/fe-ubuntu:4.1.5-ee
    replicas: 3
    requests:
      cpu: 1
      memory: 2Gi
    limits:
      cpu: 4
      memory: 16Gi
    service:
      type: LoadBalancer
    configMapInfo:
      configMapName: phoenixaicluster-sample-fe-cm   # the fe.conf with your shared-data settings
      resolveKey: fe.conf
  phoenixAICnSpec:
    image: us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/cn-ubuntu:4.1.5-ee
    replicas: 3
    requests:
      cpu: 1
      memory: 2Gi
    limits:
      cpu: 4
      memory: 8Gi
---
# The FE config that turns on shared-data mode. Fill in your shared storage (S3, MinIO, ...)
# settings here; see doc/GetStarted/quickstart_s3.md for a complete example.
apiVersion: v1
kind: ConfigMap
metadata:
  name: phoenixaicluster-sample-fe-cm
  namespace: phoenixai
data:
  fe.conf: |
    http_port = 8030
    rpc_port = 9020
    query_port = 9030
    edit_log_port = 9010
    sys_log_level = INFO
    # config for shared-data mode
    run_mode = shared_data
    cloud_native_meta_port = 6090
    enable_load_volume_from_conf = false
    # ... add your cloud_native_storage_type / S3 settings here
```

```console
kubectl apply -f phoenixai-shared-data.yaml
```

### 4. Connect the PhoenixAI cluster

To connect, just use the mysql client and connect to the PhoenixAI cluster port 9030.  An example of a connection is shown below. 

> [!NOTE]  
>  If you want to connect remotely or through your desktop, you will need to enable the k8s Load Balander.

```sh
kubectl -n phoenixai get svc
```

```sh
NAME                                 TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)                                                       AGE
phoenixaicluster-sample-cn-search    ClusterIP      None            <none>        9050/TCP                                                      5m2s
phoenixaicluster-sample-cn-service   ClusterIP      10.103.248.52   <none>        9060/TCP,8040/TCP,9050/TCP,8060/TCP                           5m2s
phoenixaicluster-sample-fe-search    ClusterIP      None            <none>        9030/TCP                                                      6m22s
phoenixaicluster-sample-fe-service   LoadBalancer   10.99.14.222    localhost     8030:32326/TCP,9020:32578/TCP,9030:30774/TCP,9010:32505/TCP   6m22s
```

```sh
mysql -h 127.0.0.1 -P 9030 -uroot
```

```sh
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 3
Server version: 5.1.0 3.2.1-79ee91d

Copyright (c) 2000, 2024, Oracle and/or its affiliates.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql>
```

### 5. Upgrade the PhoenixAI cluster

To upgrade, just patch the PhoenixAI cluster. 

```console
kubectl -n phoenixai patch phoenixaicluster phoenixaicluster-sample --type='merge' -p '{"spec":{"phoenixAIFeSpec":{"image":"us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/fe-ubuntu:4.1.5-ee"}}}'
kubectl -n phoenixai patch phoenixaicluster phoenixaicluster-sample --type='merge' -p '{"spec":{"phoenixAICnSpec":{"image":"us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/cn-ubuntu:4.1.5-ee"}}}'
```

### 6. Resize the PhoenixAI cluster

To resize, just patch the PhoenixAI cluster. 

> [!IMPORTANT]  
>  Once you deploy with 3 FE nodes, you are in HA mode.  Do not resize FE nodes below 3 since that will affect cluster quorum.  This rule doesn't apply to CN nodes.

```console
kubectl -n phoenixai patch phoenixaicluster phoenixaicluster-sample --type='merge' -p '{"spec":{"phoenixAICnSpec":{"replicas":9}}}'
```

### 7. Delete/stop the PhoenixAI cluster

To delete/stop the PhoenixAI cluster, just execute the delete command.

```console
kubectl delete -f phoenixai-shared-data.yaml
```
or
```console
kubectl delete phoenixaicluster phoenixaicluster-sample -n phoenixai
```

### 8. Delete/stop the PhoenixAI Operator

To delete/stop the PhoenixAI Operate, just execute the delete command.

```console
kubectl delete -f https://raw.githubusercontent.com/celerdata/phoenixai-kubernetes-operator/main/deploy/operator.yaml
```


## Installation by Helm Chart

Please see [kube-anywhere](./helm-charts/charts/kube-anywhere/README.md) for how to install both operator and
PhoenixAI cluster by Helm Chart. The kube-anywhere chart can also optionally install the PhoenixAI Anywhere
console with `anywhere.enabled=true`.

If you want more flexibility in managing your PhoenixAI clusters, you can deploy Operator
using [operator](./helm-charts/charts/kube-anywhere/charts/operator) Helm Chart and PhoenixAI
using [phoenixai](./helm-charts/charts/kube-anywhere/charts/phoenixai) Helm Chart separately.

## Other Documents

- In [doc](./doc) directory, you can find more documents about how to use PhoenixAI Operator.
- In [examples](./examples/phoenixai) directory, you can find more examples about how to write PhoenixAICluster CR.