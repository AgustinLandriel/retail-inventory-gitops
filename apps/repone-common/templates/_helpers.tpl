{{/*
Nombre del recurso: sale de .Values.name (el mismo que ya usamos hoy),
con fallback al nombre del chart.
*/}}
{{- define "repone-common.name" -}}
{{- default .Chart.Name .Values.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Namespace donde se instala el release (lo define ArgoCD en destination.namespace).
*/}}
{{- define "repone-common.namespace" -}}
{{- .Release.Namespace }}
{{- end }}

{{/*
Chart name y version, para el label helm.sh/chart.
*/}}
{{- define "repone-common.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Labels que van en selector del Deployment y del Service.
No deben cambiar nunca: el selector de un Deployment es inmutable.
*/}}
{{- define "repone-common.selectorLabels" -}}
app.kubernetes.io/name: {{ include "repone-common.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Labels completos para metadata.labels.
*/}}
{{- define "repone-common.labels" -}}
helm.sh/chart: {{ include "repone-common.chart" . }}
{{ include "repone-common.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}