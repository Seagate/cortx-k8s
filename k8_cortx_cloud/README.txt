#######################################
# Local block storage requirements    #
#######################################
1. Update the "solution.yaml" file to have correct node names, devices,
   and a list of worker nodes. The info in this file is used to create
   persistent volumes and persistent volume claims for CORTX Provisioner
   and CORTX Data.

Note: "solution.nodes.node<1/2/3/4>.devices.system" is the disk partition used
by "Rancher Local Path Provisioner". Currently the script doesn't mount this
disk partition on each worker node automatically and it's required that the user
has to mount it manually as instructed below.

###############################################
# Rancher Local Path Provisioner Requirements #
###############################################
1. Mount disk partition and create a directory for Rancher local path provisioner
mount -t ext4 <disk-partition> /mnt/fs-local-volume
mkdir -p /mnt/fs-local-volume/local-path-provisioner

Example:
mount -t ext4 /dev/sdd /mnt/fs-local-volume

Rancher Local Path location on worker node:
/mnt/fs-local-volume/local-path-provisioner/pvc-<UID>_default_cortx-fs-local-pvc-node-1

Rancher Local Path location in all Pod containers (CORTX Provisioner, Data,
Control, and Support):
/data

#######################################
# GlusterFS requirements              #
#######################################
1. Create directories for GlusterFS if they don't exist on each worker node
that is used to deploy GlusterFS

mkdir -p /mnt/fs-local-volume/etc/gluster
mkdir -p /mnt/fs-local-volume/var/log/gluster
mkdir -p /mnt/fs-local-volume/var/lib/glusterd

Shared glusterFS folder on the worker nodes and inside the Pod containers is located at:
/mnt/fs-local-volume/etc/gluster

#########################
# OpenLDAP Requirements #
#########################
1. Load OpenLDAP docker image:
docker load -i cortx-openldap.tar

2. On each worker node perform the following:
mkdir -p /var/lib/ldap
echo "ldap:x:55:" >> /etc/group
echo "ldap:x:55:55:OpenLDAP server:/var/lib/ldap:/sbin/nologin" >> /etc/passwd
chown -R ldap.ldap /var/lib/ldap

Note: If "/var/lib/ldap" already exists prior to deploy CORTX cloud, make sure
the folder is empty.