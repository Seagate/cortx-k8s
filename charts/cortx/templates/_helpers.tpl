{{/*
Expand the name of the chart.
*/}}
{{- define "cortx.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "cortx.fullname" -}}
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
Create a default fully qualified app name for Consul subchart
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "cortx.consul.fullname" -}}
{{/*
{{- include "common.names.dependency.fullname" (dict "chartName" "kafka" "chartValues" .Values.kafka "context" $) -}}
*/}}
{{- printf "%s-consul" (include "cortx.fullname" .) -}}
{{- end -}}

{{/*
Create a default fully qualified app name for Kafka subchart
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "cortx.kafka.fullname" -}}
{{/*
{{- include "common.names.dependency.fullname" (dict "chartName" "kafka" "chartValues" .Values.kafka "context" $) -}}
*/}}
{{- printf "%s-kafka" (include "cortx.fullname" .) -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "cortx.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "cortx.labels" -}}
helm.sh/chart: {{ include "cortx.chart" . }}
{{ include "cortx.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "cortx.selectorLabels" -}}
app.kubernetes.io/name: {{ include "cortx.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "cortx.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "cortx.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the CORTX configuration configmap
*/}}
{{- define "cortx.configmapName" -}}
{{- include "cortx.fullname" . -}}
{{- end -}}

{{/*
Return the CORTX SSL certificate configmap
*/}}
{{- define "cortx.tls.configmapName" -}}
{{- printf "%s-ssl-cert" (include "cortx.fullname" .) -}}
{{- end -}}

{{/*
Return the name of the Control component
*/}}
{{- define "cortx.control.fullname" -}}
{{- printf "%s-control" (include "cortx.fullname" .) -}}
{{- end -}}

{{/*
Return the name of the HA component
*/}}
{{- define "cortx.ha.fullname" -}}
{{- printf "%s-ha" (include "cortx.fullname" .) -}}
{{- end -}}
