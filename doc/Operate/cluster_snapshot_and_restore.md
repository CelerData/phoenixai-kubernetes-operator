---
title: Cluster Snapshot & Restore
sidebar_label: Cluster Snapshot & Restore
description: Take a cluster snapshot, and restore a cluster from one.
---

# Cluster Snapshot & Restore

A cluster snapshot writes the cluster's metadata to object storage. Table data already lives in
object storage; the snapshot is what makes it readable again. If a cluster is lost, you restore it
by creating a new one that loads the snapshot on startup.

This page covers two things:

1. How Anywhere runs a restore.
2. A worked example, from taking a snapshot through to a recovered cluster.

## How Anywhere runs a restore

A restore is driven by these fields on the cluster:

```yaml
spec:
  disasterRecovery:
    generation: 1
    enabled: true

status:
  disasterRecoveryStatus:
    phase: todo/doing/done
    reason: ""
    observedGeneration: 1
    startTimestamp: xxx   # unix timestamp
    endTimestamp: yyy     # unix timestamp  
```

### When a restore is triggered

1. The `enabled` field must be true.
2. The `generation` is a monotonically increasing integer that represents the expected state (spec) change version of
   the resource object. `observedGeneration` represents the version of the restore that has been executed. The
   Operator compares the values of `generation` and `observedGeneration`: when `disasterRecoveryStatus` is empty,
   or `observedGeneration < generation`, a new restore is triggered.
   If `generation == observedGeneration` && `disasterRecovery.Phase` != `v1.DRPhaseDone`, it means that after the last
   reconcile, the cluster has entered restore mode.
If both conditions are met, the cluster enters restore mode.

### How the restore runs

For the CN component, reconciliation is paused.

The reconcile process for FE is as follows:

1. Traverse `spec.phoenixAIFeSpec.ConfigMaps` to confirm that `cluster_snapshot.yaml` has been mounted. Currently,
   this check is relatively simple, mainly to check whether the `SubPath` field is equal to `cluster_snapshot.yaml`.
2. Modify the FE Statefulset, including:
    1. Start a single-replica FE.
    2. Inject the `RESTORE_CLUSTER_GENERATION` and `RESTORE_CLUSTER_SNAPSHOT` environment variables. The former is
       used to determine the Generation to which the Pod belongs, and the latter is an environment variable passed to
       the FE module to trigger the restore on the FE Pod.
    3. Delete the startup/liveness configuration, because a restore can take a long time.
    4. Modify the Readiness configuration. The configuration for normal cluster is to send an HTTP request to FE 8030;
       the new configuration is used to detect whether the FE 9030 port is connected. Once connected, it means that the
       FE Pod restore is complete.
3. Once the FE Pod restore is complete, the cluster starts normally, following the PhoenixAICluster spec.

### How the restore phase is reported

`disasterRecoveryStatus.phase` reports how far the restore has got: `todo`, `doing`, or `done`.

The status update logic is as follows:

1. Restore mode is entered for the first time (`disasterRecoveryStatus` is empty) or
   `observedGeneration < generation`. The phase becomes `todo`.
2. Once the modified StatefulSet is applied, the phase becomes `doing`. How long it stays there depends on how
   long the restore takes.
3. The FE Pod is checked periodically: first its `generation`, then whether it is Ready.
4. Once the FE Pod is Ready, the phase becomes `done`.

## Example

Inorder to keep it simple and easy for users to follow this document, we use the `kube-anywhere` Helm Chart to deploy.
Please note:

1. Be sure to use at least v1.10.0 version of Operator and CRD.
3. Sensitive information is replaced by xxx, please set it to a reasonable value.

### 1. Create a normal working cluster

Prepare the `./phoenixai-values.yaml` file:
> Note: we set `automated_cluster_snapshot_interval_seconds` to configure every minute to take a snapshot.

```yaml
operator:
  phoenixAIOperator:
    image:
      repository: us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/operator
      tag: v1.10.0
    imagePullPolicy: IfNotPresent
    replicaCount: 1
    resources:
      requests:
        cpu: 1m
        memory: 20Mi
phoenixai:
  phoenixAICluster:
    enabledCn: true
  phoenixAICnSpec:
    config: |
      sys_log_level = INFO
      # ports for admin, web, heartbeat service
      thrift_port = 9060
      webserver_port = 8040
      heartbeat_service_port = 9050
      brpc_port = 8060
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
    storageSpec:
      name: cn
      logStorageSize: 1Gi
      storageSize: 10Gi
  phoenixAIFeSpec:
    feEnvVars:
      - name: LOG_CONSOLE
        value: "1"
    config: |
      LOG_DIR = ${STARROCKS_HOME}/log
      DATE = "$(date +%Y%m%d-%H%M%S)"
      JAVA_OPTS="-Dlog4j2.formatMsgNoLookups=true -Xmx8192m -XX:+UseG1GC -Xlog:gc*:${LOG_DIR}/fe.gc.log.$DATE:time -XX:ErrorFile=${LOG_DIR}/hs_err_pid%p.log -Djava.security.policy=${STARROCKS_HOME}/conf/udf_security.policy"
      http_port = 8030
      rpc_port = 9020
      query_port = 9030
      edit_log_port = 9010
      mysql_service_nio_enabled = true
      sys_log_level = INFO
      run_mode = shared_data
      cloud_native_meta_port = 6090
      enable_load_volume_from_conf = true
      cloud_native_storage_type = S3
      aws_s3_path = xxx
      aws_s3_region = xxx
      aws_s3_endpoint = xxx
      aws_s3_access_key = xxx
      aws_s3_secret_key = xxx
      # we add this configuration because we want to get cluster snapshot quickly
      automated_cluster_snapshot_interval_seconds = 60
    replicas: 3
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
    storageSpec:
      logStorageSize: 1Gi
      name: fe-storage
      storageSize: 10Gi
```

