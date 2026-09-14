# Mount external configMaps or secrets

PhoenixAI Kubernetes Operator supports mounting multiple external configmaps or secrets into PhoenixAI. This document
describes how to mount configmaps into PhoenixAI.
> You can mount secrets in the same way.

## 1. Mount configMaps by PhoenixAI CRD YAML file

You can specify `configMaps` in the corresponding component spec. The following is an example

```shell
apiVersion: phoenixdata.ai/v1
kind: PhoenixAICluster
metadata:
  name: kube-anywhere
  namespace: kb-system
spec:
  phoenixAIFeSpec:
    image: "us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/fe-ubuntu:<database-image-tag>"
    replicas: 1
    configMaps:
      - name: my-configmap
        mountPath: /etc/my-configmap
  phoenixAICnSpec:
    image: "us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/cn-ubuntu:<database-image-tag>"
    replicas: 1
    configMaps:
      - name: my-configmap
        mountPath: /etc/my-configmap
```

> Note: The specific `ConfigMap` resources should be available in kubernetes cluster before enabling this feature.

## 2. Mount configMaps by helm chart

By using Helm chart, you can also mount multiple external configmaps into PhoenixAI. You can specify `configMaps` in
the corresponding component spec. The following is an example by using `kube-anywhere` Helm chart.

```shell
phoenixai:
  phoenixAICnSpec:
    configMaps:
      # mount the whole configmap `my-configmap` to `/etc/my-configmap`
      - name: my-configmap
        mountPath: /etc/my-configmap

  # a configmap named `my-configmap` will be created with the following content.
  configMaps:
  - name: my-configmap
    data:
      key.conf: |
        this is the content of the configmap
        when mounted, key will be the name of the file
```

## 3. Mount configMaps to a subPath by Helm Chart

You can also mount external configmaps into PhoenixAI with a subPath. The following is an example by
using `kube-anywhere` Helm chart.

```shell
phoenixai:
  phoenixAICnSpec:
    configMaps:
      # mount the file `key.conf` in configmap `my-configmap` to `/opt/starrocks/cn/conf/key.conf`
      - name: my-configmap
        mountPath: /opt/starrocks/cn/conf/key.conf
        subPath: key.conf

  # a configmap named `my-configmap` will be created with the following content.
  configMaps:
  - name: my-configmap
    data:
      key.conf: |
        this is the content of the configmap
        when mounted, key will be the name of the file
```

In `/opt/starrocks/cn/conf`, the original file if existed will be overwritten, but other files will not be affected.
