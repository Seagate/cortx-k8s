###############################################
# Local block storage requirements            #
###############################################
1. Update the "solution.yaml" file to have correct node names in
   "solution.nodes.nodeX.name" (ensure this field match the 'NAME' field
   from the output of 'kubectl get nodes'), devices, and a list of worker
   nodes. The info in this file is used to create persistent volumes and
   persistent volume claims for CORTX Provisioner and CORTX Data.

Note: "solution.nodes.nodeX.devices.system" is the mount point/directory used
by "Rancher Local Path Provisioner". Currently the script doesn't mount this
disk partition on each worker node automatically and it's required that the user
has to mount it manually as instructed below.

###############################################
# Run prerequisite deployment script          #
###############################################
1. Copy "prereq-deploy-cortx-cloud.sh" script to all worker nodes, and untainted master
   node that allows scheduling:

scp prereq-deploy-cortx-cloud.sh root@<worker-node-IP-address>:<path-to-prereq-script>

Example:
scp prereq-deploy-cortx-cloud.sh root@192.168.1.1:/home/

2. Run prerequisite script on all worker nodes, and untainted master node that allows
   scheduling. "<disk-partition>" and "<mount-path>" are required inputs to run this script.
   The disk mount point should match "solution.nodes.nodeX.devices.system" in the "solution.yaml"
   file. This disk partition should NOT match any devices listed in "solution.storage.cvg*":

./prereq-deploy-cortx-cloud.sh <disk-partition> <mount-path>

Example:
./prereq-deploy-cortx-cloud.sh /dev/sdb /mnt/fs-local-volume

###############################################
# Deploy and destroy CORTX cloud              #
###############################################
1. Deploy CORTX cloud:
./deploy-cortx-cloud.sh

2. Destroy CORTX cloud:
./destroy-cortx-cloud.sh

NOTE:
If the mount path in the "solution.yaml" file at "solution.nodes.nodeX.devices.system" is
"/mnt/fs-local-volume" then:
- Rancher Local Path location on worker node is available at:
/mnt/fs-local-volume/local-path-provisioner/pvc-<UID>_default_cortx-fs-local-pvc-<node-name>

- Rancher Local Path location in all Pod containers (CORTX Provisioners, Data, Control) is
available at:
/data

- Shared glusterFS folder on the worker nodes and inside the Pod containers is located at:
/mnt/fs-local-volume/etc/gluster/

###########################################################
# Replacing a dummy container with real CORTX container   #
###########################################################
See the following example from CORTX Data helm chart, replace the image and
command section hightlighted with "<<===" with the relevant CORTX container
commands required for the entrypoint. An "args" section also can
be added to provide additional arguments.

./k8_cortx_cloud/cortx-cloud-helm-pkg/cortx-data/templates/cortx-data-pod.yaml

containers:
- name: cortx-s3-server
   image: {{ .Values.cortxdata.image }}
   imagePullPolicy: IfNotPresent
   command: ["/bin/sleep", "3650d"]    <<===
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
    cortxcontrolprov: centos:7
    cortxcontrol: centos:7
    cortxdataprov: centos:7
    cortxdata: centos:7
    cortxsupport: centos:7