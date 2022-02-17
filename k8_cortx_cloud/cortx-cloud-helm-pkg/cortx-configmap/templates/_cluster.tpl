{{- define "storageset.node" -}}
- name: {{ .name }}
  id: {{ default uuidv4 .id | replace "-" "" | quote }}
  hostname: {{ .name }}
  type: {{ .type }}
{{- end -}}

{{- define "cluster.yaml" -}}
cluster:
  name: {{ .Values.clusterName }}
  id: {{ default uuidv4 .Values.clusterId | replace "-" "" | quote }}
  node_types:
  - name: data_node
    components:
      - name: utils
      - name: motr
        services:
          - io
      - name: hare
    {{- with .Values.clusterStorageVolumes }}
    storage:
    {{- range $key, $val := . }}
    - name: {{ $key }}
      type: {{ $val.type }}
      devices:
        metadata: {{- toYaml $val.metadataDevices | nindent 10 }}
        data: {{- toYaml $val.dataDevices | nindent 10 }}
    {{- end }}
    {{- end }}
  - name: server_node
    components:
    - name: utils
    - name: hare
    - name: rgw
  - name: control_node
    components:
    - name: utils
    - name: csm
      services:
      - agent
  - name: ha_node
    components:
    - name: utils
    - name: ha
  - name: client_node
    components:
    - name: hare
    - name: motr
      services:
        - motr_client
  {{- with .Values.clusterStorageSets }}
  storage_sets:
  {{- range $key, $val := . }}
  - name: {{ $key }}
    durability:
      sns: {{ $val.durability.sns | quote }}
      dix: {{ $val.durability.dix | quote }}
    nodes:
    {{- include "storageset.node" (dict "name" "cortx-control" "id" $val.controlUuid "type" "control_node") | nindent 4 }}
    {{- include "storageset.node" (dict "name" "cortx-ha-headless-svc" "id" $val.haUuid "type" "ha_node") | nindent 4 }}
    {{- range $key, $val := $val.nodes }}
    {{- $shortHost := (split "." $key)._0 -}}
    {{- $serverName := printf "cortx-server-headless-svc-%s" $shortHost -}}
    {{- $dataName := printf "cortx-data-headless-svc-%s" $shortHost -}}
    {{- $clientName := printf "cortx-client-headless-svc-%s" $shortHost -}}
    {{- include "storageset.node" (dict "name" $serverName "id" $val.serverUuid "type" "server_node") | nindent 4 }}
    {{- include "storageset.node" (dict "name" $dataName "id" $val.dataUuid "type" "data_node") | nindent 4 }}
    {{- if $val.clientUuid -}}
    {{- include "storageset.node" (dict "name" $clientName "id" $val.clientUuid "type" "client_node") | nindent 4 }}
    {{- end }}
    {{- end }}
  {{- end }}
  {{- end }}
{{- end -}}
