#!/bin/bash

storage_class='local-path'

# Delete old "node-list-info.txt" file
find $(pwd)/cortx-cloud-3rd-party-pkg/openldap -name "node-list-info*" -delete

max_openldap_inst=3 # Default max openldap instances
max_consul_inst=3
max_kafka_inst=3
num_openldap_replicas=0 # Default the number of actual openldap instances
num_worker_nodes=0
while IFS= read -r line; do
    IFS=" " read -r -a node_name <<< "$line"
    if [[ "$node_name" != "NAME" ]]; then
        output=$(kubectl describe nodes $node_name | grep Taints | grep NoSchedule)
        if [[ "$output" == "" ]]; then
            node_list_str="$num_worker_nodes $node_name"
            num_worker_nodes=$((num_worker_nodes+1))

            if [[ "$num_worker_nodes" -le "$max_openldap_inst" ]]; then
                num_openldap_replicas=$num_worker_nodes
                node_list_info_path=$(pwd)/cortx-cloud-3rd-party-pkg/openldap/node-list-info.txt
                if [[ -s $node_list_info_path ]]; then
                    printf "\n" >> $node_list_info_path
                fi
                printf "$node_list_str" >> $node_list_info_path
            fi
        fi
    fi
done <<< "$(kubectl get nodes)"
printf "Number of worker nodes detected: $num_worker_nodes\n"

function parseSolution()
{
    echo "$(./parse_scripts/parse_yaml.sh solution.yaml $1)"
}

function extractBlock()
{
    echo "$(./parse_scripts/yaml_extract_block.sh solution.yaml $1)"
}

namespace=$(parseSolution 'solution.namespace')
namespace=$(echo $namespace | cut -f2 -d'>')
parsed_node_output=$(parseSolution 'solution.nodes.node*.name')

# Split parsed output into an array of vars and vals
IFS=';' read -r -a parsed_var_val_array <<< "$parsed_node_output"

tainted_worker_node_list=[]
num_tainted_worker_nodes=0
not_found_node_list=[]
num_not_found_nodes=0
# Validate solution yaml file doesn't have nodes that are tainted with "NoSchedule"
for parsed_var_val_element in "${parsed_var_val_array[@]}";
do
    node_name=$(echo $parsed_var_val_element | cut -f2 -d'>')
    output_get_node=$(kubectl get nodes | grep $node_name)
    output=$(kubectl describe nodes $node_name | grep Taints | grep NoSchedule)
    if [[ "$output" != "" ]]; then
        tainted_worker_node_list[$num_tainted_worker_nodes]=$node_name
        num_tainted_worker_nodes=$((num_tainted_worker_nodes+1))
    elif [[ "$output_get_node" == "" ]]; then
        not_found_node_list[$num_not_found_nodes]=$node_name
        num_not_found_nodes=$((num_not_found_nodes+1))
    fi
done

if [[ $num_tainted_worker_nodes -gt 0 || $num_not_found_nodes -gt 0 ]]; then
    echo "Can't deploy CORTX cloud."
    if [[ $num_tainted_worker_nodes -gt 0 ]]; then
        echo "List of tainted nodes:"
        for tainted_node_name in "${tainted_worker_node_list[@]}"; do
            echo "- $tainted_node_name"
        done
    fi
    if [[ $num_not_found_nodes -gt 0 ]]; then
        echo "List of nodes don't exist in the cluster:"
        for node_not_found in "${not_found_node_list[@]}"; do
            echo "- $node_not_found"
        done
    fi
fi

find $(pwd)/cortx-cloud-helm-pkg/cortx-data-provisioner -name "mnt-blk-*" -delete
find $(pwd)/cortx-cloud-helm-pkg/cortx-data -name "mnt-blk-*" -delete

