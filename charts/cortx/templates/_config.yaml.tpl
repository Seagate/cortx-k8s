{{- define "config.yaml.service.limits" -}}
- name: {{ .name }}
  memory:
    min: {{ .resources.requests.memory }}
    max: {{ .resources.limits.memory }}
  cpu:
    min: {{ .resources.requests.cpu }}
    max: {{ .resources.limits.cpu }}
{{- end -}}

{{- define "config.yaml" -}}
{{- $dataHostnames := list -}}
{{- range $i := until (int .Values.cortxdata.replicas) -}}
{{- $dataHostnames = append $dataHostnames (printf "%s-%d.%s" (include "cortx.data.fullname" $) $i (include "cortx.data.serviceDomain" $)) -}}
{{- end -}}
{{- $serverHostnames := list -}}
{{- if .Values.cortxserver.enabled -}}
{{- range $i := until (int .Values.cortxserver.replicas) -}}
{{- $serverHostnames = append $serverHostnames (printf "%s-%d.%s" (include "cortx.server.fullname" $) $i (include "cortx.server.serviceDomain" $)) -}}
{{- end -}}
{{- end -}}
{{- $iosPort := 21002 -}}
{{- $confdPort := 21001 -}}
{{- $rgwClientPort := 22501 -}}
cortx:
  external:
    kafka:
      {{- if .Values.kafka.enabled }}
      endpoints:
        - tcp://{{ include "cortx.fullname" . }}-kafka:9092
      {{- else }}
      endpoints: {{- toYaml .Values.externalKafka.endpoints | nindent 8 }}
      {{- end }}
      admin: {{ .Values.externalKafka.adminUser }}
      secret: {{ .Values.externalKafka.adminSecretName }}
    consul:
      {{- if .Values.consul.enabled }}
      endpoints:
        - tcp://{{ include "cortx.fullname" . }}-consul-server:8301
        - http://{{ include "cortx.fullname" . }}-consul-server:8500
      {{- else }}
      endpoints: {{- toYaml .Values.externalConsul.endpoints | nindent 8 }}
      {{- end }}
      admin: {{ .Values.externalConsul.adminUser }}
      secret: {{ .Values.externalConsul.adminSecretName }}
  common:
    release:
      name: CORTX
      version: {{ .Values.configmap.cortxVersion }}
    service:
      admin: admin
      secret: common_admin_secret
    storage: {{- toYaml .Values.configmap.cortxStoragePaths | nindent 6 }}
    security:
      ssl_certificate: /etc/cortx/solution/ssl/s3.seagate.com.pem
      domain_certificate: /etc/cortx/solution/ssl/stx.pem
      device_certificate: /etc/cortx/solution/ssl/stx.pem
  utils:
    message_bus_backend: kafka
  {{- if .Values.cortxserver.enabled }}
  rgw:
    auth_user: {{ .Values.cortxserver.authUser }}
    auth_admin: {{ .Values.cortxserver.authAdmin }}
    auth_secret: {{ .Values.cortxserver.authSecret }}
    public:
      endpoints:
      - {{ printf "http://%s-0:%d" (include "cortx.server.fullname" .) (.Values.cortxserver.service.ports.http | int) }}
      - {{ printf "https://%s-0:%d" (include "cortx.server.fullname" .) (.Values.cortxserver.service.ports.https | int) }}
    service:
      endpoints:
      - http://:22751
      - https://:23001
    io_max_units: 8
    max_start_timeout: {{ .Values.cortxserver.maxStartTimeout | int }}
    service_instances: 1
    limits:
      services:
      - name: rgw
        memory:
          min: {{ .Values.cortxserver.rgw.resources.requests.memory }}
          max: {{ .Values.cortxserver.rgw.resources.limits.memory }}
        cpu:
          min: {{ .Values.cortxserver.rgw.resources.requests.cpu }}
          max: {{ .Values.cortxserver.rgw.resources.limits.cpu }}
    {{- if .Values.cortxserver.extraConfiguration }}
    {{- tpl .Values.cortxserver.extraConfiguration . | nindent 4 }}
    {{- end }}
  {{- end }}
  hare:
    hax:
      endpoints:
      - {{ include "cortx.hare.hax.url" . }}
      {{- range (concat $dataHostnames $serverHostnames) }}
      - {{ printf "tcp://%s:%d" . (include "cortx.hare.hax.tcpPort" $ | int) }}
      {{- end }}
      {{- if .Values.configmap.cortxHare.haxClientEndpoints }}
      {{- toYaml .Values.configmap.cortxHare.haxClientEndpoints | nindent 6 }}
      {{- end }}
    limits:
      services:
      {{- include "config.yaml.service.limits" (dict "name" "hax" "resources" .Values.hare.hax.resources) | nindent 6 }}
  motr:
    interface_family: inet
    transport_type: libfab
    ios:
      endpoints:
      {{- range $dataHostnames }}
      - {{ printf "tcp://%s:%d" . $iosPort }}
      {{- end }}
    confd:
      endpoints:
      {{- range $dataHostnames }}
      - {{ printf "tcp://%s:%d" . $confdPort }}
      {{- end }}
    clients:
    {{- if .Values.cortxserver.enabled }}
    - name: rgw_s3
      num_instances: 1  # number of instances *per-pod*
      endpoints:
      {{- range $serverHostnames }}
      - {{ printf "tcp://%s:%d" . $rgwClientPort }}
      {{- end }}
    {{- end }}
    - name: motr_client
      num_instances: {{ .Values.configmap.cortxMotr.clientInstanceCount | int }}
      num_subscriptions: 1
      subscriptions:
      - fdmi
      endpoints: {{- toYaml .Values.configmap.cortxMotr.clientEndpoints | nindent 6 }}
    limits:
      services:
      {{- include "config.yaml.service.limits" (dict "name" "ios" "resources" .Values.configmap.cortxMotr.motr.resources) | nindent 6 }}
      {{- include "config.yaml.service.limits" (dict "name" "confd" "resources" .Values.configmap.cortxMotr.confd.resources) | nindent 6 }}
    {{- if .Values.configmap.cortxMotr.extraConfiguration }}
    {{- tpl .Values.configmap.cortxMotr.extraConfiguration . | nindent 4 }}
    {{- end }}
  {{- if .Values.cortxcontrol.enabled }}
  csm:
    agent:
      endpoints:
      - https://:23256
    auth_admin: authadmin
    auth_secret: csm_auth_admin_secret
    email_address: cortx@seagate.com # Optional
    mgmt_admin: cortxadmin
    mgmt_secret: csm_mgmt_admin_secret
    limits:
      services:
      {{- include "config.yaml.service.limits" (dict "name" "agent" "resources" .Values.configmap.cortxControl.agent.resources) | nindent 6 }}
  {{- end }}
  {{- if .Values.cortxha.enabled }}
  ha:
    limits:
      services:
      {{- include "config.yaml.service.limits" (dict "name" "fault_tolerance" "resources" .Values.cortxha.fault_tolerance.resources) | nindent 6 }}
      {{- include "config.yaml.service.limits" (dict "name" "health_monitor" "resources" .Values.cortxha.health_monitor.resources) | nindent 6 }}
      {{- include "config.yaml.service.limits" (dict "name" "k8s_monitor" "resources" .Values.cortxha.k8s_monitor.resources) | nindent 6 }}
  {{- end }}
{{- end -}}
