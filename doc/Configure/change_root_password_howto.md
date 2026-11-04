---
sidebar_position: 2
---

# Change root user password

The password is empty for the `root` user when deploying a PhoenixAI cluster from fresh installation. This can be a
security concern. This document describes steps to change root password and still the operator can manage the cluster
correctly.

In the following examples, `mysql_password` is taken as the password for the root user, it can be replaced with any
password chosen for the root.

People are not the only ones who log in as root. Three other parties use the root password, and
every one of them reads it from the `MYSQL_PWD` entry that step 2 declares:

- **The FE and CN containers.** Their entrypoint scripts log in as root when a pod starts, to find
  the leader and join the cluster (`ALTER SYSTEM ADD FOLLOWER`, registering a CN).
- **The operator.** It logs in before it touches a CN workload, and when it scales in or deletes.
  Section 4 describes what you see when its password and the FE disagree.
- **PhoenixAI Anywhere.** The console reads the same `MYSQL_PWD` entry for everything it does on
  the cluster as root, query-history collection above all. Section 5 describes what breaks in the
  console while the two disagree, and what a signed-in console user sees when their own password
  changes.

Steps 1 and 2 are one maintenance action: do them back to back, and do not restart, scale or
upgrade FE or CN pods in between. Read sections 4 to 6 before the first rotation so you know what
to expect in the gap, and section 2.3 if the cluster already has a root password and you are
rotating it.

## Prerequisites

**A PhoenixAI cluster is deployed and up with empty root password by the operator.**

## 1. Change the password for root user

Connect to PhoenixAI FE with a MySQL client and change the root user password.

```SQL
mysql
-h <FE_IP/FE_SERVICE> -P 9030 -u root

# change root password to `mysql_password`
MySQL [(none)]> SET PASSWORD = PASSWORD('mysql_password');
```

## 2. Inject MYSQL_PWD environment variable to PhoenixAI components

There are two ways to deploy PhoenixAI cluster:

1. Deploy PhoenixAI cluster with `PhoenixAICluster` CR yaml.
2. Deploy PhoenixAI cluster with Helm chart.

Therefore, there are two ways to inject the MYSQL_PWD environment variable into PhoenixAI components.

A warehouse's compute nodes register with the FE as root too, and a `PhoenixAIWarehouse` does not
inherit the cluster's entry. Give every warehouse the same `MYSQL_PWD` entry, pointing at the same
Secret: `spec.template.envVars` of the `PhoenixAIWarehouse`, or `envVars` in the `warehouse` chart's
`values.yaml`.

### 2.1 inject MYSQL_PWD environment variable with PhoenixAICluster CRD yaml

1. Create a secret **rootcredential** with the key **password** to store the root password

   ```shell
   kubectl create secret generic rootcredential --from-literal=password=mysql_password
   ```

2. Add the following snippets to `phoenixAIFeSpec/phoenixAICnSpec` respectively if the corresponding
   components are deployed.

   ```yaml
   # for phoenixAIFeSpec
   feEnvVars:
   - name: "MYSQL_PWD"
     valueFrom:
       secretKeyRef:
         name: rootcredential
         key: password

   # for phoenixAICnSpec
   cnEnvVars:
   - name: "MYSQL_PWD"
     valueFrom:
       secretKeyRef:
         name: rootcredential
         key: password
   ```

3. Apply the crd yaml

   ```shell
   kubectl apply -f <crd_yaml>
   ```

It will trigger a rolling restart of the cluster, wait until the cluster restart completed.

### 2.2 Inject MYSQL_PWD environment variable with helm chart

If you are using the `kube-anywhere` Helm chart, add the following snippets to `values.yaml`.

```yaml

phoenixai:
  # create secrets if necessary.
  secrets:
    - name: rootcredential
      data:
        password: mysql_password

  phoenixAIFeSpec:
    feEnvVars:
      - name: "MYSQL_PWD"
        valueFrom:
          secretKeyRef:
            name: rootcredential
            key: password

  phoenixAICnSpec:
    cnEnvVars:
      - name: "MYSQL_PWD"
        valueFrom:
          secretKeyRef:
            name: rootcredential
            key: password
```

If you are using the `phoenixai` Helm chart, add the following snippets to `values.yaml`.

```yaml
# create secrets if necessary.
secrets:
- name: rootcredential
  data:
    password: mysql_password

phoenixAIFeSpec:
  feEnvVars:
  - name: "MYSQL_PWD"
    valueFrom:
      secretKeyRef:
        name: rootcredential
        key: password

phoenixAICnSpec:
  cnEnvVars:
  - name: "MYSQL_PWD"
    valueFrom:
      secretKeyRef:
        name: rootcredential
        key: password
```

