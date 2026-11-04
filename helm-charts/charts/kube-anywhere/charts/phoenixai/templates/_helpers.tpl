{{/*
Common labels
*/}}
{{- define "phoenixaicluster.labels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
initpassword secret name
*/}}

{{- define "phoenixaicluster.initpassword.secret.name" -}}
{{ default (print (include "phoenixaicluster.name" .) "-credential") .Values.initPassword.passwordSecret }}
{{- end }}

{{/*
phoenixaicluster
*/}}

{{- define "phoenixaicluster.name" -}}
{{ default (default .Chart.Name .Values.nameOverride) .Values.phoenixAICluster.name }}
{{- end }}

{{- define "phoenixaicluster.namespace" -}}
{{ default .Release.Namespace .Values.phoenixAICluster.namespace }}
{{- end }}

{{- define "phoenixaicluster.fe.name" -}}
{{- print (include "phoenixaicluster.name" .) "-fe" }}
{{- end }}

{{- define "phoenixaicluster.cn.name" -}}
{{- print (include "phoenixaicluster.name" .) "-cn" }}
{{- end }}

{{- define "phoenixaicluster.fe.configmap.name" -}}
{{- print (include "phoenixaicluster.fe.name" .) "-cm" }}
{{- end }}

{{- define "phoenixaicluster.cn.configmap.name" -}}
{{- print (include "phoenixaicluster.cn.name" .) "-cm" }}
{{- end }}

{{- /*
phoenixaicluster.fe.configNamesBucket reports "true" when the given phoenixAIFeSpec names an object
store in fe.conf (aws_s3_path, from configyaml when it is used, else from config). NOTES.txt uses it
to warn that a cluster without one has no storage volume until the user creates one.
*/}}
{{- define "phoenixaicluster.fe.configNamesBucket" -}}
{{- if and .configyaml (kindIs "map" .configyaml) -}}
{{- if hasKey .configyaml "aws_s3_path" }}true{{ end -}}
{{- else if regexMatch "(?m)^[ \\t]*aws_s3_path[ \\t]*=" (toString .config) }}true{{ end -}}
{{- end }}

{{- define "phoenixaicluster.fe.config" -}}
fe.conf: |
{{- if and .Values.phoenixAIFeSpec.configyaml (kindIs "map" .Values.phoenixAIFeSpec.configyaml) }}
  {{- range $key, $value := .Values.phoenixAIFeSpec.configyaml }}
    {{ $key }} = {{ $value }}
  {{- end }}
{{- else if .Values.phoenixAIFeSpec.configyaml }}
  {{ fail "configyaml must be a map" }}
{{- else }}
  {{- .Values.phoenixAIFeSpec.config | nindent 2 }}
{{- end }}
{{- end }}

{{- define "phoenixaicluster.cn.config" -}}
cn.conf: |
{{- if and .Values.phoenixAICnSpec.configyaml (kindIs "map" .Values.phoenixAICnSpec.configyaml) }}
  {{- range $key, $value := .Values.phoenixAICnSpec.configyaml }}
    {{ $key }} = {{ $value }}
  {{- end }}
{{- else if .Values.phoenixAICnSpec.configyaml }}
  {{ fail "configyaml must be a map" }}
{{- else }}
  {{- .Values.phoenixAICnSpec.config | nindent 2 }}
{{- end }}
{{- end }}

{{- define "phoenixaicluster.fe.meta.suffix" -}}
{{- print "-meta" }}
{{- end }}

{{- define "phoenixaicluster.fe.meta.path" -}}
{{- if .Values.phoenixAIFeSpec.storageSpec.storageMountPath }}
{{- print .Values.phoenixAIFeSpec.storageSpec.storageMountPath }}
{{- else }}
{{- print "/opt/starrocks/fe/meta" }}
{{- end }}
{{- end }}

{{- define "phoenixaicluster.fe.log.suffix" -}}
{{- print "-log" }}
{{- end }}

{{- define "phoenixaicluster.fe.log.path" -}}
{{- if .Values.phoenixAIFeSpec.storageSpec.logMountPath }}
{{- print .Values.phoenixAIFeSpec.storageSpec.logMountPath }}
{{- else }}
{{- print "/opt/starrocks/fe/log" }}
{{- end }}
{{- end }}

{{- define "phoenixaicluster.cn.data.suffix" -}}
{{- print "-data" }}
{{- end }}

{{- define "phoenixaicluster.cn.data.path" -}}
{{- if .Values.phoenixAICnSpec.storageSpec.storageMountPath }}
{{- print .Values.phoenixAICnSpec.storageSpec.storageMountPath }}
{{- else }}
{{- print "/opt/starrocks/cn/storage" }}
{{- end }}
{{- end }}

{{- define "phoenixaicluster.cn.log.suffix" -}}
{{- print "-log" }}
{{- end }}

