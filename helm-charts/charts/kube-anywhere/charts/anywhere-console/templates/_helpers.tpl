{{/*
The prefix every resource of this chart carries. Same shape as the operator and
phoenixai subcharts alongside it: a shipped nameOverride, falling back to
"anywhere". It does NOT follow the release name — overriding it is what lets a
second console live in a namespace that already has one.
The fallback is the literal "anywhere", not .Chart.Name: up to 2.0.x the chart
itself was named "anywhere", so a standalone install with nameOverride="" owns
its resources — the data PVC data-anywhere-0 among them — under that prefix, and
following the chart's later name would hand it a new, empty PVC on upgrade.
Through the parent chart the alias is "anywhere" too, so nothing changes there.
*/}}
{{- define "anywhere.name" -}}
{{- default "anywhere" .Values.nameOverride -}}
{{- end }}

{{/*
The ServiceAccount the pod runs as; defaults to the nameOverride prefix like every other resource.
*/}}
{{- define "anywhere.serviceAccountName" -}}
{{- default (include "anywhere.name" .) .Values.serviceAccount.name -}}
{{- end }}

{{/*
The image repository. Up to 2.0.x the console image was published as
.../enterprise/anywhere; it is now .../enterprise/anywhere-console, and the old
repository receives no new versions. An install still carrying the old value —
pinned in its own values file (the 2.0.x example did that), or reused by
`helm upgrade --reuse-values` (the 2.0.x parent chart set it explicitly) — would
otherwise pull <old repository>:<this chart's appVersion>, a tag that does not
exist, and the single console pod would stay in ImagePullBackOff.
So the old repository is rewritten to the current one only when the tag follows
the chart (image.tag empty -> appVersion): that is the one case that can name a
tag the old repository will never get. With an explicit image.tag the repository
is used as written, because every tag the old repository ever had is still
served there (v2.0.0-rc1 exists only there). Any other repository, a mirror
included, is always used as given.
This mapping stays for good, or until a migration rewrites the stored value:
`--reuse-values` keeps carrying the old value into every later release, so
dropping it would break an install that has already upgraded through it.
*/}}
{{- define "anywhere.legacyImageRepository" -}}
us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/anywhere
{{- end }}

{{/* "true" when image.repository is the 2.0.x repository and the tag follows the chart. */}}
{{- define "anywhere.legacyImageRemapped" -}}
{{- if and (eq (.Values.image.repository | default "") (include "anywhere.legacyImageRepository" .)) (not .Values.image.tag) -}}
true
{{- end -}}
{{- end }}

{{- define "anywhere.imageRepository" -}}
{{- if include "anywhere.legacyImageRemapped" . -}}
us-west1-docker.pkg.dev/phoenix-ai-images/enterprise/anywhere-console
{{- else -}}
{{- .Values.image.repository | default "" -}}
{{- end -}}
{{- end }}

{{/*
The image tag defaults to the chart appVersion.
*/}}
{{- define "anywhere.imageTag" -}}
{{- default .Chart.AppVersion .Values.image.tag -}}
{{- end }}

{{/*
The Secret holding the Admin Console accounts (key = username, value =
password): the user-provided one, or the chart-rendered "<name>-admin".
*/}}
{{- define "anywhere.adminSecretName" -}}
{{- default (printf "%s-admin" (include "anywhere.name" .)) .Values.admin.existingSecret -}}
{{- end }}

{{/*
The data PVC the StatefulSet mounts: the user-provided existingClaim, or the
chart-rendered one (templates/pvc.yaml), named data-<name>-0.
*/}}
{{- define "anywhere.dataPVCName" -}}
{{- default (printf "data-%s-0" (include "anywhere.name" .)) .Values.persistence.existingClaim -}}
{{- end }}

{{/*
The namespaces anywhere serves, deduplicated, as a JSON array (use with
fromJsonArray). Empty means all namespaces (cluster-scoped RBAC, pairing a
global-mode operator).
*/}}
{{- define "anywhere.watchNamespaces" -}}
{{- $namespaces := list -}}
{{- range .Values.watchNamespaces -}}
{{- if and . (not (has . $namespaces)) -}}
{{- $namespaces = append $namespaces . -}}
{{- end -}}
{{- end -}}
{{- toJson $namespaces -}}
{{- end }}

{{/*
The spellings of a boolean the binary's config decoder (YAML 1.1) accepts, compared without
regard to case. Three switches used to be rendered verbatim, so "no" / "off" / "n" reached the
binary and decoded as false; reading them any other way would flip a switch on upgrade.
*/}}
{{- define "anywhere.boolFalseSpellings" -}}
{{- toJson (list "" "false" "no" "off" "n" "0") -}}
{{- end }}
{{- define "anywhere.boolTrueSpellings" -}}
{{- toJson (list "true" "yes" "on" "y" "1") -}}
{{- end }}

{{/*
A boolean switch: renders "true" or "false". Never a bare `if`: in a template any non-empty
string is true, so `if "false"` turned a switch ON for a value that arrives as a string
(--set-string, a quoted values file, a GitOps tool that stringifies values). A string is read
the way YAML 1.1 reads it, case-insensitively — "", "false", "no", "off", "n", "0" are false;
"true", "yes", "on", "y", "1" are true — and any other non-empty string stays true, as it always
was: the chart is GA, so a value that upgrades today must not stop `helm upgrade` tomorrow.
anywhere.boolWarnings names such a value in NOTES.txt. A non-string keeps its truthiness (a real
boolean as it is, absent as false).
Usage: include "anywhere.bool" <value>
*/}}
{{- define "anywhere.bool" -}}
{{- if kindIs "string" . -}}
{{- if has (lower .) (include "anywhere.boolFalseSpellings" . | fromJsonArray) }}false{{ else }}true{{ end -}}
{{- else if . }}true{{ else }}false{{ end -}}
{{- end }}

{{/*
One WARNING line per boolean switch of the config Secret that holds a string which is no
spelling of a boolean: anywhere.bool reads it as true, which whoever wrote it may not have meant.
The list must name exactly the switches secret-config.yaml reads through anywhere.bool — the
render test counts both sides.
*/}}
{{- define "anywhere.boolWarnings" -}}
{{- $deps := .Values.dependencies | default dict -}}
{{- $prom := $deps.prometheus | default dict -}}
{{- $known := concat (include "anywhere.boolFalseSpellings" . | fromJsonArray) (include "anywhere.boolTrueSpellings" . | fromJsonArray) -}}
{{- $sw := dict -}}
{{- $_ := set $sw "auth.secureCookies" (index (.Values.auth | default dict) "secureCookies") -}}
{{- $_ := set $sw "dependencies.gs.useComputeEngineServiceAccount" (index ($deps.gs | default dict) "useComputeEngineServiceAccount") -}}
{{- $_ := set $sw "dependencies.prometheus.enabled" (index $prom "enabled") -}}
{{- $_ := set $sw "dependencies.prometheus.tls.insecureSkipVerify" (index ($prom.tls | default dict) "insecureSkipVerify") -}}
{{- $_ := set $sw "dependencies.s3.usePathStyle" (index ($deps.s3 | default dict) "usePathStyle") -}}
{{- $_ := set $sw "queryHistory.enabled" (index (.Values.queryHistory | default dict) "enabled") -}}
{{- range $key, $v := $sw }}
{{- if and (kindIs "string" $v) (not (has (lower $v) $known)) }}
WARNING: {{ $key }} should be true or false; it is {{ $v | quote }}, which is read as true.
{{- end }}
{{- end }}
{{- end }}
