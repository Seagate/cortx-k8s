###############################################
# Rancher Local Path Provisioner Requirements #
###############################################
1. Mount disk partition specified in the "solution.yaml" file in
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

Note: if there's no disk partition on all worker nodes then just create folder
"/mnt/fs-local-volume/local-path-provisioner" with the exact same path on all
worker nodes.

###############################################
# OpenLDAP Requirements                       #
###############################################
1. On each worker node perform the following:
mkdir -p /etc/3rd-party/openldap
mkdir -p /var/data/3rd-party
mkdir -p /var/log/3rd-party

###############################################
# Deploy and destroy CORTX cloud 3rd party    #
###############################################
1. Deploy 3rd party:
./deploy-cortx-cloud-3rd-party.sh

2. Destroy 3rd party:
./destroy-cortx-cloud-3rd-party.sh