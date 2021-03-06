{{- define "storageset.node" -}}
- name: {{ .name }}
  id: {{ required "A storageset node id is required" .id | quote }}
  hostname: {{ coalesce .hostname .name }}
  type: {{ .type }}
{{- end -}}

{{- define "cluster.yaml" -}}
{{- $statefulSetCount := (include "cortx.data.statefulSetCount" .) | int -}}
{{- $storageSet := dict -}}
{{- $cvgGroups := list -}}
{{- if gt $statefulSetCount 0 -}}
{{- $storageSet = first .Values.storageSets -}}
{{- $cvgGroups = $storageSet.storage | chunk ($storageSet.containerGroupSize | int) -}}
{{- end -}}
cluster:
  name: {{ default (include "cortx.fullname" .) .Values.clusterName | quote }}
  id: {{ default uuidv4 .Values.clusterId | quote }}
  node_types:
  {{- range $stsIndex := until (len $cvgGroups) }}
  - name: {{ include "cortx.data.dataNodeName" $stsIndex }}
    components:
    - name: utils
    - name: motr
      services:
      - io
    - name: hare
    storage:
    {{- range $cvg := index $cvgGroups $stsIndex }}
    - name: {{ $cvg.name }}
      type: {{ $cvg.type }}
      devices:
        {{- with $cvg.devices.metadata }}
        metadata:
        {{- range . }}
        - {{ .path }}
        {{- end }}
        {{- end }}
        {{- with $cvg.devices.log }}
        log:
        {{- range . }}
        - {{ .path }}
        {{- end }}
        {{- end }}
        {{- with $cvg.devices.data }}
        data:
        {{- range . }}
        - {{ .path }}
        {{- end }}
        {{- end }}
    {{- end }}
  {{- end }}
  {{- if .Values.server.enabled }}
  - name: server_node
    components:
    - name: utils
    - name: hare
    - name: rgw
      services:
      - rgw_s3
  {{- end }}
  {{- if .Values.control.enabled }}
  - name: control_node
    components:
    - name: utils
    - name: csm
      services:
      - agent
  {{- end }}
  {{- if .Values.ha.enabled }}
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
  {{- with .Values.storageSets }}
  storage_sets:
  {{- range $storageSet := . }}
  - name: {{ $storageSet.name }}
    durability:
      sns: {{ $storageSet.durability.sns | quote }}
      dix: {{ $storageSet.durability.dix | quote }}
    nodes:
    {{- if $root.Values.control.enabled }}
    {{- $nodeName := (include "cortx.control.fullname" $root) }}
    {{- include "storageset.node" (dict "name" $nodeName "id" $nodeName "type" "control_node") | nindent 4 }}
    {{- end }}
    {{- if $root.Values.ha.enabled }}
    {{- $nodeName := (include "cortx.ha.fullname" $root) }}
    {{- $hostName := (printf "%s-headless" $nodeName) }}
    {{- include "storageset.node" (dict "name" $nodeName "hostname" $hostName "id" $hostName "type" "ha_node") | nindent 4 }}
    {{- end }}
    {{- range $stsIndex := until $statefulSetCount }}
    {{- range $i := until (int $root.Values.data.replicaCount) }}
    {{- $nodeType := (include "cortx.data.dataNodeName" $stsIndex) }}
    {{- $nodeName := printf "%s-%d" (include "cortx.data.groupFullname" (dict "root" $ "stsIndex" $stsIndex)) $i }}
    {{- $hostName := printf "%s.%s" $nodeName (include "cortx.data.serviceDomain" $root) }}
    {{- include "storageset.node" (dict "name" $nodeName "hostname" $hostName "id" $hostName "type" $nodeType) | nindent 4 }}
    {{- end }}
    {{- end }}
    {{- if $root.Values.server.enabled }}
    {{- range $i := until (int $root.Values.server.replicaCount) }}
    {{- $nodeName := printf "%s-%d" (include "cortx.server.fullname" $root) $i }}
    {{- $hostName := printf "%s.%s" $nodeName (include "cortx.server.serviceDomain" $root) }}
    {{- include "storageset.node" (dict "name" $nodeName "hostname" $hostName "id" $hostName "type" "server_node") | nindent 4 }}
    {{- end }}
    {{- end }}
    {{- range $i := until (int $root.Values.client.replicaCount) }}
    {{- $nodeName := printf "%s-%d" (include "cortx.client.fullname" $root) $i }}
    {{- $hostName := printf "%s.%s" $nodeName (include "cortx.client.serviceDomain" $root) }}
    {{- include "storageset.node" (dict "name" $nodeName "hostname" $hostName "id" $hostName "type" "client_node") | nindent 4 }}
    {{- end }}
  {{- end }}
  {{- end }}
{{- end -}}
