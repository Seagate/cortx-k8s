#!/bin/bash

namespace="default"
storage_class=${1:-'local-path'}

# Default list of worker nodes to be used to deploy OpenLDAP
openldap_worker_node_list[0]='node-1'
openldap_worker_node_list[1]='node-2'
openldap_worker_node_list[2]='node-3'

num_worker_nodes=0
while IFS= read -r line; do
    if [[ $line != *"master"* && $line != *"AGE"* ]]
    then
        IFS=" " read -r -a node_name <<< "$line"
        openldap_worker_node_list[num_worker_nodes]=$node_name
        num_worker_nodes=$((num_worker_nodes+1))
    fi
done <<< "$(kubectl get nodes)"
printf "Number of worker nodes detected: $num_worker_nodes\n"

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

# Validate solution yaml file contains the same number of worker nodes
echo "Number of worker nodes in solution.yaml: ${#parsed_var_val_array[@]}"
if [[ "$num_worker_nodes" != "${#parsed_var_val_array[@]}" ]]
then
    printf "\nThe number of detected worker nodes is not the same as the number of\n"
    printf "nodes defined in the 'solution.yaml' file\n"
    exit 1
fi

node_name_list=[] # short version
node_selector_list=[] # long version
count=0
# Loop the var val tuple array
for var_val_element in "${parsed_var_val_array[@]}"
do
    node_name=$(echo $var_val_element | cut -f2 -d'>')
    node_selector_list[count]=$node_name
    shorter_node_name=$(echo $node_name | cut -f1 -d'.')
    node_name_list[count]=$shorter_node_name
    count=$((count+1))
    file_name="mnt-blk-info-$shorter_node_name.txt"
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
            if [[ -s $provisioner_file_path ]]; then
                printf "\n" >> $provisioner_file_path
            fi
            if [[ -s $data_file_path ]]; then
                printf "\n" >> $data_file_path
            fi
            printf $device >> $provisioner_file_path
            printf $device >> $data_file_path
        fi
    done
done

if [[ "$namespace" != "default" ]]; then
    kubectl create namespace $namespace
fi

##########################################################
# Deploy CORTX 3rd party
##########################################################

printf "######################################################\n"
printf "# Deploy Consul                                       \n"
printf "######################################################\n"

# Add the HashiCorp Helm Repository:
helm repo add hashicorp https://helm.releases.hashicorp.com
if [[ $storage_class == "local-path" ]]
then
    printf "Install Rancher Local Path Provisioner"
    kubectl create -f cortx-cloud-3rd-party-pkg/local-path-storage.yaml
fi

helm install "consul" hashicorp/consul \
    --set global.name="consul" \
    --set server.storageClass=$storage_class \
    --set server.replicas=$num_worker_nodes

printf "######################################################\n"
printf "# Deploy openLDAP                                     \n"
printf "######################################################\n"
# Set max number of OpenLDAP replicas to be 3
num_replicas=3
if [[ "$num_worker_nodes" -le 3 ]]; then
    num_replicas=$num_worker_nodes
fi

helm install "openldap" cortx-cloud-3rd-party-pkg/openldap \
    --set storageclass="openldap-storage" \
    --set storagesize="1Gi" \
    --set service.name="openldap-svc" \
    --set service.ip="10.105.117.12" \
    --set statefulset.name="openldap" \
    --set statefulset.replicas=$num_replicas \
    --set pv1.name="openldap-pv-0" \
    --set pv1.node=${openldap_worker_node_list[0]} \
    --set pv1.localpath="/var/lib/ldap" \
    --set pv2.name="openldap-pv-1" \
    --set pv2.node=${openldap_worker_node_list[1]} \
    --set pv2.localpath="/var/lib/ldap" \
    --set pv3.name="openldap-pv-2" \
    --set pv3.node=${openldap_worker_node_list[2]} \
    --set pv3.localpath="/var/lib/ldap" \
    --set namespace="default"

