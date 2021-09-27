###############################################
# Rancher Local Path Provisioner Requirements #
###############################################
1. Mount disk partition and create a directory for Rancher local path provisioner
mount -t ext4 <disk-partition> /mnt/fs-local-volume
mkdir -p /mnt/fs-local-volume/local-path-provisioner

Example:
mount -t ext4 /dev/sdd /mnt/fs-local-volume

Note: if there's no disk partition on all worker nodes then just create folder
"/mnt/fs-local-volume/local-path-provisioner" with the exact same path on worker
nodes.

###############################################
# GlusterFS requirements                      #
###############################################
1. Create directories for GlusterFS if they don't exist on each worker node
that is used to deploy GlusterFS

mkdir -p /mnt/fs-local-volume/etc/gluster
mkdir -p /mnt/fs-local-volume/var/log/gluster
mkdir -p /mnt/fs-local-volume/var/lib/glusterd

###############################################
# OpenLDAP Requirements                       #
###############################################
1. Load OpenLDAP docker image:
docker load -i cortx-openldap.tar

2. On each worker node perform the following:
mkdir -p /var/lib/ldap
echo "ldap:x:55:" >> /etc/group
echo "ldap:x:55:55:OpenLDAP server:/var/lib/ldap:/sbin/nologin" >> /etc/passwd
chown -R ldap.ldap /var/lib/ldap

Note: If "/var/lib/ldap" already exists prior to deploy CORTX cloud, make sure
the folder is empty.

###############################################
# Deploy and destroy CORTX cloud 3rd party    #
###############################################
1. Deploy 3rd party:
./deploy_cortx_cloud_3rd_party.sh

2. Destroy 3rd party:
./destroy_cortx_cloud_3rd_party.sh