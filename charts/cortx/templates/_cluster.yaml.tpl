### TODO CORTX-28968 Revisit UUID defaults here since we are moving away from UUID entirely...
### TODO CORTX-28968 Revisit formatting for line 82 and necessary values parameters
{{- define "storageset.node" -}}
- name: {{ .name }}
  {{- if eq .type "server_node" }}
  id: {{ default uuidv4 .id | quote }}
  hostname: {{ .hostname }}
  {{- else }}
  id: {{ default uuidv4 .id | replace "-" "" | quote }}
  hostname: {{ .name }}
  {{- end }}
  type: {{ .type }}
{{- end -}}

{{- define "cluster.yaml" -}}
cluster:
  name: {{ .Values.configmap.clusterName }}
  id: {{ default uuidv4 .Values.configmap.clusterId | replace "-" "" | quote }}
  node_types:
  - name: data_node
    components:
      - name: utils
      - name: motr
        services:
          - io
      - name: hare
    {{- with .Values.configmap.clusterStorageVolumes }}
    storage:
    {{- range $key, $val := . }}
    - name: {{ $key }}
      type: {{ $val.type }}
      devices:
        metadata: {{- toYaml $val.metadataDevices | nindent 10 }}
        data: {{- toYaml $val.dataDevices | nindent 10 }}
    {{- end }}
    {{- end }}
  {{- if .Values.configmap.cortxRgw.enabled }}
  - name: server_node
    components:
    - name: utils
    - name: hare
    - name: rgw
      services:
        - rgw_s3
  {{- end }}
  {{- if .Values.cortxcontrol.enabled }}
  - name: control_node
    components:
    - name: utils
    - name: csm
      services:
      - agent
  {{- end }}
  {{- if .Values.configmap.cortxHa.enabled }}
  - name: ha_node
    components:
    - name: utils
    - name: ha
  {{- end }}
  - name: client_node
    components:
    - name: utils
    - name: motr
      services:
        - motr_client
    - name: hare
  {{- with .Values.configmap.clusterStorageSets }}
  storage_sets:
  {{- range $key, $val := . }}
  - name: {{ $key }}
    durability:
      sns: {{ $val.durability.sns | quote }}
      dix: {{ $val.durability.dix | quote }}
    nodes:
    {{- if $.Values.cortxcontrol.enabled }}
    {{- include "storageset.node" (dict "name" (include "cortx.control.fullname" $) "id" $val.controlUuid "type" "control_node") | nindent 4 }}
    {{- end }}
    {{- if $.Values.configmap.cortxHa.enabled }}
    {{- include "storageset.node" (dict "name" "cortx-ha-headless-svc" "id" $val.haUuid "type" "ha_node") | nindent 4 }}
    {{- end }}
    {{- range $key, $val := $val.nodes }}
    {{- $shortHost := (split "." $key)._0 -}}
    {{- if and $.Values.configmap.cortxRgw.enabled $val.serverUuid }}
    {{- $serverName := printf "%s.cortx-server.default.svc.cluster.local" $key -}}
    {{- include "storageset.node" (dict "name" $key "hostname" $serverName "id" $val.serverUuid "type" "server_node") | nindent 4 }}
    {{- end }}
    {{- if $val.dataUuid }}
    {{- $dataName := printf "cortx-data-headless-svc-%s" $shortHost -}}
    {{- include "storageset.node" (dict "name" $dataName "id" $val.dataUuid "type" "data_node") | nindent 4 }}
    {{- end }}
    {{- if $val.clientUuid -}}
    {{- $clientName := printf "cortx-client-headless-svc-%s" $shortHost -}}
    {{- include "storageset.node" (dict "name" $clientName "id" $val.clientUuid "type" "client_node") | nindent 4 }}
    {{- end }}
    {{- end }}
  {{- end }}
  {{- end }}
{{- end -}}
