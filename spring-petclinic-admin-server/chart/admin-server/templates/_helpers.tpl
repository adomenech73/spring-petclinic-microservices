{{/*
Generate the full name of the chart.
*/}}
{{- define "petclinic-chart.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Generate labels.
*/}}
{{- define "petclinic-chart.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: Helm
{{- end -}}

{{/*
Generate service account name.
*/}}
{{- define "petclinic-chart.serviceAccountName" -}}
{{- if .Values.serviceAccount.name }}
{{ .Values.serviceAccount.name }}
{{- else }}
{{ include "petclinic-chart.fullname" . }}
{{- end }}
{{- end -}}
