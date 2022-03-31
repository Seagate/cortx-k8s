{{- define "config.yaml" -}}
cortx:
  external:
    {{- if .Values.externalKafka.enabled }}
    kafka:
      endpoints: {{- toYaml .Values.externalKafka.endpoints | nindent 8 }}
      admin: {{ .Values.externalKafka.adminUser }}
      secret: {{ .Values.externalKafka.adminSecretName }}
    {{- end }}
    {{- if .Values.externalConsul.enabled }}
    consul:
      endpoints: {{- toYaml .Values.externalConsul.endpoints | nindent 8 }}
      admin: {{ .Values.externalConsul.adminUser }}
      secret: {{ .Values.externalConsul.adminSecretName }}
    {{- end }}
  common:
    release:
      name: CORTX
      version: {{ .Values.cortxVersion }}
    environment_type: K8                                            # DEPRECATED
    setup_size: {{ .Values.cortxSetupSize }}
    service:
      admin: admin
      secret: common_admin_secret
    storage: {{- toYaml .Values.cortxStoragePaths | nindent 6 }}
    security:
      ssl_certificate: /etc/cortx/solution/ssl/s3.seagate.com.pem
      domain_certificate: /etc/cortx/solution/ssl/stx.pem
      device_certificate: /etc/cortx/solution/ssl/stx.pem
  utils:
    message_bus_backend: kafka
  {{- if .Values.cortxRgw.enabled }}
  rgw:
    {{- $ioSvcName := required "A valid cortxIoService.name is required!" .Values.cortxIoService.name }}
    {{- $iosvcHttpPort := required "A valid cortxIoService.ports.http is required!" .Values.cortxIoService.ports.http }}
    {{- $iosvcHttpsPort := required "A valid cortxIoService.ports.https is required!" .Values.cortxIoService.ports.https }}
    auth_user: {{ .Values.cortxRgw.authUser }}
    auth_admin: {{ .Values.cortxRgw.authAdmin }}
    auth_secret: {{ .Values.cortxRgw.authSecret }}
    s3:                                                        # deprecated
      endpoints:
      - http://{{ $ioSvcName }}:{{ $iosvcHttpPort }}
      - https://{{ $ioSvcName }}:{{ $iosvcHttpsPort }}
    public:
      endpoints:
      - http://{{ $ioSvcName }}:{{ $iosvcHttpPort }}
      - https://{{ $ioSvcName }}:{{ $iosvcHttpsPort }}
    service:
      endpoints:
      - http://:22751
      - https://:23001
    io_max_units: 8
    max_start_timeout: {{ .Values.cortxRgw.maxStartTimeout | int }}
    service_instances: 1
    limits:
      services:
      - name: rgw
        memory:
          min: 128Mi
          max: 1Gi
        cpu:
          min: 250m
          max: 1000m
    {{- if .Values.cortxRgw.extraConfiguration }}
    {{- tpl .Values.cortxRgw.extraConfiguration . | nindent 4 }}
    {{- end }}
  {{- end }}
  hare:
    hax:
      endpoints:
      {{- with .Values.cortxHare.haxService }}
        - {{ .protocol }}://{{ .name }}:{{ .port }}
      {{- end }}
      {{- toYaml .Values.cortxHare.haxDataEndpoints | nindent 8 }}
      {{- if .Values.cortxRgw.enabled }}
      {{- toYaml .Values.cortxHare.haxServerEndpoints | nindent 8 }}
      {{- end }}
      {{- if gt (len .Values.cortxHare.haxClientEndpoints) 0 -}}
        {{- toYaml .Values.cortxHare.haxClientEndpoints | nindent 8 }}
      {{- end }}
    limits:
      services:
      - name: hax
        memory:
          min: 128Mi
          max: 1Gi
        cpu:
          min: 250m
          max: 500m
  motr:
    client_instances: {{ len .Values.cortxMotr.clientEndpoints }}   #DEPRECATED
    interface_type: tcp                                             #DEPRECATED
    interface_family: inet
    transport_type: libfab
    md_size: {{ .Values.cortxMotr.md_size }}
    ios:
      group_size: {{ .Values.cortxMotr.group_size }}
      endpoints: {{- toYaml .Values.cortxMotr.iosEndpoints | nindent 6 }}
    confd:
      endpoints: {{- toYaml .Values.cortxMotr.confdEndpoints | nindent 6 }}
    clients:
    {{- if .Values.cortxRgw.enabled }}
    - name: rgw
      num_instances: 1  # number of instances *per-pod*
      endpoints: {{- toYaml .Values.cortxMotr.rgwEndpoints | nindent 8 }}
    {{- end }}
    - name: motr_client
      num_instances: {{ .Values.cortxMotr.clientInstanceCount | int }}
      num_subscriptions: 1
      subscriptions:
      - fdmi
      endpoints: {{- toYaml .Values.cortxMotr.clientEndpoints | nindent 8 }}
    limits:
      services:
      - name: ios
        memory:
          min: 1Gi
          max: 2Gi
        cpu:
          min: 250m
          max: 1000m
      - name: confd
        memory:
          min: 128Mi
          max: 512Mi
        cpu:
          min: 250m
          max: 500m
    {{- if .Values.cortxMotr.extraConfiguration }}
    {{- tpl .Values.cortxMotr.extraConfiguration . | nindent 4 }}
    {{- end }}
  {{- if .Values.cortxControl.enabled }}
  csm:
    {{- $ioSvcName := required "A valid cortxIoService.name is required!" .Values.cortxIoService.name }}
    {{- $iosvcHttpPort := required "A valid cortxIoService.ports.http is required!" .Values.cortxIoService.ports.http }}
    {{- $iosvcHttpsPort := required "A valid cortxIoService.ports.https is required!" .Values.cortxIoService.ports.https }}
    auth_admin: authadmin
    auth_secret: csm_auth_admin_secret
    mgmt_admin: cortxadmin
    mgmt_secret: csm_mgmt_admin_secret
    email_address: cortx@seagate.com
    agent:
      endpoints:
      - https://{{ $ioSvcName }}:8081
    limits:
      services:
      - name: agent
        memory:
          min: 128Mi
          max: 256Mi
        cpu:
          min: 250m
          max: 500m
  {{- end }}
  {{- if .Values.cortxHa.enabled }}
  ha:
    limits:
      services:
      - name: fault_tolerance
        memory:
          min: 128Mi
          max: 1Gi
        cpu:
          min: 250m
          max: 500m
      - name: health_monitor
        memory:
          min: 128Mi
          max: 1Gi
        cpu:
          min: 250m
          max: 500m
      - name: k8s_monitor
        memory:
          min: 128Mi
          max: 1Gi
        cpu:
          min: 250m
          max: 500m
  {{- end }}
{{- end -}}