{{- define "phoenixaicluster.cn.log.path" -}}
{{- if .Values.phoenixAICnSpec.storageSpec.logMountPath }}
{{- print .Values.phoenixAICnSpec.storageSpec.logMountPath }}
{{- else }}
{{- print "/opt/starrocks/cn/log" }}
{{- end }}
{{- end }}

{{- define "phoenixaicluster.cn.spill.suffix" -}}
{{- print "-spill" }}
{{- end }}

{{- define "phoenixaicluster.cn.spill.path" -}}
{{- if .Values.phoenixAICnSpec.storageSpec.spillMountPath }}
{{- print .Values.phoenixAICnSpec.storageSpec.spillMountPath }}
{{- else }}
{{- print "/opt/starrocks/cn/spill" }}
{{- end }}
{{- end }}

{{- define "phoenixaicluster.entrypoint.script.name" -}}
{{- print "entrypoint.sh" }}
{{- end }}

{{- define "phoenixaicluster.entrypoint.mount.path" -}}
{{- print "/etc/phoenixai" }}
{{- end }}

{{- define "phoenixaicluster.fe.entrypoint.script.configmap.name" -}}
{{- print (include "phoenixaicluster.name" .) "-fe-entrypoint-script" }}
{{- end }}

{{- define "phoenixaicluster.cn.entrypoint.script.configmap.name" -}}
{{- print (include "phoenixaicluster.name" .) "-cn-entrypoint-script" }}
{{- end }}

{{/*
Define a function to handle resource limits for fe
*/}}
{{- define "phoenixaicluster.fe.resources" -}}
requests:
  {{- toYaml .Values.phoenixAIFeSpec.resources.requests | nindent 2 }}
limits:
{{- range $key, $value := .Values.phoenixAIFeSpec.resources.limits }}
  {{- if ne (toString $value) "unlimited" }}
  {{ $key }}: {{ $value }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
Define a function to handle resource limits for cn
*/}}
{{- define "phoenixaicluster.cn.resources" -}}
requests:
  {{- toYaml .Values.phoenixAICnSpec.resources.requests | nindent 2 }}
limits:
{{- range $key, $value := .Values.phoenixAICnSpec.resources.limits }}
  {{- if ne (toString $value) "unlimited" }}
  {{ $key }}: {{ $value }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
phoenixaicluster.fe.config.hash is used to calculate the hash value of the fe.conf, and due to the length limit, only
the first 8 digits are taken, which will be used as the annotations for pods.
*/}}
{{- define "phoenixaicluster.fe.config.hash" }}
  {{- if and .Values.phoenixAIFeSpec.configyaml (kindIs "map" .Values.phoenixAIFeSpec.configyaml) }}
    {{- $hash := toJson .Values.phoenixAIFeSpec.configyaml | sha256sum | trunc 8 }}
    {{- printf "%s" $hash }}
  {{- else if .Values.phoenixAIFeSpec.configyaml }}
    {{ fail "configyaml must be a map" }}
  {{- else if .Values.phoenixAIFeSpec.config }}
    {{- $hash := toJson .Values.phoenixAIFeSpec.config | sha256sum | trunc 8 }}
    {{- printf "%s" $hash }}
  {{- else }}
    {{- printf "no-config" }}
  {{- end }}
{{- end }}


{{/*
phoenixaicluster.cn.config.hash is used to calculate the hash value of the cn.conf, and due to the length limit, only
the first 8 digits are taken, which will be used as the annotations for pods.
*/}}
{{- define "phoenixaicluster.cn.config.hash" }}
  {{- if and .Values.phoenixAICnSpec.configyaml (kindIs "map" .Values.phoenixAICnSpec.configyaml) }}
    {{- $hash := toJson .Values.phoenixAICnSpec.configyaml | sha256sum | trunc 8 }}
    {{- printf "%s" $hash }}
  {{- else if .Values.phoenixAICnSpec.configyaml }}
    {{ fail "configyaml must be a map" }}
  {{- else if .Values.phoenixAICnSpec.config }}
    {{- $hash := toJson .Values.phoenixAICnSpec.config | sha256sum | trunc 8 }}
    {{- printf "%s" $hash }}
  {{- else }}
    {{- printf "no-config" }}
  {{- end }}
{{- end }}

{{- define "phoenixaicluster.fe.query.port" -}}
{{- $config := index .Values.phoenixAIFeSpec.config  -}}
{{- $configMap := dict -}}
{{- range $line := splitList "\n" $config -}}
{{- $pair := splitList "=" $line -}}
{{- if eq (len $pair) 2 -}}
{{- $_ := set $configMap (trim (index $pair 0)) (trim (index $pair 1)) -}}
{{- end -}}
{{- end -}}
{{- if (index $configMap "query_port") -}}
{{- print (index $configMap "query_port") }}
{{- end }}
{{- end }}

