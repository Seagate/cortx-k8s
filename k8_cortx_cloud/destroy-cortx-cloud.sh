#!/bin/bash

PVC_CONSUL_FILTER="data-default-consul"
PVC_KAFKA_FILTER="kafka"
PVC_ZOOKEEPER_FILTER="zookeeper"
PV_FILTER="pvc"
OPENLDAP_PVC="openldap-data"

namespace="default"

#############################################################
# Destroy CORTX Cloud
#############################################################

printf "########################################################\n"
printf "# Delete CORTX data                                     \n"
printf "########################################################\n"
while IFS= read -r line; do
    if [[ $line != *"master"* && $line != *"AGE"* ]]
    then
        IFS=" " read -r -a node_name <<< "$line"
        helm uninstall "cortx-data-$node_name"
    fi
done <<< "$(kubectl get nodes)"

printf "########################################################\n"
printf "# Delete CORTX provisioner                              \n"
printf "########################################################\n"
while IFS= read -r line; do
    if [[ $line != *"master"* && $line != *"AGE"* ]]
    then
        IFS=" " read -r -a node_name <<< "$line"
        helm uninstall "cortx-provisioner-$node_name"
    fi
done <<< "$(kubectl get nodes)"

printf "########################################################\n"
printf "# Delete CORTX GlusterFS                                \n"
printf "########################################################\n"
gluster_vol="myvol"
gluster_folder="/etc/gluster/test_folder"
pod_ctr_mount_path="/mnt/glusterfs"

# Build Gluster endpoint array
gluster_ep_array=[]
count=0
while IFS= read -r line; do
    if [[ $line == *"gluster-"* ]]
    then
        IFS=" " read -r -a my_array <<< "$line"
        gluster_ep_array[count]=$line
        count=$((count+1))
    fi
done <<< "$(kubectl get pods -A -o wide | grep 'gluster-')"

# Loop through all gluster endpoint array and find endoint IP address
# and gluster node name
count=0
first_gluster_node_name=''
for gluster_ep in "${gluster_ep_array[@]}"
do
    IFS=" " read -r -a my_array <<< "$gluster_ep"
    gluster_ep_ip=${my_array[6]}
    gluster_node_name=${my_array[1]}
    printf "=================================================================\n"
    printf "Stop and delete GlusterFS volume: $gluster_node_name             \n"
    printf "=================================================================\n"

    if [[ "$count" == 0 ]]; then
        first_gluster_node_name=$gluster_node_name
        echo y | kubectl exec --namespace=$namespace -i $gluster_node_name -- gluster volume stop $gluster_vol
        echo y | kubectl exec --namespace=$namespace -i $gluster_node_name -- gluster volume delete $gluster_vol
    else
        echo y | kubectl exec --namespace=$namespace -i $first_gluster_node_name -- gluster peer detach $gluster_ep_ip
    fi    
    count=$((count+1))
done

# Get a list of PODs in the cluster
pod_list=[]
count=0
while IFS= read -r line; do
    IFS=" " read -r -a my_array <<< "$line"
    pod_name=${my_array[1]}
    pod_list[count]=$pod_name
    count=$((count+1))
done <<< "$(kubectl get pods -A | grep 'cortx-provisioner-pod-')"

printf "=================================================================\n"
printf "Un-mount GlusterFS                                               \n"
printf "=================================================================\n"
count=0
for pod_name in "${pod_list[@]}"
do
    ctr_name="container001"
    count=$((count+1))
    printf "Un-mount GlusterFS on node: $pod_name\n"
    kubectl exec --namespace=$namespace -i $pod_name -- umount $pod_ctr_mount_path
done

helm uninstall "cortx-gluster-node-1"

printf "######################################################\n"
printf "# Delete CORTX Local Block Storage                    \n"
printf "######################################################\n"
while IFS= read -r line; do
    if [[ $line != *"master"* && $line != *"AGE"* ]]
    then
        IFS=" " read -r -a node_name <<< "$line"
        file_path="cortx-cloud-helm-pkg/cortx-provisioner/mnt-blk-info-$node_name.txt"
        count=001
        while IFS=' ' read -r mount_path || [[ -n "$mount_path" ]]; do
            count_str=$(printf "%03d" $count)
            count=$((count+1))
            helm_name1="cortx-data-blk-data$count_str-$node_name"
            helm uninstall $helm_name1
        done < "$file_path"
    fi
done <<< "$(kubectl get nodes)"

printf "######################################################\n"
printf "# Delete Persistent Volume Claims                     \n"
printf "######################################################\n"
while IFS= read -r line; do
    if [[ $line != *"master"* && $line != *"AGE"* ]]
    then
        IFS=" " read -r -a pvc_line <<< "$line"
        if [[ "${pvc_line[5]}" == *"cortx-"* ]]; then
            printf "Removing ${pvc_line[0]}\n"
            kubectl delete pv ${pvc_line[0]}
        fi
    fi
done <<< "$(kubectl get pv -A)"

#############################################################
# Destroy CORTX 3rd party
#############################################################

printf "###################################\n"
printf "# Delete Kafka                    #\n"
printf "###################################\n"
helm uninstall kafka

printf "###################################\n"
printf "# Delete Zookeeper                #\n"
printf "###################################\n"
helm uninstall zookeeper

printf "###################################\n"
printf "# Delete openLDAP                 #\n"
printf "###################################\n"
helm uninstall "openldap"
# # Delete everything in "/var/lib/ldap folder" in all worker nodes
# node1=${1:-'192.168.5.148'}
# node2=${2:-'192.168.5.150'}
# ssh root@$node1 "rm -rf /var/lib/ldap/*"
# ssh root@$node2 "rm -rf /var/lib/ldap/*"

printf "###################################\n"
printf "# Delete Consul                   #\n"
printf "###################################\n"
helm delete consul
# kubectl delete -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl delete -f cortx-cloud-3rd-party-pkg/local-path-storage.yaml

printf "###################################\n"
printf "# Delete Persistent Volume Claims #\n"
printf "###################################\n"
VOLUME_CLAIMS=$(kubectl get pvc | grep -E "$PVC_CONSUL_FILTER|$PVC_KAFKA_FILTER|$PVC_ZOOKEEPER_FILTER|$OPENLDAP_PVC" | cut -f1 -d " ")
echo $VOLUME_CLAIMS
for VOLUME_CLAIM in $VOLUME_CLAIMS
do
    printf "Removing $VOLUME_CLAIM\n"
    kubectl delete pvc $VOLUME_CLAIM
done

printf "###################################\n"
printf "# Delete Persistent Volumes       #\n"
printf "###################################\n"
PERSISTENT_VOLUMES=$(kubectl get pv | grep -E "$PVC_CONSUL_FILTER|$PVC_KAFKA_FILTER|$PVC_ZOOKEEPER_FILTER" | cut -f1 -d " ")
echo $PERSISTENT_VOLUMES
for PERSISTENT_VOLUME in $PERSISTENT_VOLUMES
do
    printf "Removing $PERSISTENT_VOLUME\n"
    kubectl delete pv $PERSISTENT_VOLUME
done