# Wait for all openLDAP pods to be ready and build up openLDAP endpoint array
# which consists of "<openLDAP-pod-name> <openLDAP-endpoint-ip-addr>""
printf "\nWait for openLDAP PODs to be ready"
while true; do
    openldap_ep_array=[]
    count=0

    while IFS= read -r line; do
        IFS=" " read -r -a my_array <<< "$line"
        openldap_ep_array[count]="${my_array[1]} ${my_array[6]}"
        if [[ ${my_array[6]} == "<none>" ]]; then
            break
        fi
        count=$((count+1))
    done <<< "$(kubectl get pods -A -o wide | grep 'openldap-')"

    if [[ $count -eq $num_replicas ]]
    then
        break
    else
        printf "."
    fi
    sleep 1s
done
printf "\n\n"

num_openldap_nodes=${#openldap_ep_array[@]}
replicate_ldif_file="opt/seagate/cortx/s3/install/ldap/replicate.ldif"
if [[ $num_openldap_nodes -eq 2 ]]
then    
    replicate_ldif_file="opt/seagate/cortx/s3/install/ldap/replicate_2nodes.ldif"
fi

# Update openLDAP config
for openldap_ep in "${openldap_ep_array[@]}"
do
    IFS=" " read -r -a my_array <<< "$openldap_ep"

    SHA=$(kubectl exec -i ${my_array[0]} --namespace="default" -- slappasswd -s ldapadmin)
    ESC_SHA=$(kubectl exec -i ${my_array[0]} --namespace=default -- echo $SHA | sed 's/[/]/\\\//g')
    EXPR='s/userPassword: *.*/userPassword: '$ESC_SHA'/g'
    kubectl exec -i ${my_array[0]} --namespace="default" -- \
        sed -i "$EXPR" opt/seagate/cortx/s3/install/ldap/iam-admin.ldif

    kubectl exec -i ${my_array[0]} --namespace="default" -- \
        ldapadd -x -D "cn=admin,dc=seagate,dc=com" \
        -w ldapadmin \
        -f opt/seagate/cortx/s3/install/ldap/ldap-init.ldif \
        -H ldap://${my_array[1]}

    kubectl exec -i ${my_array[0]} --namespace="default" -- \
        ldapadd -x -D "cn=admin,dc=seagate,dc=com" \
        -w ldapadmin \
        -f opt/seagate/cortx/s3/install/ldap/iam-admin.ldif \
        -H ldap://${my_array[1]}

    kubectl exec -i ${my_array[0]} --namespace="default" -- \
        ldapmodify -x -a -D cn=admin,dc=seagate,dc=com \
        -w ldapadmin \
        -f opt/seagate/cortx/s3/install/ldap/ppolicy-default.ldif \
        -H ldap://${my_array[1]}
        
    kubectl exec -i ${my_array[0]} --namespace="default" -- \
        ldapadd -Y EXTERNAL -H ldapi:/// \
        -f opt/seagate/cortx/s3/install/ldap/syncprov_mod.ldif
        
    kubectl exec -i ${my_array[0]} --namespace="default" -- \
        ldapadd -Y EXTERNAL -H ldapi:/// \
        -f opt/seagate/cortx/s3/install/ldap/syncprov.ldif
        
    uri_count=1
    for openldap_ep in "${openldap_ep_array[@]}"
    do
        IFS=" " read -r -a temp_array <<< "$openldap_ep"
        output=$(kubectl exec -i ${my_array[0]} --namespace=default -- \
                    sed "s/<sample_provider_URI_$uri_count>/${temp_array[1]}/g" \
                    $replicate_ldif_file)
        kubectl exec -i ${my_array[0]} --namespace="default" -- bash -c "echo '$output' > $replicate_ldif_file"
        uri_count=$((uri_count+1))
    done
done

printf "######################################################\n"
printf "# Deploy Zookeeper                                    \n"
printf "######################################################\n"
# Add Zookeeper and Kafka Repository
helm repo add bitnami https://charts.bitnami.com/bitnami

helm install zookeeper bitnami/zookeeper \
    --set replicaCount=$num_worker_nodes \
    --set auth.enabled=false \
    --set allowAnonymousLogin=true \
    --set global.storageClass=$storage_class

printf "######################################################\n"
printf "# Deploy Kafka                                        \n"
printf "######################################################\n"
helm install kafka bitnami/kafka \
    --set zookeeper.enabled=false \
    --set replicaCount=$num_worker_nodes \
    --set externalZookeeper.servers=zookeeper.default.svc.cluster.local \
    --set global.storageClass=$storage_class \
    --set defaultReplicationFactor=$num_worker_nodes \
    --set offsetTopicReplicationFactor=$num_worker_nodes \
    --set transactionStateLogReplicationFactor=$num_worker_nodes \
    --set auth.enabled=false \
    --set allowAnonymousLogin=true \
    --set deleteTopicEnable=true \
    --set transactionStateLogMinIsr=2

printf "\nWait for CORTX 3rd party to be ready"
while true; do
    count=0
    while IFS= read -r line; do
        IFS=" " read -r -a pod_status <<< "$line"        
        IFS="/" read -r -a ready_status <<< "${pod_status[2]}"
        if [[ "${pod_status[3]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            count=$((count+1))
            break
        fi
    done <<< "$(kubectl get pods -A | grep 'consul\|kafka\|openldap\|zookeeper')"

    if [[ $count -eq 0 ]]; then
        break
    else
        printf "."
    fi    
    sleep 1s
done
printf "\n\n"

##########################################################
# Deploy CORTX cloud
##########################################################
# GlusterFS
gluster_vol="myvol"
gluster_folder="/etc/gluster"
pod_ctr_mount_path="/mnt/fs-local-volume/$gluster_folder"
gluster_pv_name="gluster-default-volume"
gluster_pvc_name="gluster-claim"

printf "######################################################\n"
printf "# Deploy CORTX Local Block Storage                    \n"
printf "######################################################\n"
for i in "${!node_selector_list[@]}"; do
    node_name=${node_name_list[i]}
    node_selector=${node_selector_list[i]}
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
            --set cortxblkdata.nodename=$node_selector \
            --set cortxblkdata.storage.localpath=$mount_path \
            --set cortxblkdata.storage.size=$storage_size \
            --set cortxblkdata.storageclass=$storage_class_name1 \
            --set cortxblkdata.storage.pvc.name=$pvc1_name \
            --set cortxblkdata.storage.pv.name=$pv1_name \
            --set cortxblkdata.storage.volumemode="Block" \
            --set namespace=$namespace
    done < "$file_path"
done

printf "########################################################\n"
printf "# Deploy CORTX GlusterFS                                \n"
printf "########################################################\n"
# Deploy GlusterFS
first_node_name=${node_name_list[0]}
first_node_selector=${node_selector_list[0]}

helm install "cortx-gluster-$first_node_name" cortx-cloud-helm-pkg/cortx-gluster \
    --set cortxgluster.name="gluster-$node_name_list" \
    --set cortxgluster.nodename=$first_node_selector \
    --set cortxgluster.service.name="cortx-gluster-svc-$first_node_name" \
    --set cortxgluster.storagesize="1Gi" \
    --set cortxgluster.storageclass="cortx-gluster-storage" \
    --set cortxgluster.pv.path=$gluster_vol \
    --set cortxgluster.pv.name=$gluster_pv_name \
    --set cortxgluster.pvc.name=$gluster_pvc_name \
    --set cortxgluster.hostpath.etc=$pod_ctr_mount_path \
    --set cortxgluster.hostpath.logs="/mnt/fs-local-volume/var/log/gluster" \
    --set cortxgluster.hostpath.config="/mnt/fs-local-volume/var/lib/glusterd" \
    --set namespace=$namespace
num_nodes=1

printf "\nWait for GlusterFS endpoint to be ready"
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
printf "\n\n"

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
printf "# Deploy CORTX Provisioner                              \n"
printf "########################################################\n"
for i in "${!node_selector_list[@]}"; do
    node_name=${node_name_list[i]}
    node_selector=${node_selector_list[i]}
    helm install "cortx-provisioner-$node_name" cortx-cloud-helm-pkg/cortx-provisioner \
        --set cortxprov.name="cortx-provisioner-pod-$node_name" \
        --set cortxprov.nodename=$node_name \
        --set cortxprov.mountblkinfo="mnt-blk-info-$node_name.txt" \
        --set cortxprov.service.name="cortx-data-clusterip-svc-$node_name" \
        --set cortxgluster.pv.name=$gluster_pv_name \
        --set cortxgluster.pv.mountpath=$pod_ctr_mount_path \
        --set cortxgluster.pvc.name=$gluster_pvc_name \
        --set cortxprov.cfgmap.name="cortx-provisioner-cfgmap001-$node_name" \
        --set cortxprov.cfgmap.volmountname="config001-$node_name" \
        --set cortxprov.cfgmap.mountpath="/etc/cortx" \
        --set cortxprov.localpathpvc.name="cortx-fs-local-pvc-$node_name" \
        --set cortxprov.localpathpvc.mountpath="/data" \
        --set cortxprov.localpathpvc.requeststoragesize="1Gi" \
        --set namespace=$namespace
done

# Check if all OpenLDAP are up and running
node_count="${#node_selector_list[@]}"

printf "\nWait for CORTX Provisioner to complete"
while true; do
    count=0
    while IFS= read -r line; do
        IFS=" " read -r -a pod_status <<< "$line"
        if [[ "${pod_status[2]}" != "Completed" ]]; then
            break
        fi
        count=$((count+1))
    done <<< "$(kubectl get pods --namespace=$namespace | grep 'cortx-provisioner-pod-')"

    if [[ $node_count -eq $count ]]; then
        break
    else
        printf "."
    fi    
    sleep 1s
done
printf "\n\n"

# Delete CORTX Provisioner Services
for i in "${!node_selector_list[@]}"; do
    node_name=${node_name_list[i]}
    node_selector=${node_selector_list[i]}
    num_nodes=$((num_nodes+1))
    kubectl delete service "cortx-data-clusterip-svc-$node_name" --namespace=$namespace
done

printf "########################################################\n"
printf "# Deploy CORTX Data                                     \n"
printf "########################################################\n"
num_nodes=0
for i in "${!node_selector_list[@]}"; do
    num_nodes=$((num_nodes+1))
    node_name=${node_name_list[i]}
    node_selector=${node_selector_list[i]}
    helm install "cortx-data-$node_name" cortx-cloud-helm-pkg/cortx-data \
        --set cortxdata.name="cortx-data-pod-$node_name" \
        --set cortxdata.nodename=$node_name \
        --set cortxdata.mountblkinfo="mnt-blk-info-$node_name.txt" \
        --set cortxdata.service.name="cortx-data-clusterip-svc-$node_name" \
        --set cortxgluster.pv.name=$gluster_pv_name \
        --set cortxgluster.pv.mountpath=$pod_ctr_mount_path \
        --set cortxgluster.pvc.name=$gluster_pvc_name \
        --set cortxdata.cfgmap.name="cortx-data-cfgmap001-$node_name" \
        --set cortxdata.cfgmap.volmountname="config001-$node_name" \
        --set cortxdata.cfgmap.mountpath="/etc/cortx" \
        --set cortxdata.localpathpvc.name="cortx-fs-local-pvc-$node_name" \
        --set cortxdata.localpathpvc.mountpath="/data" \
        --set namespace=$namespace
done

printf "\nWait for CORTX Data to be ready"
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
printf "\n\n"

printf "########################################################\n"
printf "# Deploy CORTX Control                                  \n"
printf "########################################################\n"
num_nodes=1
# This local path pvc has to match with the one created by CORTX Provisioner
local_path_pvc="cortx-fs-local-pvc-$first_node_name"
helm install "cortx-control" cortx-cloud-helm-pkg/cortx-control \
    --set cortxcontrol.name="cortx-control-pod" \
    --set cortxcontrol.service.name="cortx-control-clusterip-svc" \
    --set cortxcontrol.cfgmap.mountpath="/etc/cortx" \
    --set cortxcontrol.cfgmap.name="cortx-control-cfgmap001" \
    --set cortxcontrol.cfgmap.volmountname="config001" \
    --set cortxcontrol.localpathpvc.name=$local_path_pvc \
    --set cortxcontrol.localpathpvc.mountpath="/data" \
    --set cortxgluster.pv.name="gluster-default-name" \
    --set cortxgluster.pv.mountpath=$pod_ctr_mount_path \
    --set cortxgluster.pvc.name="gluster-claim" \
    --set namespace=$namespace

printf "\nWait for CORTX Control to be ready"
while true; do
    count=0
    while IFS= read -r line; do
        IFS=" " read -r -a pod_status <<< "$line"        
        IFS="/" read -r -a ready_status <<< "${pod_status[1]}"
        if [[ "${pod_status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            break
        fi
        count=$((count+1))
    done <<< "$(kubectl get pods --namespace=$namespace | grep 'cortx-control-pod-')"

    if [[ $num_nodes -eq $count ]]; then
        break
    else
        printf "."
    fi    
    sleep 1s
done
printf "\n\n"

printf "########################################################\n"
printf "# Deploy CORTX Support                                  \n"
printf "########################################################\n"
num_nodes=1
# This local path pvc has to match with the one created by CORTX Provisioner
local_path_pvc="cortx-fs-local-pvc-$first_node_name"
helm install "cortx-support" cortx-cloud-helm-pkg/cortx-support \
    --set cortxsupport.name="cortx-support-pod" \
    --set cortxsupport.service.name="cortx-support-clusterip-svc" \
    --set cortxsupport.cfgmap.mountpath="/etc/cortx" \
    --set cortxsupport.cfgmap.name="cortx-support-cfgmap001" \
    --set cortxsupport.cfgmap.volmountname="config001" \
    --set cortxsupport.localpathpvc.name=$local_path_pvc \
    --set cortxsupport.localpathpvc.mountpath="/data" \
    --set cortxgluster.pv.name="gluster-default-name" \
    --set cortxgluster.pv.mountpath=$pod_ctr_mount_path \
    --set cortxgluster.pvc.name="gluster-claim" \
    --set namespace=$namespace

printf "Wait for CORTX Support to be ready"
while true; do
    count=0
    while IFS= read -r line; do
        IFS=" " read -r -a pod_status <<< "$line"        
        IFS="/" read -r -a ready_status <<< "${pod_status[1]}"
        if [[ "${pod_status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            break
        fi
        count=$((count+1))
    done <<< "$(kubectl get pods --namespace=$namespace | grep 'cortx-support-pod-')"

    if [[ $num_nodes -eq $count ]]; then
        break
    else
        printf "."
    fi    
    sleep 1s
done
printf "\n"

#################################################################
# Delete files that contain disk partitions on the worker nodes
#################################################################
# Split parsed output into an array of vars and vals
IFS=';' read -r -a parsed_var_val_array <<< "$parsed_node_output"
# Loop the var val tuple array
for var_val_element in "${parsed_var_val_array[@]}"
do
    node_name=$(echo $var_val_element | cut -f2 -d'>')
    shorter_node_name=$(echo $node_name | cut -f1 -d'.')
    file_name="mnt-blk-info-$shorter_node_name.txt"
    rm $(pwd)/cortx-cloud-helm-pkg/cortx-provisioner/$file_name
    rm $(pwd)/cortx-cloud-helm-pkg/cortx-data/$file_name
done