{{- define "phoenixaicluster.fe.entrypoint.script.hash" }}
  {{- if .Values.phoenixAIFeSpec.entrypoint }}
    {{- $hash := toJson .Values.phoenixAIFeSpec.entrypoint.script | sha256sum | trunc 8 }}
    {{- printf "%s" $hash }}
  {{- else }}
    {{- printf "no-config" }}
  {{- end }}
{{- end }}

{{- define "phoenixaicluster.cn.entrypoint.script.hash" }}
  {{- if .Values.phoenixAICnSpec.entrypoint }}
    {{- $hash := toJson .Values.phoenixAICnSpec.entrypoint.script | sha256sum | trunc 8 }}
    {{- printf "%s" $hash }}
  {{- else }}
    {{- printf "no-config" }}
  {{- end }}
{{- end }}

{{- define "phoenixaicluster.fe.http.port" -}}
{{- $config := index .Values.phoenixAIFeSpec.config  -}}
{{- $configMap := dict -}}
{{- range $line := splitList "\n" $config -}}
{{- $pair := splitList "=" $line -}}
{{- if eq (len $pair) 2 -}}
{{- $_ := set $configMap (trim (index $pair 0)) (trim (index $pair 1)) -}}
{{- end -}}
{{- end -}}
{{- if (index $configMap "http_port") -}}
{{- print (index $configMap "http_port") }}
{{- end }}
{{- end }}

{{- define "phoenixaicluster.cn.webserver.port" -}}
{{- include "phoenixaicluster.webserver.port" .Values.phoenixAICnSpec }}
{{- end }}

{{- define "phoenixaicluster.webserver.port" -}}
{{- $config := index .config  -}}
{{- $configMap := dict -}}
{{- range $line := splitList "\n" $config -}}
{{- $pair := splitList "=" $line -}}
{{- if eq (len $pair) 2 -}}
{{- $_ := set $configMap (trim (index $pair 0)) (trim (index $pair 1)) -}}
{{- end -}}
{{- end -}}
{{- if (index $configMap "webserver_port") -}}
{{- print (index $configMap "webserver_port") }}
{{- end }}
{{- end }}

{{/*
Get the value of the schedulerName field in the phoenixAIFeSpec
*/}}
{{- define "phoenixaicluster.fe.schedulerName" -}}
{{- if .Values.phoenixAIFeSpec.schedulerName -}}
{{- .Values.phoenixAIFeSpec.schedulerName -}}
{{- else if .Values.phoenixAICluster.componentValues.schedulerName -}}
{{- .Values.phoenixAICluster.componentValues.schedulerName -}}
{{- end -}}
{{- end -}}

{{/*
Get the value of the schedulerName field in the phoenixAICnSpec
*/}}
{{- define "phoenixaicluster.cn.schedulerName" -}}
{{- if .Values.phoenixAICnSpec.schedulerName -}}
{{- .Values.phoenixAICnSpec.schedulerName -}}
{{- else if .Values.phoenixAICluster.componentValues.schedulerName -}}
{{- .Values.phoenixAICluster.componentValues.schedulerName -}}
{{- end -}}
{{- end -}}

{{/*
Get the value of the serviceAccount field in the phoenixAIFeSpec
*/}}
{{- define "phoenixaicluster.fe.serviceAccount" -}}
{{- if .Values.phoenixAIFeSpec.serviceAccount -}}
{{- .Values.phoenixAIFeSpec.serviceAccount -}}
{{- else if .Values.phoenixAICluster.componentValues.serviceAccount -}}
{{- .Values.phoenixAICluster.componentValues.serviceAccount -}}
{{- end -}}
{{- end -}}

{{/*
Get the value of the serviceAccount field in the phoenixAICnSpec
*/}}
{{- define "phoenixaicluster.cn.serviceAccount" -}}
{{- if .Values.phoenixAICnSpec.serviceAccount -}}
{{- .Values.phoenixAICnSpec.serviceAccount -}}
{{- else if .Values.phoenixAICluster.componentValues.serviceAccount -}}
{{- .Values.phoenixAICluster.componentValues.serviceAccount -}}
{{- end -}}
{{- end -}}

{{/*
Get the value of the imagePullSecrets field in the phoenixAIFeSpec
*/}}
{{- define "phoenixaicluster.fe.imagePullSecrets" -}}
{{- if .Values.phoenixAIFeSpec.imagePullSecrets -}}
{{- toYaml .Values.phoenixAIFeSpec.imagePullSecrets -}}
{{- else if .Values.phoenixAICluster.componentValues.imagePullSecrets -}}
{{- toYaml .Values.phoenixAICluster.componentValues.imagePullSecrets -}}
{{- end -}}
{{- end -}}

