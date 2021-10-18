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
# Rancher Local Path Provisioner Requirements #
###############################################
1. Mount the mount point/directory specified in the "solution.yaml" file in
   "solution.nodes.nodeX.devices.system" and create a directory for Rancher
   local path provisioner on each worker node, and untained master node that
   allows scheduling:
mkdir -p /mnt/fs-local-volume/local-path-provisioner
mkfs.ext4 <disk-partition>
mount -t ext4 <disk-partition> /mnt/fs-local-volume

Example:
mkfs.ext4 /dev/sdd
mount -t ext4 /dev/sdd /mnt/fs-local-volume

Rancher Local Path location on worker node:
/mnt/fs-local-volume/local-path-provisioner/pvc-<UID>_default_cortx-fs-local-pvc-<node-name>

Rancher Local Path location in all Pod containers (CORTX Provisioner, Data,
Control, and Support):
/data

###############################################
# GlusterFS requirements                      #
###############################################
1. Create directories for GlusterFS if they don't exist on each worker node, and untained
master node that allows scheduling, that are used to deploy GlusterFS:

mkdir -p /mnt/fs-local-volume/etc/gluster
mkdir -p /mnt/fs-local-volume/var/log/glusterfs
mkdir -p /mnt/fs-local-volume/var/lib/glusterd

2. Install glusterfs-fuse package on each worker node:
yum install glusterfs-fuse -y

Shared glusterFS folder on the worker nodes and inside the Pod containers is located at:
/mnt/fs-local-volume/etc/gluster/

###############################################
# OpenLDAP Requirements                       #
###############################################
1. On each worker node, and untained master node that allows scheduling, perform the following:
mkdir -p /etc/3rd-party/openldap
mkdir -p /var/data/3rd-party
mkdir -p /var/log/3rd-party

###############################################
# Deploy and destroy CORTX cloud              #
###############################################
1. Deploy CORTX cloud:
./deploy-cortx-cloud.sh

2. Destroy CORTX cloud:
./destroy-cortx-cloud.sh

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