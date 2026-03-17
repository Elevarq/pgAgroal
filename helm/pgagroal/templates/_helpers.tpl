{{/*
Expand the name of the chart.
*/}}
{{- define "pgagroal.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "pgagroal.fullname" -}}
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
Chart label values.
*/}}
{{- define "pgagroal.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "pgagroal.labels" -}}
helm.sh/chart: {{ include "pgagroal.chart" . }}
{{ include "pgagroal.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "pgagroal.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pgagroal.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
ServiceAccount name.
*/}}
{{- define "pgagroal.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "pgagroal.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Secret name for PostgreSQL credentials.
*/}}
{{- define "pgagroal.secretName" -}}
{{- if .Values.credentials.existingSecret }}
{{- .Values.credentials.existingSecret }}
{{- else }}
{{- include "pgagroal.fullname" . }}
{{- end }}
{{- end }}
