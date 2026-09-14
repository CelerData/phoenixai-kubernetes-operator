# Deploying with a read-only fielsystem

PhoenixAI has two components: Frontend (FE) and Compute Node (CN). When the `readOnlyRootFilesystem` is
set to `true`, the components of PhoenixAI cannot start normally. This is because the components of PhoenixAI write data
to the disk, and the `readOnlyRootFilesystem` setting prevents the components from writing data to the disk.

For the FE component, FE writes data to the following directories:

```bash
# in fe directory
drwxr-xr-x 2 root      root      4.0K Nov 19 11:27 plugins
drwxr-xr-x 4 root      root      4.0K Nov 19 11:27 temp_dir

# in fe/bin directory
-rw-r--r-- 1 root      root         2 Nov 19 11:27 fe.pid

# in fe/conf directory
lrwxrwxrwx 1 root      root        30 Nov 19 11:27 fe.conf -> /etc/phoenixai/fe/conf/fe.conf
```

For the CN component, CN writes data to the following directories:

```bash
# in cn directory
drwxr-xr-x 2 root      root      4.0K Nov 19 11:27 spill

# in cn/conf directory
lrwxrwxrwx 1 root      root        30 Nov 19 11:27 cn.conf -> /etc/phoenixai/cn/conf/cn.conf

# in cn/bin directory
-rw-r----- 1 root      root         3 Nov 19 11:27 cn.pid

# in cn/lib directory
drwxr-xr-x   2 root      root      4.0K Nov 19 11:27 jdbc_drivers
drwxr-xr-x   2 root      root      4.0K Nov 19 11:27 small_file
drwxr-xr-x 130 root      root      4.0K Nov 19 11:27 udf
drwxr-xr-x   2 root      root      4.0K Nov 19 11:27 udf-runtime
```

This document describes how to set up PhoenixAI when the `readOnlyRootFilesystem` field is set to `true`.

## How

We create and mount a volume, and in the entrypoint script, we will copy everything from the original directory to the
mounted volume. This way, the components of PhoenixAI can write data to the mounted volume.

> Note: you should use the operator version `v1.9.9` or later.

## Steps

There are two ways to deploy PhoenixAI cluster:

1. Deploy PhoenixAI cluster with `PhoenixAICluster` CR yaml.
2. Deploy PhoenixAI cluster with Helm chart.

Therefore, there are two ways to set up PhoenixAI when the `readOnlyRootFilesystem` field is set to `true`.

### Using PhoenixAICluster CR yaml

```yaml
apiVersion: phoenixdata.ai/v1
kind: PhoenixAICluster
metadata:
  name: kube-anywhere
  namespace: phoenixai
spec:
  phoenixAIFeSpec:
    readOnlyRootFilesystem: true
    runAsNonRoot: true
    configMapInfo:
      configMapName: kube-anywhere-fe-cm
      resolveKey: fe.conf
    storageVolumes:
    - mountPath: /opt/starrocks-artifacts
      name: fe-artifacts
      storageClassName: emptyDir
      storageSize: 20Gi
    - mountPath: /opt/starrocks-meta
      name: fe-meta   # must be this
      storageSize: 10Gi
    - mountPath: /opt/starrocks-log
      name: fe-log    # must be this
      storageSize: 10Gi
    command: ["bash", "-c"]
    args:
      - cp -r /opt/starrocks/* /opt/starrocks-artifacts && exec /opt/starrocks-artifacts/fe_entrypoint.sh $FE_SERVICE_NAME
    feEnvVars:
    - name: STARROCKS_ROOT
      value: /opt/starrocks-artifacts
    image: us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/fe-ubuntu:<database-image-tag>
    imagePullPolicy: IfNotPresent
    replicas: 1
    requests:
      cpu: 1m
      memory: 22Mi
  phoenixAICnSpec:
    readOnlyRootFilesystem: true
    runAsNonRoot: true
    configMapInfo:
      configMapName: kube-anywhere-cn-cm
      resolveKey: cn.conf
    storageVolumes:
    - mountPath: /opt/starrocks-artifacts
      name: cn-artifacts
      storageClassName: emptyDir
      storageSize: 20Gi
    - mountPath: /opt/starrocks-storage
      name: cn-storage  # must be this
      storageSize: 10Gi
    - mountPath: /opt/starrocks-log
      name: cn-log  # must be this
      storageSize: 10Gi
    command: ["bash", "-c"]
    args:
      - cp -r /opt/starrocks/* /opt/starrocks-artifacts && exec /opt/starrocks-artifacts/cn_entrypoint.sh $FE_SERVICE_NAME
    cnEnvVars:
    - name: STARROCKS_ROOT
      value: /opt/starrocks-artifacts
    image: us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/cn-ubuntu:<database-image-tag>
    imagePullPolicy: IfNotPresent
    replicas: 2
    requests:
      cpu: 1m
      memory: 10Mi

---

apiVersion: v1
data:
  fe.conf: |
    LOG_DIR = ${STARROCKS_HOME}/log
    DATE = "$(date +%Y%m%d-%H%M%S)"
    JAVA_OPTS="-Dlog4j2.formatMsgNoLookups=true -Xmx8192m -XX:+UseG1GC -Xlog:gc*:${LOG_DIR}/fe.gc.log.$DATE:time"
    http_port = 8030
    rpc_port = 9020
    query_port = 9030
    edit_log_port = 9010
    mysql_service_nio_enabled = true
    sys_log_level = INFO
    
    # config for meta and log
    meta_dir = /opt/starrocks-meta
    dump_log_dir = /opt/starrocks-log
    sys_log_dir = /opt/starrocks-log
    audit_log_dir = /opt/starrocks-log
kind: ConfigMap
metadata:
  name: kube-anywhere-fe-cm
  namespace: phoenixai

---

apiVersion: v1
data:
  cn.conf: |
    thrift_port = 9060
    webserver_port = 8040
    heartbeat_service_port = 9050
    brpc_port = 8060
    sys_log_level = INFO

    # config for storage and log
    storage_root_path = /opt/starrocks-storage
    sys_log_dir = /opt/starrocks-log
kind: ConfigMap
metadata:
  name: kube-anywhere-cn-cm
  namespace: phoenixai
```

