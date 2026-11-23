{{- /*
=============================================================================
File        : charts/tasktracker/templates/_helpers.tpl
Assignment  : DSO202 Assignment 4 (from Assignment 3, adjusted for GitOps)
Descriptor  : Unit III 3.2 - named templates
Purpose     : Shared fragments: labels, selector labels, the image reference,
              and the per-tier ConfigMap checksum.
=============================================================================
*/ -}}

{{- /* Labels on every object. The tier label is added per object. */ -}}
{{- define "tasktracker.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
app.kubernetes.io/part-of: tasktracker
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/environment: {{ .Values.environment }}
{{- end }}

{{- /* Selector labels: the Assignment 1 tier label plus the release name.
       Usage: include "tasktracker.selectorLabels" (dict "root" . "tier" "backend") */ -}}
{{- define "tasktracker.selectorLabels" -}}
tier: {{ .tier }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- end }}

{{- /* C1: image reference built only from values; no tag is written in a template.
       Usage: include "tasktracker.image" .Values.backend */ -}}
{{- define "tasktracker.image" -}}
{{ required "image.repository is required" .image.repository }}:{{ required "image.tag is required" .image.tag }}
{{- end }}

{{- /* C2: a tier's ConfigMap rendered from its 'env' map.
       Usage: include "tasktracker.envConfigMap" (dict "root" . "tier" "backend" "env" .Values.backend.env) */ -}}
{{- define "tasktracker.envConfigMap" -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .tier }}-config
  labels:
    {{- include "tasktracker.labels" .root | nindent 4 }}
    tier: {{ .tier }}
data:
  {{- range $key, $value := .env }}
  {{ $key }}: {{ $value | toString | quote }}
  {{- end }}
{{- end }}

{{- /* Checksum of a tier's ConfigMap, put on its Pod template. A values change
       to that tier's environment changes the Pod template, so the Pods roll
       (a running container does not re-read its ConfigMap).
       Usage: include "tasktracker.configChecksum" (dict "root" . "tier" "backend" "env" .Values.backend.env) */ -}}
{{- define "tasktracker.configChecksum" -}}
checksum/config: {{ include "tasktracker.envConfigMap" . | sha256sum }}
{{- end }}
