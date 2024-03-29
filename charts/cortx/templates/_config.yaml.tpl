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
{{- $statefulSetCount := (include "cortx.data.statefulSetCount" .) | int -}}
{{- range $stsIndex := until $statefulSetCount }}
{{- range $i := until (int $.Values.data.replicaCount) -}}
{{- $dataHostnames = append $dataHostnames (printf "%s-%d.%s" (include "cortx.data.groupFullname" (dict "root" $ "stsIndex" $stsIndex)) $i (include "cortx.data.serviceDomain" $)) -}}
{{- end -}}
{{- end -}}
{{- $serverHostnames := list -}}
{{- if .Values.server.enabled -}}
{{- range $i := until (int .Values.server.replicaCount) -}}
{{- $serverHostnames = append $serverHostnames (printf "%s-%d.%s" (include "cortx.server.fullname" $) $i (include "cortx.server.serviceDomain" $)) -}}
{{- end -}}
{{- end -}}
{{- $clientHostnames := list -}}
{{- if .Values.client.enabled -}}
{{- range $i := until (int .Values.client.replicaCount) -}}
{{- $clientHostnames = append $clientHostnames (printf "%s-%d.%s" (include "cortx.client.fullname" $) $i (include "cortx.client.serviceDomain" $)) -}}
{{- end -}}
{{- end -}}
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
    service:
      admin: admin
      secret: common_admin_secret
    storage:
      log: /etc/cortx/log
      local: /etc/cortx
      config: /etc/cortx
    security:
      ssl_certificate: /etc/cortx/solution/ssl/cortx.pem
      domain_certificate: /etc/cortx/solution/ssl/stx.pem
      device_certificate: /etc/cortx/solution/ssl/stx.pem
  utils:
    message_bus_backend: kafka
  {{- if .Values.server.enabled }}
  rgw:
    auth_user: {{ .Values.server.auth.adminUser }}
    auth_admin: {{ .Values.server.auth.adminAccessKey }}
    auth_secret: s3_auth_admin_secret
    public:
      endpoints:
      - {{ printf "http://%s-0:%d" (include "cortx.server.fullname" .) (.Values.server.service.ports.http | int) }}
      - {{ printf "https://%s-0:%d" (include "cortx.server.fullname" .) (.Values.server.service.ports.https | int) }}
    service:
      endpoints:
      - {{ printf "http://:%d" (include "cortx.server.rgwHttpPort" . | int) }}
      - {{ printf "https://:%d" (include "cortx.server.rgwHttpsPort" . | int) }}
    io_max_units: 8
    max_start_timeout: {{ .Values.server.maxStartTimeout | int }}
    service_instances: 1
    limits:
      services:
      - name: rgw
        memory:
          min: {{ .Values.server.rgw.resources.requests.memory }}
          max: {{ .Values.server.rgw.resources.limits.memory }}
        cpu:
          min: {{ .Values.server.rgw.resources.requests.cpu }}
          max: {{ .Values.server.rgw.resources.limits.cpu }}
    {{- if .Values.server.extraConfiguration }}
    {{- tpl .Values.server.extraConfiguration . | nindent 4 }}
    {{- end }}
  {{- end }}
  hare:
    hax:
      endpoints:
      - {{ include "cortx.hare.hax.url" . }}
      {{- range (concat $dataHostnames $serverHostnames $clientHostnames) }}
      - {{ printf "tcp://%s:%d" . (include "cortx.hare.hax.tcpPort" $ | int) }}
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
      - {{ printf "tcp://%s:%d" . (include "cortx.data.iosPort" $ | int) }}
      {{- end }}
    confd:
      endpoints:
      {{- range $dataHostnames }}
      - {{ printf "tcp://%s:%d" . (include "cortx.data.confdPort" $ | int) }}
      {{- end }}
    clients:
    {{- if .Values.server.enabled }}
    - name: rgw_s3
      num_instances: 1  # number of instances *per-pod*
      endpoints:
      {{- range $serverHostnames }}
      - {{ printf "tcp://%s:%d" . (include "cortx.server.motrClientPort" $ | int) }}
      {{- end }}
    {{- end }}
    {{- if .Values.client.enabled }}
    - name: motr_client
      num_instances: {{ .Values.client.instanceCount | int }}
      num_subscriptions: 1
      subscriptions:
      - fdmi
      endpoints:
      {{- range $clientHostnames }}
      - {{ printf "tcp://%s:%d" . (include "cortx.client.motrClientPort" $ | int) }}
      {{- end }}
    {{- end }}
    limits:
      services:
      {{- include "config.yaml.service.limits" (dict "name" "ios" "resources" .Values.data.ios.resources) | nindent 6 }}
      {{- include "config.yaml.service.limits" (dict "name" "confd" "resources" .Values.data.confd.resources) | nindent 6 }}
    {{- if .Values.data.extraConfiguration }}
    {{- tpl .Values.data.extraConfiguration . | nindent 4 }}
    {{- end }}
  {{- if .Values.control.enabled }}
  csm:
    agent:
      endpoints:
      - {{ printf "https://:%d" (include "cortx.control.agentPort" . | int) }}
    auth_admin: authadmin
    auth_secret: csm_auth_admin_secret
    email_address: cortx@seagate.com # Optional
    mgmt_admin: cortxadmin
    mgmt_secret: csm_mgmt_admin_secret
    limits:
      services:
      {{- include "config.yaml.service.limits" (dict "name" "agent" "resources" .Values.control.agent.resources) | nindent 6 }}
  {{- end }}
  {{- if .Values.ha.enabled }}
  ha:
    limits:
      services:
      {{- include "config.yaml.service.limits" (dict "name" "fault_tolerance" "resources" .Values.ha.faultTolerance.resources) | nindent 6 }}
      {{- include "config.yaml.service.limits" (dict "name" "health_monitor" "resources" .Values.ha.healthMonitor.resources) | nindent 6 }}
      {{- include "config.yaml.service.limits" (dict "name" "k8s_monitor" "resources" .Values.ha.k8sMonitor.resources) | nindent 6 }}
  {{- end }}
{{- end -}}