{{/*
Get the value of the imagePullSecrets field in the phoenixAICnSpec
*/}}
{{- define "phoenixaicluster.cn.imagePullSecrets" -}}
{{- if .Values.phoenixAICnSpec.imagePullSecrets -}}
{{- toYaml .Values.phoenixAICnSpec.imagePullSecrets -}}
{{- else if .Values.phoenixAICluster.componentValues.imagePullSecrets -}}
{{- toYaml .Values.phoenixAICluster.componentValues.imagePullSecrets -}}
{{- end -}}
{{- end -}}

{{/*
Get the value of the tolerations field in the phoenixAIFeSpec
*/}}
{{- define "phoenixaicluster.fe.tolerations" -}}
{{- if .Values.phoenixAIFeSpec.tolerations -}}
{{- toYaml .Values.phoenixAIFeSpec.tolerations -}}
{{- else if .Values.phoenixAICluster.componentValues.tolerations -}}
{{- toYaml .Values.phoenixAICluster.componentValues.tolerations -}}
{{- end -}}
{{- end -}}

{{/*
Get the value of the tolerations field in the phoenixAICnSpec
*/}}
{{- define "phoenixaicluster.cn.tolerations" -}}
{{- if .Values.phoenixAICnSpec.tolerations -}}
{{- toYaml .Values.phoenixAICnSpec.tolerations -}}
{{- else if .Values.phoenixAICluster.componentValues.tolerations -}}
{{- toYaml .Values.phoenixAICluster.componentValues.tolerations -}}
{{- end -}}
{{- end -}}

{{/*
Get the value of the nodeSelector field in the phoenixAIFeSpec
*/}}
{{- define "phoenixaicluster.fe.nodeSelector" -}}
{{- if .Values.phoenixAIFeSpec.nodeSelector -}}
{{- toYaml .Values.phoenixAIFeSpec.nodeSelector -}}
{{- else if .Values.phoenixAICluster.componentValues.nodeSelector -}}
{{- toYaml .Values.phoenixAICluster.componentValues.nodeSelector -}}
{{- end -}}
{{- end -}}

{{/*
Get the value of the nodeSelector field in the phoenixAICnSpec
*/}}
{{- define "phoenixaicluster.cn.nodeSelector" -}}
{{- if .Values.phoenixAICnSpec.nodeSelector -}}
{{- toYaml .Values.phoenixAICnSpec.nodeSelector -}}
{{- else if .Values.phoenixAICluster.componentValues.nodeSelector -}}
{{- toYaml .Values.phoenixAICluster.componentValues.nodeSelector -}}
{{- end -}}
{{- end -}}

{{/*
Get the value of the affinity field in the phoenixAIFeSpec
*/}}
{{- define "phoenixaicluster.fe.affinity" -}}
{{- if .Values.phoenixAIFeSpec.affinity -}}
{{- toYaml .Values.phoenixAIFeSpec.affinity -}}
{{- else if .Values.phoenixAICluster.componentValues.affinity -}}
{{- toYaml .Values.phoenixAICluster.componentValues.affinity -}}
{{- end -}}
{{- end -}}

{{/*
Get the value of the affinity field in the phoenixAICnSpec
*/}}
{{- define "phoenixaicluster.cn.affinity" -}}
{{- if .Values.phoenixAICnSpec.affinity -}}
{{- toYaml .Values.phoenixAICnSpec.affinity -}}
{{- else if .Values.phoenixAICluster.componentValues.affinity -}}
{{- toYaml .Values.phoenixAICluster.componentValues.affinity -}}
{{- end -}}
{{- end -}}

{{/*
Get the value of the topologySpreadConstraints field in the phoenixAIFeSpec
*/}}
{{- define "phoenixaicluster.fe.topologySpreadConstraints" -}}
{{- if .Values.phoenixAIFeSpec.topologySpreadConstraints -}}
{{- toYaml .Values.phoenixAIFeSpec.topologySpreadConstraints -}}
{{- else if .Values.phoenixAICluster.componentValues.topologySpreadConstraints -}}
{{- toYaml .Values.phoenixAICluster.componentValues.topologySpreadConstraints -}}
{{- end -}}
{{- end -}}

{{/*
Get the value of the topologySpreadConstraints field in the phoenixAICnSpec
*/}}
{{- define "phoenixaicluster.cn.topologySpreadConstraints" -}}
{{- if .Values.phoenixAICnSpec.topologySpreadConstraints -}}
{{- toYaml .Values.phoenixAICnSpec.topologySpreadConstraints -}}
{{- else if .Values.phoenixAICluster.componentValues.topologySpreadConstraints -}}
{{- toYaml .Values.phoenixAICluster.componentValues.topologySpreadConstraints -}}
{{- end -}}
{{- end -}}

