---
sidebar_position: 1
---

# Initializing the Root User Password in PhoenixAI

Upon deploying a fresh PhoenixAI cluster, the `root` user's password remains unset, potentially posing a security risk.
This guide delineates the process to establish a root password when a new installation.

> Note that this only works for helm install, can't use it in helm upgrade

## Prerequisites

- Ensure that you have installed the Kubernetes cluster. v1.23.0+ is recommended.
- Ensure that you have installed the [Helm](https://helm.sh/) package manager. 3.0.0+ is recommended.
- Ensure the helm chart repo for PhoenixAI is added.
  See [Step 2 — Get the chart](../Deploy/install_with_helm.md#step-2--get-the-chart).

In this guide, we will use `phoenixai/kube-anywhere` chart to deploy both PhoenixAI operator and cluster.

## 1. Download the values.yaml file for the kube-anywhere chart

The values.yaml file contains the default configurations for the PhoenixAI Operator and the PhoenixAI cluster.

```Bash
helm show values phoenixai/kube-anywhere > values.yaml
```

The following is a snippet of the values.yaml file:

```yaml
phoenixai:
  # This configuration is used to modify the root password during initial deployment.
  # After deployment is completed, it won't take effect to modify the password here and to do a `helm upgrade`.
  # It also supports providing secret name that contains password, using the password in the secret instead of the plaintext in the values.yaml.
  # When both password and passwordSecret are set, only passwordSecret takes effect.
  initPassword:
    enabled: false
    password: ""
    # The secret name that contains password, the key of the secret is "password", and you should create it first.
    passwordSecret: ""
```

## 2. Initialize the root password

Configure a YAML File for Custom Settings (for instance, `my-values.yaml`). There are two ways to
initialize the root password. You can choose one of them.

### 2.1. Setting the Root User Password By plaintext

We use `mysql_password` serves as a placeholder for the root user's password. You can substitute this
with any preferred password.

To initialize the root password, embed the following snippet:

```yaml
phoenixai:
  initPassword:
    enabled: true
    password: "mysql_password"
```

### 2.2. Setting the Root User Password By Secret

You can also use a secret to set the root password. The secret must be created before deploying the helm chart.

> Note the key of the secret must be `password`.

```bash
kubectl create secret generic phoenixai-root-password --from-literal=password=mysql_password
```

To initialize the root password, embed the following snippet:

```yaml
phoenixai:
  initPassword:
    enabled: true
    passwordSecret: phoenixai-root-password
```

## 3. Deploy the PhoenixAI Operator and the PhoenixAI cluster

Execute Deployment with Custom Specifications. Run the subsequent command to deploy the PhoenixAI Operator and the
PhoenixAI cluster.

```shell
helm install -f my-values.yaml kube-anywhere phoenixai/kube-anywhere
```

## 4. Access Your Cluster

```bash
# in one terminal
kubectl port-forward service/kube-anywhere-fe-service 9030:9030

# in another terminal
mysql -h 127.0.0.1 -P 9030 -u root -p mysql_password
```
