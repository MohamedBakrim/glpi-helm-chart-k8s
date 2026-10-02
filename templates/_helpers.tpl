{{/*
Expand the name of the chart.
*/}}
{{- define "MyHelm.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "MyHelm.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "MyHelm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "MyHelm.labels" -}}
helm.sh/chart: {{ include "MyHelm.chart" . }}
{{ include "MyHelm.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "MyHelm.selectorLabels" -}}
app.kubernetes.io/name: {{ include "MyHelm.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Render a `- name:` volume entry backed by a PVC when persistence for that volume is
enabled, otherwise an emptyDir fallback (data becomes ephemeral) so pods never reference
a non-existent claim. Usage:
{{ include "MyHelm.dataVolume" (dict "name" "files" "claimName" "glpi-myhelm-files" "enabled" .Values.filesPersistence.enabled) | nindent 8 }}
*/}}
{{- define "MyHelm.dataVolume" -}}
- name: {{ .name }}
  {{- if .enabled }}
  persistentVolumeClaim:
    claimName: {{ .claimName }}
  {{- else }}
  emptyDir: {}
  {{- end }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "MyHelm.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "MyHelm.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
