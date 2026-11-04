{{- define "phoenixaiwarehouse.name" -}}
{{ .Release.Name }}
{{- end }}

{{- define "phoenixaiwarehouse.namespace" -}}
{{ .Release.Namespace }}
{{- end }}

{{/*
phoenixaiwarehouse.prefix is the name prefix the operator gives every sub-resource of a warehouse
(StatefulSet, Services, ConfigMap, HPA), and the value it puts in their
app.phoenixai.ownerreference/name label. It must stay in sync with GetPrefixNameForWarehouse in
pkg/k8sutils/templates/object/meta.go.
*/}}
{{- define "phoenixaiwarehouse.prefix" -}}
{{- print (include "phoenixaiwarehouse.name" .) "-warehouse" }}
{{- end }}

{{- define "phoenixaiwarehouse.cn.name" -}}
{{- print (include "phoenixaiwarehouse.prefix" .) "-cn" }}
{{- end }}

{{- define "phoenixaiwarehouse.labels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "phoenixaiwarehouse.configmap.name" -}}
{{- print (include "phoenixaiwarehouse.name" .) "-cm" }}
{{- end }}

{{- define "phoenixaiwarehouse.config" -}}
cn.conf: |
{{- if .Values.spec.config }}
{{- .Values.spec.config | nindent 2 }}
{{- end }}
{{- end }}

{{/*
phoenixaiwarehouse.config.hash is used to calculate the hash value of the cn.conf, and due to the length limit, only
the first 8 digits are taken, which will be used as the annotations for pods.
*/}}
{{- define "phoenixaiwarehouse.config.hash" }}
  {{- if .Values.spec.config }}
    {{- $hash := toJson .Values.spec.config | sha256sum | trunc 8 }}
    {{- printf "%s" $hash }}
  {{- else }}
    {{- printf "no-config" }}
  {{- end }}
{{- end }}

{{- define "phoenixaiwarehouse.webserver.port" -}}
{{- include "phoenixaiwarehouse.get.webserver.port" .Values.spec }}
{{- end }}

{{- define "phoenixaiwarehouse.get.webserver.port" -}}
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

{{- define "phoenixaicluster.cn.data.suffix" -}}
{{- print "-data" }}
{{- end }}

{{- define "phoenixaicluster.cn.data.path" -}}
{{- print "/opt/starrocks/cn/storage" }}
{{- end }}

{{- define "phoenixaicluster.cn.log.suffix" -}}
{{- print "-log" }}
{{- end }}

{{- define "phoenixaicluster.cn.log.path" -}}
{{- print "/opt/starrocks/cn/log" }}
{{- end }}

{{/*
phoenixaiwarehouse.cnspec renders the CN spec shared by the PhoenixAIWarehouse (spec.template) and
by every PhoenixAICnGroup (spec.phoenixAICnSpec). Both sit two levels deep, so the body is emitted
at its final indentation and callers include it directly.

The body reads the values block as .Values.spec.* on purpose, never through a variable: an IDE
resolves `.Values.spec.tolerations` to the key in values.yaml (find usages, go to definition) but
cannot follow a `$spec` that arrived through a dict argument. So the argument is not the spec but a
context shaped like the chart's own, a dict with two keys:

  Values  the chart values. For the warehouse itself that is .Values; for a CN group it is a copy of
          .Values whose `spec` key is replaced by the entry, built with
          `set (omit $root.Values "spec") "spec" $entry`. Never build it with merge: sprig's merge
          recurses into nested maps, so the entry would inherit every key the warehouse's spec sets.
  cnspec  what differs per call:
            configMapName  the cn.conf ConfigMap to point at
            configHash     the value of the cn-config-hash annotation
            envVarsKey     "envVars" (PhoenixAIWarehouse.spec.template, the default) or
                           "cnEnvVars" (PhoenixAICnSpec)
            config         the cn.conf that applies to these pods when it is not .Values.spec.config
            extraEnvVars   environment variables the caller has to add (the phoenixai subchart uses
                           it for the generated root password; unset here)

The phoenixai subchart carries a copy of this body as phoenixaicluster.cngroup.cnspec so that a CN
group declared next to a cluster renders identically; scripts/internal/check-helm.sh renders the
same entry through both charts and diffs the result to catch drift.
*/}}
{{- define "phoenixaiwarehouse.cnspec" -}}
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
        prometheus.io/port: "{{- default 8040 (include "phoenixaiwarehouse.get.webserver.port" (dict "config" $config)) }}"
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
      ad.datadoghq.com/warehouse.logs: '[{"service":"warehouse"}]'
      {{- else }}
      ad.datadoghq.com/warehouse.logs: {{ printf "[%s]" (printf "{%s, \"service\": \"warehouse\"}" (trimAll " {}" .Values.datadog.log.logConfig) | fromJson | toJson) | squote }}
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

{{/*
phoenixaiwarehouse.cngroup.name is the PhoenixAICnGroup CR name for one entry of .Values.cnGroups.
The operator turns it into the CN group name in the FE by replacing '-' with '_', and derives every
sub-resource name from it, so it is also what the length limit applies to.
*/}}
{{- define "phoenixaiwarehouse.cngroup.name" -}}
{{- printf "%s-%s" (include "phoenixaiwarehouse.name" .root) .entry.name }}
{{- end }}

{{- define "phoenixaiwarehouse.cngroup.configmap.name" -}}
{{- printf "%s-cm" (include "phoenixaiwarehouse.cngroup.name" .) }}
{{- end }}

{{/*
phoenixaiwarehouse.cngroup.hasOwnConfig is the one place that decides whether a CN group entry brings
its own cn.conf: "true" when config has content, "" (false) when it is missing, null or empty. Three
templates must agree on this or a group points at a ConfigMap that is never created: cnconfigmap.yaml
(whether the entry's ConfigMap is rendered), cngroup.config.hash (which config rolls its pods) and
phoenixaicngroup.yaml (which ConfigMap the CR mounts). Takes the entry itself:
  {{ if include "phoenixaiwarehouse.cngroup.hasOwnConfig" $entry }}
*/}}
{{- define "phoenixaiwarehouse.cngroup.hasOwnConfig" -}}
{{- if not (empty .config) -}}true{{- end -}}
{{- end }}

{{/*
phoenixaiwarehouse.cngroup.config.hash mirrors phoenixaiwarehouse.config.hash for a CN group entry:
a group that brings its own cn.conf must roll when that config changes, and a group that shares the
warehouse's ConfigMap must roll exactly when the warehouse does.
*/}}
{{- define "phoenixaiwarehouse.cngroup.config.hash" -}}
{{- if include "phoenixaiwarehouse.cngroup.hasOwnConfig" .entry -}}
{{- toJson .entry.config | sha256sum | trunc 8 -}}
{{- else -}}
{{- include "phoenixaiwarehouse.config.hash" .root | trim -}}
{{- end -}}
{{- end }}

{{/*
phoenixaiwarehouse.cngroup.validate fails the render on an entry that the operator would only reject
later, in status.reason. A helm error at install time is much easier to act on.
*/}}
{{- define "phoenixaiwarehouse.cngroup.validate" -}}
{{- $entry := .entry -}}
{{- $crName := include "phoenixaiwarehouse.cngroup.name" . -}}
{{- if not $entry.name -}}
{{- fail "cnGroups: every entry needs a name" -}}
{{- end -}}
{{- if not (regexMatch "^[a-z][a-z0-9-]*$" $entry.name) -}}
{{- fail (printf "cnGroups: name %q must match ^[a-z][a-z0-9-]*$" $entry.name) -}}
{{- end -}}
{{- if gt (len $crName) 41 -}}
{{- fail (printf "cnGroups: the resulting PhoenixAICnGroup name %q is %d characters; the limit is 41 because the operator appends -cngroup-cn and a revision hash to it" $crName (len $crName)) -}}
{{- end -}}
{{- if or (not $entry.image) (not $entry.image.repository) -}}
{{- fail (printf "cnGroups: entry %q needs image.repository" $entry.name) -}}
{{- end -}}
{{- if not $entry.image.tag -}}
{{- fail (printf "cnGroups: entry %q needs image.tag; CN Group requires a CN image >= 4.1.6-ee" $entry.name) -}}
{{- end -}}
{{- /* replicas is deliberately optional. Left out (or null), the CR carries no replicas and the CRD
     default of 1 applies once; after that whoever scales the group -- an HPA through
     autoScalingPolicy, or kubectl scale -- owns the count, because a helm upgrade that never mentions
     the field never resets it. A string is refused here because the render would otherwise succeed
     and the API server reject the CR: `--set cnGroups[0].replicas=` passes an empty string, which
     would render as a null. */}}
{{- if kindIs "string" $entry.replicas -}}
{{- fail (printf "cnGroups: entry %q: replicas must be a number, got the string %q; leave the key out to let an HPA or kubectl scale own the count" $entry.name $entry.replicas) -}}
{{- end -}}
{{- /* Same fallback test as cnconfigmap.yaml's: an entry without its own config mounts the warehouse
     ConfigMap, which is rendered only for a non-empty spec.config. */}}
{{- if and (not (include "phoenixaiwarehouse.cngroup.hasOwnConfig" $entry)) (not (and .root.Values.spec .root.Values.spec.config)) -}}
{{- fail (printf "cnGroups: entry %q has no config, and this release renders no warehouse ConfigMap to fall back on (spec.config is empty); give the entry its own config" $entry.name) -}}
{{- end -}}
{{- end }}
