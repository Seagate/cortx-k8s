{{- define "config.yaml" -}}
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
  {{- if .Values.configmap.cortxRgw.enabled }}
  rgw:
    auth_user: {{ .Values.configmap.cortxRgw.authUser }}
    auth_admin: {{ .Values.configmap.cortxRgw.authAdmin }}
    auth_secret: {{ .Values.configmap.cortxRgw.authSecret }}
    public:
      endpoints:
      - http://{{ .Values.configmap.cortxIoService.name }}:{{ .Values.configmap.cortxIoService.ports.http }}
      - https://{{ .Values.configmap.cortxIoService.name }}:{{ .Values.configmap.cortxIoService.ports.https }}
    service:
      endpoints:
      - http://:22751
      - https://:23001
    io_max_units: 8
    max_start_timeout: {{ .Values.configmap.cortxRgw.maxStartTimeout | int }}
    service_instances: 1
    limits:
      services:
      - name: rgw
        memory:
          min: {{ .Values.configmap.cortxRgw.resources.rgw.requests.memory }}
          max: {{ .Values.configmap.cortxRgw.resources.rgw.limits.memory }}
        cpu:
          min: {{ .Values.configmap.cortxRgw.resources.rgw.requests.cpu }}
          max: {{ .Values.configmap.cortxRgw.resources.rgw.limits.cpu }}
    {{- if .Values.configmap.cortxRgw.extraConfiguration }}
    {{- tpl .Values.configmap.cortxRgw.extraConfiguration . | nindent 4 }}
    {{- end }}
  {{- end }}
  hare:
    hax:
      {{- with .Values.configmap.cortxHare }}
      {{- $endpoints := concat (list (printf "%s://%s:%d" .haxService.protocol .haxService.name (.haxService.port | int))) .haxDataEndpoints .haxClientEndpoints -}}
      {{- if $.Values.configmap.cortxRgw.enabled }}
      {{- $endpoints = concat $endpoints .haxServerEndpoints -}}
      {{- end }}
      endpoints:
      {{- toYaml (default (list) $endpoints) | nindent 8 }}
      {{- end }}
    limits:
      services:
      - name: hax
        memory:
          min: {{ .Values.configmap.cortxHare.resources.hax.requests.memory }}
          max: {{ .Values.configmap.cortxHare.resources.hax.limits.memory }}
        cpu:
          min: {{ .Values.configmap.cortxHare.resources.hax.requests.cpu }}
          max: {{ .Values.configmap.cortxHare.resources.hax.limits.cpu }}
  motr:
    interface_family: inet
    transport_type: libfab
    ios:
      endpoints: {{- toYaml .Values.configmap.cortxMotr.iosEndpoints | nindent 6 }}
    confd:
      endpoints: {{- toYaml .Values.configmap.cortxMotr.confdEndpoints | nindent 6 }}
    clients:
    {{- if .Values.configmap.cortxRgw.enabled }}
    - name: rgw_s3
      num_instances: 1  # number of instances *per-pod*
      endpoints: {{- toYaml .Values.configmap.cortxMotr.rgwEndpoints | nindent 8 }}
    {{- end }}
    - name: motr_client
      num_instances: {{ .Values.configmap.cortxMotr.clientInstanceCount | int }}
      num_subscriptions: 1
      subscriptions:
      - fdmi
      endpoints: {{- toYaml .Values.configmap.cortxMotr.clientEndpoints | nindent 8 }}
    limits:
      services:
      - name: ios
        memory:
          min: {{ .Values.configmap.cortxMotr.resources.motr.requests.memory }}
          max: {{ .Values.configmap.cortxMotr.resources.motr.limits.memory }}
        cpu:
          min: {{ .Values.configmap.cortxMotr.resources.motr.requests.cpu }}
          max: {{ .Values.configmap.cortxMotr.resources.motr.limits.cpu }}
      - name: confd
        memory:
          min: {{ .Values.configmap.cortxMotr.resources.confd.requests.memory }}
          max: {{ .Values.configmap.cortxMotr.resources.confd.limits.memory }}
        cpu:
          min: {{ .Values.configmap.cortxMotr.resources.confd.requests.cpu }}
          max: {{ .Values.configmap.cortxMotr.resources.confd.limits.cpu }}
    {{- if .Values.configmap.cortxMotr.extraConfiguration }}
    {{- tpl .Values.configmap.cortxMotr.extraConfiguration . | nindent 4 }}
    {{- end }}
  {{- if .Values.configmap.cortxControl.enabled }}
  csm:
    auth_admin: authadmin
    auth_secret: csm_auth_admin_secret
    mgmt_admin: cortxadmin
    mgmt_secret: csm_mgmt_admin_secret
    email_address: cortx@seagate.com
    agent:
      endpoints:
      - https://{{ .Values.configmap.cortxIoService.name }}:8081
    limits:
      services:
      - name: agent
        memory:
          min: {{ .Values.configmap.cortxControl.resources.agent.requests.memory }}
          max: {{ .Values.configmap.cortxControl.resources.agent.limits.memory }}
        cpu:
          min: {{ .Values.configmap.cortxControl.resources.agent.requests.cpu }}
          max: {{ .Values.configmap.cortxControl.resources.agent.limits.cpu }}
  {{- end }}
  {{- if .Values.configmap.cortxHa.enabled }}
  ha:
    limits:
      services:
      - name: fault_tolerance
        memory:
          min: {{ .Values.configmap.cortxHa.resources.fault_tolerance.requests.memory }}
          max: {{ .Values.configmap.cortxHa.resources.fault_tolerance.limits.memory }}
        cpu:
          min: {{ .Values.configmap.cortxHa.resources.fault_tolerance.requests.cpu }}
          max: {{ .Values.configmap.cortxHa.resources.fault_tolerance.limits.cpu }}
      - name: health_monitor
        memory:
          min: {{ .Values.configmap.cortxHa.resources.health_monitor.requests.memory }}
          max: {{ .Values.configmap.cortxHa.resources.health_monitor.limits.memory }}
        cpu:
          min: {{ .Values.configmap.cortxHa.resources.health_monitor.requests.cpu }}
          max: {{ .Values.configmap.cortxHa.resources.health_monitor.limits.cpu }}
      - name: k8s_monitor
        memory:
          min: {{ .Values.configmap.cortxHa.resources.k8s_monitor.requests.memory }}
          max: {{ .Values.configmap.cortxHa.resources.k8s_monitor.limits.memory }}
        cpu:
          min: {{ .Values.configmap.cortxHa.resources.k8s_monitor.requests.cpu }}
          max: {{ .Values.configmap.cortxHa.resources.k8s_monitor.limits.cpu }}
  {{- end }}
{{- end -}}