node_name_list=[] # short version. Ex: ssc-vm-g3-rhev4-1490
node_selector_list=[] # long version. Ex: ssc-vm-g3-rhev4-1490.colo.seagate.com
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
    file_name_storage_size="mnt-blk-storage-size-$shorter_node_name.txt"
    data_prov_file_path=$(pwd)/cortx-cloud-helm-pkg/cortx-data-provisioner/$file_name
    data_prov_storage_size_file_path=$(pwd)/cortx-cloud-helm-pkg/cortx-data-provisioner/$file_name_storage_size
    data_file_path=$(pwd)/cortx-cloud-helm-pkg/cortx-data/$file_name
    data_storage_size_file_path=$(pwd)/cortx-cloud-helm-pkg/cortx-data/$file_name_storage_size

    # Get the node var from the tuple
    node=$(echo $var_val_element | cut -f3 -d'.')

    # Get the devices from the solution
    filter="solution.storage.cvg*.devices*.device"
    parsed_dev_output=$(parseSolution $filter)
    IFS=';' read -r -a parsed_dev_array <<< "$parsed_dev_output"

    # Get the sizes from the solution
    filter="solution.storage.cvg*.devices*.size"
    parsed_size_output=$(parseSolution $filter)
    IFS=';' read -r -a parsed_size_array <<< "$parsed_size_output"

    if [[ "${#parsed_dev_array[@]}" != "${#parsed_size_array[@]}" ]]
    then
        printf "\nStorage sizes are not defined for all of the storage devices\n"
        printf "in the 'solution.yaml' file\n"
        exit 1
    fi

    for dev in "${parsed_dev_array[@]}"
    do
        if [[ "$dev" != *"system"* ]]
        then
            device=$(echo $dev | cut -f2 -d'>')
            if [[ -s $data_prov_file_path ]]; then
                printf "\n" >> $data_prov_file_path
            fi
            if [[ -s $data_file_path ]]; then
                printf "\n" >> $data_file_path
            fi
            printf $device >> $data_prov_file_path
            printf $device >> $data_file_path
        fi
    done

    for dev in "${parsed_size_array[@]}"
    do
        if [[ "$dev" != *"system"* ]]
        then
            size=$(echo $dev | cut -f2 -d'>')
            if [[ -s $data_prov_storage_size_file_path ]]; then
                printf "\n" >> $data_prov_storage_size_file_path
            fi
            if [[ -s $data_storage_size_file_path ]]; then
                printf "\n" >> $data_storage_size_file_path
            fi
            printf $size >> $data_prov_storage_size_file_path
            printf $size >> $data_storage_size_file_path
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
num_consul_replicas=$num_worker_nodes
if [[ "$num_worker_nodes" -gt "$max_consul_inst" ]]; then
    num_consul_replicas=$max_consul_inst
fi

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
    --set server.replicas=$num_consul_replicas

printf "######################################################\n"
printf "# Deploy openLDAP                                     \n"
printf "######################################################\n"

openldap_password=$(parseSolution 'solution.3rdparty.openldap.password')
openldap_password=$(echo $openldap_password | cut -f2 -d'>')

helm install "openldap" cortx-cloud-3rd-party-pkg/openldap \
    --set openldap.servicename="openldap-svc" \
    --set openldap.storageclass="openldap-local-storage" \
    --set openldap.storagesize="5Gi" \
    --set openldap.nodelistinfo="node-list-info.txt" \
    --set openldap.numreplicas=$num_openldap_replicas \
    --set openldap.password=$openldap_password

