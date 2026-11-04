{{/*
The default service account name to use for the operator.
*/}}
{{- define "operator.serviceAccountName" -}}
{{- default "phoenixai" .Values.global.rbac.serviceAccount.name }}
{{- end }}

{{- define "operator.namespace" -}}
{{- default .Release.Namespace .Values.phoenixAIOperator.namespaceOverride }}
{{- end }}

{{- define "operator.name" -}}
{{- default .Chart.Name .Values.nameOverride -}}
{{- end }}

{{/*
The Service in front of the operator's gRPC query API. It is named after the
Deployment it fronts (<prefix>-operator) rather than a bare <prefix>-api: one
release can carry both this and the Anywhere console, which serves an API of
its own, and which API a Service leads to has to be readable from its name.
*/}}
{{- define "operator.apiServiceName" -}}
{{- printf "%s-operator-api" (include "operator.name" .) -}}
{{- end }}