Create the cluster using Helm:

```bash
helm install -f ./phoenixai-values.yaml kube-anywhere phoenixai/kube-anywhere

# make sure the cluster has been successfully deployed
kubectl get pods
NAME READY STATUS RESTARTS AGE
kube-anywhere-cn-0 1/1 Running 0 23s
kube-anywhere-fe-0 1/1 Running 0 79s
kube-anywhere-fe-1 1/1 Running 0 79s
kube-anywhere-fe-2 1/1 Running 0 79s
```

### 2. Create a table and insert data

Connect to the FE Pod:

```bash
# enter FE pod
kubectl exec -it kube-anywhere-fe-0 bash

# use mysql client to login
mysql -h 127.0.0.1 -P9030 -uroot
...
mysql>    
```

Execute the following SQL statement:

```sql
CREATE
DATABASE IF NOT EXISTS quickstart;

USE
quickstart;

-- create table
CREATE TABLE source_wiki_edit
(
    event_time     DATETIME,
    channel        VARCHAR(32)  DEFAULT '',
    user           VARCHAR(128) DEFAULT '',
    is_anonymous   TINYINT      DEFAULT '0',
    is_minor       TINYINT      DEFAULT '0',
    is_new         TINYINT      DEFAULT '0',
    is_robot       TINYINT      DEFAULT '0',
    is_unpatrolled TINYINT      DEFAULT '0',
    delta          INT          DEFAULT '0',
    added          INT          DEFAULT '0',
    deleted        INT          DEFAULT '0'
) DUPLICATE KEY(
   event_time,
   channel,user,
   is_anonymous,
   is_minor,
   is_new,
   is_robot,
   is_unpatrolled
)
PARTITION BY RANGE(event_time)(
PARTITION p06 VALUES LESS THAN ('2015-09-12 06:00:00'),
PARTITION p12 VALUES LESS THAN ('2015-09-12 12:00:00'),
PARTITION p18 VALUES LESS THAN ('2015-09-12 18:00:00'),
PARTITION p24 VALUES LESS THAN ('2015-09-13 00:00:00')
)
DISTRIBUTED BY HASH(user);

-- insert data
INSERT INTO source_wiki_edit
VALUES ("2015-09-12 00:00:00", "#en.wikipedia", "AustinFF", 0, 0, 0, 0, 0, 21, 5, 0),
       ("2015-09-12 00:00:00", "#ca.wikipedia", "helloSR", 0, 1, 0, 1, 0, 3, 23, 0),
       ("2015-09-12 08:00:00", "#ca.wikipedia", "helloSR", 0, 1, 0, 1, 0, 3, 23, 0);

-- select data
select *
from source_wiki_edit;
```

### 3. Generate Cluster Snapshot

Begin backup:

```sql
mysql
> ADMIN SET AUTOMATED CLUSTER SNAPSHOT ON STORAGE VOLUME builtin_storage_volume;
Query
OK, 0 rows affected (0.10 sec)
```

Wait for the backup to complete:

```sql
SELECT *
FROM INFORMATION_SCHEMA.CLUSTER_SNAPSHOT_JOBS \ G;
SNAPSHOT_NAME
: automated_cluster_snapshot_1739864377140
       JOB_ID: 13018
 CREATED_TIME: 2025-02-18 15:39:37
FINISHED_TIME: 2025-02-18 15:40:27
        STATE: FINISHED
  DETAIL_INFO:
ERROR_MESSAGE:

mysql>
SELECT *
FROM INFORMATION_SCHEMA.CLUSTER_SNAPSHOTS \ G;
*
************************** 1. row ***************************
     SNAPSHOT_NAME: automated_cluster_snapshot_1739864488333
     SNAPSHOT_TYPE: AUTOMATED
      CREATED_TIME: 2025-02-18 15:41:28
     FE_JOURNAL_ID: 1776
STARMGR_JOURNAL_ID: 126
        PROPERTIES:
    STORAGE_VOLUME: builtin_storage_volume
      STORAGE_PATH: s3://xxx/data/7351ce6a-f4a4-4937-a876-cb8801085aea/meta/image/automated_cluster_snapshot_1739864488333
1 row in set (0.03 sec)
```

