{{- define "storageset.node" -}}
- name: {{ .name }}
  id: {{ required "A storageset node id is required" .id | quote }}
  hostname: {{ coalesce .hostname .name }}
  type: {{ .type }}
{{- end -}}

{{- define "cluster.yaml" -}}
cluster:
  name: {{ default (include "cortx.fullname" .) .Values.clusterName | quote }}
  id: {{ default uuidv4 .Values.clusterId | quote }}
  node_types:
  {{- $statefulSetCount := (include "cortx.data.statefulSetCount" .) | int -}}
  {{- $validatedContainerGroupSize := (include "cortx.data.validatedContainerGroupSize" .) | int -}}
  {{- range $stsIndex := until $statefulSetCount }}
  {{- $startingCvgIndex := (mul $stsIndex ($validatedContainerGroupSize | int)) | int }}
  {{- $endingCvgIndex := (add (mul $stsIndex ($validatedContainerGroupSize | int)) ($validatedContainerGroupSize | int)) | int }}
  - name: {{ include "cortx.data.dataNodeName" $stsIndex }}
    components:
      - name: utils
      - name: motr
        services:
          - io
      - name: hare
    storage:
    {{- range $cvgIndex := untilStep $startingCvgIndex $endingCvgIndex 1 }}
    {{- $cvg := index $.Values.cortxdata.cvgs $cvgIndex }}
    - name: {{ $cvg.name }}
      type: {{ $cvg.type }}
      devices:
        {{- if $cvg.devices.metadata }}
        metadata:
          - {{ $cvg.devices.metadata.device }}
        {{- end }}
        data:
        {{- range $cvg.devices.data }}
          - {{ .device }}
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
  {{- with .Values.storageSets }}
  storage_sets:
  {{- range $storageSetName, $storageSet := . }}
  - name: {{ $storageSetName }}
    durability:
      sns: {{ $storageSet.durability.sns | quote }}
      dix: {{ $storageSet.durability.dix | quote }}
    nodes:
    {{- if $root.Values.cortxcontrol.enabled }}
    {{- $nodeName := (include "cortx.control.fullname" $root) }}
    {{- include "storageset.node" (dict "name" $nodeName "id" $nodeName "type" "control_node") | nindent 4 }}
    {{- end }}
    {{- if $root.Values.cortxha.enabled }}
    {{- $nodeName := (include "cortx.ha.fullname" $root) }}
    {{- $hostName := (printf "%s-headless" $nodeName) }}
    {{- include "storageset.node" (dict "name" $nodeName "hostname" $hostName "id" $hostName "type" "ha_node") | nindent 4 }}
    {{- end }}
    {{- range $stsIndex := until $statefulSetCount }}
    {{- range $i := until (int $root.Values.cortxdata.replicas) }}
    {{- $nodeType := (include "cortx.data.dataNodeName" $stsIndex) }}
    {{- $nodeName := printf "%s-%d" (include "cortx.data.groupFullname" (dict "root" $ "stsIndex" $stsIndex)) $i }}
    {{- $hostName := printf "%s.%s" $nodeName (include "cortx.data.serviceDomain" $root) }}
    {{- include "storageset.node" (dict "name" $nodeName "hostname" $hostName "id" $hostName "type" $nodeType) | nindent 4 }}
    {{- end }}
    {{- end }}
    {{- if $root.Values.cortxserver.enabled }}
    {{- range $i := until (int $root.Values.cortxserver.replicas) }}
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