{{/*
Get the value of the runAsNonRoot field in the phoenixAIFeSpec
*/}}
{{- define "phoenixaicluster.fe.runAsNonRoot" -}}
{{- if .Values.phoenixAIFeSpec.runAsNonRoot -}}
{{- .Values.phoenixAIFeSpec.runAsNonRoot -}}
{{- else if .Values.phoenixAICluster.componentValues.runAsNonRoot -}}
{{- .Values.phoenixAICluster.componentValues.runAsNonRoot -}}
{{- else -}}
false
{{- end -}}
{{- end -}}

{{/*
Get the value of the runAsNonRoot field in the phoenixAICnSpec
*/}}
{{- define "phoenixaicluster.cn.runAsNonRoot" -}}
{{- if .Values.phoenixAICnSpec.runAsNonRoot -}}
{{- .Values.phoenixAICnSpec.runAsNonRoot -}}
{{- else if .Values.phoenixAICluster.componentValues.runAsNonRoot -}}
{{- .Values.phoenixAICluster.componentValues.runAsNonRoot -}}
{{- else -}}
false
{{- end -}}
{{- end -}}

{{/*
Get the value of hostAliases field in the phoenixAIFeSpec
*/}}
{{- define "phoenixaicluster.fe.hostAliases" -}}
{{- if .Values.phoenixAIFeSpec.hostAliases -}}
{{- toYaml .Values.phoenixAIFeSpec.hostAliases -}}
{{- else if .Values.phoenixAICluster.componentValues.hostAliases -}}
{{- toYaml .Values.phoenixAICluster.componentValues.hostAliases -}}
{{- end -}}
{{- end -}}

{{/*
Get the value of hostAliases field in the phoenixAICnSpec
*/}}
{{- define "phoenixaicluster.cn.hostAliases" -}}
{{- if .Values.phoenixAICnSpec.hostAliases -}}
{{- toYaml .Values.phoenixAICnSpec.hostAliases -}}
{{- else if .Values.phoenixAICluster.componentValues.hostAliases -}}
{{- toYaml .Values.phoenixAICluster.componentValues.hostAliases -}}
{{- end -}}
{{- end -}}

{{/*
Get the value of tag field in the phoenixAIFeSpec
*/}}
{{- define "phoenixaicluster.fe.image.tag" -}}
{{- if and .Values.phoenixAIFeSpec.image.tag (ne (toString .Values.phoenixAIFeSpec.image.tag) "") -}}
{{- .Values.phoenixAIFeSpec.image.tag -}}
{{- else -}}
{{- .Values.phoenixAICluster.componentValues.image.tag -}}
{{- end -}}
{{- end -}}

{{/*
Get the value of tag field in the phoenixAICnSpec
*/}}
{{- define "phoenixaicluster.cn.image.tag" -}}
{{- if and .Values.phoenixAICnSpec.image.tag (ne (toString .Values.phoenixAICnSpec.image.tag) "") -}}
{{- .Values.phoenixAICnSpec.image.tag -}}
{{- else -}}
{{- .Values.phoenixAICluster.componentValues.image.tag -}}
{{- end -}}
{{- end -}}

{{/*
Get the value of podLabels field in the phoenixAIFeSpec
*/}}
{{- define "phoenixaicluster.fe.podLabels" -}}
{{- if .Values.phoenixAIFeSpec.podLabels -}}
{{- toYaml .Values.phoenixAIFeSpec.podLabels -}}
{{- else if .Values.phoenixAICluster.componentValues.podLabels -}}
{{- toYaml .Values.phoenixAICluster.componentValues.podLabels -}}
{{- end -}}
{{- end -}}

{{/*
Get the value of podLabels field in the phoenixAICnSpec
*/}}
{{- define "phoenixaicluster.cn.podLabels" -}}
{{- if .Values.phoenixAICnSpec.podLabels -}}
{{- toYaml .Values.phoenixAICnSpec.podLabels -}}
{{- else if .Values.phoenixAICluster.componentValues.podLabels -}}
{{- toYaml .Values.phoenixAICluster.componentValues.podLabels -}}
{{- end -}}
{{- end -}}

