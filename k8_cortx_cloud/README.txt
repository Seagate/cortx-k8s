###############################################
# Local block storage requirements            #
###############################################
1. Update the "solution.yaml" file to have correct worker node names in
   "solution.nodes.nodeX.name" (ensure this field match the 'NAME' field
   from the output of 'kubectl get nodes'), devices in the "storage.cvg*".
   This info is used to create persistent volumes and persistent volume
   claims for CORTX Provisioner and CORTX Data.

Note: "solution.common.storage_provisioner_path" is the mount point/directory used
by "Rancher Local Path Provisioner". The user must follow the
"Run prerequisite deployment script" section on each of the worker nodes in the
cluster

###############################################
# Run prerequisite deployment script          #
###############################################
1. Install the entire content of "k8_cortx_cloud" on both master node and all worker
   nodes. The directory structure must be maintained.

2. Run prerequisite script on all worker nodes in the cluster, and untainted master node
   that allows scheduling. "<disk>" is a required input to run this script. This disk
   should NOT be any of the devices listed in "solution.storage.cvg*" in the "solution.yaml"
   file:

./prereq-deploy-cortx-cloud.sh <disk>

Example:
./prereq-deploy-cortx-cloud.sh /dev/sdb

###############################################
# Deploy and destroy CORTX cloud              #
###############################################
1. Deploy CORTX cloud:
./deploy-cortx-cloud.sh

2. Destroy CORTX cloud:
./destroy-cortx-cloud.sh

NOTE:
Rancher Local Path location on worker node:
/mnt/fs-local-volume/local-path-provisioner/pvc-<UID>_default_cortx-fs-local-pvc-<node-name>

Rancher Local Path mount point in all Pod containers (CORTX Provisioners, Data, Control):
/data

Shared glusterFS folder on the worker nodes and inside the Pod containers is located at:
/mnt/fs-local-volume/etc/gluster/

###########################################################
# Replacing a dummy container with real CORTX container   #
###########################################################

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
The Helm charts work with both "dummy" and "CORTX ALL" containers. 
If image is centos:7 helm runs in "dummy" mode any other name runs "CORTX ALL" mode

{- if eq $.Values.cortxdata.image  "centos:7" }}  # DO NOT CHANGE
command: ["/bin/sleep", "3650d"]                  # DO NOT CHANGE 
{{- else }}                                       # DO NOT CHANGE
command: ["/bin/sleep", "3650d"]    #<<=========================== REPLACE THIS WITH THE CORTX ENTRY POINT 
{{- end }}                                        # DO NOT CHANGE
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

See the following example from CORTX Data helm chart, replace the command section
hightlighted with "<<===" with the relevant CORTX container commands required for
the entrypoint. An "args" section also can be added to provide additional arguments.

./k8_cortx_cloud/cortx-cloud-helm-pkg/cortx-data/templates/cortx-data-pod.yaml

containers:
- name: cortx-s3-haproxy
   image: {{ .Values.cortxdata.image }}
   imagePullPolicy: IfNotPresent
   {- if eq $.Values.cortxdata.image  "centos:7" }}  # DO NOT CHANGE
   command: ["/bin/sleep", "3650d"]                  # DO NOT CHANGE 
   {{- else }}                                       # DO NOT CHANGE
   command: ["/bin/sleep", "3650d"]    #<<=========================== REPLACE THIS WITH THE CORTX ENTRY POINT 
   {{- end }}                                        # DO NOT CHANGE
   volumeDevices:
   {{- range .Files.Lines .Values.cortxdata.mountblkinfo }}
   - name: {{ printf "cortx-data-%s-pv-%s" ( base .) $nodename }}
      devicePath: {{ . }}
   {{- end }}
   volumeMounts:
   - name: {{ .Values.cortxdata.cfgmap.volmountname }}
      mountPath: {{ .Values.cortxdata.cfgmap.mountpath }}
   - name: {{ .Values.cortxdata.machineid.volmountname }}
      mountPath: {{ .Values.cortxdata.machineid.mountpath }}
   - name: {{ .Values.cortxgluster.pv.name }}
      mountPath: {{ .Values.cortxgluster.pv.mountpath }}
   - name: local-path-pv
      mountPath: {{ .Values.cortxdata.localpathpvc.mountpath }}
   env:
   - name: UDS_CLOUD_CONTAINER_NAME
      value: {{ .Values.cortxdata.name }}
   ports:
   - containerPort: 80
   - containerPort: 443
   - containerPort: 9080
   - containerPort: 9443

The images can be changed by modifying the solution.yaml file section solution.images

solution:
  namespace: default
  images:
   cortxcontrolprov: ghcr.io/seagate/cortx-all:2.0.0-latest-custom-ci
   cortxcontrol: ghcr.io/seagate/cortx-all:2.0.0-latest-custom-ci
   cortxdataprov: ghcr.io/seagate/cortx-all:2.0.0-latest-custom-ci
   cortxdata: ghcr.io/seagate/cortx-all:2.0.0-latest-custom-ci
   openldap: ghcr.io/seagate/symas-openldap:standalone
   consul: hashicorp/consul:1.10.0
   kafka: bitnami/kafka:3.0.0-debian-10-r7
   zookeeper: bitnami/zookeeper:3.7.0-debian-10-r182
   gluster: docker.io/gluster/gluster-centos:latest
   rancher: rancher/local-path-provisioner:v0.0.20