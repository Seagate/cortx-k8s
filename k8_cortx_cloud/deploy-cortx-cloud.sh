#!/bin/bash

solution_yaml=${1:-'solution.yaml'}
storage_class='local-path'

##TODO Extract from solution.yaml ?
serviceAccountName=cortx-sa

# Check if the file exists
if [ ! -f $solution_yaml ]
then
    echo "ERROR: $solution_yaml does not exist"
    exit 1
fi

# Validate the "solution.yaml" file against the "solution_check.yaml" file
while IFS= read -r line; do
    echo "$line"
    if [[ "$line" != *"Validate solution file result"* ]]; then
        continue
    fi
    if [[ "$line" == *"failed"* ]]; then
        exit 1
    fi
done <<< "$(./solution_validation_scripts/solution-validation.sh $solution_yaml)"

# Delete old "node-list-info.txt" file
find $(pwd)/cortx-cloud-3rd-party-pkg/openldap -name "node-list-info*" -delete

max_openldap_inst=3 # Default max openldap instances
max_consul_inst=3
max_kafka_inst=3
num_openldap_replicas=0 # Default the number of actual openldap instances
num_worker_nodes=0
not_ready_node_list=[]
not_ready_node_count=0
# Create a file consist of a list of node info and up to 'max_openldap_inst'
# number of nodes. This file is used by OpenLDAP helm chart and will be deleted
# at the end of this script.
while IFS= read -r line; do
    IFS=" " read -r -a my_array <<< "$line"
    node_name="${my_array[0]}"
    node_status="${my_array[1]}"
    if [[ "$node_status" == "NotReady" ]]; then
        not_ready_node_list[$not_ready_node_count]="$node_name"
        not_ready_node_count=$((not_ready_node_count+1))
    fi

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

done <<< "$(kubectl get nodes --no-headers)"
printf "Number of worker nodes detected: $num_worker_nodes\n"


# Check for nodes listed in the solution file are in "Ready" state. If not, ask
# the users whether they want to continue to deploy or exit early
exit_early=false
if [ $not_ready_node_count -gt 0 ]; then
    echo "Number of 'NotReady' worker nodes detected in the cluster: $not_ready_node_count"
    echo "List of 'NotReady' worker nodes:"
    for not_ready_node in "${not_ready_node_list[@]}"; do
        echo "- $not_ready_node"
    done

    printf "\nContinue CORTX Cloud deployment could lead to unexpeted results.\n"
    read -p "Do you want to continue (y/n, yes/no)? " reply
    if [[ "$reply" =~ ^(y|Y)*.(es)$ || "$reply" =~ ^(y|Y)$ ]]; then
        exit_early=false
    elif [[ "$reply" =~ ^(n|N)*.(o)$ || "$reply" =~ ^(n|N)$ ]]; then
        exit_early=true
    else
        echo "Invalid response."
        exit_early=true
    fi
fi

if [[ "$exit_early" = true ]]; then
    echo "Exit script early."
    exit 1
fi

function parseSolution()
{
    echo "$(./parse_scripts/parse_yaml.sh $solution_yaml $1)"
}

