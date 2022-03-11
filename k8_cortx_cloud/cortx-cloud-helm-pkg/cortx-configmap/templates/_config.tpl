{{- define "config.yaml" -}}
{{- $ioSvcName := printf "%s-0" .Values.cortxIoServiceName -}}
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
  s3:                                                               # DEPRECATED - ENTIRE S3 KEY
    iam:
      endpoints:
      - https://{{ $ioSvcName }}:9443
      - http://{{ $ioSvcName }}:9080
    data:
      endpoints:
      - http://{{ $ioSvcName }}:80
      - https://{{ $ioSvcName }}:443
    internal:
      endpoints:
      - http://{{ $ioSvcName }}:28049
    {{- with .Values.cortxS3.instanceCount }}
    service_instances: {{ . | int }}
    {{- end }}
    io_max_units: 8
    {{- with .Values.cortxS3.maxStartTimeout }}
    max_start_timeout: {{ . | int }}
    {{- end }}
    auth_user: {{ .Values.cortxRgw.authUser }}
    auth_admin: {{ .Values.cortxRgw.authAdmin }}
    auth_secret: {{ .Values.cortxRgw.authSecret }}
  rgw:
    iam:                                                            # DEPRECATED - IAM KEY
      endpoints:
      - https://{{ $ioSvcName }}:8443
      - http://{{ $ioSvcName }}:8000
    data:
      endpoints:
      - http://{{ $ioSvcName }}:8000
      - https://{{ $ioSvcName }}:8443
    s3:
      endpoints:
      - http://{{ $ioSvcName }}:8000
      - https://{{ $ioSvcName }}:8443
    {{- with .Values.cortxS3.instanceCount }}
    service_instances: {{ . | int }}
    {{- end }}
    io_max_units: 8                                                 #HARDCODED
    {{- with .Values.cortxS3.maxStartTimeout }}
    max_start_timeout: {{ . | int }}
    {{- end }}
    auth_user: {{ .Values.cortxRgw.authUser }}
    auth_admin: {{ .Values.cortxRgw.authAdmin }}
    auth_secret: {{ .Values.cortxRgw.authSecret }}
    limits:
      num_services: 1                                               #HARDCODED
      services:
      - name: rgw
        memory:
          min: 128Mi
          max: 1Gi
        cpu:
          min: 250m
          max: 1000m
    {{- tpl .Values.cortxRgw.extraConfiguration . | nindent 4 }}
  hare:
    hax:
      endpoints:
      {{- with .Values.cortxHa.haxService }}
        - {{ .protocol }}://{{ .name }}:{{ .port }}
      {{- end }}
      {{- toYaml .Values.cortxHare.haxDataEndpoints | nindent 8 }}
      {{- toYaml .Values.cortxHare.haxServerEndpoints | nindent 8 }}
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
    ios:
      endpoints: {{- toYaml .Values.cortxMotr.iosEndpoints | nindent 6 }}
    confd:
      endpoints: {{- toYaml .Values.cortxMotr.confdEndpoints | nindent 6 }}
    clients:
      - name: rgw
        num_instances: 1  # number of instances *per-pod*
        endpoints: {{- toYaml .Values.cortxMotr.rgwEndpoints | nindent 8 }}
    {{- if gt (len .Values.cortxMotr.clientEndpoints) 0 }}
      - name: motr_client
        num_instances: {{ len .Values.cortxMotr.clientEndpoints }}
        num_subscriptions: 1
        subscriptions:
        - fdmi
        endpoints: {{- toYaml .Values.cortxMotr.clientEndpoints | nindent 8 }}
    {{- end }}
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
    {{- tpl .Values.cortxMotr.extraConfiguration . | nindent 4 }}
  csm:
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
{{- end -}}
