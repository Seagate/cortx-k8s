#!/bin/bash

pvc_consul_filter="data-default-consul"
pvc_kafka_filter="kafka"
pvc_zookeeper_filter="zookeeper"
pv_filter="pvc"
openldap_pvc="openldap-data"

namespace="default"

#################################################################
# Create files that contain disk partitions on the worker nodes
#################################################################
function parseSolution()
{
    echo "$(./parse_yaml.sh solution.yaml $1)"
}

parsed_node_output=$(parseSolution 'solution.nodes.node*.name')

# Split parsed output into an array of vars and vals
IFS=';' read -r -a parsed_var_val_array <<< "$parsed_node_output"
# Loop the var val tuple array
for var_val_element in "${parsed_var_val_array[@]}"
do
    node_name=$(echo $var_val_element | cut -f2 -d'>')
    file_name="mnt-blk-info-$node_name.txt"
    provisioner_file_path=$(pwd)/cortx-cloud-helm-pkg/cortx-provisioner/$file_name
    data_file_path=$(pwd)/cortx-cloud-helm-pkg/cortx-data/$file_name

    if [[ -f $provisioner_file_path ]]; then
        rm $provisioner_file_path
    elif [[ -f $data_file_path ]]; then
        rm $data_file_path
    fi

    # Get the node var from the tuple
    node=$(echo $var_val_element | cut -f3 -d'.')
    
    filter="solution.nodes.$node.devices*"
    parsed_dev_output=$(parseSolution $filter)
    IFS=';' read -r -a parsed_dev_array <<< "$parsed_dev_output"
    for dev in "${parsed_dev_array[@]}"
    do
        if [[ "$dev" != *"system"* ]]
        then
            device=$(echo $dev | cut -f2 -d'>')
            # echo $device >> $provisioner_file_path
            # echo $device >> $data_file_path
            if [[ -s $provisioner_file_path ]]; then
                printf "\n" >> $provisioner_file_path
            elif [[ -s $data_file_path ]]; then
                printf "\n" >> $data_file_path
            fi
            printf $device >> $provisioner_file_path
            printf $device >> $data_file_path
        fi
    done
done

#############################################################
# Destroy CORTX Cloud
#############################################################

printf "########################################################\n"
printf "# Delete CORTX Support                                  \n"
printf "########################################################\n"
helm uninstall "cortx-support"

printf "########################################################\n"
printf "# Delete CORTX Control                                  \n"
printf "########################################################\n"
helm uninstall "cortx-control"

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
gluster_folder="/etc/gluster"
pod_ctr_mount_path="/mnt/fs-local-volume/$gluster_folder"

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
volume_claims=$(kubectl get pvc | grep -E "$pvc_consul_filter|$pvc_kafka_filter|$pvc_zookeeper_filter|$openldap_pvc" | cut -f1 -d " ")
echo $volume_claims
for volume_claim in $volume_claims
do
    printf "Removing $volume_claim\n"
    kubectl delete pvc $volume_claim
done

printf "###################################\n"
printf "# Delete Persistent Volumes       #\n"
printf "###################################\n"
persistent_volumes=$(kubectl get pv | grep -E "$pvc_consul_filter|$pvc_kafka_filter|$pvc_zookeeper_filter" | cut -f1 -d " ")
echo $persistent_volumes
for persistent_volume in $persistent_volumes
do
    printf "Removing $persistent_volume\n"
    kubectl delete pv $persistent_volume
done

# Delete CORTX namespace
if [[ "$namespace" != "default" ]]; then
    kubectl delete namespace $namespace
fi

#################################################################
# Delete files that contain disk partitions on the worker nodes #
#################################################################
# Split parsed output into an array of vars and vals
IFS=';' read -r -a parsed_var_val_array <<< "$parsed_node_output"
# Loop the var val tuple array
for var_val_element in "${parsed_var_val_array[@]}"
do
    node_name=$(echo $var_val_element | cut -f2 -d'>')
    file_name="mnt-blk-info-$node_name.txt"
    rm $(pwd)/cortx-cloud-helm-pkg/cortx-provisioner/$file_name
    rm $(pwd)/cortx-cloud-helm-pkg/cortx-data/$file_name
done

# Delete everything in "/var/lib/ldap folder" in all worker nodes
sshpass -p "dton" ssh root@192.168.5.148 "rm -rf /var/lib/ldap/* /mnt/fs-local-volume/local-path-provisioner/*"
sshpass -p "dton" ssh root@192.168.5.150 "rm -rf /var/lib/ldap/* /mnt/fs-local-volume/local-path-provisioner/*"
