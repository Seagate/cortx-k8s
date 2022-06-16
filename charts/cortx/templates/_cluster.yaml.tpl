### TODO Revisit UUID defaults here since we are moving away from UUID entirely...
{{- define "storageset.node" -}}
- name: {{ .name }}
  {{- if eq .type "server_node" }}
  id: {{ required "A valid id is required for server nodes" .id | quote }}
  {{- else if eq .type "data_node" }}
  id: {{ required "A valid id is required for data nodes" .id | quote }}
  {{- else }}
  id: {{ default uuidv4 .id | replace "-" "" | quote }}
  {{- end }}
  hostname: {{ coalesce .hostname .name }}
  type: {{ .type }}
{{- end -}}

{{- define "cluster.yaml" -}}
cluster:
  name: {{ .Values.configmap.clusterName }}
  id: {{ default uuidv4 .Values.configmap.clusterId | replace "-" "" | quote }}
  ### TODO CORTX-29861 Create additional data_node types here based upon StatefulSet names
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
  {{- if .Values.cortxserver.enabled }}
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
  {{- if .Values.cortxha.enabled }}
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
  {{- $root := . }}
  {{- with .Values.configmap.clusterStorageSets }}
  storage_sets:
  {{- range $storageSetName, $storageSet := . }}
  - name: {{ $storageSetName }}
    durability:
      sns: {{ $storageSet.durability.sns | quote }}
      dix: {{ $storageSet.durability.dix | quote }}
    nodes:
    {{- if $root.Values.cortxcontrol.enabled }}
    {{- include "storageset.node" (dict "name" (include "cortx.control.fullname" $root) "id" $storageSet.controlUuid "type" "control_node") | nindent 4 }}
    {{- end }}
    {{- if $root.Values.cortxha.enabled }}
    {{- include "storageset.node" (dict "name" (printf "%s-headless" (include "cortx.ha.fullname" $root)) "id" $storageSet.haUuid "type" "ha_node") | nindent 4 }}
    {{- end }}
    {{- range $i := until (int $root.Values.cortxdata.replicas) }}
    {{- $nodeName := (include "cortx.data.fullname" $root) }}
    {{- $hostName := printf "%s-%d.%s" $nodeName $i (include "cortx.data.serviceDomain" $root) }}
    {{- include "storageset.node" (dict "name" $nodeName "hostname" $hostName "id" $hostName "type" "data_node") | nindent 4 }}
    {{- end }}
    {{- range $nodeName, $node := $storageSet.nodes }}
    {{- if and $root.Values.cortxserver.enabled $node.serverUuid }}
    {{- include "storageset.node" (dict "name" $nodeName "hostname" $node.serverUuid "id" $node.serverUuid "type" "server_node") | nindent 4 }}
    {{- end }}
    {{- if $node.clientUuid }}
    {{- $clientName := printf "cortx-client-headless-svc-%s" (split "." $nodeName)._0 }}
    {{- include "storageset.node" (dict "name" $clientName "id" $node.clientUuid "type" "client_node") | nindent 4 }}
    {{- end }}
    {{- end }}
  {{- end }}
  {{- end }}
{{- end -}}
