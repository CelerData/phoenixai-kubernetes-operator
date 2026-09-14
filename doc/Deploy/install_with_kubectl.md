---
sidebar_label: Install with kubectl
sidebar_position: 4
title: Install with kubectl
---

# Deploy PhoenixAI Cluster with Operator

This document introduces how to use the PhoenixAI Operator to automate the deployment and management of a PhoenixAI
cluster on a Kubernetes cluster.

It includes the following parts:

1. Deploy PhoenixAI Operator
2. Deploy PhoenixAI cluster
3. Manage PhoenixAI Cluster
    1. Access PhoenixAI cluster
    2. Upgrade PhoenixAI cluster
    3. Scale PhoenixAI cluster
    4. Using ConfigMap to configure your PhoenixAI cluster
4. Install the Anywhere console

:::note What this path installs
The manifests on this page deploy the **operator** and a **PhoenixAI cluster** — not the
**PhoenixAI Anywhere console**. The console ships only as a Helm chart, so there are no manifests
to apply for it here. [Install with Helm](./install_with_helm.md) is the complete install
including the console; to add the console next to an operator and cluster you manage with
kubectl, see [Install the Anywhere console](#4-install-the-anywhere-console) at the end of this
page.
:::

> [!NOTE]  
> The PhoenixAI k8s operator was designed to be a level 2 operator.   See https://sdk.operatorframework.io/docs/overview/operator-capabilities/ to understand more about the capabilities of a level 2 operator.

## Prerequisites

1. Kubernetes cluster version >= 1.23.0+
2. kubelet version >= 1.23.0+

## 1. Deploy PhoenixAI Operator

It includes the following main steps:

1. Apply the PhoenixAI CRDs.
2. Deploy PhoenixAI Operator.

### 1.1. Apply the PhoenixAI CRDs

PhoenixAICluster and PhoenixAIWarehouse are the custom resource definitions (CRDs) that define a PhoenixAI cluster and
an additional compute warehouse. They are used to create and manage those objects by using the PhoenixAI Operator.
Please refer to [api.md](../api.md) for their detailed description.

Apply **both** CRDs before you deploy the operator. The operator decides whether to run the warehouse controller once,
at startup, so a warehouse CRD applied later is ignored until the operator is restarted — applying both now avoids
that. Installing the warehouse CRD costs nothing if you never create a warehouse.

```bash
kubectl apply -f https://raw.githubusercontent.com/celerdata/phoenixai-kubernetes-operator/main/deploy/phoenixdata.ai_phoenixaiclusters.yaml
kubectl apply -f https://raw.githubusercontent.com/celerdata/phoenixai-kubernetes-operator/main/deploy/phoenixdata.ai_phoenixaiwarehouses.yaml
```

### 1.2. Deploy PhoenixAI Operator

You can choose to deploy the PhoenixAI Operator by using a default configuration file or a custom configuration file.

1. **Deploy the PhoenixAI Operator by using a default configuration file.**

   ```bash
   kubectl apply -f https://raw.githubusercontent.com/celerdata/phoenixai-kubernetes-operator/main/deploy/operator.yaml
   ```

   The PhoenixAI Operator is deployed to the namespace `phoenixai` and manages all PhoenixAI clusters under all
   namespaces. After `operator.yaml` is applied, The following resources will be created:

    ```bash
    namespace/phoenixai created
    serviceaccount/phoenixai created
    clusterrole.rbac.authorization.k8s.io/kube-anywhere-operator created
    clusterrole.rbac.authorization.k8s.io/kube-anywhere-operator-pvc-expansion created
    clusterrolebinding.rbac.authorization.k8s.io/kube-anywhere-operator created
    clusterrolebinding.rbac.authorization.k8s.io/kube-anywhere-operator-pvc-expansion created
    role.rbac.authorization.k8s.io/phoenixai-leader-election-role created
    rolebinding.rbac.authorization.k8s.io/phoenixai-leader-election-rolebinding created
    service/kube-anywhere-operator-api created
    deployment.apps/kube-anywhere-operator created
    ```

   Two of those are worth knowing by name. `kube-anywhere-operator-api` is the operator's gRPC API
   Service on port 9090 — nothing else on this page uses it, but
   [section 4](#4-install-the-anywhere-console) does, because that is what the Anywhere console
   reads clusters through. The `kube-anywhere-operator-pvc-expansion` ClusterRole is what lets the
   operator grow persistent volumes later; see
   [Expand a persistent volume](../Operate/expand_persistent_volume_howto.md).

2. **Deploy the PhoenixAI Operator by using a custom configuration file.** By default, the Operator is configured to
   install in the phoenixai namespace. To use the Operator in a custom namespace, download the Operator manifest and
   substitute all instances of namespace to your custom namespace.
    1. Download the configuration file **operator.yaml**, which is used to deploy the PhoenixAI Operator.

       ```bash
       curl -O https://raw.githubusercontent.com/celerdata/phoenixai-kubernetes-operator/main/deploy/operator.yaml
       ```

    2. Modify the configuration file **operator.yaml** to suit your needs.
    3. Deploy the PhoenixAI Operator.

       ```bash
       kubectl apply -f operator.yaml
       ```

3. **Check the running status of the PhoenixAI Operator.** If the pod is in the `Running` state and all containers
   inside the pod are `READY`, the PhoenixAI Operator is running as expected.

    ```bash
    $ kubectl -n phoenixai get pods
    NAME                                      READY   STATUS    RESTARTS   AGE
    kube-anywhere-operator-5499bc6d59-xdcpq   1/1     Running   0          5m6s
    ```

## 2. Deploy PhoenixAI Cluster

You need to prepare a separate yaml file to deploy the PhoenixAI FE and CN components. You can directly use
the [sample configuration files](https://github.com/CelerData/phoenixai-kubernetes-operator/tree/main/examples/phoenixai)
provided by PhoenixAI to deploy a PhoenixAI cluster (an object instantiated by using the custom resource PhoenixAI
Cluster). For example, you can use **deploy_a_phoenixai_cluster_running_in_shared_data_mode.yaml** to deploy a
PhoenixAI cluster that consists of three FE nodes and one CN node. Note that you need to download and edit this
file first to specify the details of your shared storage in the FE ConfigMap.

```bash
kubectl apply -f deploy_a_phoenixai_cluster_running_in_shared_data_mode.yaml
```

The following table describes a few important fields in the **deploy_a_phoenixai_cluster_running_in_shared_data_mode.yaml** file.

| **Field** | **Description**                                                                                                                                                                                                                                    |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Kind      | The resource type of the object. The value must be `PhoenixAICluster`.                                                                                                                                                                             |
| Metadata  | Metadata, in which the following sub-fields are nested:<ul><li>`name`: the name of the object. Each object name uniquely identifies an object of the same resource type.</li><li>`namespace`: the namespace to which the object belongs.</li></ul> |
| Spec      | The expected status of the object. Valid values are `phoenixAIFeSpec` and `phoenixAICnSpec`.                                                                                                                                                       |

You can also deploy the PhoenixAI cluster by using a modified configuration file. For supported fields and detailed
descriptions, see [api.md](../api.md).

Deploying the PhoenixAI cluster takes a while. During this period, you can use the
command `kubectl -n phoenixai get pods` to check the starting status of the PhoenixAI cluster. If all the pods are in
the `Running` state and all containers inside the pods are `READY`, the PhoenixAI cluster is running as expected.

> **NOTE**
>
> If you customize the namespace in which the PhoenixAI cluster is located, you need to replace `phoenixai` with the
> name of your customized namespace.

```bash
$ kubectl -n phoenixai get pods
NAME                                  READY   STATUS    RESTARTS   AGE
phoenixai-controller-65bb8679-jkbtg   1/1     Running   0          22h
phoenixaicluster-sample-cn-0          1/1     Running   0          23h
phoenixaicluster-sample-fe-0          1/1     Running   0          21h
phoenixaicluster-sample-fe-1          1/1     Running   0          21h
phoenixaicluster-sample-fe-2          1/1     Running   0          22h
```

> **Note**
>
> If some pods cannot be up after a long period of time, you can use `kubectl logs -n phoenixai <pod_name>` to view the
> log information or use `kubectl -n phoenixai describe pod <pod_name>` to view the event information to address the
> problem.

## 3. Manage PhoenixAI Cluster

### 3.1. Access PhoenixAI Cluster

The components of the PhoenixAI cluster can be accessed through their associated Services, such as the FE Service. For
detailed descriptions of Services and their access addresses,
see [api.md](../api.md)
and [Services](https://kubernetes.io/docs/concepts/services-networking/service/).

The following table describes the FE Services of the PhoenixAI cluster. `phoenixaicluster-sample-fe-service` is the
Service that user can configure it from PhoenixAICluster CR, and user should only use it to access the PhoenixAI.
`phoenixaicluster-sample-fe-search` is the internal Service that is used by PhoenixAI Cluster to discover the FE nodes.

```bash
$ kubectl get svc
NAME                                 TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)                               AGE
phoenixaicluster-sample-fe-search    ClusterIP   None           <none>        9030/TCP                              76s
phoenixaicluster-sample-fe-service   ClusterIP   10.96.26.146   <none>        8030/TCP,9020/TCP,9030/TCP,9010/TCP   76s
```

#### 3.1.1. Access PhoenixAI Cluster from within Kubernetes Cluster

From within the Kubernetes cluster, the PhoenixAI cluster can be accessed through the FE Service's ClusterIP.

1. Obtain the internal virtual IP address `CLUSTER-IP` and port `PORT(S)` of the FE Service.

    ```Bash
    $ kubectl -n phoenixai get svc 
    NAME                                 TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)                               AGE
    phoenixaicluster-sample-cn-search    ClusterIP   None           <none>        9050/TCP                              66s
    phoenixaicluster-sample-cn-service   ClusterIP   10.96.86.207   <none>        9060/TCP,8040/TCP,9050/TCP,8060/TCP   66s
    phoenixaicluster-sample-fe-search    ClusterIP   None           <none>        9030/TCP                              2m27s
    phoenixaicluster-sample-fe-service   ClusterIP   10.96.26.146   <none>        8030/TCP,9020/TCP,9030/TCP,9010/TCP   2m27s
    ```

2. Access the PhoenixAI cluster by using the MySQL client from within the Kubernetes cluster.

   ```Bash
   mysql -h 10.100.162.xxx -P 9030 -uroot
   ```

   Upon deploying a fresh PhoenixAI cluster, the `root` user's password remains unset, potentially posing a security
   risk. See [Change root user password](../Configure/change_root_password_howto.md) for details on how to set
   the `root` user's password.

#### 3.1.2. Access PhoenixAI Cluster from outside Kubernetes Cluster by using LoadBalancer or NodePort

From outside the Kubernetes cluster, you can access the PhoenixAI cluster through the FE Service's LoadBalancer or
NodePort. This topic uses LoadBalancer as an example:

1. Run the command `kubectl -n phoenixai edit pac phoenixaicluster-sample` to update the PhoenixAI cluster configuration
   file, and add `service` field to the `phoenixAIFeSpec` field.

    ```YAML
    spec:
      phoenixAIFeSpec:
        service:            
          type: LoadBalancer # specified as LoadBalancer
    ```

2. Obtain the IP address `EXTERNAL-IP` and port `PORT(S)` that the FE Service exposes to the outside.

    ```Bash
    $ kubectl -n phoenixai get svc
    NAME                                 TYPE           CLUSTER-IP       EXTERNAL-IP                                                              PORT(S)                                                       AGE
    phoenixaicluster-sample-cn-search    ClusterIP      None           <none>        9050/TCP                                                      6m39s
    phoenixaicluster-sample-cn-service   ClusterIP      10.96.86.207   <none>        9060/TCP,8040/TCP,9050/TCP,8060/TCP                           6m39s
    phoenixaicluster-sample-fe-search    ClusterIP      None           <none>        9030/TCP                                                      8m
    phoenixaicluster-sample-fe-service   LoadBalancer   10.96.26.146   a7509284bf3784983a596c6eec7fc212-618xxxxxx.us-west-2.elb.amazonaws.com     8030:30028/TCP,9020:32241/TCP,9030:32640/TCP,9010:32384/TCP   8m
    ```

3. Log in to your machine host and access the PhoenixAI cluster by using the MySQL client.

    ```Bash
    mysql -h a7509284bf3784983a596c6eec7fc212-618xxxxxx.us-west-2.elb.amazonaws.com -P9030 -uroot
    ```

#### 3.1.3. Access PhoenixAI Cluster from outside Kubernetes Cluster by port forwarding

From outside the Kubernetes cluster, you can access the PhoenixAI cluster through the FE Service's port forwarding.

1. Make sure that you have installed the `kubectl` command-line tool and configured access to the Kubernetes cluster.
2. Run the command `kubectl -n phoenixai port-forward service/phoenixaicluster-sample-fe-service 9030:9030` to forward
   local port `9030` to FE Service's port `9030`.
3. Access the PhoenixAI cluster by using the MySQL client.

    ```Bash
    mysql -h 127.0.0.1 -P9030 -uroot
    ```

### 3.2. Upgrade PhoenixAI Cluster

#### 3.2.1. Upgrade CN nodes

Run the following command to specify a new CN image file, such as `us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/cn-ubuntu:<database-image-tag>`:

```bash
kubectl -n phoenixai patch phoenixaicluster phoenixaicluster-sample --type='merge' -p '{"spec":{"phoenixAICnSpec":{"image": us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/cn-ubuntu:<database-image-tag>"}}}'
```

#### 3.2.2. Upgrade FE nodes

Run the following command to specify a new FE image file, such as `us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/fe-ubuntu:<database-image-tag>`:

```bash
kubectl -n phoenixai patch phoenixaicluster phoenixaicluster-sample --type='merge' -p '{"spec":{"phoenixAIFeSpec":{"image": us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/fe-ubuntu:<database-image-tag>"}}}'
```

The upgrade process lasts for a while. You can run the command `kubectl -n phoenixai get pods` to view the upgrade
progress.

### 3.3. Scale PhoenixAI cluster

This topic takes scaling out the CN and FE clusters as examples.

#### 3.3.1. Scale out CN cluster

Run the following command to scale out the CN cluster to 9 nodes:

```bash
kubectl -n phoenixai patch phoenixaicluster phoenixaicluster-sample --type='merge' -p '{"spec":{"phoenixAICnSpec":{"replicas":9}}}'
```

#### 3.3.2. Scale out FE cluster

Run the following command to scale out the FE cluster to 4 nodes:

```bash
kubectl -n phoenixai patch phoenixaicluster phoenixaicluster-sample --type='merge' -p '{"spec":{"phoenixAIFeSpec":{"replicas":4}}}'
```

The scaling process lasts for a while. You can use the command `kubectl -n phoenixai get pods` to view the scaling
progress.

**Add cautions on scale-in FE nodes**:

FE nodes can be scaled-in, but there are some limitations:

1. FE nodes can only be scaled-in step by step. If the last scale-in operation is not completed, the next scale-in
   operation cannot be performed.
2. Each time less than half of the nodes can be scaled-in.
3. You can't do 3->1 scale in.

### 3.4. Using ConfigMap to configure your PhoenixAI cluster

The official images contains default application configuration file, however, they can be overwritten by configuring
kubernetes configmap deployment crd.

You can generate the configmap from an PhoenixAI configuration file.
Below is an example of creating a Kubernetes configmap `fe-config-map` from the `fe.conf` configuration file. You can do
the same with CN.

```console
# create fe-config-map from starrocks/fe/conf/fe.conf file
kubectl create configmap fe-config-map --from-file=starrocks/fe/conf/fe.conf
```

Once the configmap is created, you can reference the configmap in the yaml file.
For example:

```yaml
# fe use configmap example
phoenixAIFeSpec:
  configMapInfo:
    configMapName: fe-config-map
    resolveKey: fe.conf
# cn use configmap example
phoenixAICnSpec:
  configMapInfo:
    configMapName: cn-config-map
    resolveKey: cn.conf
```

## 4. Install the Anywhere console

The PhoenixAI Anywhere console — the web UI for cluster inventory, health checks, monitoring,
license and usage — is delivered **only as a Helm chart**. There are no standalone manifests to
`kubectl apply`: the console's config Secret, StatefulSet, Services and RBAC are all rendered by
the chart from your values.

The console runs independently of how the operator was installed, so an operator and cluster
deployed from the manifests above can still get the console. Two ways to add it:

1. **Install the standalone `anywhere` chart with Helm (recommended).** The standalone chart
   exists exactly for installing the console next to an operator that is managed separately:

   ```bash
   helm repo add phoenixai https://celerdata.github.io/phoenixai-kubernetes-operator
   helm repo update phoenixai
   helm install anywhere phoenixai/anywhere --namespace phoenixai -f console-values.yaml
   ```

   The settings to put in `console-values.yaml` are the `anywhere.*` values from
   [Install with Helm, Step 3](./install_with_helm.md#step-3--set-the-root-password-and-write-your-values-file),
   **without the `anywhere.` prefix**: on the standalone chart, `anywhere.operatorApiAddrs`
   becomes `operatorApiAddrs`, `anywhere.dependencies.s3` becomes `dependencies.s3`, and so on.
   The console reads clusters through the operator's gRPC API, which the `operator.yaml` from
   [section 1](#12-deploy-phoenixai-operator) already enables — point `operatorApiAddrs` at the
   `kube-anywhere-operator-api` Service it created. A working file is short:

   ```yaml
   # console-values.yaml
   operatorApiAddrs:
     - kube-anywhere-operator-api.phoenixai:9090

   # Required. The console image is an enterprise build in a private registry, and the
   # chart pulls it with no credentials unless you name a secret here. Without this the
   # console pod sits in ImagePullBackOff.
   imagePullSecrets:
     - name: phoenixai-registry

   # Required. Without a bucket the chart refuses to render at all, because the console
   # keeps query profiles and support bundles in object storage.
   dependencies:
     s3:
       bucket: <bucket>
       region: <region>
       accessKey: <access-key>
       secretKey: <secret-key>

   # Optional, but the default is admin/admin — set it now rather than after the console
   # is reachable.
   admin:
     users:
       admin: "<console-password>"
   ```

   `phoenixai-registry` is the pull secret; create it in the console's namespace if you do not
   already have one there — see
   [Install with Helm, Step 1](./install_with_helm.md#step-1--get-the-images-and-teach-kubernetes-to-pull-them)
   for how to get the key file and turn it into a secret. Use whatever name you gave it.

   If you deployed the operator into a namespace other than `phoenixai` — the custom
   configuration file in [section 1.2](#12-deploy-phoenixai-operator) — use that namespace in
   the address instead of `.phoenixai`.

2. **Render the chart to YAML and apply it with kubectl.** If your rollout process only permits
   applying manifests, use Helm as a client-side renderer — no Helm access to the Kubernetes
   cluster is needed:

   ```bash
   helm template anywhere phoenixai/anywhere --namespace phoenixai -f console-values.yaml > console.yaml
   kubectl apply -n phoenixai -f console.yaml
   ```

   Be aware of what this gives up: `helm template` records no release in the cluster, so
   `helm upgrade`, `helm rollback` and `helm uninstall` will not work later. Every settings
   change means re-rendering and re-applying, and removal means deleting the rendered objects
   yourself. Prefer option 1 unless a policy rules it out.

## FAQ

**Issue description:** When a custom resource PhoenixAICluster is installed using `kubectl apply -f xxx`, an error is
returned `The CustomResourceDefinition 'phoenixaiclusters.phoenixdata.ai' is invalid: metadata.annotations: Too long: must have at most 262144 bytes`.

**Cause analysis:** Whenever `kubectl apply -f xxx` is used to create or update resources, a metadata
annotation `kubectl.kubernetes.io/last-applied-configuration` is added. This metadata annotation is in JSON format and
records the *last-applied-configuration*. `kubectl apply -f xxx` is suitable for most cases, but when the object itself
is large, that copy can push the annotation past the limit.

The PhoenixAICluster CRD is close to that line. It ships at roughly 242 KB against the 262144-byte limit — it does fit,
but with under 8% to spare, and only because the released CRDs are generated with field descriptions stripped. Any
growth can put it back over, and `kubectl create` / `kubectl replace` do not write that annotation at all, so they are
the safe choice regardless of the current margin.

**Solution:** If you install the custom resource PhoenixAICluster for the first time, it is recommended to
use `kubectl create -f xxx`. If the custom resource PhoenixAICluster is already installed in the environment, and you
need to update its configuration, it is recommended to use `kubectl replace -f xxx`.