Run the following command to upgrade the cluster.

```shell
helm upgrade <release_name> <chart_path> -f values.yaml
```

It will trigger a rolling restart of the cluster, wait until the cluster restart completed.

### 2.3 Rotating a password that is already declared

The rolling restart above happens the first time through, because adding the `MYSQL_PWD` entry
changes the FE and CN StatefulSets. A later rotation changes only the value inside the Secret. The
CR and the StatefulSets stay the same, so **nothing restarts**:

- With the Helm chart, change the password under `secrets` in `values.yaml` and run the same
  `helm upgrade`. The chart updates the Secret in place.
- With a CR, write the new value into the Secret:

  ```shell
  kubectl create secret generic rootcredential --from-literal=password=new_password \
    --dry-run=client -o yaml | kubectl apply -f -
  ```

A running FE or CN pod keeps the old value in its environment, and that is fine: the container
reads `MYSQL_PWD` only when it starts, to join the cluster. The next container start of any FE or CN
pod (a restart, a scale-out, an image rollout) reads the Secret's current value. This is also why
the Secret must be updated right after step 1: a pod that starts in between logs in with the old
password and cannot join.

The operator and PhoenixAI Anywhere read the Secret themselves rather than the pod environment, so
they pick up the new value without any restart; sections 4 and 5 say how soon.

## 3. Verify the password is all set

After the pods are restarted, run the following command to check the correctness of the password.

``` shell
kubectl exec <podName> -- sh -c 'echo $MYSQL_PWD'
```

After a rotation (section 2.3) the pods are not restarted, so this still prints the old value.
Check the Secret and the login instead:

``` shell
kubectl get secret rootcredential -o jsonpath='{.data.password}' | base64 -d; echo
kubectl exec <fePodName> -- mysql -h127.0.0.1 -P9030 -uroot -pnew_password -e "select 1"
```

## 4. What happens when the password in the CR does not match FE

Every time the operator itself logs in to FE, it uses the `MYSQL_PWD` of the FE spec
(`spec.phoenixAIFeSpec.feEnvVars` of the `PhoenixAICluster`). That covers the login check below, the
FE feature probe, the version check that orders FE and CN image rollouts, and the SQL it sends when it
scales in CN or deletes a warehouse or CN group. The `MYSQL_PWD` of a CN spec, a warehouse or a CN
group is what those CN pods register with; the operator does not log in with it. This is why step 2
puts the password in the FE spec as well as in the CN spec.

Once FE is ready and before it creates or updates a CN workload of a cluster, warehouse or CN group,
the operator logs in to the FE query port with that password. If the login fails, the CN workload is
not touched and the object reports why:

- On a cluster, `status.phase` becomes `failed` and `status.reason` starts with
  `error from CN controller: operator cannot log in to fe:`. On a warehouse or CN group,
  `status.reason` starts with `operator cannot log in to fe:`.
- The reason names the cause: the FE rejected the password (and that it came from the `MYSQL_PWD`
  env var of the FE StatefulSet, or that none is set), the FE service name did not resolve, the query
  port refused the connection or timed out, the `--fe-ssl-mode` of the operator does not match the FE
  SSL configuration, or the referenced Secret could not be read.