### Using a Helm Chart

If you are using the `kube-anywhere` Helm chart, add the following snippets to `values.yaml`.

> Note: you should use the chart version `v1.9.9` or later.

```yaml
operator:
  phoenixAIOperator:
    image:
      repository: us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/operator
      tag: v1.9.9
    imagePullPolicy: IfNotPresent
    resources:
      requests:
        cpu: 1m
        memory: 20Mi
phoenixai:
  phoenixAIFeSpec:
    readOnlyRootFilesystem: true
    runAsNonRoot: true
    storageSpec:
      name: fe  # must be this
      storageSize: 10Gi
      storageMountPath: /opt/starrocks-meta
      logStorageSize: 10Gi
      logMountPath: /opt/starrocks-log
    emptyDirs:
    - name: fe-artifacts
      mountPath: /opt/starrocks-artifacts
    entrypoint:
      script: |
        #! /bin/bash
        cp -r /opt/starrocks/* /opt/starrocks-artifacts
        exec /opt/starrocks/fe_entrypoint.sh $FE_SERVICE_NAME
    feEnvVars:
    - name: STARROCKS_ROOT
      value: /opt/starrocks-artifacts
    image:
      repository: us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/fe-ubuntu
      tag: <database-image-tag>
    resources:
      limits:
        cpu: 2
        memory: 4Gi
      requests:
        cpu: 1m
        memory: 20Mi
    config: |
      LOG_DIR = ${STARROCKS_HOME}/log
      DATE = "$(date +%Y%m%d-%H%M%S)"
      JAVA_OPTS="-Dlog4j2.formatMsgNoLookups=true -Xmx8192m -XX:+UseG1GC -Xlog:gc*:${LOG_DIR}/fe.gc.log.$DATE:time"
      http_port = 8030
      rpc_port = 9020
      query_port = 9030
      edit_log_port = 9010
      mysql_service_nio_enabled = true
      sys_log_level = INFO
      # config for meta and log
      meta_dir = /opt/starrocks-meta
      dump_log_dir = /opt/starrocks-log
      sys_log_dir = /opt/starrocks-log
      audit_log_dir = /opt/starrocks-log
  phoenixAICnSpec:
    readOnlyRootFilesystem: true
    runAsNonRoot: true
    storageSpec:
      name: cn  # must be this
      storageSize: 10Gi
      storageMountPath: /opt/starrocks-storage
      logStorageSize: 10Gi
      logMountPath: /opt/starrocks-log
      spillStorageSize: 10Gi
      spillMountPath: /opt/starrocks-spill
    emptyDirs:
    - name: cn-artifacts
      mountPath: /opt/starrocks-artifacts
    entrypoint:
      script: |
        #! /bin/bash
        cp -r /opt/starrocks/* /opt/starrocks-artifacts 
        exec /opt/starrocks-artifacts/cn_entrypoint.sh $FE_SERVICE_NAME
    cnEnvVars:
    - name: STARROCKS_ROOT
      value: /opt/starrocks-artifacts
    image:
      repository: us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/cn-ubuntu
      tag: <database-image-tag>
    replicas: 1
    resources:
      limits:
        cpu: 8
        memory: 8Gi
      requests:
        cpu: 1m
        memory: 10Mi
    config: |
      thrift_port = 9060
      webserver_port = 8040
      heartbeat_service_port = 9050
      brpc_port = 8060
      sys_log_level = INFO
      # config for storage and log
      storage_root_path = /opt/starrocks-storage
      sys_log_dir = /opt/starrocks-log
      spill_local_storage_dir = /opt/starrocks-spill
```
