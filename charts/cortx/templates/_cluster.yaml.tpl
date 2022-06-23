{{- /* TODO Revisit UUID defaults here since we are moving away from UUID entirely... */ -}}
{{- /* TODO CORTX-29861 Update this logic block to account for dynamic Data Pod types more elegantly than supertype */ -}}
{{- define "storageset.node" -}}
- name: {{ .name }}
  {{- if eq .type "server_node" }}
  id: {{ required "A valid id is required for server nodes" .id | quote }}
  {{- else if (or (eq .type "data_node") (eq .supertype "data_node")) }}
  id: {{ required "A valid id is required for data nodes" .id | quote }}
  {{- else if eq .type "client_node" }}
  id: {{ required "A valid id is required for client nodes" .id | quote }}
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
  {{- /* TODO CORTX-29861 Create additional data_node types here based upon StatefulSet names */}}
  node_types:
  {{- range $sts_index := until (ceil (div (len .Values.cortxdata.cvgs) (.Values.cortxdata.motr.containerGroupSize|int)) | int) }}
  - name: {{ printf "%s-%s%02d" (include "cortx.data.fullname" $) $.Values.cortxdata.motr.containerGroupName $sts_index }}
    components:
      - name: utils
      - name: motr
        services:
          - io
      - name: hare
    storage:
    {{- range $group_size_iterator := until ($.Values.cortxdata.motr.containerGroupSize|int) }}
    {{- $cvg_index := (add (mul $sts_index ($.Values.cortxdata.motr.containerGroupSize|int)) $group_size_iterator) -}}
    {{- $cvg := index $.Values.cortxdata.cvgs $cvg_index  -}}
    {{- range $cvg.devices.data }}
    - name: {{ $cvg.name }}
      type: {{ $cvg.type }}
      devices:
        {{- if $cvg.devices.metadata }}
        metadata:
          - {{ $cvg.devices.metadata.device }}
        {{ end -}}
        data:
        {{- range $cvg.devices.data }}
          - {{ .device }}
        {{- end }}
    {{- end }}
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
    {{- range $sts_index := until (ceil (div (len $root.Values.cortxdata.cvgs) ($root.Values.cortxdata.motr.containerGroupSize|int)) | int) }}
    {{- range $i := until (int $root.Values.cortxdata.replicas) }}
    {{- $nodeGroup := printf "%s-%s%02d" (include "cortx.data.fullname" $root) $.Values.cortxdata.motr.containerGroupName $sts_index }}
    {{- $nodeName := printf "%s-%d" $nodeGroup $i }}
    {{- $hostName := printf "%s.%s" $nodeName (include "cortx.data.serviceDomain" $root) }}
    {{- include "storageset.node" (dict "name" $nodeName "hostname" $hostName "id" $hostName "type" $nodeGroup "supertype" "data_node") | nindent 4 }}
    {{- end }}
    {{- end }}
    {{- if $root.Values.cortxserver.enabled }}
    {{- range $i := until (int $root.Values.cortxserver.replicas) }}
    {{- $nodeName := printf "%s-%d" (include "cortx.server.fullname" $root) $i }}
    {{- $hostName := printf "%s.%s" $nodeName (include "cortx.server.serviceDomain" $root) }}
    {{- include "storageset.node" (dict "name" $nodeName "hostname" $hostName "id" $hostName "type" "server_node") | nindent 4 }}
    {{- end }}
    {{- end }}
    {{- range $i := until (int $root.Values.cortxclient.replicas) }}
    {{- $nodeName := printf "%s-%d" (include "cortx.client.fullname" $root) $i }}
    {{- $hostName := printf "%s.%s" $nodeName (include "cortx.client.serviceDomain" $root) }}
    {{- include "storageset.node" (dict "name" $nodeName "hostname" $hostName "id" $hostName "type" "client_node") | nindent 4 }}
    {{- end }}
  {{- end }}
  {{- end }}
{{- end -}}
