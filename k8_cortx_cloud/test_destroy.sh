#!/bin/bash

namespace="cortx-cloud"

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

# printf "######################################################\n"
# printf "# Delete CORTX Local Filesystem Storage               \n"
# printf "######################################################\n"
# while IFS= read -r line; do
#     if [[ $line != *"master"* && $line != *"AGE"* ]]
#     then
#         IFS=" " read -r -a node_name <<< "$line"
#         helm_name1="cortx-data-fs-local001-$node_name"
#         helm uninstall $helm_name1
#     fi
# done <<< "$(kubectl get nodes)"

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

# printf "######################################################\n"
# printf "# Delete Rancher Local Path Provisioner               \n"
# printf "######################################################\n"
# kubectl delete -f cortx-cloud-3rd-party-pkg/local-path-storage.yaml

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

# Delete CORTX namespace
if [[ "$namespace" != "default" ]]; then
    kubectl delete namespace $namespace
fi