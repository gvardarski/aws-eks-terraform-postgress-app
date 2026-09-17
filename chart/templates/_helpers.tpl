{{- define "inventory.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "inventory.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "inventory.api.fullname" -}}
{{- printf "%s-api" (include "inventory.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "inventory.postgres.fullname" -}}
{{- printf "%s-postgres" (include "inventory.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "inventory.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "inventory.labels" -}}
helm.sh/chart: {{ include "inventory.chart" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ include "inventory.name" . }}
{{- end -}}

{{- define "inventory.api.selectorLabels" -}}
app.kubernetes.io/name: api
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "inventory.postgres.selectorLabels" -}}
app.kubernetes.io/name: postgres
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Name of the Secret holding the PostgreSQL credentials, which is either
pre-created out of band or rendered by this chart.
*/}}
{{- define "inventory.secretName" -}}
{{- if .Values.postgres.auth.existingSecret -}}
{{- .Values.postgres.auth.existingSecret -}}
{{- else -}}
{{- include "inventory.postgres.fullname" . -}}
{{- end -}}
{{- end -}}
