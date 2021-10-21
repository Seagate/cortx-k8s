#!/bin/bash

disk=$1
solution_yaml=${2:-'solution.yaml'}

# Check if the file exists
if [ ! -f $solution_yaml ]
then
    echo "ERROR: $solution_yaml does not exist"
    exit 1
fi

function parseSolution()
{
    echo "$(./parse_scripts/parse_yaml.sh $solution_yaml $1)"
}

fs_mount_path="/mnt/fs-local-volume"

if [[ "$disk" == "" ]]
then
    echo "Invalid input paramters"
    echo "./prereq-deploy-cortx-cloud.sh <disk-partition>"
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

image=$(parseSolution 'solution.images.cortxcontrolprov')
image=$(echo $image | cut -f2 -d'>')
if [[ "$(docker images -q $image 2> /dev/null)" == "" ]]; then
    docker pull $image
fi

image=$(parseSolution 'solution.images.cortxcontrol')
image=$(echo $image | cut -f2 -d'>')
if [[ "$(docker images -q $image 2> /dev/null)" == "" ]]; then
    docker pull $image
fi

image=$(parseSolution 'solution.images.cortxdataprov')
image=$(echo $image | cut -f2 -d'>')
if [[ "$(docker images -q $image 2> /dev/null)" == "" ]]; then
    docker pull $image
fi

image=$(parseSolution 'solution.images.cortxdata')
image=$(echo $image | cut -f2 -d'>')
if [[ "$(docker images -q $image 2> /dev/null)" == "" ]]; then
    docker pull $image
fi

image=$(parseSolution 'solution.images.openldap')
image=$(echo $image | cut -f2 -d'>')
if [[ "$(docker images -q $image 2> /dev/null)" == "" ]]; then
    docker pull $image
fi

image=$(parseSolution 'solution.images.consul')
image=$(echo $image | cut -f2 -d'>')
if [[ "$(docker images -q $image 2> /dev/null)" == "" ]]; then
    docker pull $image
fi

image=$(parseSolution 'solution.images.kafka')
image=$(echo $image | cut -f2 -d'>')
if [[ "$(docker images -q $image 2> /dev/null)" == "" ]]; then
    docker pull $image
fi

image=$(parseSolution 'solution.images.zookeeper')
image=$(echo $image | cut -f2 -d'>')
if [[ "$(docker images -q $image 2> /dev/null)" == "" ]]; then
    docker pull $image
fi

image=$(parseSolution 'solution.images.gluster')
image=$(echo $image | cut -f2 -d'>')
if [[ "$(docker images -q $image 2> /dev/null)" == "" ]]; then
    docker pull $image
fi

image=$(parseSolution 'solution.images.rancher')
image=$(echo $image | cut -f2 -d'>')
if [[ "$(docker images -q $image 2> /dev/null)" == "" ]]; then
    docker pull $image
fi

# Pull the latest busybox image
docker pull busybox

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
echo "Create folder '$fs_mount_path/local-path-provisioner'"
mkdir -p $fs_mount_path/local-path-provisioner
count=0
while true; do
    if [[ -d $fs_mount_path/local-path-provisioner || $count -gt 5 ]]; then
        break
    else
        echo "Create folder '$fs_mount_path/local-path-provisioner' failed. Retry..."
        mkdir -p $fs_mount_path/local-path-provisioner
    fi
    count=$((count+1))
    sleep 1s
done

if [[ $(findmnt -m $fs_mount_path) ]];then
    echo "$fs_mount_path already mounted..."
else
    echo y | mkfs.ext4 $disk
    mount -t ext4 $disk $fs_mount_path
fi

# Prep for GlusterFS deployment
yum install glusterfs-fuse -y
mkdir -p $fs_mount_path/etc/gluster
mkdir -p $fs_mount_path/etc/gluster/var/log/cortx
mkdir -p $fs_mount_path/var/log/glusterfs
mkdir -p $fs_mount_path/var/lib/glusterd

# Prep for OpenLDAP deployment
mkdir -p /etc/3rd-party/openldap
mkdir -p /var/data/3rd-party
mkdir -p /var/log/3rd-party