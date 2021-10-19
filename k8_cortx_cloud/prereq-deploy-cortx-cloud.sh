#!/bin/bash

disk_partition=$1
fs_mount_path=$2

if [[ "$disk_partition" == "" || "$fs_mount_path" == "" ]]
then
    echo "Invalid input paramters"
    echo "./prereq-deploy-cortx-cloud.sh <disk-partition> <mount-path>"
    exit 1
fi

printf "####################################################\n"
printf "# Install helm                                      \n"
printf "####################################################\n"
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

printf "####################################################\n"
printf "# Pull required docker images                       \n"
printf "####################################################\n"
# pull docker 3rd party images
docker pull bitnami/kafka
docker pull docker.io/gluster/gluster-centos 
docker pull rancher/local-path-provisioner:v0.0.20
docker pull bitnami/zookeeper
docker pull hashicorp/consul:1.10.2
docker pull busybox

#Pull cortx-all docker image
docker pull ghcr.io/seagate/cortx-all:2.0.0-latest-custom-ci

printf "####################################################\n"
printf "# Clean up                                          \n"
printf "####################################################\n"
# cleanup
rm -rf /etc/3rd-party/openldap /var/data/3rd-party/*
rm -rf $fs_mount_path/local-path-provisioner/*
rm -rf $fs_mount_path/etc/gluster/var/log/cortx/*

# Increase Resources
sysctl -w vm.max_map_count=30000000;

printf "####################################################\n"
printf "# Prep for CORTX deployment                         \n"
printf "####################################################\n"
# Prep for Rancher Local Path Provisioner deployment
mkdir -p $fs_mount_path/local-path-provisioner
echo y | mkfs.ext4 $disk_partition
mount -t ext4 $disk_partition $fs_mount_path

# Prep for GlusterFS deployment
yum install glusterfs-fuse -y
mkdir -p $fs_mount_path/etc/gluster
mkdir -p $fs_mount_path/var/log/glusterfs
mkdir -p $fs_mount_path/var/lib/glusterd

# Prep for OpenLDAP deployment
mkdir -p /etc/3rd-party/openldap
mkdir -p /var/data/3rd-party
mkdir -p /var/log/3rd-party