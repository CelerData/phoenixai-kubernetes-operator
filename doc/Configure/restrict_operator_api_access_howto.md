---
sidebar_label: Restrict access to the operator API
sidebar_position: 10
title: Restrict access to the operator API
description: Put a NetworkPolicy in front of the operator so that only the Anywhere console can reach its gRPC query API, while the operator's own connections stay untouched.
---

# Restrict access to the operator API

The operator serves a read-only gRPC query API (`enableApiServer`, port `apiServerPort`, 9090 by
default) that the Anywhere console reads every cluster's state through. Inside a Kubernetes
cluster any pod can open a connection to any other pod unless something says otherwise, so by
default that port is reachable from every workload in the cluster, whoever runs it.

The chart can render a **NetworkPolicy** that closes it: the operator pod then accepts
connections on the API port only from the console's pods, plus connections to its health port
(8081, which serves nothing but `/healthz` and `/readyz`) so that the kubelet's probes keep
working. Nothing else inbound is admitted. The policy says nothing about outbound traffic, so the
operator's own connections — to the Kubernetes API server, to the FE's MySQL port, to DNS — work
as before.

:::caution Your network plugin has to enforce it
A NetworkPolicy is an ordinary Kubernetes object that the **network plugin** of the cluster
enforces. A plugin that implements it (Calico, Cilium, Azure Network Policy on AKS, the VPC CNI
with network policy enabled on EKS, …) applies it; one that does not accepts the object and
ignores it, silently. Before relying on the policy, confirm your plugin enforces it — the
[check below](#check-that-it-is-enforced) does that.
:::

## Turn it on

```yaml
# my-values.yaml
operator:
  phoenixAIOperator:
    enableApiServer: true
    networkPolicy:
      enabled: true
```

With only `enabled`, the policy admits the console pods **in the operator's own namespace** —
the pods carrying the label `app: kube-anywhere-console`, which is the console's name in the
chart (`anywhere.nameOverride`). Apply with the usual `helm upgrade --install … -f my-values.yaml`;
no pod restarts, the policy takes effect as soon as it is created.

**The console in another namespace.** One console can serve operators in several namespaces,
and then it is not in the operator's. List the namespaces its pods may call from:

```yaml
operator:
  phoenixAIOperator:
    networkPolicy:
      enabled: true
      apiClientNamespaces: ["anywhere"]   # where the console runs
```

A namespace is matched by its name (the `kubernetes.io/metadata.name` label every namespace
carries), so nothing has to be labelled by hand. Leaving the list empty means "this namespace
only"; listing namespaces replaces that, so include the operator's own namespace in the list if
a console runs there too.

**A console under another name.** If `anywhere.nameOverride` was changed, name its pods'
label instead:

```yaml
      apiClientPodLabels:
        app: <your nameOverride>
```

**Anything else that must reach the operator** — a Prometheus scraping its metrics port (8080),
say — needs a rule of its own, appended as written:

```yaml
      extraIngress:
        - ports: [{port: 8080, protocol: TCP}]
          from:
            - namespaceSelector:
                matchLabels: {kubernetes.io/metadata.name: monitoring}
```

## Check that it is enforced

The check connects to the API port from two throwaway pods that are **not** the console — one in
another namespace, one unlabelled in the operator's own namespace — and you run it **twice**:
once before enabling the policy, once after. A failed connection alone proves nothing, because a
wrong address fails too; only `REACHABLE` before and `BLOCKED` after shows that the policy is
what refuses the connection.

Set the three variables to your installation (the Service is `<operator nameOverride>-operator-api`,
`kube-anywhere-operator-api` by default), then define the probe. It connects to the Service's
cluster IP and port as read from the cluster, so no DNS name or port is guessed:

```bash
OP_NS=phoenixai                      # the operator's namespace
API_SVC=kube-anywhere-operator-api   # the operator's API Service
OTHER_NS=default                     # any namespace without a console

TARGET="$(kubectl -n "$OP_NS" get svc "$API_SVC" -o jsonpath='{.spec.clusterIP} {.spec.ports[0].port}')"
echo "probing $TARGET"   # must print an IP and a port; stop here if it does not

probe() { # probe <namespace>
  kubectl -n "$1" run np-probe --restart=Never --image=busybox:1.36 -- \
    sh -c "nc -z -w 5 $TARGET && echo REACHABLE || echo BLOCKED" >/dev/null
  kubectl -n "$1" wait --for=jsonpath='{.status.phase}'=Succeeded pod/np-probe --timeout=60s >/dev/null
  echo "from $1: $(kubectl -n "$1" logs np-probe)"
  kubectl -n "$1" delete pod np-probe >/dev/null
}

probe "$OTHER_NS"; probe "$OP_NS"
```

1. **Before enabling the policy**, both lines must say `REACHABLE`. This proves the probe reaches
   the API at all; if either says `BLOCKED` now, the address or port is wrong (or something else
   already blocks it) and the check after enabling would mean nothing.
2. **After enabling it**, run `probe "$OTHER_NS"; probe "$OP_NS"` again: both must say `BLOCKED`.

`REACHABLE` after enabling means the API is still open to that pod — either the plugin does not
enforce the policy (see the caution above), or another NetworkPolicy also admits it.
NetworkPolicies add up: a pod reachable under any policy that selects it stays reachable, so a
namespace-wide "allow traffic within the namespace" policy keeps the API open to every pod in
the operator's namespace. List what else selects the operator with
`kubectl -n "$OP_NS" get networkpolicy` and narrow or remove the permissive one.

Then open the console: its cluster list must still show every cluster, with its phase. The
console reads that list from the operator's API, so a populated list is the proof that the
console's own connections are admitted. The operator pod itself stays `Running` and `1/1`
throughout: its probes are admitted by the policy's health-port rule.

## What the policy does not do

- **It does not close the health port.** Port 8081 stays open to every source: the kubelet calls
  it from the node's own address, which no pod or namespace selector can name, and it serves
  only `/healthz` and `/readyz`.
- **It does not authenticate.** It decides which pods can open a connection, not who they are;
  a pod that matches the selector is trusted.
- **It does not encrypt.** The API is served in plaintext inside the cluster; the policy keeps
  other workloads from connecting, not from observing traffic on a shared network they already
  control.
- **It does not limit the operator's outbound traffic.** A cluster that also restricts egress
  must allow the operator to reach the Kubernetes API server, every FE's query port (9030) and
  HTTP port (8030), and the cluster's DNS; the console additionally needs the API port above, the
  CN webserver port (8040), the object store, and — for Azure identities — Microsoft Entra ID.
  Those addresses are specific to each installation, which is why the chart renders no egress
  rule.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| The console shows no clusters right after enabling the policy | The console runs in a namespace the policy does not list. Add it to `apiClientNamespaces` |
| The console shows no clusters, and its pods' `app` label is not `kube-anywhere-console` | `anywhere.nameOverride` was changed; set `apiClientPodLabels` to match |
| A probe prints `BLOCKED` before the policy is enabled | The probe does not reach the API: check `OP_NS` and `API_SVC`, and that the operator pod is `Running`. Fix this first — a `BLOCKED` after enabling means nothing until the probe is `REACHABLE` without the policy |
| A probe prints `REACHABLE` after the policy is enabled | Either the network plugin does not enforce NetworkPolicy — enable its policy mode (for AKS: a cluster created with `--network-policy azure` or `cilium`), or install Calico / Cilium — or another NetworkPolicy in the operator's namespace also admits that pod; `kubectl -n <namespace> get networkpolicy` lists them |
| A Prometheus scrape of the operator's metrics stops | Add an `extraIngress` rule for port 8080 from the scraper's namespace, as above |
