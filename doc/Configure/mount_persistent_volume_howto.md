# Mount Persistent Volume

PhoenixAI Kubernetes Operator supports mounting persistent volumes to PhoenixAI FE and CN pods. If not specified, the
operator will use emptyDir mode to store FE meta and CN cache data. **When container restarts, the data will be lost.**

This document describes how to mount persistent volumes to PhoenixAI FE and CN pods. There are two ways to mount
persistent volumes to PhoenixAI FE and CN pods:

1. Mounting persistent volumes to PhoenixAI FE and CN pods by the PhoenixAI CRD YAML file.
2. Mounting persistent volumes to PhoenixAI FE and CN pods by Helm chart.

> Note: phoenixai operator will create a new PVC for each storageVolume. You should not create PVC manually.

## 1. Mounting Persistent Volumes by PhoenixAI CRD YAML File

If you want to use external storage to store FE meta and CN cache data for persistence, you can specify `storageVolumes` in
the corresponding component spec.

The following is an example of mounting persistent volumes to PhoenixAI FE and CN.

```bash
apiVersion: phoenixdata.ai/v1
kind: PhoenixAICluster
metadata:
  name: kube-anywhere
  namespace: phoenixai
  labels:
    cluster: kube-anywhere
spec:
  phoenixAIFeSpec:
    image: "us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/fe-ubuntu:<database-image-tag>"
    replicas: 1
    storageVolumes:
    - name: fe-meta
      storageClassName: standard-rwo  # standard-rwo is the default storageClassName in GKE.
      # fe container stop running if the disk free space which the fe meta directory residents, is less than 5Gi.
      storageSize: 10Gi
      mountPath: /opt/starrocks/fe/meta
    - name: fe-log
      storageClassName: standard-rwo
      storageSize: 5Gi
      mountPath: /opt/starrocks/fe/log
  phoenixAICnSpec:
    image: "us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/cn-ubuntu:<database-image-tag>"
    replicas: 3
    storageVolumes:
    - name: cn-data
      storageClassName: standard-rwo
      storageSize: 1Ti
      mountPath: /opt/starrocks/cn/storage
    - name: cn-log
      storageClassName: standard-rwo
      storageSize: 1Gi
      mountPath: /opt/starrocks/cn/log
```

Note that the specific `storageClassName` should be available in kubernetes cluster before enabling this storageVolume
feature. If `StorageVolume` info is not specified in CRD spec, the operator will use emptydir mode to store FE meta and
CN cache data.

## 2. Mounting Persistent Volumes by Helm Chart

See [Step 2 — Get the chart](../Deploy/install_with_helm.md#step-2--get-the-chart) to learn how to add the Helm chart repo for PhoenixAI. In this
guide, we will use `phoenixai/kube-anywhere` chart to deploy both PhoenixAI operator and cluster.

### 2.1. Download the values.yaml file for the kube-anywhere chart

The values.yaml file contains the default configurations for the PhoenixAI Operator and the PhoenixAI cluster.

```Bash
helm show values phoenixai/kube-anywhere > values.yaml
```

The following is a snippet of the values.yaml file:

```yaml
phoenixai:
  phoenixAIFeSpec: # fe storageSpec for persistent metadata.
    storageSpec:
      name: "fe"
      # the storageClassName represent the used storageclass name. if not set will use k8s cluster default storageclass.
      # you must set name when you set storageClassName
      # storageClassName: ""
      # the persistent volume size， default 10Gi.
      # fe container stop running if the disk free space which the fe meta directory residents, is less than 5Gi.
      storageSize: 10Gi
      # Setting this parameter can persist log storage
      logStorageSize: 5Gi

  phoenixAICnSpec: # specify storageclass name and request size.
    storageSpec: # the name of volume for mount. if not will use emptyDir.
      name: ""
      # the storageClassName represent the used storageclass name. if not set will use k8s cluster default storageclass.
      # you must set name when you set storageClassName
      storageClassName: ""
      storageSize: 1Ti
      # Setting this parameter can persist log storage
      logStorageSize: 1Gi
```

`storageSpec.name` is the switch for its whole block. While it is `""` — the shipped CN default —
no PersistentVolumeClaim is created and every other field beside it is ignored: `storageClassName`,
`storageSize`, `storageCount`, `storageMountPath` and `logStorageSize` all have no effect, and
nothing reports that they were ignored. Set the name first, then the rest of the block takes effect.

### 2.2. Configure a YAML File with storageSpec settings

The following is an example of a custom values.yaml with storageSpec settings:

```yaml
phoenixai:
   phoenixAIFeSpec:
      image:
         repository: us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/fe-ubuntu
         tag: <database-image-tag>
      storageSpec:
         name: fe-data
         storageClassName: standard-rwo   # standard-rwo is the default storageClassName in GKE.
         logStorageSize: 10Gi
         storageSize: 100Gi
   phoenixAICnSpec:
      image:
         repository: us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/cn-ubuntu
         tag: <database-image-tag>
      replicas: 3
      storageSpec:
         name: cn-storage
         storageClassName: standard-rwo
         logStorageSize: 10Gi
         storageSize: 500Gi
```

### 2.3. Deploy PhoenixAI Operator and Cluster

See [Install PhoenixAI by kube-anywhere chart](../../helm-charts/charts/kube-anywhere/README.md) to learn how to deploy
PhoenixAI Operator and Cluster

## 3. Some Special storageClassName

Normally, the `storageClassName` is the name of the StorageClass that you want to use for the PersistentVolumeClaim.
We have also provided some special `storageClassName` for you to use:

1. `emptyDir`. It is a good choice when you want to mount a volume into the container for temporary usage, e.g. /tmp. Be aware that the files and directories written to the volume will be completely lost upon container restarting.
2. `hostPath`. It is a good choice when you want to the host's storage for the container, the data will be still there as along as the container is still running on the host. The data will be unavailable upon the container rescheduling to a different host. The typical scenario is to use it as cache volume. The `hostPath` field is required when this type is used.
   field.
   e.g.:

    ```yaml
        storageVolumes:
        - name: cn-cache
          storageClassName: "hostPath"
          hostPath:
            path: /storage
          mountPath: /storage   
    ```

> Note: In both cases, the `storageSize` field will be ignored.
