#!/bin/bash

namespace="cortx-cloud"
kubectl create namespace $namespace

# GlusterFS
gluster_vol="myvol"
gluster_folder="/etc/gluster/test_folder"
pod_ctr_mount_path="/mnt/fs-local-volume/etc/gluster/test_folder/"
gluster_pv_name="gluster-default-volume"
gluster_pvc_name="gluster-claim"

# printf "######################################################\n"
# printf "# Deploy Rancher Local Path Provisioner               \n"
# printf "######################################################\n"
# kubectl create -f cortx-cloud-3rd-party-pkg/local-path-storage.yaml

printf "######################################################\n"
printf "# Deploy CORTX Local Block Storage                    \n"
printf "######################################################\n"
while IFS= read -r line; do
    if [[ $line != *"master"* && $line != *"AGE"* ]]
    then
        IFS=" " read -r -a node_name <<< "$line"
        file_path="cortx-cloud-helm-pkg/cortx-provisioner/mnt-blk-info-$node_name.txt"
        count=001
        while IFS=' ' read -r mount_path || [[ -n "$mount_path" ]]; do
            mount_base_dir=$( echo "$mount_path" | sed -e 's/\/.*\///g')
            count_str=$(printf "%03d" $count)
            count=$((count+1))
            helm_name1="cortx-data-blk-data$count_str-$node_name"
            storage_class_name1="local-blk-storage$count_str-$node_name"
            pvc1_name="cortx-data-$mount_base_dir-pvc-$node_name"
            pv1_name="cortx-data-$mount_base_dir-pv-$node_name"
            storage_size="5Gi"
            helm install $helm_name1 cortx-cloud-helm-pkg/cortx-data-blk-data \
                --set cortxblkdata.nodename=$node_name \
                --set cortxblkdata.storage.localpath=$mount_path \
                --set cortxblkdata.storage.size=$storage_size \
                --set cortxblkdata.storageclass=$storage_class_name1 \
                --set cortxblkdata.storage.pvc.name=$pvc1_name \
                --set cortxblkdata.storage.pv.name=$pv1_name \
                --set cortxblkdata.storage.volumemode="Block" \
                --set namespace=$namespace
        done < "$file_path"
    fi
done <<< "$(kubectl get nodes)"

printf "########################################################\n"
printf "# Deploy CORTX GlusterFS                                \n"
printf "########################################################\n"
# Deploy GlusterFS
node_name="node-1"
helm install "cortx-gluster-$node_name" cortx-cloud-helm-pkg/cortx-gluster \
    --set cortxgluster.name="gluster-$node_name" \
    --set cortxgluster.nodename=$node_name \
    --set cortxgluster.service.name="cortx-gluster-svc-$node_name" \
    --set cortxgluster.storagesize="1Gi" \
    --set cortxgluster.pv.path=$gluster_vol \
    --set cortxgluster.pv.name=$gluster_pv_name \
    --set cortxgluster.pvc.name=$gluster_pvc_name \
    --set cortxgluster.hostpath.etc="/mnt/fs-local-volume/etc/gluster" \
    --set cortxgluster.hostpath.logs="/mnt/fs-local-volume/var/log/gluster" \
    --set cortxgluster.hostpath.config="/mnt/fs-local-volume/var/lib/glusterd" \
    --set namespace=$namespace
num_nodes=1

printf "Wait for GlusterFS endpoint to be ready"
while true; do
    count=0
    while IFS= read -r line; do
        IFS=" " read -r -a service_status <<< "$line"        
        IFS="/" read -r -a ready_status <<< "${pod_status[1]}"
        if [[ "${service_status[2]}" == "<none>" ]]; then
            break
        fi
        count=$((count+1))
    done <<< "$(kubectl get endpoints -A | grep 'gluster-')"

    if [[ $num_nodes -eq $count ]]; then
        break
    else
        printf "."
    fi    
    sleep 1s
done
printf "\n"

