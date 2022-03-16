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
    thread_pool_size: 10
    data_path: /var/cortx/radosgw/$clusterid
    init_timeout: 300
    gc_max_objs: 32
    gc_obj_min_wait: 1800
    gc_processor_max_time: 3600
    gc_processor_period: 3600
    
    motr_layout_id: 9                          
    motr_unit_size: 1048576 
    motr_max_units_per_request: 8
    motr_max_idx_fetch_count: 30
    motr_max_rpc_msg_size: 524288
    motr_reconnect_interval: 5
    motr_reconnect_retry_count: 25
    iam:                                                            # DEPRECATED - IAM KEY
      endpoints:
      - https://{{ $ioSvcName }}:443
      - http://{{ $ioSvcName }}:80
    data:
      endpoints:
      - http://{{ $ioSvcName }}:80
      - https://{{ $ioSvcName }}:443
    s3:
      endpoints:
      - http://{{ $ioSvcName }}:80
      - https://{{ $ioSvcName }}:443
    public:
      endpoints:
      - http://{{ $ioSvcName }}:80
      - https://{{ $ioSvcName }}:443
    service:
      endpoints:
      {{- toYaml .Values.cortxRgw.rgwServiceHttpEndpoints | nindent 8 }}
      {{- toYaml .Values.cortxRgw.rgwServiceHttpsEndpoints | nindent 8 }}
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
    md_size: {{ .Values.cortxMotr.md_size }}
    ios:
      group_size: {{ .Values.cortxMotr.group_size }}
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
