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

{{/*
Return the name of the Hare hax component
*/}}
{{- define "cortx.hare.hax.fullname" -}}
{{- printf "%s-hax" (include "cortx.fullname" .) -}}
{{- end -}}

{{/*
Create a URL for the Hare hax HTTP endpoint
*/}}
{{- define "cortx.hare.hax.url" -}}
{{- printf "%s://%s:%d" .Values.hare.hax.ports.http.protocol (include "cortx.hare.hax.fullname" $) (int .Values.hare.hax.ports.http.port) -}}
{{- end -}}

{{/*
Return the Hare hax TCP endpoint port
*/}}
{{- define "cortx.hare.hax.tcpPort" -}}
22001
{{- end -}}

{{/*
Return the name of the Server component
*/}}
{{- define "cortx.server.fullname" -}}
{{- printf "%s-server" (include "cortx.fullname" .) -}}
{{- end -}}

{{/*
Return the name of the Server service domain
*/}}
{{- define "cortx.server.serviceDomain" -}}
{{- printf "%s-headless.%s.svc.%s" (include "cortx.server.fullname" .) .Release.Namespace .Values.clusterDomain -}}
{{- end -}}

{{/*
Return the name of the Data component
*/}}
{{- define "cortx.data.fullname" -}}
{{- printf "%s-data" (include "cortx.fullname" .) -}}
{{- end -}}

{{/*
Return the name of the Data service domain
*/}}
{{- define "cortx.data.serviceDomain" -}}
{{- printf "%s-headless.%s.svc.%s" (include "cortx.data.fullname" .) .Release.Namespace .Values.clusterDomain -}}
{{- end -}}

{{/*
Return the Motr IOS endpoint port
*/}}
{{- define "cortx.data.iosPort" -}}
21002
{{- end -}}
