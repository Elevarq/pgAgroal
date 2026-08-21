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
{{- .Values.credentials.existingSecret }}
{{- end }}

{{/*
Fail closed when no credential Secret is provided. The image and chart ship
NO credential values of any kind: the operator supplies their own existing
PostgreSQL credentials in a Kubernetes Secret referenced by
credentials.existingSecret. The chart never creates a Secret and never
contains a password value; it only references the operator's Secret.
*/}}
{{- define "pgagroal.validateCredentials" -}}
{{- if not .Values.credentials.existingSecret }}
{{- fail "pgagroal: set credentials.existingSecret to the name of a Kubernetes Secret containing PG_USERNAME and PG_PASSWORD. The chart contains no credential values and does not create the Secret." }}
{{- end }}
{{- end }}

{{/*
Validate the frontend TLS values (fail closed on typed or unsupported input).
*/}}
{{- define "pgagroal.validateTLS" -}}
{{- if not (kindIs "bool" .Values.tls.enabled) }}
{{- fail "pgagroal: tls.enabled must be a boolean (true or false, not a quoted string)" }}
{{- end }}
{{- if not (kindIs "bool" .Values.tls.mutualTLS) }}
{{- fail "pgagroal: tls.mutualTLS must be a boolean (true or false, not a quoted string)" }}
{{- end }}
{{- if and .Values.tls.enabled (empty .Values.tls.existingSecret) }}
{{- fail "pgagroal: tls.existingSecret is required when tls.enabled is true (a Secret with keys tls.crt, tls.key, and ca.crt for mutual TLS)" }}
{{- end }}
{{- if and .Values.tls.mutualTLS (not .Values.tls.enabled) }}
{{- fail "pgagroal: tls.mutualTLS requires tls.enabled=true" }}
{{- end }}
{{- if ne .Values.tls.certAuthMode "verify-ca" }}
{{- fail "pgagroal: tls.certAuthMode must be verify-ca (the pgagroal 2.1.0 pooler supports verify-ca client-certificate checking only)" }}
{{- end }}
{{- end }}

{{/*
pgexporter (optional metrics-exporter component) names and labels.
*/}}
{{- define "pgagroal.pgexporter.fullname" -}}
{{- printf "%s-pgexporter" (include "pgagroal.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "pgagroal.pgexporter.selectorLabels" -}}
app.kubernetes.io/name: {{ printf "%s-pgexporter" (include "pgagroal.name" .) }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: metrics-exporter
{{- end }}

{{- define "pgagroal.pgexporter.labels" -}}
helm.sh/chart: {{ include "pgagroal.chart" . }}
{{ include "pgagroal.pgexporter.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.pgexporter.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Secret name for the pgexporter monitoring-role credentials. Mirrors the
pooler credentials: the chart ships NO credential values and never creates
a Secret; the operator provides one and the chart references it by name.
*/}}
{{- define "pgagroal.pgexporter.secretName" -}}
{{- if .Values.pgexporter.credentials.existingSecret }}
{{- .Values.pgexporter.credentials.existingSecret }}
{{- else }}
{{- fail "pgagroal: set pgexporter.credentials.existingSecret to the name of a Kubernetes Secret containing PGEXPORTER_USER and PGEXPORTER_PASSWORD. The chart contains no credential values and does not create the Secret." }}
{{- end }}
{{- end }}