Please note: because we set the backup interval to 1 minute, the backup path may be different from the above. The final
result can be viewed through s3:

```bash
s3cmd ls s3://xxx/data/7351ce6a-f4a4-4937-a876-cb8801085aea/meta/image/

sDIR s3://xxx/data/7351ce6a-f4a4-4937-a876-cb8801085aea/meta/image/automated_cluster_snapshot_1739858235830/
```

### 4. Delete the created cluster

```bash
helm uninstall kube-anywhere

# delete pvcs
kubectl get pvc | awk '{if (NR>1){print $1}}' | xargs kubectl delete pvc
persistentvolumeclaim "cn-data-kube-anywhere-cn-0" deleted
persistentvolumeclaim "cn-log-kube-anywhere-cn-0" deleted
persistentvolumeclaim "fe-storage-log-kube-anywhere-fe-0" deleted
persistentvolumeclaim "fe-storage-log-kube-anywhere-fe-1" deleted
persistentvolumeclaim "fe-storage-log-kube-anywhere-fe-2" deleted
persistentvolumeclaim "fe-storage-meta-kube-anywhere-fe-0" deleted
persistentvolumeclaim "fe-storage-meta-kube-anywhere-fe-1" deleted
persistentvolumeclaim "fe-storage-meta-kube-anywhere-fe-2" deleted
```

### 5. Create a new cluster to restore into

We will reuse the previous `phoenixai-values.yaml` file, so be sure to ensure the security of this configuration file.
Prepare a new file named `override.yaml`, which contains the configuration required for the restore.

```yaml
phoenixai:
  phoenixAICluster: # enable restore
    disasterRecovery:
      enabled: true
      generation: 1
  phoenixAIFeSpec: # mount the cluster_snapshot.yaml
    configMaps:
      - name: cluster-snapshot
        mountPath: /opt/starrocks/fe/conf/cluster_snapshot.yaml
        subPath: cluster_snapshot.yaml

  configMaps:
    - name: cluster-snapshot
      data:
        cluster_snapshot.yaml: |
          # information about the cluster snapshot to be downloaded and restored
          cluster_snapshot:
              cluster_snapshot_path: s3://xxx/data/7351ce6a-f4a4-4937-a876-cb8801085aea/meta/image/automated_cluster_snapshot_1739858235830
              storage_volume_name: builtin_storage_volume

          # Operator will add the other FE followers automatically
          # just leave it blank
          frontends:

          # Operator will add the CN nodes automatically
          # just leave it blank
          compute_nodes:

          # used for restoring a cloned snapshot
          storage_volumes:
            - name: builtin_storage_volume
              type: S3
              location: s3://xxx/data
              comment: my s3 volume
              properties:
                - key: aws.s3.region
                  value: xxx
                - key: aws.s3.endpoint
                  value: xxx
                - key: aws.s3.access_key
                  value: xxx
                - key: aws.s3.secret_key
                  value: xxx
```

This time, we will deploy the cluster with the following command:

```bash
# Note:
# 1. make sure you are using the at least v1.10.0 version of Operator and CRD
# 2. the command to deploy the cluster is different from the first time. We specify two files, and the override.yaml
#    is used for the recovery configuration.
helm install -f ./phoenixai-values.yaml -f override.yaml kube-anywhere phoenixai/kube-anywhere --version 1.10.0

```

The restore runs as follows:

1. Anywhere starts a single FE Pod and begins the restore.

   ```text
   kubectl get pods
   NAME                  READY   STATUS    RESTARTS        AGE
   kube-anywhere-fe-0    1/1     Running   0               4m37s
   ```

   If you check the status of the PhoenixAICluster at this time, you will see:

   ```text
   kubectl get pac kube-anywhere -oyaml | less
   status:
     phase: running
     disasterRecovery:
       observedGeneration: 1
       phase: doing
       reason: disaster recovery is in progress
       startTimestamp: "1739860263"
   ```

2. Once the restore is complete, the remaining Pods start automatically.

   ```text
   kubectl get pods
   NAME                  READY   STATUS    RESTARTS        AGE
   kube-anywhere-cn-0    1/1     Running   0               7m54s
   kube-anywhere-fe-0    1/1     Running   0               7m1s
   kube-anywhere-fe-1    1/1     Running   0               7m54s
   kube-anywhere-fe-2    1/1     Running   0               7m54s
   ```

   The cluster status is as follows:

   ```text
   status:
     phase: running
     disasterRecoveryStatus:
       endTimestamp: 1739861262
       observedGeneration: 1
       phase: done
       reason: disaster recovery is done
       startTimestamp: 1739860263
   ```

### Verify the restore

```shell
# enter the pod
kubectl exec -it kube-anywhere-fe-0 bash

# connect mysql
mysql -h 127.0.0.1 -P9030 -uroot

# get the data

mysql >USE quickstart
Reading table information for completion of table and column names
You can turn off this feature to get a quicker startup with -A

Database changed
mysql >select * from source_wiki_edit
```