# Wait for all openLDAP pods to be ready
printf "\nWait for openLDAP PODs to be ready"
while true; do
    count=0
    while IFS= read -r line; do
        IFS=" " read -r -a pod_status <<< "$line"
        IFS="/" read -r -a ready_status <<< "${pod_status[2]}"
        if [[ "${pod_status[3]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            break
        fi
        count=$((count+1))
    done <<< "$(kubectl get pods -A | grep 'openldap')"

    if [[ $count -eq $num_openldap_replicas ]]; then
        break
    else
        printf "."
    fi
    sleep 1s
done
printf "\n\n"

printf "===========================================================\n"
printf "Setup OpenLDAP replication                                 \n"
printf "===========================================================\n"
# Run replication script
./cortx-cloud-3rd-party-pkg/openldap-replication/replication.sh --rootdnpassword $openldap_password

printf "######################################################\n"
printf "# Deploy Zookeeper                                    \n"
printf "######################################################\n"
num_kafka_replicas=$num_worker_nodes
if [[ "$num_worker_nodes" -gt "$max_kafka_inst" ]]; then
    num_kafka_replicas=$max_kafka_inst
fi

# Add Zookeeper and Kafka Repository
helm repo add bitnami https://charts.bitnami.com/bitnami

helm install zookeeper bitnami/zookeeper \
    --set replicaCount=$num_kafka_replicas \
    --set auth.enabled=false \
    --set allowAnonymousLogin=true \
    --set global.storageClass=$storage_class

printf "######################################################\n"
printf "# Deploy Kafka                                        \n"
printf "######################################################\n"
helm install kafka bitnami/kafka \
    --set zookeeper.enabled=false \
    --set replicaCount=$num_kafka_replicas \
    --set externalZookeeper.servers=zookeeper.default.svc.cluster.local \
    --set global.storageClass=$storage_class \
    --set defaultReplicationFactor=$num_kafka_replicas \
    --set offsetTopicReplicationFactor=$num_kafka_replicas \
    --set transactionStateLogReplicationFactor=$num_kafka_replicas \
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

# Get the storage paths to use
local_storage=$(parseSolution 'solution.common.storage.local')
local_storage=$(echo $local_storage | cut -f2 -d'>')
shared_storage=$(parseSolution 'solution.common.storage.shared')
shared_storage=$(echo $shared_storage | cut -f2 -d'>')
log_storage=$(parseSolution 'solution.common.storage.log')
log_storage=$(echo $log_storage | cut -f2 -d'>')

# GlusterFS
gluster_vol="myvol"
gluster_folder="/etc/gluster"
gluster_etc_path="/mnt/fs-local-volume/$gluster_folder"
gluster_pv_name="gluster-default-volume"
gluster_pvc_name="gluster-claim"

printf "######################################################\n"
printf "# Deploy CORTX Local Block Storage                    \n"
printf "######################################################\n"
for i in "${!node_selector_list[@]}"; do
    node_name=${node_name_list[i]}
    node_selector=${node_selector_list[i]}

    storage_size_file_path="cortx-cloud-helm-pkg/cortx-data-provisioner/mnt-blk-storage-size-$node_name.txt"
    storage_size=[]
    size_count=0
    while IFS=' ' read -r size || [[ -n "$size" ]]; do
        storage_size[size_count]=$size
        size_count=$((size_count+1))        
    done < "$storage_size_file_path"


    file_path="cortx-cloud-helm-pkg/cortx-data-provisioner/mnt-blk-info-$node_name.txt"
    count=001
    size_count=0
    while IFS=' ' read -r mount_path || [[ -n "$mount_path" ]]; do
        mount_base_dir=$( echo "$mount_path" | sed -e 's/\/.*\///g')
        count_str=$(printf "%03d" $count)
        count=$((count+1))
        helm_name1="cortx-data-blk-data$count_str-$node_name"
        storage_class_name1="local-blk-storage$count_str-$node_name"
        pvc1_name="cortx-data-$mount_base_dir-pvc-$node_name"
        pv1_name="cortx-data-$mount_base_dir-pv-$node_name"
        helm install $helm_name1 cortx-cloud-helm-pkg/cortx-data-blk-data \
            --set cortxblkdata.nodename=$node_selector \
            --set cortxblkdata.storage.localpath=$mount_path \
            --set cortxblkdata.storage.size=${storage_size[size_count]} \
            --set cortxblkdata.storageclass=$storage_class_name1 \
            --set cortxblkdata.storage.pvc.name=$pvc1_name \
            --set cortxblkdata.storage.pv.name=$pv1_name \
            --set cortxblkdata.storage.volumemode="Block" \
            --set namespace=$namespace
        size_count=$((size_count+1))
    done < "$file_path"
done

printf "########################################################\n"
printf "# Deploy CORTX GlusterFS                                \n"
printf "########################################################\n"
# Deploy GlusterFS
first_node_name=${node_name_list[0]}
first_node_selector=${node_selector_list[0]}

helm install "cortx-gluster-$first_node_name" cortx-cloud-helm-pkg/cortx-gluster \
    --set cortxgluster.name="gluster-$first_node_name" \
    --set cortxgluster.nodename=$first_node_selector \
    --set cortxgluster.service.name="cortx-gluster-svc-$first_node_name" \
    --set cortxgluster.storagesize="1Gi" \
    --set cortxgluster.storageclass="cortx-gluster-storage" \
    --set cortxgluster.pv.path=$gluster_vol \
    --set cortxgluster.pv.name=$gluster_pv_name \
    --set cortxgluster.pvc.name=$gluster_pvc_name \
    --set cortxgluster.hostpath.etc=$gluster_etc_path \
    --set cortxgluster.hostpath.logs="/mnt/fs-local-volume/var/log/glusterfs" \
    --set cortxgluster.hostpath.config="/mnt/fs-local-volume/var/lib/glusterd" \
    --set namespace=$namespace
num_nodes=1

printf "\nWait for GlusterFS endpoint to be ready"
while true; do
    count=0
    while IFS= read -r line; do
        IFS=" " read -r -a service_status <<< "$line"
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
printf "# Deploy CORTX Configmap                                \n"
printf "########################################################\n"
# Delete all stale auto gen folders
rm -rf $(pwd)/cortx-cloud-helm-pkg/cortx-configmap/auto-gen-cfgmap
rm -rf $(pwd)/cortx-cloud-helm-pkg/cortx-configmap/auto-gen-control
rm -rf $(pwd)/cortx-cloud-helm-pkg/cortx-configmap/auto-gen-secret
rm -rf $(pwd)/cortx-cloud-helm-pkg/cortx-configmap/node-info
rm -rf $(pwd)/cortx-cloud-helm-pkg/cortx-configmap/storage-info
for i in "${!node_name_list[@]}"; do
    rm -rf $(pwd)/cortx-cloud-helm-pkg/cortx-configmap/auto-gen-${node_name_list[i]}
done

# Default path to CORTX configmap
cfgmap_path="./cortx-cloud-helm-pkg/cortx-configmap"

# Create node template folder
node_info_folder="$cfgmap_path/node-info"
mkdir -p $node_info_folder

# Create storage template folder
storage_info_folder="$cfgmap_path/storage-info"
mkdir -p $storage_info_folder
storage_info_temp_folder="$storage_info_folder/temp_folder"
mkdir -p $storage_info_temp_folder

# Create auto-gen config folder
auto_gen_path="$cfgmap_path/auto-gen-cfgmap"
mkdir -p $auto_gen_path

# Generate config files
for i in "${!node_name_list[@]}"; do
    new_gen_file="$auto_gen_path/config.yaml"
    cp "$cfgmap_path/templates/config-template.yaml" $new_gen_file
    # 3rd party endpoints
    kafka_endpoint="kafka.default.svc.cluster.local"
    openldap_endpoint="openldap-svc.default.svc.cluster.local"
    consul_endpoint="consul-server.default.svc.cluster.local"
    openldap_servers=""
    while IFS= read -r line; do
        IFS=" " read -r -a my_array <<< "$line"
        if [ "$openldap_servers" == "" ]
        then
            openldap_servers="- ""${my_array[1]}"".""$openldap_endpoint"
        else
            openldap_servers="$openldap_servers"$'\n'"- ""${my_array[1]}"".""$openldap_endpoint"
        fi
    done <<< "$(kubectl get pods -A | grep 'openldap-')"

    ./parse_scripts/subst.sh $new_gen_file "cortx.external.kafka.endpoints" $kafka_endpoint
    ./parse_scripts/subst.sh $new_gen_file "cortx.external.openldap.endpoints" $openldap_endpoint
    ./parse_scripts/yaml_insert_block.sh $new_gen_file "$openldap_servers" 8 "cortx.external.openldap.servers"
    ./parse_scripts/subst.sh $new_gen_file "cortx.external.consul.endpoints" $consul_endpoint
    ./parse_scripts/subst.sh $new_gen_file "cortx.io.svc" "cortx-io-svc"
    ./parse_scripts/subst.sh $new_gen_file "cortx.num_s3_inst" $(extractBlock 'solution.common.s3.num_inst')
    ./parse_scripts/subst.sh $new_gen_file "cortx.num_motr_inst" $(extractBlock 'solution.common.motr.num_client_inst')
    ./parse_scripts/subst.sh $new_gen_file "cortx.common.storage.local" $(extractBlock 'solution.common.storage.local')
    ./parse_scripts/subst.sh $new_gen_file "cortx.common.storage.shared" $(extractBlock 'solution.common.storage.shared')
    ./parse_scripts/subst.sh $new_gen_file "cortx.common.storage.log" $(extractBlock 'solution.common.storage.log')
    # Generate node file with type storage_node in "node-info" folder
    new_gen_file="$node_info_folder/cluster-storage-node-${node_name_list[$i]}.yaml"
    cp "$cfgmap_path/templates/cluster-node-template.yaml" $new_gen_file
    ./parse_scripts/subst.sh $new_gen_file "cortx.node.name" "cortx-data-headless-svc-${node_name_list[$i]}"
    uuid_str=$(UUID=$(uuidgen); echo ${UUID//-/})
    ./parse_scripts/subst.sh $new_gen_file "cortx.pod.uuid" "$uuid_str"
    ./parse_scripts/subst.sh $new_gen_file "cortx.svc.name" "cortx-data-headless-svc-${node_name_list[$i]}"
    ./parse_scripts/subst.sh $new_gen_file "cortx.node.type" "storage_node"
    
    # Create data machine id file
    auto_gen_node_path="$cfgmap_path/auto-gen-${node_name_list[$i]}/data"
    mkdir -p $auto_gen_node_path
    echo $uuid_str > $auto_gen_node_path/id
done

# Generate node file with type control_node in "node-info" folder
new_gen_file="$node_info_folder/cluster-control-node.yaml"
cp "$cfgmap_path/templates/cluster-node-template.yaml" $new_gen_file
./parse_scripts/subst.sh $new_gen_file "cortx.node.name" "cortx-control-headless-svc"
uuid_str=$(UUID=$(uuidgen); echo ${UUID//-/})
./parse_scripts/subst.sh $new_gen_file "cortx.pod.uuid" "$uuid_str"
./parse_scripts/subst.sh $new_gen_file "cortx.svc.name" "cortx-control-headless-svc"
./parse_scripts/subst.sh $new_gen_file "cortx.node.type" "control_node"

# Create control machine id file
auto_gen_control_path="$cfgmap_path/auto-gen-control"
mkdir -p $auto_gen_control_path
echo $uuid_str > $auto_gen_control_path/id        

# Copy cluster template
cp "$cfgmap_path/templates/cluster-template.yaml" "$auto_gen_path/cluster.yaml"

# Insert all node info stored in "node-info" folder into "cluster.yaml" file
cluster_uuid=$(UUID=$(uuidgen); echo ${UUID//-/})
extract_output=""
node_info_folder="$cfgmap_path/node-info"
./parse_scripts/subst.sh "$auto_gen_path/cluster.yaml" "cortx.cluster.id" $cluster_uuid

# Populate the storage set info
storage_set_name=$(parseSolution 'solution.common.storage_sets.name')
storage_set_name=$(echo $storage_set_name | cut -f2 -d'>')
storage_set_dur_sns=$(parseSolution 'solution.common.storage_sets.durability.sns')
storage_set_dur_sns=$(echo $storage_set_dur_sns | cut -f2 -d'>')
storage_set_dur_dix=$(parseSolution 'solution.common.storage_sets.durability.dix')
storage_set_dur_dix=$(echo $storage_set_dur_dix | cut -f2 -d'>')

./parse_scripts/subst.sh "$auto_gen_path/cluster.yaml" "cluster.storage_sets.name" $storage_set_name
./parse_scripts/subst.sh "$auto_gen_path/cluster.yaml" "cluster.storage_sets.durability.sns" $storage_set_dur_sns
./parse_scripts/subst.sh "$auto_gen_path/cluster.yaml" "cluster.storage_sets.durability.dix" $storage_set_dur_dix

for fname in ./cortx-cloud-helm-pkg/cortx-configmap/node-info/*; do
    if [ "$extract_output" == "" ]
    then
        extract_output="$(./parse_scripts/yaml_extract_block.sh $fname)"
    else
        extract_output="$extract_output"$'\n'"$(./parse_scripts/yaml_extract_block.sh $fname)"
    fi
done
./parse_scripts/yaml_insert_block.sh "$auto_gen_path/cluster.yaml" "$extract_output" 4 "cluster.storage_sets.nodes"


cvg_output=$(parseSolution 'solution.storage.cvg*.name')
IFS=';' read -r -a cvg_var_val_array <<< "$cvg_output"
# Build CVG index list (ex: [cvg1, cvg2, cvg3])
cvg_index_list=[]
count=0
for cvg_var_val_element in "${cvg_var_val_array[@]}"; do
    cvg_name=$(echo $cvg_var_val_element | cut -f2 -d'>')
    cvg_filter=$(echo $cvg_var_val_element | cut -f1 -d'>')
    cvg_index=$(echo $cvg_filter | cut -f3 -d'.')    
    cvg_index_list[$count]=$cvg_index
    count=$((count+1))
done

for cvg_index in "${cvg_index_list[@]}"; do
    storage_cvg_data_auto_gen_file="$storage_info_temp_folder/cluster-storage-$cvg_index-data.yaml"
    filter="solution.storage.$cvg_index.devices.data.d*.device"
    cvg_devices_output=$(parseSolution $filter)
    IFS=';' read -r -a cvg_dev_var_val_array <<< "$cvg_devices_output"
    for cvg_dev_var_val_element in "${cvg_dev_var_val_array[@]}"; do
        cvg_dev=$(echo $cvg_dev_var_val_element | cut -f2 -d'>')
        echo "- $cvg_dev" >> $storage_cvg_data_auto_gen_file
    done
    
    # Substitute all the variables in the template file
    storage_info_gen_file="$storage_info_folder/cluster-storage-$cvg_index-info.yaml"
    cp "$cfgmap_path/templates/cluster-storage-template.yaml" $storage_info_gen_file

    cvg_name_output=$(parseSolution "solution.storage.$cvg_index.name")
    cvg_name=$(echo $cvg_name_output | cut -f2 -d'>')
    ./parse_scripts/subst.sh $storage_info_gen_file "cortx.storage.name" $cvg_name

    cvg_type_output=$(parseSolution "solution.storage.$cvg_index.type")
    cvg_type=$(echo $cvg_type_output | cut -f2 -d'>')
    ./parse_scripts/subst.sh $storage_info_gen_file "cortx.storage.type" $cvg_type
    
    cvg_metadata_output=$(parseSolution "solution.storage.$cvg_index.devices.metadata.device")
    cvg_metadata=$(echo $cvg_metadata_output | cut -f2 -d'>')
    ./parse_scripts/subst.sh $storage_info_gen_file "cortx.metadata.dev_partition" $cvg_metadata
    
    extract_output="$(./parse_scripts/yaml_extract_block.sh $storage_cvg_data_auto_gen_file)"
    ./parse_scripts/yaml_insert_block.sh "$storage_info_gen_file" "$extract_output" 4 "cortx.data.dev_partition"
done
# Remove "storage-info/temp_folder"
rm -rf $storage_info_temp_folder
# Insert data device info stored in 'storage-info' folder into 'cluster-storage-node.yaml' file
extract_output=""
for fname in ./cortx-cloud-helm-pkg/cortx-configmap/storage-info/*; do
    if [ "$extract_output" == "" ]
    then
        extract_output="$(./parse_scripts/yaml_extract_block.sh $fname)"
    else
        extract_output="$extract_output"$'\n'"$(./parse_scripts/yaml_extract_block.sh $fname)"
    fi
done
./parse_scripts/yaml_insert_block.sh "$auto_gen_path/cluster.yaml" "$extract_output" 4 "cluster.storage_list"

# Delete node-info folder
node_info_folder="$cfgmap_path/node-info"
rm -rf $node_info_folder

# Create config maps
auto_gen_path="$cfgmap_path/auto-gen-cfgmap"
kubectl create configmap "cortx-cfgmap" \
    --namespace=$namespace \
    --from-file=$auto_gen_path

# Create data machine ID config maps
for i in "${!node_name_list[@]}"; do
    auto_gen_cfgmap_path="$cfgmap_path/auto-gen-${node_name_list[i]}/data"
    kubectl create configmap "cortx-data-machine-id-cfgmap-${node_name_list[i]}" \
        --namespace=$namespace \
        --from-file=$auto_gen_cfgmap_path
done

# Create control machine ID config maps
auto_gen_control_path="$cfgmap_path/auto-gen-control"
kubectl create configmap "cortx-control-machine-id-cfgmap" \
    --namespace=$namespace \
    --from-file=$auto_gen_control_path

# Create SSL cert config map
ssl_cert_path="$cfgmap_path/ssl-cert"
kubectl create configmap "cortx-ssl-cert-cfgmap" \
    --namespace=$namespace \
    --from-file=$ssl_cert_path

printf "########################################################\n"
printf "# Deploy CORTX Secrets                                  \n"
printf "########################################################\n"
# Parse secret from the solution file and create all secret yaml files
# in the "auto-gen-secret" folder
secret_auto_gen_path="$cfgmap_path/auto-gen-secret"
mkdir -p $secret_auto_gen_path
output=$(./parse_scripts/parse_yaml.sh solution.yaml "solution.secrets.name")
IFS=';' read -r -a parsed_secret_name_array <<< "$output"
for secret_name in "${parsed_secret_name_array[@]}"
do
    secret_fname=$(echo $secret_name | cut -f2 -d'>')
    yaml_content_path=$(echo $secret_name | cut -f1 -d'>')
    yaml_content_path=${yaml_content_path/.name/".content"}
    secrets="$(./parse_scripts/yaml_extract_block.sh solution.yaml $yaml_content_path 2)"

    new_secret_gen_file="$secret_auto_gen_path/$secret_fname.yaml"
    cp "$cfgmap_path/templates/secret-template.yaml" $new_secret_gen_file
    ./parse_scripts/subst.sh $new_secret_gen_file "secret.name" "$secret_fname"
    ./parse_scripts/subst.sh $new_secret_gen_file "secret.content" "$secrets"
    
    kubectl create -f $new_secret_gen_file --namespace=$namespace

    control_prov_secret_path="./cortx-cloud-helm-pkg/cortx-control-provisioner/secret-info.txt"
    control_secret_path="./cortx-cloud-helm-pkg/cortx-control/secret-info.txt"
    data_prov_secret_path="./cortx-cloud-helm-pkg/cortx-data-provisioner/secret-info.txt"
    data_secret_path="./cortx-cloud-helm-pkg/cortx-data/secret-info.txt"
    if [[ -s $control_prov_secret_path ]]; then
        printf "\n" >> $control_prov_secret_path
    fi
    if [[ -s $control_secret_path ]]; then
        printf "\n" >> $control_secret_path
    fi
    if [[ -s $data_prov_secret_path ]]; then
        printf "\n" >> $data_prov_secret_path
    fi
    if [[ -s $data_secret_path ]]; then
        printf "\n" >> $data_secret_path
    fi
    printf "$secret_fname" >> $control_prov_secret_path
    printf "$secret_fname" >> $control_secret_path
    printf "$secret_fname" >> $data_prov_secret_path
    printf "$secret_fname" >> $data_secret_path
done


printf "########################################################\n"
printf "# Deploy CORTX Control Provisioner                      \n"
printf "########################################################\n"
cortxcontrolprov_image=$(parseSolution 'solution.images.cortxcontrolprov')
cortxcontrolprov_image=$(echo $cortxcontrolprov_image | cut -f2 -d'>')

helm install "cortx-control-provisioner" cortx-cloud-helm-pkg/cortx-control-provisioner \
    --set cortxcontrolprov.name="cortx-control-provisioner-pod" \
    --set cortxcontrolprov.image=$cortxcontrolprov_image \
    --set cortxcontrolprov.service.clusterip.name="cortx-control-clusterip-svc" \
    --set cortxcontrolprov.service.headless.name="cortx-control-headless-svc" \
    --set cortxgluster.pv.name=$gluster_pv_name \
    --set cortxgluster.pv.mountpath=$shared_storage \
    --set cortxgluster.pvc.name=$gluster_pvc_name \
    --set cortxcontrolprov.cfgmap.name="cortx-cfgmap" \
    --set cortxcontrolprov.cfgmap.volmountname="config001" \
    --set cortxcontrolprov.cfgmap.mountpath="/etc/cortx/solution" \
    --set cortxcontrolprov.sslcfgmap.name="cortx-ssl-cert-cfgmap" \
    --set cortxcontrolprov.sslcfgmap.volmountname="ssl-config001" \
    --set cortxcontrolprov.sslcfgmap.mountpath="/etc/cortx/solution/ssl" \
    --set cortxcontrolprov.machineid.name="cortx-control-machine-id-cfgmap" \
    --set cortxcontrolprov.localpathpvc.name="cortx-control-fs-local-pvc" \
    --set cortxcontrolprov.localpathpvc.mountpath="$local_storage" \
    --set cortxcontrolprov.localpathpvc.requeststoragesize="1Gi" \
    --set cortxcontrolprov.secretinfo="secret-info.txt" \
    --set namespace=$namespace

# Check if all Cortx Control Provisioner is up and running
node_count=1
printf "\nWait for CORTX Control Provisioner to complete"
while true; do
    count=0
    while IFS= read -r line; do
        IFS=" " read -r -a pod_status <<< "$line"
        if [[ "${pod_status[2]}" != "Completed" ]]; then
            break
        fi
        count=$((count+1))
    done <<< "$(kubectl get pods --namespace=$namespace | grep 'cortx-control-provisioner-pod')"

    if [[ $node_count -eq $count ]]; then
        break
    else
        printf "."
    fi
    sleep 1s
done
printf "\n\n"

# Delete CORTX Provisioner Services
kubectl delete service "cortx-control-clusterip-svc" --namespace=$namespace
kubectl delete service "cortx-control-headless-svc" --namespace=$namespace

printf "########################################################\n"
printf "# Deploy CORTX Data Provisioner                              \n"
printf "########################################################\n"
cortxdataprov_image=$(parseSolution 'solution.images.cortxdataprov')
cortxdataprov_image=$(echo $cortxdataprov_image | cut -f2 -d'>')

for i in "${!node_selector_list[@]}"; do
    node_name=${node_name_list[i]}
    node_selector=${node_selector_list[i]}
    helm install "cortx-data-provisioner-$node_name" cortx-cloud-helm-pkg/cortx-data-provisioner \
        --set cortxdataprov.name="cortx-data-provisioner-pod-$node_name" \
        --set cortxdataprov.image=$cortxdataprov_image \
        --set cortxdataprov.nodename=$node_name \
        --set cortxdataprov.mountblkinfo="mnt-blk-info-$node_name.txt" \
        --set cortxdataprov.service.clusterip.name="cortx-data-clusterip-svc-$node_name" \
        --set cortxdataprov.service.headless.name="cortx-data-headless-svc-$node_name" \
        --set cortxgluster.pv.name=$gluster_pv_name \
        --set cortxgluster.pv.mountpath=$shared_storage \
        --set cortxgluster.pvc.name=$gluster_pvc_name \
        --set cortxdataprov.cfgmap.name="cortx-cfgmap" \
        --set cortxdataprov.cfgmap.volmountname="config001-$node_name" \
        --set cortxdataprov.cfgmap.mountpath="/etc/cortx/solution" \
        --set cortxdataprov.sslcfgmap.name="cortx-ssl-cert-cfgmap" \
        --set cortxdataprov.sslcfgmap.volmountname="ssl-config001" \
        --set cortxdataprov.sslcfgmap.mountpath="/etc/cortx/solution/ssl" \
        --set cortxdataprov.machineid.name="cortx-data-machine-id-cfgmap-$node_name" \
        --set cortxdataprov.localpathpvc.name="cortx-data-fs-local-pvc-$node_name" \
        --set cortxdataprov.localpathpvc.mountpath="$local_storage" \
        --set cortxdataprov.localpathpvc.requeststoragesize="1Gi" \
        --set cortxdataprov.secretinfo="secret-info.txt" \
        --set namespace=$namespace
done

# Check if all OpenLDAP are up and running
node_count="${#node_selector_list[@]}"

printf "\nWait for CORTX Data Provisioner to complete"
while true; do
    count=0
    while IFS= read -r line; do
        IFS=" " read -r -a pod_status <<< "$line"
        if [[ "${pod_status[2]}" != "Completed" ]]; then
            break
        fi
        count=$((count+1))
    done <<< "$(kubectl get pods --namespace=$namespace | grep 'cortx-data-provisioner-pod-')"

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
    kubectl delete service "cortx-data-headless-svc-$node_name" --namespace=$namespace
done

printf "########################################################\n"
printf "# Deploy CORTX Control                                  \n"
printf "########################################################\n"
cortxcontrol_image=$(parseSolution 'solution.images.cortxcontrol')
cortxcontrol_image=$(echo $cortxcontrol_image | cut -f2 -d'>')

num_nodes=1
# This local path pvc has to match with the one created by CORTX Control Provisioner
helm install "cortx-control" cortx-cloud-helm-pkg/cortx-control \
    --set cortxcontrol.name="cortx-control-pod" \
    --set cortxcontrol.image=$cortxcontrol_image \
    --set cortxcontrol.service.clusterip.name="cortx-control-clusterip-svc" \
    --set cortxcontrol.service.headless.name="cortx-control-headless-svc" \
    --set cortxcontrol.nodeport.name="cortx-control-nodeport-svc" \
    --set cortxcontrol.cfgmap.mountpath="/etc/cortx/solution" \
    --set cortxcontrol.cfgmap.name="cortx-cfgmap" \
    --set cortxcontrol.cfgmap.volmountname="config001" \
    --set cortxcontrol.sslcfgmap.name="cortx-ssl-cert-cfgmap" \
    --set cortxcontrol.sslcfgmap.volmountname="ssl-config001" \
    --set cortxcontrol.sslcfgmap.mountpath="/etc/cortx/solution/ssl" \
    --set cortxcontrol.machineid.name="cortx-control-machine-id-cfgmap" \
    --set cortxcontrol.localpathpvc.name="cortx-control-fs-local-pvc" \
    --set cortxcontrol.localpathpvc.mountpath="$local_storage" \
    --set cortxcontrol.secretinfo="secret-info.txt" \
    --set cortxgluster.pv.name="gluster-default-name" \
    --set cortxgluster.pv.mountpath=$shared_storage \
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
printf "# Deploy CORTX Data                                     \n"
printf "########################################################\n"
cortxdata_image=$(parseSolution 'solution.images.cortxdata')
cortxdata_image=$(echo $cortxdata_image | cut -f2 -d'>')

num_nodes=0
for i in "${!node_selector_list[@]}"; do
    num_nodes=$((num_nodes+1))
    node_name=${node_name_list[i]}
    node_selector=${node_selector_list[i]}
    helm install "cortx-data-$node_name" cortx-cloud-helm-pkg/cortx-data \
        --set cortxdata.name="cortx-data-pod-$node_name" \
        --set cortxdata.image=$cortxdata_image \
        --set cortxdata.nodename=$node_name \
        --set cortxdata.mountblkinfo="mnt-blk-info-$node_name.txt" \
        --set cortxdata.service.clusterip.name="cortx-data-clusterip-svc-$node_name" \
        --set cortxdata.service.headless.name="cortx-data-headless-svc-$node_name" \
        --set cortxdata.service.loadbal.name="cortx-data-loadbal-svc-$node_name" \
        --set cortxgluster.pv.name=$gluster_pv_name \
        --set cortxgluster.pv.mountpath=$shared_storage \
        --set cortxgluster.pvc.name=$gluster_pvc_name \
        --set cortxdata.cfgmap.name="cortx-cfgmap" \
        --set cortxdata.cfgmap.volmountname="config001-$node_name" \
        --set cortxdata.cfgmap.mountpath="/etc/cortx/solution" \
        --set cortxdata.sslcfgmap.name="cortx-ssl-cert-cfgmap" \
        --set cortxdata.sslcfgmap.volmountname="ssl-config001" \
        --set cortxdata.sslcfgmap.mountpath="/etc/cortx/solution/ssl" \
        --set cortxdata.machineid.name="cortx-data-machine-id-cfgmap-$node_name" \
        --set cortxdata.localpathpvc.name="cortx-data-fs-local-pvc-$node_name" \
        --set cortxdata.localpathpvc.mountpath="$local_storage" \
        --set cortxdata.motr.numclientinst=$(extractBlock 'solution.common.motr.num_client_inst') \
        --set cortxdata.motr.numiosinst=${#cvg_index_list[@]} \
        --set cortxdata.motr.startportnum=$(extractBlock 'solution.common.motr.start_port_num') \
        --set cortxdata.s3.numinst=$(extractBlock 'solution.common.s3.num_inst') \
        --set cortxdata.s3.startportnum=$(extractBlock 'solution.common.s3.start_port_num') \
        --set cortxdata.secretinfo="secret-info.txt" \
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
printf "# Deploy Services                                       \n"
printf "########################################################\n"
kubectl apply -f services/cortx-io-svc.yaml --namespace=$namespace

cortx_io_svc_ingress=$(parseSolution 'solution.common.cortx_io_svc_ingress')
cortx_io_svc_ingress=$(echo $cortx_io_svc_ingress | cut -f2 -d'>')
if [ "$cortx_io_svc_ingress" == "true" ]
then
    kubectl apply -f services/cortx-io-svc-ingress.yaml --namespace=$namespace
fi

printf "########################################################\n"
printf "# Delete CORTX Data provisioner                         \n"
printf "########################################################\n"
while IFS= read -r line; do
    IFS=" " read -r -a pod_status <<< "$line"
    kubectl delete pod "${pod_status[0]}" --namespace=$namespace
    count=$((count+1))
done <<< "$(kubectl get pods --namespace=$namespace | grep 'cortx-data-provisioner-pod-')"

printf "########################################################\n"
printf "# Delete CORTX Control provisioner                      \n"
printf "########################################################\n"
kubectl delete pod cortx-control-provisioner-pod --namespace=$namespace

#################################################################
# Delete files that contain disk partitions on the worker nodes
# and the node info
#################################################################
find $(pwd)/cortx-cloud-3rd-party-pkg/openldap -name "node-list-info*" -delete
find $(pwd)/cortx-cloud-helm-pkg/cortx-data-provisioner -name "mnt-blk-*" -delete
find $(pwd)/cortx-cloud-helm-pkg/cortx-data -name "mnt-blk-*" -delete
find $(pwd)/cortx-cloud-helm-pkg/cortx-control-provisioner -name "secret-*" -delete
find $(pwd)/cortx-cloud-helm-pkg/cortx-control -name "secret-*" -delete
find $(pwd)/cortx-cloud-helm-pkg/cortx-data-provisioner -name "secret-*" -delete
find $(pwd)/cortx-cloud-helm-pkg/cortx-data -name "secret-*" -delete

rm -rf "$cfgmap_path/auto-gen-secret"