function extractBlock()
{
    echo "$(./parse_scripts/yaml_extract_block.sh $solution_yaml $1)"
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
# Validate the solution file. Check that nodes listed in the solution file
# aren't tainted and allow scheduling.
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
# Print a list of tainted nodes and nodes that don't exist in the cluster
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

# Delete disk & node info files from folders: cortx-data-blk-data, cortx-data
find $(pwd)/cortx-cloud-helm-pkg/cortx-data-blk-data -name "mnt-blk-*" -delete
find $(pwd)/cortx-cloud-helm-pkg/cortx-data-blk-data -name "node-list-*" -delete
find $(pwd)/cortx-cloud-helm-pkg/cortx-data -name "mnt-blk-*" -delete
find $(pwd)/cortx-cloud-helm-pkg/cortx-data -name "node-list-*" -delete

# Create files consist of drives per node and files consist of drive sizes.
# These files are used by the helm charts to deploy cortx data. These file
# will be deleted at the end of this script.
node_name_list=[] # short version. Ex: ssc-vm-g3-rhev4-1490
node_selector_list=[] # long version. Ex: ssc-vm-g3-rhev4-1490.colo.seagate.com
count=0

mnt_blk_info_fname="mnt-blk-info.txt"
node_list_info_fname="node-list-info.txt"
cortx_blk_data_mnt_info_path=$(pwd)/cortx-cloud-helm-pkg/cortx-data-blk-data/$mnt_blk_info_fname
cortx_blk_data_node_list_info_path=$(pwd)/cortx-cloud-helm-pkg/cortx-data-blk-data/$node_list_info_fname

count=0
for var_val_element in "${parsed_var_val_array[@]}"
do
    node_name=$(echo $var_val_element | cut -f2 -d'>')
    node_selector_list[count]=$node_name
    shorter_node_name=$(echo $node_name | cut -f1 -d'.')
    node_name_list[count]=$shorter_node_name

    # Get the node var from the tuple
    node_info_str="$count $node_name"
    if [[ -s $cortx_blk_data_node_list_info_path ]]; then
        printf "\n" >> $cortx_blk_data_node_list_info_path
    fi
    printf "$node_info_str" >> $cortx_blk_data_node_list_info_path

    count=$((count+1))
done

# Copy cluster node info file from CORTX local block helm to CORTX data
cp $cortx_blk_data_node_list_info_path $(pwd)/cortx-cloud-helm-pkg/cortx-data

# Get the devices from the solution
filter="solution.storage.cvg*.devices*.device"
parsed_dev_output=$(parseSolution $filter)
IFS=';' read -r -a parsed_dev_array <<< "$parsed_dev_output"

# Get the sizes from the solution
filter="solution.storage.cvg*.devices*.size"
parsed_size_output=$(parseSolution $filter)
IFS=';' read -r -a parsed_size_array <<< "$parsed_size_output"

# Write disk info (device name and size) to files (for cortx local blk storage and cortx data)
for index in "${!parsed_dev_array[@]}"
do
    device=$(echo ${parsed_dev_array[$index]} | cut -f2 -d'>')
    size=$(echo ${parsed_size_array[$index]} | cut -f2 -d'>')
    mnt_blk_info="$device $size"

    if [[ -s $cortx_blk_data_mnt_info_path ]]; then
        printf "\n" >> $cortx_blk_data_mnt_info_path
    fi
    printf "$mnt_blk_info" >> $cortx_blk_data_mnt_info_path
done

# Copy device info file from CORTX local block helm to CORTX data
cp $cortx_blk_data_mnt_info_path $(pwd)/cortx-cloud-helm-pkg/cortx-data

# Create CORTX namespace
if [[ "$namespace" != "default" ]]; then

    helm install "cortx-ns-$namespace" cortx-cloud-helm-pkg/cortx-platform \
        --set namespace.create="true" \
        --set namespace.name="$namespace"

fi

count=0
namespace_list=[]
namespace_index=0
while IFS= read -r line; do
    if [[ $count -eq 0 ]]; then
        count=$((count+1))
        continue
    fi
    IFS=" " read -r -a my_array <<< "$line"
    if [[ "${my_array[0]}" != *"kube-"* \
            && "${my_array[0]}" != "default" \
            && "${my_array[0]}" != "local-path-storage" ]]; then
        namespace_list[$namespace_index]=${my_array[0]}
        namespace_index=$((namespace_index+1))
    fi
    count=$((count+1))
done <<< "$(kubectl get namespaces)"

##########################################################
# Deploy CORTX k8s pre-reqs
##########################################################
function deployKubernetesPrereqs()
{

    ## PodSecurityPolicies are Cluster-scoped, so Helm doesn't handle it smoothly
    ## in the same chart as Namespace-scoped objects.
    podSecurityPolicyName="cortx-baseline"
    createPodSecurityPolicy="true"
    output=$(kubectl get psp --no-headers $podSecurityPolicyName 2>/dev/null | wc -l)
    if [[ "$output" == "1" ]]; then
        createPodSecurityPolicy="false"
    fi

    helm install "cortx-platform" cortx-cloud-helm-pkg/cortx-platform \
        --set podSecurityPolicy.create="$createPodSecurityPolicy" \
        --set rbacRole.create="true" \
        --set rbacRoleBinding.create="true" \
        --set serviceAccount.create="true" \
        --set serviceAccount.name="$serviceAccountName" \
        --set networkPolicy.create="false" \
        --set namespace.name="$namespace" \
        --set services.hax.name=$(extractBlock 'solution.common.hax.service_name') \
        --set services.hax.port=$(extractBlock 'solution.common.hax.port_num') \
        -n $namespace

}


##########################################################
# Deploy CORTX 3rd party
##########################################################
function deployRancherProvisioner()
{
    # Add the HashiCorp Helm Repository:
    helm repo add hashicorp https://helm.releases.hashicorp.com
    helm repo update hashicorp
    if [[ $storage_class == "local-path" ]]
    then
        printf "Install Rancher Local Path Provisioner"
        rancher_prov_path="$(pwd)/cortx-cloud-3rd-party-pkg/auto-gen-rancher-provisioner"
        # Clean up auto gen Rancher Provisioner folder in case it still exists and was not
        # clearned up previously by the destroy-cortx-cloud script.
        rm -rf $rancher_prov_path
        mkdir -p $rancher_prov_path
        rancher_prov_file="$rancher_prov_path/local-path-storage.yaml"
        cp $(pwd)/cortx-cloud-3rd-party-pkg/templates/local-path-storage-template.yaml $rancher_prov_file
        image=$(parseSolution 'solution.images.rancher')
        image=$(echo $image | cut -f2 -d'>')
        ./parse_scripts/subst.sh $rancher_prov_file "rancher.image" $image
        ./parse_scripts/subst.sh $rancher_prov_file "rancher.host_path" "$storage_prov_path/local-path-provisioner"

        image=$(parseSolution 'solution.images.busybox')
        image=$(echo $image | cut -f2 -d'>')
        ./parse_scripts/subst.sh $rancher_prov_file "rancher.helperPod.image" $image

        kubectl create -f $rancher_prov_file
    fi
}

function deployConsul()
{
    printf "######################################################\n"
    printf "# Deploy Consul                                       \n"
    printf "######################################################\n"
    image=$(parseSolution 'solution.images.consul')
    image=$(echo $image | cut -f2 -d'>')

    helm install "consul" hashicorp/consul \
        --set global.name="consul" \
        --set global.image=$image \
        --set ui.enabled=false \
        --set server.storageClass=$storage_class \
        --set server.replicas=$num_consul_replicas \
        --set server.resources.requests.memory=$(extractBlock 'solution.common.resource_allocation.consul.server.resources.requests.memory') \
        --set server.resources.requests.cpu=$(extractBlock 'solution.common.resource_allocation.consul.server.resources.requests.cpu') \
        --set server.resources.limits.memory=$(extractBlock 'solution.common.resource_allocation.consul.server.resources.limits.memory') \
        --set server.resources.limits.cpu=$(extractBlock 'solution.common.resource_allocation.consul.server.resources.limits.cpu') \
        --set server.containerSecurityContext.server.allowPrivilegeEscalation=false \
        --set server.storage=$(extractBlock 'solution.common.resource_allocation.consul.server.storage') \
        --set client.resources.requests.memory=$(extractBlock 'solution.common.resource_allocation.consul.client.resources.requests.memory') \
        --set client.resources.requests.cpu=$(extractBlock 'solution.common.resource_allocation.consul.client.resources.requests.cpu') \
        --set client.resources.limits.memory=$(extractBlock 'solution.common.resource_allocation.consul.client.resources.limits.memory') \
        --set client.resources.limits.cpu=$(extractBlock 'solution.common.resource_allocation.consul.client.resources.limits.cpu') \
        --set client.containerSecurityContext.client.allowPrivilegeEscalation=false

    # Patch generated ServiceAccounts to prevent automounting ServiceAccount tokens
    kubectl patch serviceaccount/consul-client -p '{"automountServiceAccountToken":false}'
    kubectl patch serviceaccount/consul-server -p '{"automountServiceAccountToken":false}'

    # Rollout a new deployment version of Consul pods to use updated Service Account settings
    kubectl rollout restart statefulset/consul-server
    kubectl rollout restart daemonset/consul

    ##TODO This needs to be maintained during upgrades etc...

}

function deployOpenLDAP()
{
    printf "######################################################\n"
    printf "# Deploy openLDAP                                     \n"
    printf "######################################################\n"
    openldap_password=$(parseSolution 'solution.secrets.content.openldap_admin_secret')
    openldap_password=$(echo $openldap_password | cut -f2 -d'>')
    image=$(parseSolution 'solution.images.openldap')
    image=$(echo $image | cut -f2 -d'>')

    helm install "openldap" cortx-cloud-3rd-party-pkg/openldap \
        --set openldap.servicename="openldap-svc" \
        --set openldap.storageclass="openldap-local-storage" \
        --set openldap.storagesize="5Gi" \
        --set openldap.nodelistinfo="node-list-info.txt" \
        --set openldap.numreplicas=$num_openldap_replicas \
        --set openldap.password=$openldap_password \
        --set openldap.image=$image \
        --set openldap.resources.requests.memory=$(extractBlock 'solution.common.resource_allocation.openldap.resources.requests.memory') \
        --set openldap.resources.requests.cpu=$(extractBlock 'solution.common.resource_allocation.openldap.resources.requests.cpu') \
        --set openldap.resources.limits.memory=$(extractBlock 'solution.common.resource_allocation.openldap.resources.limits.memory') \
        --set openldap.resources.limits.cpu=$(extractBlock 'solution.common.resource_allocation.openldap.resources.limits.cpu')

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
    if [[ $num_openldap_replicas -gt 1 ]]; then
        ./cortx-cloud-3rd-party-pkg/openldap-replication/replication.sh --rootdnpassword $openldap_password
    fi
}

function splitDockerImage()
{
    IFS='/' read -ra image <<< "$1"
    IFS=':' read -ra tag_arr <<< "${image[2]}"
    registry="${image[0]}"
    repository="${image[1]}"
    repository="${repository}/${tag_arr[0]}"
    tag="${tag_arr[1]}"
}

function deployZookeeper()
{
    printf "######################################################\n"
    printf "# Deploy Zookeeper                                    \n"
    printf "######################################################\n"
    # Add Zookeeper and Kafka Repository
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo update bitnami

    image=$(parseSolution 'solution.images.zookeeper')
    image=$(echo $image | cut -f2 -d'>')
    splitDockerImage "${image}"
    printf "\nRegistry: ${registry}\nRepository: ${repository}\nTag: ${tag}\n"

    helm install zookeeper bitnami/zookeeper \
        --set image.tag=$tag \
        --set image.registry=$registry \
        --set image.repository=$repository \
        --set replicaCount=$num_kafka_replicas \
        --set auth.enabled=false \
        --set allowAnonymousLogin=true \
        --set global.storageClass=$storage_class \
        --set resources.requests.memory=$(extractBlock 'solution.common.resource_allocation.zookeeper.resources.requests.memory') \
        --set resources.requests.cpu=$(extractBlock 'solution.common.resource_allocation.zookeeper.resources.requests.cpu') \
        --set resources.limits.memory=$(extractBlock 'solution.common.resource_allocation.zookeeper.resources.limits.memory') \
        --set resources.limits.cpu=$(extractBlock 'solution.common.resource_allocation.zookeeper.resources.limits.cpu') \
        --set persistence.size=$(extractBlock 'solution.common.resource_allocation.zookeeper.storage_request_size') \
        --set persistence.dataLogDir.size=$(extractBlock 'solution.common.resource_allocation.zookeeper.data_log_dir_request_size') \
        --set serviceAccount.create=true \
        --set serviceAccount.name="cortx-zookeeper" \
        --set serviceAccount.automountServiceAccountToken=false \
        --set containerSecurityContext.allowPrivilegeEscalation=false \
        --wait

    printf "\nWait for Zookeeper to be ready before starting kafka"
    while true; do
        count=0
        while IFS= read -r line; do
            IFS=" " read -r -a pod_status <<< "$line"
            IFS="/" read -r -a ready_status <<< "${pod_status[2]}"
            if [[ "${pod_status[3]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
                count=$((count+1))
                break
            fi
        done <<< "$(kubectl get pods -A | grep 'zookeeper')"

        if [[ $count -eq 0 ]]; then
            break
        else
            printf "."
        fi
        sleep 1s
    done
    printf "\n\n"
    sleep 2s
}

function deployKafka()
{
    printf "######################################################\n"
    printf "# Deploy Kafka                                        \n"
    printf "######################################################\n"

    image=$(parseSolution 'solution.images.kafka')
    image=$(echo $image | cut -f2 -d'>')
    splitDockerImage "${image}"
    printf "\nRegistry: ${registry}\nRepository: ${repository}\nTag: ${tag}\n"

    _KAFKA_CFG_LOG_SEGMENT_DELETE_DELAY_MS=${KAFKA_CFG_LOG_SEGMENT_DELETE_DELAY_MS:=1000}
    _KAFKA_CFG_LOG_FLUSH_OFFSET_CHECKPOINT_INTERVAL_MS=${KAFKA_CFG_LOG_FLUSH_OFFSET_CHECKPOINT_INTERVAL_MS:=1000}
    _KAFKA_CFG_LOG_RETENTION_CHECK_INTERVAL_MS=${KAFKA_CFG_LOG_RETENTION_CHECK_INTERVAL_MS:=1000}

    TMP_KAFKA_ENVVARS_YAML=tmp-kafka.yaml
    echo "extraEnvVars:" > $TMP_KAFKA_ENVVARS_YAML
    echo "- name: KAFKA_CFG_LOG_SEGMENT_DELETE_DELAY_MS" >> $TMP_KAFKA_ENVVARS_YAML
    echo "  value: \"${_KAFKA_CFG_LOG_SEGMENT_DELETE_DELAY_MS}\"" >> $TMP_KAFKA_ENVVARS_YAML
    echo "- name: KAFKA_CFG_LOG_FLUSH_OFFSET_CHECKPOINT_INTERVAL_MS" >> $TMP_KAFKA_ENVVARS_YAML
    echo "  value: \"${_KAFKA_CFG_LOG_FLUSH_OFFSET_CHECKPOINT_INTERVAL_MS}\"" >> $TMP_KAFKA_ENVVARS_YAML
    echo "- name: KAFKA_CFG_LOG_RETENTION_CHECK_INTERVAL_MS" >> $TMP_KAFKA_ENVVARS_YAML
    echo "  value: \"${_KAFKA_CFG_LOG_RETENTION_CHECK_INTERVAL_MS}\"" >> $TMP_KAFKA_ENVVARS_YAML

    helm install kafka bitnami/kafka \
        --set zookeeper.enabled=false \
        --set image.tag=$tag \
        --set image.registry=$registry \
        --set image.repository=$repository \
        --set replicaCount=$num_kafka_replicas \
        --set externalZookeeper.servers=zookeeper.default.svc.cluster.local \
        --set global.storageClass=$storage_class \
        --set defaultReplicationFactor=$num_kafka_replicas \
        --set offsetsTopicReplicationFactor=$num_kafka_replicas \
        --set transactionStateLogReplicationFactor=$num_kafka_replicas \
        --set auth.enabled=false \
        --set allowAnonymousLogin=true \
        --set deleteTopicEnable=true \
        --set transactionStateLogMinIsr=2 \
        --set resources.requests.memory=$(extractBlock 'solution.common.resource_allocation.kafka.resources.requests.memory') \
        --set resources.requests.cpu=$(extractBlock 'solution.common.resource_allocation.kafka.resources.requests.cpu') \
        --set resources.limits.memory=$(extractBlock 'solution.common.resource_allocation.kafka.resources.limits.memory') \
        --set resources.limits.cpu=$(extractBlock 'solution.common.resource_allocation.kafka.resources.limits.cpu') \
        --set persistence.size=$(extractBlock 'solution.common.resource_allocation.kafka.storage_request_size') \
        --set logPersistence.size=$(extractBlock 'solution.common.resource_allocation.kafka.log_persistence_request_size') \
        --set serviceAccount.create=true \
        --set serviceAccount.name="cortx-kafka" \
        --set serviceAccount.automountServiceAccountToken=false \
        --set serviceAccount.automountServiceAccountToken=false \
        --set containerSecurityContext.enabled=true \
        --set containerSecurityContext.allowPrivilegeEscalation=false \
        --values $TMP_KAFKA_ENVVARS_YAML  \
        --wait

    rm $TMP_KAFKA_ENVVARS_YAML

    printf "\n\n"
}

function waitForThirdParty()
{
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
}

##########################################################
# CORTX cloud deploy functions
##########################################################
function deployCortxLocalBlockStorage()
{
    printf "######################################################\n"
    printf "# Deploy CORTX Local Block Storage                    \n"
    printf "######################################################\n"
    helm install "cortx-data-blk-data-$namespace" cortx-cloud-helm-pkg/cortx-data-blk-data \
        --set cortxblkdata.storageclass="cortx-local-blk-storage-$namespace" \
        --set cortxblkdata.nodelistinfo="node-list-info.txt" \
        --set cortxblkdata.mountblkinfo="mnt-blk-info.txt" \
        --set cortxblkdata.storage.volumemode="Block" \
        --set namespace=$namespace \
        -n $namespace
}

function deleteStaleAutoGenFolders()
{
    # Delete all stale auto gen folders
    rm -rf $(pwd)/cortx-cloud-helm-pkg/cortx-configmap/auto-gen-cfgmap-$namespace
    rm -rf $(pwd)/cortx-cloud-helm-pkg/cortx-configmap/auto-gen-control-$namespace
    rm -rf $(pwd)/cortx-cloud-helm-pkg/cortx-configmap/auto-gen-secret-$namespace
    rm -rf $(pwd)/cortx-cloud-helm-pkg/cortx-configmap/node-info-$namespace
    rm -rf $(pwd)/cortx-cloud-helm-pkg/cortx-configmap/storage-info-$namespace
    for i in "${!node_name_list[@]}"; do
        rm -rf $(pwd)/cortx-cloud-helm-pkg/cortx-configmap/auto-gen-${node_name_list[i]}-$namespace
    done
}

function generateMachineId()
{
    local uuid
    uuid="$(uuidgen --random)"
    echo "${uuid//-}"
}

function deployCortxConfigMap()
{
    printf "########################################################\n"
    printf "# Deploy CORTX Configmap                                \n"
    printf "########################################################\n"

    readonly auto_gen_control_path="${cfgmap_path}/auto-gen-control-${namespace}"
    readonly auto_gen_ha_path="${cfgmap_path}/auto-gen-ha-${namespace}"

    # Create Pod machine IDs
    for path in ${auto_gen_control_path} ${auto_gen_ha_path}; do
        mkdir -p "${path}"
        generateMachineId > "${path}/id"
    done
    for node in "${node_name_list[@]}"; do
        auto_gen_path="${cfgmap_path}/auto-gen-${node}-${namespace}"
        mkdir -p "${auto_gen_path}"/{data,server,client}

        generateMachineId > "${auto_gen_path}/data/id"
        generateMachineId > "${auto_gen_path}/server/id"
        ((num_motr_client > 0)) && generateMachineId > "${auto_gen_path}/client/id"
    done

    # This assigns to a global $tag variable
    splitDockerImage "$(parseSolution 'solution.images.cortxdata' | cut -f2 -d'>' || true)"

    helm_install_args=(
        --set externalKafka.enabled=true
        --set externalLdap.enabled=true
        --set externalConsul.enabled=true
        --set cortxHa.haxService.protocol="$(extractBlock 'solution.common.hax.protocol' || true)"
        --set cortxHa.haxService.name="$(extractBlock 'solution.common.hax.service_name' || true)"
        --set cortxHa.haxService.port="$(extractBlock 'solution.common.hax.port_num' || true)"
        --set cortxS3.instanceCount="$(extractBlock 'solution.common.s3.num_inst' || true)"
        --set cortxS3.maxStartTimeout="$(extractBlock 'solution.common.s3.max_start_timeout' || true)"
        --set cortxStoragePaths.local="${local_storage}"
        --set cortxStoragePaths.shared="${shared_storage}"
        --set cortxStoragePaths.log="${log_storage}"
        --set cortxStoragePaths.config="${local_storage}"
        --set cortxVersion="${tag}"
        --set cortxSetupSize="$(extractBlock 'solution.common.setup_size' || true)"
    )

    # Build OpenLDAP server values dynamically from running pods
    readonly openldap_endpoint="openldap-svc.default.svc.cluster.local"
    IFS=" " read -r -a pods <<< "$(kubectl get pods --all-namespaces --selector name=openldap-connect --output jsonpath='{.items[*].metadata.name}' || true)"
    for idx in "${!pods[@]}"; do
        helm_install_args+=(
            --set "externalLdap.servers[${idx}]=${pods[idx]}.${openldap_endpoint}"
        )
    done

    if ((num_motr_client > 0)); then
        for idx in "${!node_name_list[@]}"; do
            helm_install_args+=(
                --set "cortxMotr.clientEndpoints[${idx}]=tcp://cortx-client-headless-svc-${node_name_list[${idx}]}:21001"
            )
        done
    fi

    # Populate the cluster storage set
    storage_set_name=$(parseSolution 'solution.common.storage_sets.name' | cut -f2 -d'>' || true)
    storage_set_dur_sns=$(parseSolution 'solution.common.storage_sets.durability.sns' | cut -f2 -d'>' || true)
    storage_set_dur_dix=$(parseSolution 'solution.common.storage_sets.durability.dix' | cut -f2 -d'>' || true)

    helm_install_args+=(
        --set "clusterStorageSets.${storage_set_name}.durability.sns=${storage_set_dur_sns}"
        --set "clusterStorageSets.${storage_set_name}.durability.dix=${storage_set_dur_dix}"
        --set "clusterStorageSets.${storage_set_name}.controlUuid=$(< "${auto_gen_control_path}/id")"
        --set "clusterStorageSets.${storage_set_name}.haUuid=$(< "${auto_gen_ha_path}/id")"
    )
    for node in "${node_name_list[@]}"; do
        helm_install_args+=(
            --set "clusterStorageSets.${storage_set_name}.nodes.${node}.dataUuid=$(< "${cfgmap_path}/auto-gen-${node}-${namespace}/data/id")"
            --set "clusterStorageSets.${storage_set_name}.nodes.${node}.serverUuid=$(< "${cfgmap_path}/auto-gen-${node}-${namespace}/server/id")"
        )
        if ((num_motr_client > 0)); then
            helm_install_args+=(
                --set "clusterStorageSets.${storage_set_name}.nodes.${node}.clientUuid=$(< "${cfgmap_path}/auto-gen-${node}-${namespace}/client/id")"
            )
        fi
    done

    # Populate the cluster storage volumes
    for cvg_index in "${cvg_index_list[@]}"; do
        cvg_key="solution.storage.${cvg_index}"
        cvg_name="$(parseSolution "${cvg_key}.name" | cut -f2 -d'>' || true)"
        cvg_type="$(parseSolution "${cvg_key}.type" | cut -f2 -d'>' || true)"
        cvg_metadata_device=$(parseSolution "${cvg_key}.devices.metadata.device" | cut -f2 -d'>' || true)

        helm_install_args+=(
            --set "clusterStorageVolumes.${cvg_name}.type=${cvg_type}"
            --set "clusterStorageVolumes.${cvg_name}.metadataDevices[0]=${cvg_metadata_device}"
        )

        IFS=';' read -r -a cvg_dev_var_val_array <<< "$(parseSolution "solution.storage.${cvg_index}.devices.data.d*.device" || true)"
        for idx in "${!cvg_dev_var_val_array[@]}"; do
            cvg_dev=$(echo "${cvg_dev_var_val_array[idx]}" | cut -f2 -d'>')
            helm_install_args+=(
                --set "clusterStorageVolumes.${cvg_name}.dataDevices[${idx}]=${cvg_dev}"
            )
        done
    done

    helm install \
        "cortx-cfgmap-${namespace}" \
        cortx-cloud-helm-pkg/cortx-configmap \
        --set fullnameOverride="cortx-cfgmap-${namespace}" \
        "${helm_install_args[@]}"

    # Create node machine ID config maps
    for node in "${node_name_list[@]}"; do
        auto_gen_path="${cfgmap_path}/auto-gen-${node}-${namespace}"

        kubectl create configmap "cortx-data-machine-id-cfgmap-${node}-${namespace}" \
            --namespace="${namespace}" \
            --from-file="${auto_gen_path}/data"

        kubectl create configmap "cortx-server-machine-id-cfgmap-${node}-${namespace}" \
            --namespace="${namespace}" \
            --from-file="${auto_gen_path}/server"

        if ((num_motr_client > 0)); then
            # Create client machine ID config maps
            kubectl create configmap "cortx-client-machine-id-cfgmap-${node}-${namespace}" \
                --namespace="${namespace}" \
                --from-file="${auto_gen_path}/client"
        fi
    done

    # Create control machine ID config map
    kubectl create configmap "cortx-control-machine-id-cfgmap-${namespace}" \
        --namespace="${namespace}" \
        --from-file="${auto_gen_control_path}"

    # Create HA machine ID config map
    kubectl create configmap "cortx-ha-machine-id-cfgmap-${namespace}" \
        --namespace="${namespace}" \
        --from-file="${auto_gen_ha_path}"
}

function deployCortxSecrets()
{
    printf "########################################################\n"
    printf "# Deploy CORTX Secrets                                  \n"
    printf "########################################################\n"
    # Parse secret from the solution file and create all secret yaml files
    # in the "auto-gen-secret" folder
    secret_auto_gen_path="${cfgmap_path}/auto-gen-secret-${namespace}"
    mkdir -p "${secret_auto_gen_path}"
    secret_name=$(parseSolution "solution.secrets.name")
    secret_fname=$(echo "${secret_name}" | cut -f2 -d'>')
    yaml_content_path=$(echo "${secret_name}" | cut -f1 -d'>')
    yaml_content_path=${yaml_content_path/.name/".content"}
    secrets="$(./parse_scripts/yaml_extract_block.sh "${solution_yaml}" "${yaml_content_path}" 2)"

    new_secret_gen_file="${secret_auto_gen_path}/${secret_fname}.yaml"
    cp "${cfgmap_path}/other/secret-template.yaml" "${new_secret_gen_file}"
    ./parse_scripts/subst.sh "${new_secret_gen_file}" "secret.name" "${secret_fname}"
    ./parse_scripts/subst.sh "${new_secret_gen_file}" "secret.content" "${secrets}"

    kubectl_cmd_output=$(kubectl create -f "${new_secret_gen_file}" --namespace="${namespace}" 2>&1)

    if [[ "${kubectl_cmd_output}" == *"BadRequest"* ]]; then
        printf "Exit early. Create secret failed with error:\n%s\n" "${kubectl_cmd_output}"
        exit 1
    fi
    echo "${kubectl_cmd_output}"

    control_secret_path="./cortx-cloud-helm-pkg/cortx-control/secret-info.txt"
    data_secret_path="./cortx-cloud-helm-pkg/cortx-data/secret-info.txt"
    server_secret_path="./cortx-cloud-helm-pkg/cortx-server/secret-info.txt"
    ha_secret_path="./cortx-cloud-helm-pkg/cortx-ha/secret-info.txt"

    printf "%s" "${secret_fname}" > ${control_secret_path}
    printf "%s" "${secret_fname}" > ${data_secret_path}
    printf "%s" "${secret_fname}" > ${server_secret_path}
    printf "%s" "${secret_fname}" > ${ha_secret_path}

    if [[ $num_motr_client -gt 0 ]]; then
        client_secret_path="./cortx-cloud-helm-pkg/cortx-client/secret-info.txt"
        printf "%s" "${secret_fname}" > ${client_secret_path}
    fi
}

function silentKill()
{
    kill "$1"
    wait "$1" 2> /dev/null
}

function waitForAllDeploymentsAvailable()
{
    TIMEOUT=$1
    shift
    DEPL_STR=$1
    shift

    START=$SECONDS
    (while true; do sleep 1; echo -n "."; done)&
    DOTPID=$!
    trap "silentKill $DOTPID" 0

    # Initial wait
    FAIL=0
    kubectl wait --for=condition=available --timeout="$TIMEOUT" $@
    if [ $? -ne 0 ]; then
        # Secondary wait
        kubectl wait --for=condition=available --timeout="$TIMEOUT" $@
        if [ $? -ne 0 ]; then
            # Still timed out.  This is a failure
            FAIL=1
        fi
    fi

    silentKill $DOTPID
    trap - 0
    ELAPSED=$((SECONDS - START))
    echo
    if [ $FAIL -eq 0 ]; then
        echo "Deployment $DEPL_STR available after $ELAPSED seconds"
    else
        echo "Deployment $DEPL_STR timed out after $ELAPSED seconds"
    fi
    echo
    return $FAIL
}


function deployCortxControl()
{
    printf "########################################################\n"
    printf "# Deploy CORTX Control                                  \n"
    printf "########################################################\n"

    cortxcontrol_image=$(parseSolution 'solution.images.cortxcontrol')
    cortxcontrol_image=$(echo $cortxcontrol_image | cut -f2 -d'>')

    external_services_type=$(parseSolution 'solution.common.external_services.type')
    external_services_type=$(echo $external_services_type | cut -f2 -d'>')

    cortxcontrol_machineid=$(cat $cfgmap_path/auto-gen-control-$namespace/id)

    num_nodes=1
    helm install "cortx-control-$namespace" cortx-cloud-helm-pkg/cortx-control \
        --set cortxcontrol.name="cortx-control" \
        --set cortxcontrol.image=$cortxcontrol_image \
        --set cortxcontrol.service.loadbal.name="cortx-control-loadbal-svc" \
        --set cortxcontrol.service.loadbal.type="$external_services_type" \
        --set cortxcontrol.cfgmap.mountpath="/etc/cortx/solution" \
        --set cortxcontrol.cfgmap.name="cortx-cfgmap-$namespace" \
        --set cortxcontrol.cfgmap.volmountname="config001" \
        --set cortxcontrol.sslcfgmap.name="cortx-ssl-cert-cfgmap-$namespace" \
        --set cortxcontrol.sslcfgmap.volmountname="ssl-config001" \
        --set cortxcontrol.sslcfgmap.mountpath="/etc/cortx/solution/ssl" \
        --set cortxcontrol.machineid.value="$cortxcontrol_machineid" \
        --set cortxcontrol.localpathpvc.name="cortx-control-fs-local-pvc-$namespace" \
        --set cortxcontrol.localpathpvc.mountpath="$local_storage" \
        --set cortxcontrol.localpathpvc.requeststoragesize="1Gi" \
        --set cortxcontrol.secretinfo="secret-info.txt" \
        --set cortxcontrol.serviceaccountname="$serviceAccountName" \
        --set namespace=$namespace \
        -n $namespace


    printf "\nWait for CORTX Control to be ready"
    if ! waitForAllDeploymentsAvailable 300s "CORTX Control" deployment/cortx-control; then
        echo "Failed.  Exiting script."
        exit 1
    fi
    printf "\n\n"
}

function deployCortxData()
{
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

        cortxdata_machineid=$(cat $cfgmap_path/auto-gen-${node_name_list[$i]}-$namespace/data/id)

        helm install "cortx-data-$node_name-$namespace" cortx-cloud-helm-pkg/cortx-data \
            --set cortxdata.name="cortx-data-$node_name" \
            --set cortxdata.image=$cortxdata_image \
            --set cortxdata.nodeselector=$node_selector \
            --set cortxdata.mountblkinfo="mnt-blk-info.txt" \
            --set cortxdata.nodelistinfo="node-list-info.txt" \
            --set cortxdata.service.clusterip.name="cortx-data-clusterip-svc-$node_name" \
            --set cortxdata.service.headless.name="cortx-data-headless-svc-$node_name" \
            --set cortxdata.cfgmap.name="cortx-cfgmap-$namespace" \
            --set cortxdata.cfgmap.volmountname="config001-$node_name" \
            --set cortxdata.cfgmap.mountpath="/etc/cortx/solution" \
            --set cortxdata.sslcfgmap.name="cortx-ssl-cert-cfgmap-$namespace" \
            --set cortxdata.sslcfgmap.volmountname="ssl-config001" \
            --set cortxdata.sslcfgmap.mountpath="/etc/cortx/solution/ssl" \
            --set cortxdata.machineid.value="$cortxdata_machineid" \
            --set cortxdata.localpathpvc.name="cortx-data-fs-local-pvc-$node_name" \
            --set cortxdata.localpathpvc.mountpath="$local_storage" \
            --set cortxdata.localpathpvc.requeststoragesize="1Gi" \
            --set cortxdata.motr.numiosinst=${#cvg_index_list[@]} \
            --set cortxdata.motr.startportnum=$(extractBlock 'solution.common.motr.start_port_num') \
            --set cortxdata.hax.port=$(extractBlock 'solution.common.hax.port_num') \
            --set cortxdata.secretinfo="secret-info.txt" \
            --set cortxdata.serviceaccountname="$serviceAccountName" \
            --set namespace=$namespace \
            -n $namespace
    done

    # Wait for all cortx-data deployments to be ready
    printf "\nWait for CORTX Data to be ready"
    local deployments=()
    for i in "${!node_selector_list[@]}"; do
        deployments+=("deployment/cortx-data-${node_name_list[i]}")
    done
    if ! waitForAllDeploymentsAvailable 300s "CORTX Data" "${deployments[@]}"; then
        echo "Failed.  Exiting script."
        exit 1
    fi

    printf "\n\n"
}


function deployCortxServer()
{
    printf "########################################################\n"
    printf "# Deploy CORTX Server                                   \n"
    printf "########################################################\n"
    cortxserver_image=$(parseSolution 'solution.images.cortxserver')
    cortxserver_image=$(echo $cortxserver_image | cut -f2 -d'>')

    external_services_type=$(parseSolution 'solution.common.external_services.type')
    external_services_type=$(echo $external_services_type | cut -f2 -d'>')

    num_nodes=0
    for i in "${!node_selector_list[@]}"; do
        num_nodes=$((num_nodes+1))
        node_name=${node_name_list[i]}
        node_selector=${node_selector_list[i]}

        cortxserver_machineid=$(cat $cfgmap_path/auto-gen-${node_name_list[$i]}-$namespace/server/id)

        helm install "cortx-server-$node_name-$namespace" cortx-cloud-helm-pkg/cortx-server \
            --set cortxserver.name="cortx-server-$node_name" \
            --set cortxserver.image=$cortxserver_image \
            --set cortxserver.nodeselector=$node_selector \
            --set cortxserver.service.clusterip.name="cortx-server-clusterip-svc-$node_name" \
            --set cortxserver.service.headless.name="cortx-server-headless-svc-$node_name" \
            --set cortxserver.service.loadbal.name="cortx-server-loadbal-svc-$node_name" \
            --set cortxserver.service.loadbal.type="$external_services_type" \
            --set cortxserver.cfgmap.name="cortx-cfgmap-$namespace" \
            --set cortxserver.cfgmap.volmountname="config001-$node_name" \
            --set cortxserver.cfgmap.mountpath="/etc/cortx/solution" \
            --set cortxserver.sslcfgmap.name="cortx-ssl-cert-cfgmap-$namespace" \
            --set cortxserver.sslcfgmap.volmountname="ssl-config001" \
            --set cortxserver.sslcfgmap.mountpath="/etc/cortx/solution/ssl" \
            --set cortxserver.machineid.value="$cortxserver_machineid" \
            --set cortxserver.localpathpvc.name="cortx-server-fs-local-pvc-$node_name" \
            --set cortxserver.localpathpvc.mountpath="$local_storage" \
            --set cortxserver.localpathpvc.requeststoragesize="1Gi" \
            --set cortxserver.s3.numinst=$(extractBlock 'solution.common.s3.num_inst') \
            --set cortxserver.s3.startportnum=$(extractBlock 'solution.common.s3.start_port_num') \
            --set cortxserver.hax.port=$(extractBlock 'solution.common.hax.port_num') \
            --set cortxserver.secretinfo="secret-info.txt" \
            --set cortxserver.serviceaccountname="$serviceAccountName" \
            --set namespace=$namespace \
            -n $namespace
    done

    printf "\nWait for CORTX Server to be ready"
    # Wait for all cortx-data deployments to be ready
    local deployments=()
    for i in "${!node_selector_list[@]}"; do
        deployments+=("deployment/cortx-server-${node_name_list[i]}")
    done
    if ! waitForAllDeploymentsAvailable 300s "CORTX Server" "${deployments[@]}"; then
        echo "Failed.  Exiting script."
        exit 1
    fi

    printf "\n\n"
}

function deployCortxHa()
{
    printf "########################################################\n"
    printf "# Deploy CORTX HA                                       \n"
    printf "########################################################\n"
    cortxha_image=$(parseSolution 'solution.images.cortxha')
    cortxha_image=$(echo $cortxha_image | cut -f2 -d'>')

    cortxha_machineid=$(cat $cfgmap_path/auto-gen-ha-$namespace/id)

    ##TOOD: cortxha.serviceaccountname should extract from solution.yaml ?

    num_nodes=1
    helm install "cortx-ha-$namespace" cortx-cloud-helm-pkg/cortx-ha \
        --set cortxha.name="cortx-ha" \
        --set cortxha.image=$cortxha_image \
        --set cortxha.secretinfo="secret-info.txt" \
        --set cortxha.serviceaccountname="ha-monitor" \
        --set cortxha.service.clusterip.name="cortx-ha-clusterip-svc" \
        --set cortxha.service.headless.name="cortx-ha-headless-svc" \
        --set cortxha.service.loadbal.name="cortx-ha-loadbal-svc" \
        --set cortxha.cfgmap.mountpath="/etc/cortx/solution" \
        --set cortxha.cfgmap.name="cortx-cfgmap-$namespace" \
        --set cortxha.cfgmap.volmountname="config001" \
        --set cortxha.sslcfgmap.name="cortx-ssl-cert-cfgmap-$namespace" \
        --set cortxha.sslcfgmap.volmountname="ssl-config001" \
        --set cortxha.sslcfgmap.mountpath="/etc/cortx/solution/ssl" \
        --set cortxha.machineid.value="$cortxha_machineid" \
        --set cortxha.localpathpvc.name="cortx-ha-fs-local-pvc-$namespace" \
        --set cortxha.localpathpvc.mountpath="$local_storage" \
        --set cortxha.localpathpvc.requeststoragesize="1Gi" \
        --set namespace=$namespace \
        -n $namespace

    printf "\nWait for CORTX HA to be ready"
    if ! waitForAllDeploymentsAvailable 120s "CORTX HA" deployment/cortx-ha; then
        echo "Failed.  Exiting script."
        exit 1
    fi
    printf "\n\n"
}

function deployCortxClient()
{
    printf "########################################################\n"
    printf "# Deploy CORTX Client                                   \n"
    printf "########################################################\n"
    cortxclient_image=$(parseSolution 'solution.images.cortxclient')
    cortxclient_image=$(echo $cortxclient_image | cut -f2 -d'>')

    external_services_type=$(parseSolution 'solution.common.external_services.type')
    external_services_type=$(echo $external_services_type | cut -f2 -d'>')

    num_nodes=0
    for i in "${!node_selector_list[@]}"; do
        num_nodes=$((num_nodes+1))
        node_name=${node_name_list[i]}
        node_selector=${node_selector_list[i]}

        cortxclient_machineid=$(cat $cfgmap_path/auto-gen-${node_name_list[$i]}-$namespace/client/id)

        helm install "cortx-client-$node_name-$namespace" cortx-cloud-helm-pkg/cortx-client \
            --set cortxclient.name="cortx-client-$node_name" \
            --set cortxclient.image=$cortxclient_image \
            --set cortxclient.nodeselector=$node_selector \
            --set cortxclient.secretinfo="secret-info.txt" \
            --set cortxclient.serviceaccountname="$serviceAccountName" \
            --set cortxclient.motr.numclientinst=$num_motr_client \
            --set cortxclient.service.clusterip.name="cortx-client-clusterip-svc-$node_name" \
            --set cortxclient.service.headless.name="cortx-client-headless-svc-$node_name" \
            --set cortxclient.service.loadbal.name="cortx-client-loadbal-svc-$node_name" \
            --set cortxclient.service.loadbal.type="$external_services_type" \
            --set cortxclient.cfgmap.name="cortx-cfgmap-$namespace" \
            --set cortxclient.cfgmap.volmountname="config001-$node_name" \
            --set cortxclient.cfgmap.mountpath="/etc/cortx/solution" \
            --set cortxclient.sslcfgmap.name="cortx-ssl-cert-cfgmap-$namespace" \
            --set cortxclient.sslcfgmap.volmountname="ssl-config001" \
            --set cortxclient.sslcfgmap.mountpath="/etc/cortx/solution/ssl" \
            --set cortxclient.machineid.value="$cortxclient_machineid" \
            --set cortxclient.localpathpvc.name="cortx-client-fs-local-pvc-$node_name" \
            --set cortxclient.localpathpvc.mountpath="$local_storage" \
            --set cortxclient.localpathpvc.requeststoragesize="1Gi" \
            --set namespace=$namespace \
            -n $namespace
    done

    printf "\nWait for CORTX Client to be ready"
    while true; do
        count=0
        while IFS= read -r line; do
            IFS=" " read -r -a pod_status <<< "$line"
            IFS="/" read -r -a ready_status <<< "${pod_status[1]}"
            if [[ "${pod_status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
                if [[ "${pod_status[2]}" == "Error" || "${pod_status[2]}" == "Init:Error" ]]; then
                    printf "\n'${pod_status[0]}' pod deployment did not complete. Exit early.\n"
                    exit 1
                fi
                break
            fi
            count=$((count+1))
        done <<< "$(kubectl get pods --namespace=$namespace | grep 'cortx-client-')"

        if [[ $num_nodes -eq $count ]]; then
            break
        else
            printf "."
        fi
        sleep 1s
    done
    printf "\n\n"
}

function cleanup()
{
    #################################################################
    # Delete files that contain disk partitions on the worker nodes
    # and the node info
    #################################################################
    find $(pwd)/cortx-cloud-3rd-party-pkg/openldap -name "node-list-info*" -delete
    find $(pwd)/cortx-cloud-helm-pkg/cortx-control -name "secret-*" -delete
    find $(pwd)/cortx-cloud-helm-pkg/cortx-data -name "secret-*" -delete
    find $(pwd)/cortx-cloud-helm-pkg/cortx-server -name "secret-*" -delete
    find $(pwd)/cortx-cloud-helm-pkg/cortx-ha -name "secret-*" -delete
    find $(pwd)/cortx-cloud-helm-pkg/cortx-client -name "secret-*" -delete

    rm -rf "$cfgmap_path/auto-gen-secret-$namespace"

    find $(pwd)/cortx-cloud-helm-pkg/cortx-data-blk-data -name "mnt-blk-*" -delete
    find $(pwd)/cortx-cloud-helm-pkg/cortx-data-blk-data -name "node-list-*" -delete
    find $(pwd)/cortx-cloud-helm-pkg/cortx-data -name "mnt-blk-*" -delete
    find $(pwd)/cortx-cloud-helm-pkg/cortx-data -name "node-list-*" -delete
}

##########################################################
# Deploy Kubernetes prerequisite configurations
##########################################################
deployKubernetesPrereqs

##########################################################
# Deploy CORTX 3rd party
##########################################################
found_match_nsp=false
for np in "${namespace_list[@]}"; do
    if [[ "$np" == "$namespace" ]]; then
        found_match_nsp=true
        break
    fi
done

# Extract storage provisioner path from the "solution.yaml" file
filter='solution.common.storage_provisioner_path'
parse_storage_prov_output=$(parseSolution $filter)
# Get the storage provisioner var from the tuple
storage_prov_path=$(echo $parse_storage_prov_output | cut -f2 -d'>')

# Get number of consul replicas and make sure it doesn't exceed the limit
num_consul_replicas=$num_worker_nodes
if [[ "$num_worker_nodes" -gt "$max_consul_inst" ]]; then
    num_consul_replicas=$max_consul_inst
fi

# Get number of kafka replicas and make sure it doesn't exceed the limit
num_kafka_replicas=$num_worker_nodes
if [[ "$num_worker_nodes" -gt "$max_kafka_inst" ]]; then
    num_kafka_replicas=$max_kafka_inst
fi

if [[ (${#namespace_list[@]} -le 1 && "$found_match_nsp" = true) || "$namespace" == "default" ]]; then
    deployRancherProvisioner
    deployConsul
    deployOpenLDAP
    deployZookeeper
    deployKafka
    waitForThirdParty
fi

##########################################################
# Deploy CORTX cloud
##########################################################
# Get the storage paths to use
local_storage=$(parseSolution 'solution.common.container_path.local')
local_storage=$(echo $local_storage | cut -f2 -d'>')
shared_storage=$(parseSolution 'solution.common.container_path.shared')
shared_storage=$(echo $shared_storage | cut -f2 -d'>')
log_storage=$(parseSolution 'solution.common.container_path.log')
log_storage=$(echo $log_storage | cut -f2 -d'>')


# Default path to CORTX configmap
cfgmap_path="./cortx-cloud-helm-pkg/cortx-configmap"

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

num_motr_client=$(extractBlock 'solution.common.motr.num_client_inst')

deployCortxLocalBlockStorage
deleteStaleAutoGenFolders
deployCortxConfigMap
deployCortxSecrets
deployCortxControl
deployCortxData
deployCortxServer
deployCortxHa
if [[ $num_motr_client -gt 0 ]]; then
    deployCortxClient
fi
cleanup