The check is retried like any other CN reconcile error, and every object is reconciled again by
the operator's periodic resync (every 2 minutes), so fixing the Secret value, the `MYSQL_PWD`
entry in the FE spec, or the password in FE is enough for the operator to resume within a couple of
minutes. A successful login is remembered for 10 minutes, so the frequent reconciles of a healthy
cluster do not each log in to FE (and do not each leave a root login in FE's audit log). The memory
is keyed by the FE address, the SSL mode and the `MYSQL_PWD` entry of the FE spec as written (its
value, or the Secret it references): changing that entry is checked at once, while a new value
inside the same Secret, or a password changed only inside FE with `SET PASSWORD`, is noticed on the
first check after those 10 minutes.

A typical mismatch after step 1 but before step 2 looks like this:

```shell
kubectl get phoenixaicluster <name> -o jsonpath='{.status.phase}{"\n"}{.status.reason}{"\n"}'
failed
error from CN controller: operator cannot log in to fe: FE at <name>-fe-service.<namespace>:9030 rejected the root password (Error 1045 (28000): Access denied for user 'root' (using password: NO)); FE StatefulSet <name>-fe has no MYSQL_PWD env var, so an empty password was used; if the root password has been changed, declare it in spec.phoenixAIFeSpec.feEnvVars of the PhoenixAICluster
```

## 5. What happens in PhoenixAI Anywhere when a password changes

This section applies when the `kube-anywhere` chart runs the Anywhere console (`anywhere.enabled`).
Two different things change when a password does, and they fail in different places: the
console's **own root access**, which only the root password affects, and the **Cluster Console
session** of a signed-in user, which only that user's password affects.

### 5.1 The console's own root access

Anywhere never asks for a cluster password. For everything it does on a cluster by itself it logs
in as root, with the password it resolves from the `MYSQL_PWD` entry of the FE spec: a literal
value, or the Secret the entry references. It resolves that entry through the operator and caches
the result for one minute. When the FE rejects the password, the cached value is dropped at once,
and the next attempt reads the Secret again. So after step 2, the console recovers on its own on
the next attempt; no restart is needed, in either direction of the mismatch.

Between step 1 and step 2, everything the console does as root fails against the FE with
`Access denied` (MySQL error 1045):

- **Query-history collection** is the one that runs on its own. It polls every FE every 10
  seconds by default, and on a rejected password it stops the round and retries on the next tick. Nothing in
  the console pages says so: queries simply stop appearing in **Query insights**, including the
  queries of users who are signed in with their own, unchanged credentials. The console log is
  where it shows:

  ```
  "msg":"query-history: fetch query_detail failed; retrying next interval","err":"access denied: invalid cluster username or password","pod":"<cluster>-fe-0"
  ```

  Collection resumes from where it stopped once the password is accepted again. The FE keeps
  query details for a limited time, so queries that ran during a long gap can be lost.
- **Health checks** are the one place the console reports it. Run the cluster's health checks
  and the `cluster-sql-unreachable` rule fails as critical, naming the rejected credentials and
  the surfaces that are down; it runs only when you ask for it, not in the background.
- In the **Anywhere Console**, the cluster pages that read the cluster over SQL (query insights,
  catalog browsing, job listings, the License page) and the SQL parts of a **support bundle**
  report `cluster credentials were rejected` until the two agree, from the moment they need a new
  connection to the FE. A connection the console already holds is not closed by the password
  change, so these can keep working for a while after step 1. The same pages in the Cluster
  Console use the signed-in user's own credentials and are not affected (section 5.2).
- **Usage metering** is not affected: it reads the FE metrics endpoint over HTTP, without the root
  password.

The console's own root access is tied to the password only, not to the sessions below: changing
root's password does not sign anyone out, and signing in as root in the Cluster Console with the
new password works as soon as step 1 is done.

### 5.2 A Cluster Console session whose user's password changes

A Cluster Console session is opened with a database user's own username and password and passes
them through on every query. The session keeps the password it was opened with, and Anywhere
never re-reads it. So when that user's password changes in the cluster, whether by an
administrator or by the user in the SQL editor with `SET PASSWORD`, the session is left holding
the old one:

- A **SQL editor tab that is already open** keeps working. Each tab holds one dedicated connection
  to the FE, and the FE does not close an established connection when the password behind it
  changes (the same as any MySQL server). The tab's connection is closed when the tab is hidden,
  closed, or idle for 30 minutes.
- **Everything that opens a new connection** fails with `cluster credentials were rejected; please
  log in again`: a new editor tab, the next statement in a tab whose connection has been closed,
  and creating, editing or dropping an external catalog or opening its edit form, which opens a
  connection of its own every time. The other Cluster Console pages, such as data-catalog
  browsing and Query insights, reuse their connections for up to a minute, so they can keep
  working for that long before they fail.
- The failure raises a **Session expired** dialog; confirming it takes you to the Cluster Console
  sign-in page.

The rule is therefore: **after changing your own password, sign out and sign in again right
away**, before opening anything else. For root this includes the password rotation of this guide:
if you ran step 1 from the SQL editor as root, the tab you ran it in keeps working, but everything
else in your root session fails as soon as it needs a new connection to the FE.

Changing root's password does not touch the sessions of other users, and changing another user's
password does not touch the console's own root access (section 5.1).

## 6. Rotation checklist

1. Tell the Cluster Console users who sign in as root that their sessions will end.
2. Step 1 (`SET PASSWORD`) and step 2 (the Secret, or the `MYSQL_PWD` entry the first time)
   back to back. Do not restart, scale or upgrade FE or CN pods in between.
3. Expect, in the gap and for a short while after it:
   - Anywhere: query-history collection stops (console log, section 5.1) and resumes on the next
     10-second tick after the Secret holds the new value.
   - Operator: a login check that falls in the gap marks the object `failed` with
     `operator cannot log in to fe` (section 4) and clears on the next check after the Secret
     holds the new value, within 10 minutes plus one resync.
4. Verify (section 3): the Secret holds the new value, a root login with it succeeds, the console
   log is quiet, and `kubectl get phoenixaicluster <name>` reports `running`.
5. Sign in to the Cluster Console again as root if you use it.