{{/*
Build the Datadog log annotation value for a given component.
Arguments (passed as a dict via "include"):
  .root = root context (has .Values)
  .component = "fe" or "cn"
  .multilinePattern = regex pattern string for multi_line rule
  .multilineName = name for the multi_line rule
Usage: include "phoenixaicluster.datadog.log.annotation" (dict "root" . "component" "fe" "multilinePattern" "..." "multilineName" "...")
*/}}
{{- define "phoenixaicluster.datadog.log.annotation" -}}
{{- $root := .root -}}
{{- $component := .component -}}
{{- $multilinePattern := .multilinePattern -}}
{{- $multilineName := .multilineName -}}
{{- $logConfig := $root.Values.datadog.log.logConfig -}}
{{- $base := dict "service" "phoenixai" "source" $component -}}
{{- if eq (kindOf $logConfig) "map" -}}
  {{- $base = merge $base $logConfig -}}
{{- else if eq (kindOf $logConfig) "string" -}}
  {{- if ne (trimAll " {}" $logConfig) "" -}}
    {{- $extra := fromJson $logConfig -}}
    {{- $base = merge $base $extra -}}
  {{- end -}}
{{- end -}}
{{- if $root.Values.datadog.log.enableMultilineLogParsing -}}
  {{- if not (hasKey $base "log_processing_rules") -}}
    {{- $rule := dict "name" $multilineName "pattern" $multilinePattern "type" "multi_line" -}}
    {{- $_ := set $base "log_processing_rules" (list $rule) -}}
  {{- end -}}
{{- end -}}
{{- list $base | toJson | squote -}}
{{- end -}}

