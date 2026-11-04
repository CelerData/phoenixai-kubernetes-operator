# Deploy the FE Proxy

The issue is that when the load client residents in a different network other than FE/CN's private network. FE's HTTP
307 brings CN's private network address to the client who does not recognize and can't process the redirection.

FE Proxy is a reverse proxy that can be used to solve this problem. It is a nginx server that listens on port 8080 and
proxies the HTTP request to FE and CN, including the HTTP 307 redirection.
> You need to switch the traffic, that is, the request sent to FE HTTP Port (8030) is sent to FE Proxy HTTP Port (8080).

**Note: FE proxy solves the data transfer link through HTTP protocol, non-HTTP traffic can't be proxied by the FE proxy
such as the spark connector reading data directly from CN nodes through thrift protocol.**

The following solutions for other read and write data scenarios are listed (will continue to be supplemented):

1. If you are unloading (reading) the data with the spark connector outside of k8s, a workaround
   is [INSERT INTO FILES](https://docs.starrocks.io/docs/unloading/unload_using_insert_into_files/), and then use spark
   to load data from the exported files.

## Deploy Fe Proxy Using Helm

If you install PhoenixAI with Helm, you can add the following configuration to the `values.yaml` file:

For `kube-anywhere` Helm chart:

```yaml
phoenixai:
  phoenixAIFeProxySpec:
    enabled: true
    replicas: 1
    # set the resolver for nginx server, default kube-dns.kube-system.svc.cluster.local
    resolver: ""
    resources:
      limits:
        cpu: 1
        memory: 2Gi
      requests:
        cpu: 1
        memory: 2Gi
    service:
      type: NodePort
      ports:
        - name: http-port   # fill the name from the fe proxy service ports
          containerPort: 8080
          nodePort: 30180
          port: 8080
```

For `phoenixai` Helm chart:

```yaml
phoenixAIFeProxySpec:
  enabled: true
  replicas: 1
  # set the resolver for nginx server, default kube-dns.kube-system.svc.cluster.local
  resolver: ""
  resources:
    limits:
      cpu: 1
      memory: 2Gi
    requests:
      cpu: 1
      memory: 2Gi
  service:
    type: NodePort
    ports:
      - name: http-port   # fill the name from the fe proxy service ports
        containerPort: 8080
        nodePort: 30180
        port: 8080
```

Please
see https://github.com/CelerData/phoenixai-kubernetes-operator/blob/main/helm-charts/charts/kube-anywhere/values.yaml
for more details about how to configure `phoenixAIFeProxySpec`.

## Deploy Fe Proxy Using PhoenixAICluster CR

If you install PhoenixAI with PhoenixAICluster CR yaml, please see
[deploy_a_phoenixai_cluster_with_fe_proxy.yaml](../../examples/phoenixai/deploy_a_phoenixai_cluster_with_fe_proxy.yaml)

## Load through the proxy

Once the proxy is running, `kubectl -n <namespace> get phoenixaicluster` reports `FEPROXYSTATUS`
as `running`, and its Service is named `<cluster-name>-fe-proxy-service`.

The load command is an ordinary Stream Load with **one change: the port**. Send it to the proxy's
`8080` rather than a coordinator's `8030` — that single substitution is what this whole page exists
for. Nothing else about the request changes.

Reach the proxy however your cluster exposes it. A `NodePort` or an Ingress is what you would use in
earnest; for a quick try on your own machine a port forward is enough:

```bash
kubectl -n <namespace> port-forward svc/<cluster-name>-fe-proxy-service 8080:8080
```

Then load, against `localhost:8080`:

```bash
curl --location-trusted -u <user>:<password> \
    -T ./data.csv \
    -H "label:my-load-0" \
    -H "column_separator:," \
    -H "skip_header:1" \
    -H "enclose:\"" \
    -H "columns: col_a, col_b, col_c" \
    -XPUT http://localhost:8080/api/<database>/<table>/_stream_load
```

`--location-trusted` matters: it lets curl carry the credentials through the redirect the proxy
resolves. A successful load answers with `"Status": "Success"` and the row counts it took; a
rejected one names an `ErrorURL` you can fetch for the offending rows.

Sent to `8030` instead, the same command fails with a message naming a compute node's in-cluster
address — `Could not resolve host: <cluster>-cn-0.<cluster>-cn-search.<namespace>.svc.cluster.local`
— which is the symptom this proxy removes.

## A worked example

The quick starts install the proxy and then use it to load two real datasets and query them:

- [Quick start with Amazon S3](../GetStarted/quickstart_s3.md)
- [Quick start with MinIO](../GetStarted/quickstart_minio.md)
