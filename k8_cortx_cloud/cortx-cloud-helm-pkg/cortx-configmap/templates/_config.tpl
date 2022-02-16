{{- define "config.yaml" -}}
cortx:
  external:
    {{- if .Values.externalKafka.enabled }}
    kafka:
      endpoints: {{- toYaml .Values.externalKafka.endpoints | nindent 8 }}
      admin: {{ .Values.externalKafka.adminUser }}
      secret: {{ .Values.externalKafka.adminSecretName }}
    {{- end }}
    {{- if .Values.externalLdap.enabled }}
    openldap:
      endpoints: {{- toYaml .Values.externalLdap.endpoints | nindent 8 }}
      servers: {{- toYaml .Values.externalLdap.servers | nindent 8 }}
      admin: {{ .Values.externalLdap.adminUser }}
      secret: {{ .Values.externalLdap.adminSecretName }}
      base_dn: {{ .Values.externalLdap.baseDn }}
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
    environment_type: K8
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
  s3:
    iam:
      endpoints:
      - https://{{ .Values.cortxIoServiceName }}:9443
      - http://{{ .Values.cortxIoServiceName }}:9080
    data:
      endpoints:
      - http://{{ .Values.cortxIoServiceName }}:80
      - https://{{ .Values.cortxIoServiceName }}:443
    internal:
      endpoints:
      - http://{{ .Values.cortxIoServiceName }}:28049
    {{- with .Values.cortxS3.instanceCount }}
    service_instances: {{ . | int }}
    {{- end }}
    io_max_units: 8
    {{- with .Values.cortxS3.maxStartTimeout }}
    max_start_timeout: {{ . | int }}
    {{- end }}
    auth_admin: sgiamadmin
    auth_secret: s3_auth_admin_secret
  hare:
    hax:
      endpoints:
      {{- with .Values.cortxHa.haxService }}
        - {{ .protocol }}://{{ .name }}:{{ .port }}
      {{- end }}
  motr:
    client_instances: {{ len .Values.cortxMotr.clientEndpoints }}
    interface_type: tcp
    interface_family: inet
    transport_type: libfab
    {{- if len .Values.cortxMotr.clientEndpoints }}
    clients:
      - name: motr_client
        num_instances: {{ len .Values.cortxMotr.clientEndpoints }}
        endpoints: {{- toYaml .Values.cortxMotr.clientEndpoints | nindent 8 }}
    {{- end }}
  csm:
    auth_admin: authadmin
    auth_secret: csm_auth_admin_secret
    mgmt_admin: cortxadmin
    mgmt_secret: csm_mgmt_admin_secret
    email_address: cortx@seagate.com
    agent:
      endpoints:
      - https://{{ .Values.cortxIoServiceName }}:8081
{{- end -}}