{{/*
phoenixaicluster.cngroup.cnspec is a copy of phoenixaiwarehouse.cnspec in the warehouse chart: the
same CN spec body, so that a CN group declared next to a cluster renders exactly like one declared
next to a warehouse. The two charts are separate top-level charts and cannot share a template, so
scripts/internal/check-helm.sh renders the same entry through both and diffs the result. Change one
copy and you must change the other.

The argument is a context shaped like a chart's own, a dict with two keys (see the warehouse copy
for the full description):

  Values  a copy of this chart's values whose `spec` key is the CN group entry, built with
          `set (omit $root.Values "spec") "spec" $entry` (never merge, which would recurse into the
          entry). The body reads it as .Values.spec.* so that, in the warehouse chart, an IDE can
          resolve every field to its key in values.yaml; this chart has no `spec` values key, the
          name is kept only so the two bodies stay identical.
  cnspec  configMapName, configHash, envVarsKey, config, extraEnvVars (the MYSQL_PWD entry
          generated from initPassword).
*/}}
{{- define "phoenixaicluster.cngroup.cnspec" -}}
{{- $args := .cnspec -}}
{{/* PhoenixAIWarehouse.spec.template calls the field envVars; PhoenixAICnGroup.spec.phoenixAICnSpec
     is a PhoenixAICnSpec, where the same field is cnEnvVars. Getting this wrong is not caught by a
     render: the API server rejects the object only when it is applied. */}}
{{- $envVarsKey := default "envVars" $args.envVarsKey -}}
{{/* The cn.conf that actually applies to these pods: the entry's own when it has one, otherwise the
     parent's, because that is the ConfigMap they mount. The webserver port is parsed out of it. */}}
{{- $config := default .Values.spec.config $args.config -}}
{{/* Nested blocks a CN group entry may leave out entirely. A direct .Values.spec.service.type would
     fail the render on a nil service, so these two go through a nil-safe variable. */}}
{{- $service := default dict .Values.spec.service -}}
{{- $storageSpec := default dict .Values.spec.storageSpec }}
    image: "{{ .Values.spec.image.repository }}:{{ .Values.spec.image.tag }}"
    {{- /* Not a truthiness test, so replicas: 0 survives. A missing key and an explicit null both
         read as nil and render nothing, and the CRD default applies. */}}
    {{- if not (kindIs "invalid" .Values.spec.replicas) }}
    replicas: {{ .Values.spec.replicas }}
    {{- end }}
    {{- if .Values.spec.serviceAccount }}
    serviceAccount: {{ .Values.spec.serviceAccount }}
    {{- end }}
    runAsNonRoot: {{ default false .Values.spec.runAsNonRoot }}
    {{- if .Values.spec.podLabels }}
    podLabels:
      {{- toYaml .Values.spec.podLabels | nindent 6 }}
    {{- end }}
    {{- if .Values.spec.hostAliases }}
    hostAliases:
      {{- toYaml .Values.spec.hostAliases | nindent 6 }}
    {{- end }}
    {{- if .Values.spec.schedulerName }}
    schedulerName: {{ .Values.spec.schedulerName }}
    {{- end }}
    {{- if .Values.spec.nodeSelector }}
    nodeSelector:
      {{- toYaml .Values.spec.nodeSelector | nindent 6 }}
    {{- end }}
    {{ $envVarsKey }}:
      - name: TZ
        value: {{ .Values.timeZone }}
      {{- if .Values.datadog.log.enabled }}
      - name: LOG_CONSOLE
        value: "1"
      {{- end }}
      {{- with $args.extraEnvVars }}
      {{- toYaml . | nindent 6 }}
      {{- end }}
      {{- if .Values.spec.envVars }}
      {{- toYaml .Values.spec.envVars | nindent 6 }}
      {{- end }}
    {{- if .Values.spec.affinity }}
    affinity:
      {{- toYaml .Values.spec.affinity | nindent 6 }}
    {{- end }}
    {{- if .Values.spec.tolerations }}
    tolerations:
      {{- toYaml .Values.spec.tolerations | nindent 6 }}
    {{- end }}
    {{- if .Values.spec.topologySpreadConstraints }}
    topologySpreadConstraints:
      {{- toYaml .Values.spec.topologySpreadConstraints | nindent 6 }}
    {{- end }}
    minReadySeconds: {{ default 0 .Values.spec.minReadySeconds }}
    {{- if .Values.spec.autoScalingPolicy }}
    autoScalingPolicy:
      {{- toYaml .Values.spec.autoScalingPolicy | nindent 6 }}
    {{- end }}
    {{- if .Values.spec.resources }}
    {{- toYaml .Values.spec.resources | nindent 4 }}
    {{- end }}
    {{- if $service.type }}
    service:
      type: {{ $service.type }}
      {{- if and (eq "LoadBalancer" $service.type) $service.loadbalancerIP }}
      loadBalancerIP: {{ $service.loadbalancerIP }}
      {{- end }}
      {{- if and (or (eq "LoadBalancer" $service.type) (eq "NodePort" $service.type)) $service.externalTrafficPolicy }}
      externalTrafficPolicy: {{ $service.externalTrafficPolicy }}
      {{- end }}
      {{- if $service.ports }}
      ports:
        {{- toYaml $service.ports | nindent 8 }}
      {{- end }}
      {{- if or $service.annotations .Values.datadog.metrics.enabled }}
      annotations:
        {{- if .Values.datadog.metrics.enabled }}
        prometheus.io/path: "/metrics"
        prometheus.io/port: "{{- default 8040 (include "phoenixaicluster.cngroup.get.webserver.port" (dict "config" $config)) }}"
        prometheus.io/scrape: "true"
        {{- end }}
        {{- if $service.annotations }}
        {{- toYaml $service.annotations | nindent 8 }}
        {{- end }}
      {{- end }}
      {{- if $service.labels }}
      labels:
        {{- toYaml $service.labels | nindent 8 }}
      {{- end }}
    {{- end }}
    annotations:
      app.phoenixdata.ai/cn-config-hash: "{{ $args.configHash }}"
      {{- if .Values.datadog.log.enabled }}
      {{- if eq (trimAll " {}" .Values.datadog.log.logConfig) "" }}
      ad.datadoghq.com/cn.logs: '[{"service":"cn"}]'
      {{- else }}
      ad.datadoghq.com/cn.logs: {{ printf "[%s]" (printf "{%s, \"service\": \"cn\"}" (trimAll " {}" .Values.datadog.log.logConfig) | fromJson | toJson) | squote }}
      {{- end }}
      {{- end }}
      {{- if .Values.spec.annotations }}
      {{- toYaml .Values.spec.annotations | nindent 6 }}
      {{- end }}
    {{- if .Values.spec.imagePullSecrets }}
    imagePullSecrets:
      {{- toYaml .Values.spec.imagePullSecrets | nindent 6 }}
    {{- end }}
    {{- if .Values.spec.secrets }}
    secrets:
    {{- range .Values.spec.secrets }}
    - name: {{ .name }}
      mountPath: {{ .mountPath }}
      subPath: {{ .subPath }}
    {{- end }}
    {{- end }}
    {{- if .Values.spec.configMaps }}
    configMaps:
    {{- range .Values.spec.configMaps }}
      - name: {{ .name }}
        mountPath: {{ .mountPath }}
        subPath: {{ .subPath }}
    {{- end }}
    {{- end }}
    configMapInfo:
      configMapName: {{ $args.configMapName }}
      resolveKey: cn.conf
    {{- if $storageSpec.name }}
    storageVolumes:
    - name: {{ $storageSpec.name }}{{template "phoenixaicluster.cn.data.suffix" . }}
      {{- if $storageSpec.storageClassName }}
      storageClassName: {{ $storageSpec.storageClassName }}
      {{- end }}
      {{- if $storageSpec.storageSize }}
      storageSize: {{ $storageSpec.storageSize }}
      {{- end }}
      mountPath: {{ default "/opt/starrocks/cn/storage" $storageSpec.storageMountPath }}
    {{- if $storageSpec.logStorageSize }}
    - name: {{ $storageSpec.name }}{{template "phoenixaicluster.cn.log.suffix" . }}
      {{- if $storageSpec.storageClassName }}
      storageClassName: {{ $storageSpec.storageClassName }}
      {{- end }}
      {{- if $storageSpec.logStorageSize }}
      storageSize: {{ $storageSpec.logStorageSize }}
      {{- end }}
      mountPath: {{ default "/opt/starrocks/cn/log" $storageSpec.logMountPath }}
    {{- end }}
    {{- end }}
    {{- if .Values.spec.persistentVolumeClaimRetentionPolicy }}
    persistentVolumeClaimRetentionPolicy:
      {{- toYaml .Values.spec.persistentVolumeClaimRetentionPolicy | nindent 6 }}
    {{- end }}
{{- end }}

