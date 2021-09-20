
#######################################
# Local block storage requirements    #
#######################################
1. Local block storage partition info must be updated at:
- cortx-cloud-helm-pkg/cortx-data/mnt-blk-info-<node-name>.txt
- cortx-cloud-helm-pkg/cortx-provisioner/mnt-blk-info<node-name>.txt

Note: "mnt-blk-info-<node-name>.txt" has to be created for each worker node
in the CORTX cluster. For example if there are 3 worker nodes in the cluster, 
3 "mnt-blk-info-<node-name>.txt" files are expected in the following folders:
- cortx-cloud-helm-pkg/cortx-data/
- cortx-cloud-helm-pkg/cortx-provisioner/

###############################################
# Rancher Local Path Provisioner Requirements #
###############################################
1. Mount disk partition and create a directory for Rancher local path provisioner
mount -t ext4 <disk-partition> /mnt/fs-local-volume
mkdir -p /mnt/fs-local-volume/local-path-provisioner

Example:
mount -t ext4 /dev/sdd /mnt/fs-local-volume

#######################################
# GlusterFS requirements              #
#######################################
1. Create directories for GlusterFS if they don't exist on each worker node
that is used to deploy GlusterFS

mkdir -p /mnt/fs-local-volume/etc/gluster
mkdir -p /mnt/fs-local-volume/var/log/gluster
mkdir -p /mnt/fs-local-volume/var/lib/glusterd

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