printf "Wait for GlusterFS pod to be ready"
while true; do
    count=0
    while IFS= read -r line; do
        IFS=" " read -r -a pod_status <<< "$line"        
        IFS="/" read -r -a ready_status <<< "${pod_status[2]}"
        if [[ "${pod_status[3]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            break
        fi
        count=$((count+1))
    done <<< "$(kubectl get pods -A | grep 'gluster-')"

    if [[ $num_nodes -eq $count ]]; then
        break
    else
        printf "."
    fi    
    sleep 1s
done
printf "\n"

# Build Gluster endpoint array
gluster_ep_array=[]
count=0
while IFS= read -r line; do
    IFS=" " read -r -a my_array <<< "$line"
    gluster_ep_array[count]=$line
    count=$((count+1))
done <<< "$(kubectl get pods -A -o wide | grep 'gluster-')"

gluster_and_host_name_arr=[]
# Loop through all gluster endpoint array and find endoint IP address
# and gluster node name
count=0
first_gluster_node_name=''
first_gluster_ip=''
replica_list=''
for gluster_ep in "${gluster_ep_array[@]}"
do
    IFS=" " read -r -a my_array <<< "$gluster_ep"
    gluster_ep_ip=${my_array[6]}
    gluster_node_name=${my_array[1]}    
    gluster_and_host_name_arr[count]="${gluster_ep_ip} ${gluster_node_name}"
    if [[ "$count" == 0 ]]; then
        first_gluster_node_name=$gluster_node_name
        first_gluster_ip=$gluster_ep_ip
    else
        kubectl exec -i $first_gluster_node_name --namespace=$namespace -- gluster peer probe $gluster_ep_ip
    fi
    replica_list+="$gluster_ep_ip:$gluster_folder "
    count=$((count+1))
done

len_array=${#gluster_ep_array[@]}
if [[ ${#gluster_ep_array[@]} -ge 2 ]]
then
    # Create replica gluster volumes
    kubectl exec -i $first_gluster_node_name --namespace=$namespace -- gluster volume create $gluster_vol replica $len_array $replica_list force
else
    # Add gluster volume
    kubectl exec -i $first_gluster_node_name --namespace=$namespace -- gluster volume create $gluster_vol $first_gluster_ip:$gluster_folder force
fi

# Start gluster volume
echo y | kubectl exec -i $first_gluster_node_name --namespace=$namespace --namespace=$namespace -- gluster volume start $gluster_vol

printf "########################################################\n"
printf "# Deploy CORTX provisioner                              \n"
printf "########################################################\n"
num_nodes=0
while IFS= read -r line; do
    if [[ $line != *"master"* && $line != *"AGE"* ]]; then
        IFS=" " read -r -a node_name <<< "$line"
        num_nodes=$((num_nodes+1))
        helm install "cortx-provisioner-$node_name" cortx-cloud-helm-pkg/cortx-provisioner \
            --set cortxprov.name="cortx-provisioner-pod-$node_name" \
            --set cortxprov.nodename=$node_name \
            --set cortxprov.mountblkinfo="mnt-blk-info-$node_name.txt" \
            --set cortxprov.service.name="cortx-data-clusterip-svc-$node_name" \
            --set cortxgluster.pv.name=$gluster_pv_name \
            --set cortxgluster.pv.mountpath=$pod_ctr_mount_path \
            --set cortxgluster.pvc.name=$gluster_pvc_name \
            --set cortxprov.localpathpvc.name="cortx-local-path-pvc-$node_name" \
            --set cortxprov.localpathpvc.mountpath="/data" \
            --set namespace=$namespace
    fi
done <<< "$(kubectl get nodes)"

printf "Wait for CORTX Provisioner to complete"
while true; do
    count=0
    while IFS= read -r line; do
        IFS=" " read -r -a pod_status <<< "$line"
        if [[ "${pod_status[2]}" != "Completed" ]]; then
            break
        fi
        count=$((count+1))
    done <<< "$(kubectl get pods --namespace=$namespace | grep 'cortx-provisioner-pod-')"

    if [[ $num_nodes -eq $count ]]; then
        break
    else
        printf "."
    fi    
    sleep 1s
done
printf "\n"

# Delete CORTX Provisioner Services
while IFS= read -r line; do
    if [[ $line != *"master"* && $line != *"AGE"* ]]; then
        IFS=" " read -r -a node_name <<< "$line"
        num_nodes=$((num_nodes+1))
        kubectl delete service "cortx-data-clusterip-svc-$node_name" --namespace=$namespace
    fi
done <<< "$(kubectl get nodes)"

printf "########################################################\n"
printf "# Deploy CORTX data                                     \n"
printf "########################################################\n"
num_nodes=0
while IFS= read -r line; do
    if [[ $line != *"master"* && $line != *"AGE"* ]]; then
        IFS=" " read -r -a node_name <<< "$line"
        num_nodes=$((num_nodes+1))
        helm install "cortx-data-$node_name" cortx-cloud-helm-pkg/cortx-data \
            --set cortxdata.name="cortx-data-pod-$node_name" \
            --set cortxdata.nodename=$node_name \
            --set cortxdata.mountblkinfo="mnt-blk-info-$node_name.txt" \
            --set cortxdata.service.name="cortx-data-clusterip-svc-$node_name" \
            --set cortxgluster.pv.name=$gluster_pv_name \
            --set cortxgluster.pv.mountpath=$pod_ctr_mount_path \
            --set cortxgluster.pvc.name=$gluster_pvc_name \
            --set cortxdata.cfgmap.ctr1.name="cortx-data-cfgmap001-$node_name" \
            --set cortxdata.cfgmap.ctr1.volmountname="config001-$node_name" \
            --set cortxdata.cfgmap.ctr2.name="cortx-data-cfgmap002-$node_name" \
            --set cortxdata.cfgmap.ctr2.volmountname="config002-$node_name" \
            --set cortxdata.localpathpvc.name="cortx-local-path-pvc-$node_name" \
            --set cortxdata.localpathpvc.mountpath="/data" \
            --set namespace=$namespace
    fi
done <<< "$(kubectl get nodes)"

printf "Wait for CORTX data to complete"
while true; do
    count=0
    while IFS= read -r line; do
        IFS=" " read -r -a pod_status <<< "$line"        
        IFS="/" read -r -a ready_status <<< "${pod_status[1]}"
        if [[ "${pod_status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            break
        fi
        count=$((count+1))
    done <<< "$(kubectl get pods --namespace=$namespace | grep 'cortx-data-pod-')"

    if [[ $num_nodes -eq $count ]]; then
        break
    else
        printf "."
    fi    
    sleep 1s
done
printf "\n"
