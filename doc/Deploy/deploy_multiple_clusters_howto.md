---
sidebar_label: Multiple clusters
sidebar_position: 10
---

# Deploy Multiple Clusters

If you have deployed a PhoenixAI cluster by YAML manifests, you can write a new PhoenixAICluster CR YAML to deploy
another PhoenixAI cluster.

We have split the `kube-anywhere` chart into two subcharts: `operator` and `phoenixai`. Installing `kube-anywhere` is
equivalent to installing both `operator` and `phoenixai` subcharts, and uninstalling `kube-anywhere` is equivalent to
uninstalling both `operator` and `phoenixai` subcharts.

If you have deployed a PhoenixAI cluster by `operator` + `phoenixai` helm chart, you can deploy another PhoenixAI
cluster by the `phoenixai` helm chart.

If you have deployed a PhoenixAI cluster by `kube-anywhere` helm chart, you have two ways to deploy another PhoenixAI
cluster.

1. Deploy another PhoenixAI cluster by `phoenixai` helm chart.
2. Deploy another PhoenixAI cluster by `kube-anywhere` Helm chart.

This document will guide you through the process of deploying multiple PhoenixAI clusters by `kube-anywhere` helm
chart.

## Deploy another PhoenixAI cluster by `kube-anywhere` Helm chart

By default, the operator will watch all namespaces. If you want to deploy another PhoenixAI cluster
by `kube-anywhere`, you should limit `each operator` to watch a specific namespace.

```yaml
operator:
  phoenixAIOperator:
    watchNamespace: "your-namespace"
```

> you can also add `--set operator.phoenixAIOperator.watchNamespace="your-namespace"` to the `helm` command which has
> higher priority.

So, the steps to deploy multiple PhoenixAI clusters by `kube-anywhere` are:

1. update `values.yaml` file of the first deployed PhoenixAI cluster to limit the operator to watch a specific
   namespace.
2. upgrade the first PhoenixAI cluster.
3. install the second PhoenixAI cluster by the same `kube-anywhere` chart, and do not forget to specify the namespace.
