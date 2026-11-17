---
sidebar_label: Least privilege to deploy
sidebar_position: 20
title: Least privilege to deploy
---

# Least Privilege To Deploy PhoenixAI

You can install the PhoenixAI operator and PhoenixAI cluster by kubectl or helm. No matter which way you choose, you
may need the following permissions:

> Note: Operator will use its own service account, cluster role and cluster role binding to create and manage PhoenixAI

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: install-phoenixai-rb
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: install-phoenixai-role
subjects:
  - kind: ServiceAccount
    name: your-sa-name
    namespace: your-namespace

---

apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: install-phoenixai-role
rules:
  - apiGroups:
      - ""
    resources:
      - secrets
      - serviceaccounts
      - configmaps
    verbs:
      - '*'
  - apiGroups:
      - rbac.authorization.k8s.io
    resources:
      - clusterrolebindings
      - rolebindings
      - clusterroles
      - roles
    verbs:
      - '*'
  - apiGroups:
      - apps
    resources:
      - deployments
    verbs:
      - '*'
  - apiGroups:
      - monitoring.coreos.com
    resources:
      - servicemonitors
    verbs:
      - '*'
  - apiGroups:
      - phoenixdata.ai
    resources:
      - phoenixaiclusters
      - phoenixaiwarehouses
    verbs:
      - '*'
  - apiGroups:
      - apiextensions.k8s.io
    resources:
      - customresourcedefinitions
    verbs:
      - '*'
  - apiGroups:
      - batch
    resources:
      - jobs
    verbs:
      - '*'
  # The operator's own ClusterRole grants policy/poddisruptionbudgets (the auto-PDB feature is
  # enabled by default in the Helm chart and the released operator.yaml). Kubernetes prevents
  # privilege escalation: to create that ClusterRole, the installing account must hold these
  # permissions as well.
  - apiGroups:
      - policy
    resources:
      - poddisruptionbudgets
    verbs:
      - '*'
  # Only needed when the PVC volume expansion feature is enabled
  # (phoenixAIOperator.enablePVCExpansion / enablePVCExpansionRBAC): the operator's RBAC then
  # additionally grants persistentvolumeclaims, storageclasses, and events.
  # - apiGroups:
  #     - ""
  #   resources:
  #     - persistentvolumeclaims
  #     - events
  #   verbs:
  #     - '*'
  # - apiGroups:
  #     - storage.k8s.io
  #   resources:
  #     - storageclasses
  #   verbs:
  #     - get
  #     - list
  #     - watch
```
