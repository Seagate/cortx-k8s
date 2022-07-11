{{/*
Return a valid CORTX image name from parts
{{ include "cortx.images.image" ( dict "image" .Values.path.to.the.image "root" $) }}
*/}}
{{- define "cortx.images.image" -}}
{{- printf "%s/%s:%s" .image.registry .image.repository (default .root.Chart.AppVersion .image.tag) -}}
{{- end -}}

{{/*
Return the Client image name
*/}}
{{- define "cortx.client.image" -}}
{{ include "cortx.images.image" (dict "image" .Values.client.image "root" .) }}
{{- end -}}