{{- define "phoenixaicluster.cngroup.get.webserver.port" -}}
{{- $config := default "" .config -}}
{{- $configMap := dict -}}
{{- range $line := splitList "\n" $config -}}
{{- $pair := splitList "=" $line -}}
{{- if eq (len $pair) 2 -}}
{{- $_ := set $configMap (trim (index $pair 0)) (trim (index $pair 1)) -}}
{{- end -}}
{{- end -}}
{{- if (index $configMap "webserver_port") -}}
{{- print (index $configMap "webserver_port") }}
{{- end }}
{{- end }}

{{/*
phoenixaicluster.cngroup.name is the PhoenixAICnGroup CR name for one entry of
.Values.phoenixAICnGroups. These groups attach to the cluster's default_warehouse, so the CR carries
no spec.phoenixAIWarehouse.
*/}}
{{- define "phoenixaicluster.cngroup.name" -}}
{{- printf "%s-%s" (include "phoenixaicluster.name" .root) .entry.name }}
{{- end }}

{{- define "phoenixaicluster.cngroup.configmap.name" -}}
{{- printf "%s-cm" (include "phoenixaicluster.cngroup.name" .) }}
{{- end }}

{{/*
phoenixaicluster.cngroup.hasOwnConfig is the one place that decides whether a CN group entry brings
its own cn.conf: "true" when config has content, "" (false) when it is missing, null or empty.
cnconfigmap.yaml, cngroup.config.hash and phoenixaicngroup.yaml must agree on this or a group points
at a ConfigMap that is never created. Takes the entry itself.
*/}}
{{- define "phoenixaicluster.cngroup.hasOwnConfig" -}}
{{- if not (empty .config) -}}true{{- end -}}
{{- end }}

{{- define "phoenixaicluster.cngroup.config.hash" -}}
{{- if include "phoenixaicluster.cngroup.hasOwnConfig" .entry -}}
{{- toJson .entry.config | sha256sum | trunc 8 -}}
{{- else -}}
{{- include "phoenixaicluster.cn.config.hash" .root | trim -}}
{{- end -}}
{{- end }}

{{/*
phoenixaicluster.cngroup.validate fails the render on an entry the operator would only reject later,
in status.reason.
*/}}
{{- define "phoenixaicluster.cngroup.validate" -}}
{{- $entry := .entry -}}
{{- $crName := include "phoenixaicluster.cngroup.name" . -}}
{{- if not $entry.name -}}
{{- fail "phoenixAICnGroups: every entry needs a name" -}}
{{- end -}}
{{- if not (regexMatch "^[a-z][a-z0-9-]*$" $entry.name) -}}
{{- fail (printf "phoenixAICnGroups: name %q must match ^[a-z][a-z0-9-]*$" $entry.name) -}}
{{- end -}}
{{- if gt (len $crName) 41 -}}
{{- fail (printf "phoenixAICnGroups: the resulting PhoenixAICnGroup name %q is %d characters; the limit is 41 because the operator appends -cngroup-cn and a revision hash to it" $crName (len $crName)) -}}
{{- end -}}
{{- if or (not $entry.image) (not $entry.image.repository) -}}
{{- fail (printf "phoenixAICnGroups: entry %q needs image.repository" $entry.name) -}}
{{- end -}}
{{- if not $entry.image.tag -}}
{{- fail (printf "phoenixAICnGroups: entry %q needs image.tag; CN Group requires a CN image >= 4.1.6-ee" $entry.name) -}}
{{- end -}}
{{- /* replicas is deliberately optional; see phoenixaiwarehouse.cngroup.validate in the warehouse chart. */}}
{{- if kindIs "string" $entry.replicas -}}
{{- fail (printf "phoenixAICnGroups: entry %q: replicas must be a number, got the string %q; leave the key out to let an HPA or kubectl scale own the count" $entry.name $entry.replicas) -}}
{{- end -}}
{{- /* Same fallback test as cnconfigmap.yaml's: an entry without its own config mounts the cluster CN
     ConfigMap, which is rendered only for an enabled CN with a non-empty config. */}}
{{- if and (not (include "phoenixaicluster.cngroup.hasOwnConfig" $entry)) (not (and .root.Values.phoenixAICluster.enabledCn .root.Values.phoenixAICnSpec .root.Values.phoenixAICnSpec.config)) -}}
{{- fail (printf "phoenixAICnGroups: entry %q has no config, and this release renders no cluster CN ConfigMap to fall back on; give the entry its own config" $entry.name) -}}
{{- end -}}
{{- end }}
