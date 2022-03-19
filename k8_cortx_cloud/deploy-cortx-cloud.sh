#!/bin/bash

# shellcheck disable=SC2312

solution_yaml=${1:-'solution.yaml'}
storage_class='local-path'

##TODO Extract from solution.yaml ?
serviceAccountName=cortx-sa


cortx_secret_fields=("kafka_admin_secret"
                     "consul_admin_secret"
                     "common_admin_secret"
                     "s3_auth_admin_secret"
                     "csm_auth_admin_secret"
                     "csm_mgmt_admin_secret")

function parseSolution()
{
    ./parse_scripts/parse_yaml.sh "${solution_yaml}" "$1"
}

function extractBlock()
{
    ./parse_scripts/yaml_extract_block.sh "${solution_yaml}" "$1"
}

#######################################
# Get a scalar value given a YAML path in a solution.yaml file.
# Arguments:
#   A YAML path to lookup, e.g. "solution.common.external_services.s3.type".
#   Wildcard paths are not accepted, e.g. "solution.nodes.node*.name".
# Outputs:
#   Writes the value to stdout. An empty string "" is printed if
#   the value does not exist, or the value is YAML `null` or `~`.
# Returns:
#   1 if the yaml path contains a wildcard, 0 otherwise.
#######################################
function getSolutionValue()
{
    local yaml_path=$1
    # Don't allow wildcard paths
    if [[ ${yaml_path}  == *"*"* ]]; then
        return 1
    fi

    local value
    value=$(parseSolution "${yaml_path}")
    # discard everything before and including the first '>'
    value="${value#*>}"
    [[ ${value} == "null" || ${value} == "~" ]] && value=""
    echo "${value}"
}

function configurationCheck()
{
    # Check if the file exists
    if [[ ! -f ${solution_yaml} ]]
    then
        echo "ERROR: ${solution_yaml} does not exist"
        exit 1
    fi

    # Validate secrets configuration
    secret_name=$(getSolutionValue "solution.secrets.name")
    secret_ext=$(getSolutionValue "solution.secrets.external_secret")
    if [[ -z "${secret_name}" && -z "${secret_ext}" ]] ; then
        printf "Error: %s: solution.secrets.name or solution.secrets.external_secret must be specified\n" "${solution_yaml}"
        exit 1
    elif [[ -n "${secret_name}" && -n "${secret_ext}" ]] ; then
        printf "Error: %s: Cannot specify both solution.secrets.name or solution.secrets.external_secret\n" "${solution_yaml}"
        exit 1
    elif [[ -n "${secret_ext}" ]] ; then
        # If an external_secret is specified, verify that the named secret exists
        output=$(kubectl get secrets "${secret_ext}" --no-headers)
        if [[ -z "${output}" ]] ; then
            printf "Error: %s: External Secret %s does not exist (solution.secrets.external_secret)\n" "${solution_yaml}" "${secret_ext}"
            exit 1
        fi

        # Verify that all required cortx fields are present in the external secret
        secret_output=$(kubectl describe secrets "${secret_ext}")
        fail="false"
        for field in "${cortx_secret_fields[@]}" ; do
            if [[ "${secret_output}:" != *"${field}:"* ]] ; then
                printf "Error: External Secret %s does not contain the required field '%s'\n" "${secret_ext}" "${field}"
                fail="true"
            fi
        done
        if [[ "${fail}" == "true" ]] ; then
            exit 1
        fi
    fi

    # Validate the "solution.yaml" file against the "solution_check.yaml" file
    while IFS= read -r line; do
        echo "${line}"
        if [[ "${line}" != *"Validate solution file result"* ]]; then
            continue
        fi
        if [[ "${line}" == *"failed"* ]]; then
            exit 1
        fi
    done <<< "$(./solution_validation_scripts/solution-validation.sh "${solution_yaml}")"
}

# Initial solution.yaml / system state checks
configurationCheck

max_consul_inst=3
max_kafka_inst=3
num_worker_nodes=0
not_ready_node_list=[]
not_ready_node_count=0
while IFS= read -r line; do
    IFS=" " read -r -a my_array <<< "${line}"
    node_name="${my_array[0]}"
    node_status="${my_array[1]}"
    if [[ "${node_status}" == "NotReady" ]]; then
        not_ready_node_list[${not_ready_node_count}]="${node_name}"
        not_ready_node_count=$((not_ready_node_count+1))
    fi

    output=$(kubectl describe nodes "${node_name}" | grep Taints | grep NoSchedule)
    if [[ "${output}" == "" ]]; then
        num_worker_nodes=$((num_worker_nodes+1))
    fi

done <<< "$(kubectl get nodes --no-headers)"
printf "Number of worker nodes detected: %s\n" "${num_worker_nodes}"


# Check for nodes listed in the solution file are in "Ready" state. If not, ask
# the users whether they want to continue to deploy or exit early
exit_early=false
if [[ ${not_ready_node_count} -gt 0 ]]; then
    echo "Number of 'NotReady' worker nodes detected in the cluster: ${not_ready_node_count}"
    echo "List of 'NotReady' worker nodes:"
    for not_ready_node in "${not_ready_node_list[@]}"; do
        echo "- ${not_ready_node}"
    done

    printf "\nContinue CORTX Cloud deployment could lead to unexpeted results.\n"
    read -p "Do you want to continue (y/n, yes/no)? " -r reply
    if [[ "${reply}" =~ ^(y|Y)*.(es)$ || "${reply}" =~ ^(y|Y)$ ]]; then
        exit_early=false
    elif [[ "${reply}" =~ ^(n|N)*.(o)$ || "${reply}" =~ ^(n|N)$ ]]; then
        exit_early=true
    else
        echo "Invalid response."
        exit_early=true
    fi
fi

if [[ "${exit_early}" = true ]]; then
    echo "Exit script early."
    exit 1
fi

namespace=$(parseSolution 'solution.namespace')
namespace=$(echo "${namespace}" | cut -f2 -d'>')
parsed_node_output=$(parseSolution 'solution.nodes.node*.name')

# Split parsed output into an array of vars and vals
IFS=';' read -r -a parsed_var_val_array <<< "${parsed_node_output}"

tainted_worker_node_list=[]
num_tainted_worker_nodes=0
not_found_node_list=[]
num_not_found_nodes=0
# Validate the solution file. Check that nodes listed in the solution file
# aren't tainted and allow scheduling.
for parsed_var_val_element in "${parsed_var_val_array[@]}";
do
    node_name=$(echo "${parsed_var_val_element}" | cut -f2 -d'>')
    output_get_node=$(kubectl get nodes | grep "${node_name}")
    output=$(kubectl describe nodes "${node_name}" | grep Taints | grep NoSchedule)
    if [[ "${output}" != "" ]]; then
        tainted_worker_node_list[${num_tainted_worker_nodes}]=${node_name}
        num_tainted_worker_nodes=$((num_tainted_worker_nodes+1))
    elif [[ "${output_get_node}" == "" ]]; then
        not_found_node_list[${num_not_found_nodes}]=${node_name}
        num_not_found_nodes=$((num_not_found_nodes+1))
    fi
done
# Print a list of tainted nodes and nodes that don't exist in the cluster
if [[ ${num_tainted_worker_nodes} -gt 0 || ${num_not_found_nodes} -gt 0 ]]; then
    echo "Can't deploy CORTX cloud."
    if [[ ${num_tainted_worker_nodes} -gt 0 ]]; then
        echo "List of tainted nodes:"
        for tainted_node_name in "${tainted_worker_node_list[@]}"; do
            echo "- ${tainted_node_name}"
        done
    fi
    if [[ ${num_not_found_nodes} -gt 0 ]]; then
        echo "List of nodes don't exist in the cluster:"
        for node_not_found in "${not_found_node_list[@]}"; do
            echo "- ${node_not_found}"
        done
    fi
fi

# Delete disk & node info files from folders: cortx-data-blk-data, cortx-data
find "$(pwd)/cortx-cloud-helm-pkg/cortx-data-blk-data" -name "mnt-blk-*" -delete
find "$(pwd)/cortx-cloud-helm-pkg/cortx-data-blk-data" -name "node-list-*" -delete
find "$(pwd)/cortx-cloud-helm-pkg/cortx-data" -name "mnt-blk-*" -delete
find "$(pwd)/cortx-cloud-helm-pkg/cortx-data" -name "node-list-*" -delete

# Create files consist of drives per node and files consist of drive sizes.
# These files are used by the helm charts to deploy cortx data. These file
# will be deleted at the end of this script.
node_name_list=[] # short version. Ex: ssc-vm-g3-rhev4-1490
node_selector_list=[] # long version. Ex: ssc-vm-g3-rhev4-1490.colo.seagate.com
count=0

mnt_blk_info_fname="mnt-blk-info.txt"
node_list_info_fname="node-list-info.txt"
cortx_blk_data_mnt_info_path=$(pwd)/cortx-cloud-helm-pkg/cortx-data-blk-data/${mnt_blk_info_fname}
cortx_blk_data_node_list_info_path=$(pwd)/cortx-cloud-helm-pkg/cortx-data-blk-data/${node_list_info_fname}

count=0
for var_val_element in "${parsed_var_val_array[@]}"
do
    node_name=$(echo "${var_val_element}" | cut -f2 -d'>')
    node_selector_list[count]=${node_name}
    shorter_node_name=$(echo "${node_name}" | cut -f1 -d'.')
    node_name_list[count]=${shorter_node_name}

    # Get the node var from the tuple
    node_info_str="${count} ${node_name}"
    if [[ -s ${cortx_blk_data_node_list_info_path} ]]; then
        printf "\n" >> "${cortx_blk_data_node_list_info_path}"
    fi
    printf "%s" "${node_info_str}" >> "${cortx_blk_data_node_list_info_path}"

    count=$((count+1))
done

# Copy cluster node info file from CORTX local block helm to CORTX data
cp "${cortx_blk_data_node_list_info_path}" "$(pwd)/cortx-cloud-helm-pkg/cortx-data"

# Get the devices from the solution
filter="solution.storage.cvg*.devices*.device"
parsed_dev_output=$(parseSolution "${filter}")
IFS=';' read -r -a parsed_dev_array <<< "${parsed_dev_output}"

# Get the sizes from the solution
filter="solution.storage.cvg*.devices*.size"
parsed_size_output=$(parseSolution "${filter}")
IFS=';' read -r -a parsed_size_array <<< "${parsed_size_output}"

# Write disk info (device name and size) to files (for cortx local blk storage and cortx data)
for index in "${!parsed_dev_array[@]}"
do
    device=$(echo "${parsed_dev_array[index]}" | cut -f2 -d'>')
    size=$(echo "${parsed_size_array[index]}" | cut -f2 -d'>')
    mnt_blk_info="${device} ${size}"

    if [[ -s ${cortx_blk_data_mnt_info_path} ]]; then
        printf "\n" >> "${cortx_blk_data_mnt_info_path}"
    fi
    printf "%s" "${mnt_blk_info}" >> "${cortx_blk_data_mnt_info_path}"
done

# Copy device info file from CORTX local block helm to CORTX data
cp "${cortx_blk_data_mnt_info_path}" "$(pwd)/cortx-cloud-helm-pkg/cortx-data"

# Create CORTX namespace
if [[ "${namespace}" != "default" ]]; then

    helm install "cortx-ns-${namespace}" cortx-cloud-helm-pkg/cortx-platform \
        --set namespace.create="true" \
        --set namespace.name="${namespace}"

fi

count=0
namespace_list=[]
namespace_index=0
while IFS= read -r line; do
    if [[ ${count} -eq 0 ]]; then
        count=$((count+1))
        continue
    fi
    IFS=" " read -r -a my_array <<< "${line}"
    if [[ "${my_array[0]}" != *"kube-"* \
            && "${my_array[0]}" != "default" \
            && "${my_array[0]}" != "local-path-storage" ]]; then
        namespace_list[${namespace_index}]=${my_array[0]}
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
    local podSecurityPolicyName="cortx-baseline"
    local createPodSecurityPolicy="true"
    local output
    output=$(kubectl get psp --no-headers ${podSecurityPolicyName} 2>/dev/null | wc -l || true)
    if [[ ${output} == "1" ]]; then
        createPodSecurityPolicy="false"
    fi

    local hax_service_name
    local hax_service_port
    local s3_service_type
    local s3_service_ports_http
    local s3_service_ports_https
    hax_service_name=$(getSolutionValue 'solution.common.hax.service_name')
    hax_service_port=$(getSolutionValue 'solution.common.hax.port_num')
    s3_service_type=$(getSolutionValue 'solution.common.external_services.s3.type')
    s3_service_count=$(getSolutionValue 'solution.common.external_services.s3.count')
    s3_service_ports_http=$(getSolutionValue 'solution.common.external_services.s3.ports.http')
    s3_service_ports_https=$(getSolutionValue 'solution.common.external_services.s3.ports.https')

    local optional_values=()
    local s3_service_nodeports_http
    local s3_service_nodeports_https
    s3_service_nodeports_http=$(getSolutionValue 'solution.common.external_services.s3.nodePorts.http')
    s3_service_nodeports_https=$(getSolutionValue 'solution.common.external_services.s3.nodePorts.https')
    [[ -n ${s3_service_nodeports_http} ]] && optional_values+=(--set services.io.nodePorts.http="${s3_service_nodeports_http}")
    [[ -n ${s3_service_nodeports_https} ]] && optional_values+=(--set services.io.nodePorts.https="${s3_service_nodeports_https}")

    helm install "cortx-platform" cortx-cloud-helm-pkg/cortx-platform \
        --set podSecurityPolicy.create="${createPodSecurityPolicy}" \
        --set rbacRole.create="true" \
        --set rbacRoleBinding.create="true" \
        --set serviceAccount.create="true" \
        --set serviceAccount.name="${serviceAccountName}" \
        --set networkPolicy.create="false" \
        --set namespace.name="${namespace}" \
        --set services.hax.name="${hax_service_name}" \
        --set services.hax.port="${hax_service_port}" \
        --set services.io.type="${s3_service_type}" \
        --set services.io.count="${s3_service_count}" \
        --set services.io.ports.http="${s3_service_ports_http}" \
        --set services.io.ports.https="${s3_service_ports_https}" \
        "${optional_values[@]}" \
        --namespace "${namespace}"
}


##########################################################
# Deploy CORTX 3rd party
##########################################################
function deployRancherProvisioner()
{
    local image

    # Add the HashiCorp Helm Repository:
    helm repo add hashicorp https://helm.releases.hashicorp.com
    helm repo update hashicorp
    if [[ ${storage_class} == "local-path" ]]
    then
        printf "Install Rancher Local Path Provisioner"
        rancher_prov_path="$(pwd)/cortx-cloud-3rd-party-pkg/auto-gen-rancher-provisioner"
        # Clean up auto gen Rancher Provisioner folder in case it still exists and was not
        # clearned up previously by the destroy-cortx-cloud script.
        rm -rf "${rancher_prov_path}"
        mkdir -p "${rancher_prov_path}"
        rancher_prov_file="${rancher_prov_path}/local-path-storage.yaml"
        cp "$(pwd)/cortx-cloud-3rd-party-pkg/templates/local-path-storage-template.yaml" "${rancher_prov_file}"
        image=$(parseSolution 'solution.images.rancher')
        image=$(echo "${image}" | cut -f2 -d'>')
        ./parse_scripts/subst.sh "${rancher_prov_file}" "rancher.image" "${image}"
        ./parse_scripts/subst.sh "${rancher_prov_file}" "rancher.host_path" "${storage_prov_path}/local-path-provisioner"

        image=$(parseSolution 'solution.images.busybox')
        image=$(echo "${image}" | cut -f2 -d'>')
        ./parse_scripts/subst.sh "${rancher_prov_file}" "rancher.helperPod.image" "${image}"

        kubectl create -f "${rancher_prov_file}"
    fi
}

function deployConsul()
{
    local image

    printf "######################################################\n"
    printf "# Deploy Consul                                       \n"
    printf "######################################################\n"
    image=$(parseSolution 'solution.images.consul')
    image=$(echo "${image}" | cut -f2 -d'>')

    helm install "consul" hashicorp/consul \
        --set global.name="consul" \
        --set global.image="${image}" \
        --set ui.enabled=false \
        --set server.storageClass=${storage_class} \
        --set server.replicas="${num_consul_replicas}" \
        --set server.resources.requests.memory="$(extractBlock 'solution.common.resource_allocation.consul.server.resources.requests.memory')" \
        --set server.resources.requests.cpu="$(extractBlock 'solution.common.resource_allocation.consul.server.resources.requests.cpu')" \
        --set server.resources.limits.memory="$(extractBlock 'solution.common.resource_allocation.consul.server.resources.limits.memory')" \
        --set server.resources.limits.cpu="$(extractBlock 'solution.common.resource_allocation.consul.server.resources.limits.cpu')" \
        --set server.containerSecurityContext.server.allowPrivilegeEscalation=false \
        --set server.storage="$(extractBlock 'solution.common.resource_allocation.consul.server.storage')" \
        --set client.resources.requests.memory="$(extractBlock 'solution.common.resource_allocation.consul.client.resources.requests.memory')" \
        --set client.resources.requests.cpu="$(extractBlock 'solution.common.resource_allocation.consul.client.resources.requests.cpu')" \
        --set client.resources.limits.memory="$(extractBlock 'solution.common.resource_allocation.consul.client.resources.limits.memory')" \
        --set client.resources.limits.cpu="$(extractBlock 'solution.common.resource_allocation.consul.client.resources.limits.cpu')" \
        --set client.containerSecurityContext.client.allowPrivilegeEscalation=false \
        --wait

    # Patch generated ServiceAccounts to prevent automounting ServiceAccount tokens
    kubectl patch serviceaccount/consul-client -p '{"automountServiceAccountToken":false}'
    kubectl patch serviceaccount/consul-server -p '{"automountServiceAccountToken":false}'

    # Rollout a new deployment version of Consul pods to use updated Service Account settings
    kubectl rollout restart statefulset/consul-server
    kubectl rollout restart daemonset/consul-client

    ##TODO This needs to be maintained during upgrades etc...

}

function splitDockerImage()
{
    local image
    local tag_arr

    IFS='/' read -ra image <<< "$1"
    IFS=':' read -ra tag_arr <<< "${image[2]}"
    registry="${image[0]}"
    repository="${image[1]}"
    repository="${repository}/${tag_arr[0]}"
    tag="${tag_arr[1]}"
}

function deployZookeeper()
{
    local image

    printf "######################################################\n"
    printf "# Deploy Zookeeper                                    \n"
    printf "######################################################\n"
    # Add Zookeeper and Kafka Repository
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo update bitnami

    image=$(parseSolution 'solution.images.zookeeper')
    image=$(echo "${image}" | cut -f2 -d'>')
    splitDockerImage "${image}"
    printf "\nRegistry: %s\nRepository: %s\nTag: %s\n" "${registry}" "${repository}" "${tag}"

    helm install zookeeper bitnami/zookeeper \
        --set image.tag="${tag}" \
        --set image.registry="${registry}" \
        --set image.repository="${repository}" \
        --set replicaCount="${num_kafka_replicas}" \
        --set auth.enabled=false \
        --set allowAnonymousLogin=true \
        --set global.storageClass=${storage_class} \
        --set resources.requests.memory="$(extractBlock 'solution.common.resource_allocation.zookeeper.resources.requests.memory')" \
        --set resources.requests.cpu="$(extractBlock 'solution.common.resource_allocation.zookeeper.resources.requests.cpu')" \
        --set resources.limits.memory="$(extractBlock 'solution.common.resource_allocation.zookeeper.resources.limits.memory')" \
        --set resources.limits.cpu="$(extractBlock 'solution.common.resource_allocation.zookeeper.resources.limits.cpu')" \
        --set persistence.size="$(extractBlock 'solution.common.resource_allocation.zookeeper.storage_request_size')" \
        --set persistence.dataLogDir.size="$(extractBlock 'solution.common.resource_allocation.zookeeper.data_log_dir_request_size')" \
        --set serviceAccount.create=true \
        --set serviceAccount.name="cortx-zookeeper" \
        --set serviceAccount.automountServiceAccountToken=false \
        --set containerSecurityContext.allowPrivilegeEscalation=false \
        --wait

    printf "\nWait for Zookeeper to be ready before starting kafka"
    while true; do
        count=0
        while IFS= read -r line; do
            IFS=" " read -r -a pod_status <<< "${line}"
            IFS="/" read -r -a ready_status <<< "${pod_status[2]}"
            if [[ "${pod_status[3]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
                count=$((count+1))
                break
            fi
        done <<< "$(kubectl get pods -A | grep 'zookeeper')"

        if [[ ${count} -eq 0 ]]; then
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
    local image

    printf "######################################################\n"
    printf "# Deploy Kafka                                        \n"
    printf "######################################################\n"

    image=$(parseSolution 'solution.images.kafka')
    image=$(echo "${image}" | cut -f2 -d'>')
    splitDockerImage "${image}"
    printf "\nRegistry: %s\nRepository: %s\nTag: %s\n" "${registry}" "${repository}" "${tag}"

    local kafka_cfg_log_segment_delete_delay_ms=${KAFKA_CFG_LOG_SEGMENT_DELETE_DELAY_MS:-1000}
    local kafka_cfg_log_flush_offset_checkpoint_interval_ms=${KAFKA_CFG_LOG_FLUSH_OFFSET_CHECKPOINT_INTERVAL_MS:-1000}
    local kafka_cfg_log_retention_check_interval_ms=${KAFKA_CFG_LOG_RETENTION_CHECK_INTERVAL_MS:-1000}
    local tmp_kafka_envvars_yaml="tmp-kafka.yaml"

    cat > ${tmp_kafka_envvars_yaml} << EOF
extraEnvVars:
- name: KAFKA_CFG_LOG_SEGMENT_DELETE_DELAY_MS
  value: "${kafka_cfg_log_segment_delete_delay_ms}"
- name: KAFKA_CFG_LOG_FLUSH_OFFSET_CHECKPOINT_INTEL_MS
  value: "${kafka_cfg_log_flush_offset_checkpoint_interval_ms}"
- name: KAFKA_CFG_LOG_RETENTION_CHECK_INTERVAL_MS
  value: "${kafka_cfg_log_retention_check_interval_ms}"
EOF

    helm install kafka bitnami/kafka \
        --set zookeeper.enabled=false \
        --set image.tag="${tag}" \
        --set image.registry="${registry}" \
        --set image.repository="${repository}" \
        --set replicaCount="${num_kafka_replicas}" \
        --set externalZookeeper.servers=zookeeper.default.svc.cluster.local \
        --set global.storageClass=${storage_class} \
        --set defaultReplicationFactor="${num_kafka_replicas}" \
        --set offsetsTopicReplicationFactor="${num_kafka_replicas}" \
        --set transactionStateLogReplicationFactor="${num_kafka_replicas}" \
        --set auth.enabled=false \
        --set allowAnonymousLogin=true \
        --set deleteTopicEnable=true \
        --set transactionStateLogMinIsr=2 \
        --set resources.requests.memory="$(extractBlock 'solution.common.resource_allocation.kafka.resources.requests.memory')" \
        --set resources.requests.cpu="$(extractBlock 'solution.common.resource_allocation.kafka.resources.requests.cpu')" \
        --set resources.limits.memory="$(extractBlock 'solution.common.resource_allocation.kafka.resources.limits.memory')" \
        --set resources.limits.cpu="$(extractBlock 'solution.common.resource_allocation.kafka.resources.limits.cpu')" \
        --set persistence.size="$(extractBlock 'solution.common.resource_allocation.kafka.storage_request_size')" \
        --set logPersistence.size="$(extractBlock 'solution.common.resource_allocation.kafka.log_persistence_request_size')" \
        --set serviceAccount.create=true \
        --set serviceAccount.name="cortx-kafka" \
        --set serviceAccount.automountServiceAccountToken=false \
        --set serviceAccount.automountServiceAccountToken=false \
        --set containerSecurityContext.enabled=true \
        --set containerSecurityContext.allowPrivilegeEscalation=false \
        --values ${tmp_kafka_envvars_yaml}  \
        --wait

    rm ${tmp_kafka_envvars_yaml}

    printf "\n\n"
}

function waitForThirdParty()
{
    printf "\nWait for CORTX 3rd party to be ready"
    while true; do
        count=0
        while IFS= read -r line; do
            IFS=" " read -r -a pod_status <<< "${line}"
            IFS="/" read -r -a ready_status <<< "${pod_status[2]}"
            if [[ "${pod_status[3]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
                count=$((count+1))
                break
            fi
        done <<< "$(kubectl get pods -A | grep 'consul\|kafka\|zookeeper')"

        if [[ ${count} -eq 0 ]]; then
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
    helm install "cortx-data-blk-data-${namespace}" cortx-cloud-helm-pkg/cortx-data-blk-data \
        --set cortxblkdata.storageclass="cortx-local-blk-storage-${namespace}" \
        --set cortxblkdata.nodelistinfo="node-list-info.txt" \
        --set cortxblkdata.mountblkinfo="mnt-blk-info.txt" \
        --set cortxblkdata.storage.volumemode="Block" \
        --set namespace="${namespace}" \
        -n "${namespace}"
}

function deleteStaleAutoGenFolders()
{
    # Delete all stale auto gen folders
    rm -rf "$(pwd)/cortx-cloud-helm-pkg/cortx-configmap/auto-gen-cfgmap-${namespace}"
    rm -rf "$(pwd)/cortx-cloud-helm-pkg/cortx-configmap/auto-gen-control-${namespace}"
    rm -rf "$(pwd)/cortx-cloud-helm-pkg/cortx-configmap/auto-gen-secret-${namespace}"
    rm -rf "$(pwd)/cortx-cloud-helm-pkg/cortx-configmap/node-info-${namespace}"
    rm -rf "$(pwd)/cortx-cloud-helm-pkg/cortx-configmap/storage-info-${namespace}"
    for i in "${!node_name_list[@]}"; do
        rm -rf "$(pwd)/cortx-cloud-helm-pkg/cortx-configmap/auto-gen-${node_name_list[i]}-${namespace}"
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
        --set cortxRgw.authAdmin="$(extractBlock 'solution.common.s3.default_iam_users.auth_admin' || true)"
        --set cortxRgw.authUser="$(extractBlock 'solution.common.s3.default_iam_users.auth_user' || true)"
    )

    local rgw_extra_config
    rgw_extra_config="$(extractBlock 'solution.common.s3.extra_configuration')"
    if [[ -n ${rgw_extra_config} \
          && ${rgw_extra_config} != "null" \
          && ${rgw_extra_config} != "~" ]]; then
        helm_install_args+=(--set cortxRgw.extraConfiguration="${rgw_extra_config}")
    fi

    local motr_extra_config
    motr_extra_config="$(extractBlock 'solution.common.motr.extra_configuration')"
    if [[ -n ${motr_extra_config} \
          && ${motr_extra_config} != "null" \
          && ${motr_extra_config} != "~" ]]; then
        helm_install_args+=(--set cortxMotr.extraConfiguration="${motr_extra_config}")
    fi

    for idx in "${!node_name_list[@]}"; do
        helm_install_args+=(
            --set "cortxHare.haxDataEndpoints[${idx}]=tcp://cortx-data-headless-svc-${node_name_list[idx]}:22001"
            --set "cortxHare.haxServerEndpoints[${idx}]=tcp://cortx-server-headless-svc-${node_name_list[idx]}:22001"
            --set "cortxMotr.confdEndpoints[${idx}]=tcp://cortx-data-headless-svc-${node_name_list[idx]}:22002"
            --set "cortxMotr.iosEndpoints[${idx}]=tcp://cortx-data-headless-svc-${node_name_list[idx]}:21001"
            --set "cortxMotr.rgwEndpoints[${idx}]=tcp://cortx-server-headless-svc-${node_name_list[idx]}:21001"
        )
    done

    if ((num_motr_client > 0)); then
        for idx in "${!node_name_list[@]}"; do
            helm_install_args+=(
                --set "cortxMotr.clientEndpoints[${idx}]=tcp://cortx-client-headless-svc-${node_name_list[idx]}:21201"
                --set "cortxHare.haxClientEndpoints[${idx}]=tcp://cortx-client-headless-svc-${node_name_list[idx]}:22001"
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

function pwgen()
{
    # This function generates a random password that is
    # 16 characters long, starts with an alphanumeric
    # character, and contains at least one character each
    # of upper case, lower case, digit, and a special character.

    function choose()
    {
        seqlen=$1
        charset=$2
        # https://unix.stackexchange.com/a/230676
        tr -dc "${charset}" < /dev/urandom | head -c "${seqlen}"
    }

    # Choose an alphanumeric char for the first char of the password
    local first
    first=$(choose 1 '[:alnum:]')

    # Choose one of each of the required fields, plus 11 more
    # characters, and shuffle them
    local rest
    rest=$({
        choose 1 '!@#$%^'
        choose 1 '[:digit:]'
        choose 1 '[:lower:]'
        choose 1 '[:upper:]'
        choose 11 '[:alnum:]!@#$%^'
    } | fold -w1 | shuf | tr -d '\n')

    # Cat the first char plus remaining 15 chars
    printf "%s%s" "${first}" "${rest}"
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
    cortx_secret_name=$(getSolutionValue "solution.secrets.name")
    cortx_secret_ext=$(getSolutionValue "solution.secrets.external_secret")
    if [[ -n "${cortx_secret_name}" ]]; then
        # Process secrets from solution.yaml
        secrets=()
        for field in "${cortx_secret_fields[@]}"; do
            fcontent=$(getSolutionValue "solution.secrets.content.${field}")
            if [[ -z ${fcontent} ]]; then
                # No data for this field.  Generate a password.
                pw=$(pwgen)
                fcontent=${pw}
                printf "Generated secret for %s\n" "${field}"
            fi
            secrets+=( "  ${field}: ${fcontent}" )
        done
        secrets_block=$( printf "%s\n" "${secrets[@]}" )

        new_secret_gen_file="${secret_auto_gen_path}/${cortx_secret_name}.yaml"
        cp "${cfgmap_path}/other/secret-template.yaml" "${new_secret_gen_file}"
        ./parse_scripts/subst.sh "${new_secret_gen_file}" "secret.name" "${cortx_secret_name}"
        ./parse_scripts/subst.sh "${new_secret_gen_file}" "secret.content" "${secrets_block}"
        kubectl_create_secret_cmd="kubectl create -f ${new_secret_gen_file} --namespace=${namespace}"
        if ! ${kubectl_create_secret_cmd}; then
            printf "Exit early.  Failed to create Secret '%s'\n" "${cortx_secret_name}"
            exit 1
        fi

    elif [[ -n "${cortx_secret_ext}" ]]; then
        cortx_secret_name="${cortx_secret_ext}"
        printf "Installing CORTX with existing Secret %s.\n" "${cortx_secret_name}"
    fi

    control_secret_path="./cortx-cloud-helm-pkg/cortx-control/secret-info.txt"
    data_secret_path="./cortx-cloud-helm-pkg/cortx-data/secret-info.txt"
    server_secret_path="./cortx-cloud-helm-pkg/cortx-server/secret-info.txt"
    ha_secret_path="./cortx-cloud-helm-pkg/cortx-ha/secret-info.txt"

    printf "%s" "${cortx_secret_name}" > ${control_secret_path}
    printf "%s" "${cortx_secret_name}" > ${data_secret_path}
    printf "%s" "${cortx_secret_name}" > ${server_secret_path}
    printf "%s" "${cortx_secret_name}" > ${ha_secret_path}

    if [[ ${num_motr_client} -gt 0 ]]; then
        client_secret_path="./cortx-cloud-helm-pkg/cortx-client/secret-info.txt"
        printf "%s" "${cortx_secret_name}" > ${client_secret_path}
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

    START=${SECONDS}
    (while true; do sleep 1; echo -n "."; done)&
    DOTPID=$!
    # expand var now, not later
    # shellcheck disable=SC2064
    trap "silentKill ${DOTPID}" 0

    # Initial wait
    FAIL=0
    if ! kubectl wait --for=condition=available --timeout="${TIMEOUT}" "$@"; then
        # Secondary wait
        if ! kubectl wait --for=condition=available --timeout="${TIMEOUT}" "$@"; then
            # Still timed out.  This is a failure
            FAIL=1
        fi
    fi

    silentKill ${DOTPID}
    trap - 0
    ELAPSED=$((SECONDS - START))
    echo
    if [[ ${FAIL} -eq 0 ]]; then
        echo "Deployment ${DEPL_STR} available after ${ELAPSED} seconds"
    else
        echo "Deployment ${DEPL_STR} timed out after ${ELAPSED} seconds"
    fi
    echo
    return ${FAIL}
}


function deployCortxControl()
{
    printf "########################################################\n"
    printf "# Deploy CORTX Control                                  \n"
    printf "########################################################\n"

    local control_image
    local control_service_type
    local control_service_ports_https
    local control_machineid
    control_image=$(getSolutionValue 'solution.images.cortxcontrol')
    control_service_type=$(getSolutionValue 'solution.common.external_services.control.type')
    control_service_ports_https=$(getSolutionValue 'solution.common.external_services.control.ports.https')
    control_machineid=$(cat "${cfgmap_path}/auto-gen-control-${namespace}/id")

    local optional_values=()
    local control_service_nodeports_https
    control_service_nodeports_https=$(getSolutionValue 'solution.common.external_services.control.nodePorts.https')
    [[ -n ${control_service_nodeports_https} ]] && optional_values+=(--set cortxcontrol.service.loadbal.nodePorts.https="${control_service_nodeports_https}")

    helm install "cortx-control-${namespace}" cortx-cloud-helm-pkg/cortx-control \
        --set cortxcontrol.name="cortx-control" \
        --set cortxcontrol.image="${control_image}" \
        --set cortxcontrol.service.loadbal.name="cortx-control-loadbal-svc" \
        --set cortxcontrol.service.loadbal.type="${control_service_type}" \
        --set cortxcontrol.service.loadbal.ports.https="${control_service_ports_https}" \
        --set cortxcontrol.cfgmap.mountpath="/etc/cortx/solution" \
        --set cortxcontrol.cfgmap.name="cortx-cfgmap-${namespace}" \
        --set cortxcontrol.cfgmap.volmountname="config001" \
        --set cortxcontrol.sslcfgmap.name="cortx-ssl-cert-cfgmap-${namespace}" \
        --set cortxcontrol.sslcfgmap.volmountname="ssl-config001" \
        --set cortxcontrol.sslcfgmap.mountpath="/etc/cortx/solution/ssl" \
        --set cortxcontrol.machineid.value="${control_machineid}" \
        --set cortxcontrol.localpathpvc.name="cortx-control-fs-local-pvc-${namespace}" \
        --set cortxcontrol.localpathpvc.mountpath="${local_storage}" \
        --set cortxcontrol.localpathpvc.requeststoragesize="1Gi" \
        --set cortxcontrol.secretinfo="secret-info.txt" \
        --set cortxcontrol.serviceaccountname="${serviceAccountName}" \
        --set namespace="${namespace}" \
        "${optional_values[@]}" \
        --namespace "${namespace}"

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
    cortxdata_image=$(echo "${cortxdata_image}" | cut -f2 -d'>')

    num_nodes=0
    for i in "${!node_selector_list[@]}"; do
        num_nodes=$((num_nodes+1))
        node_name=${node_name_list[i]}
        node_selector=${node_selector_list[i]}

        cortxdata_machineid=$(cat "${cfgmap_path}/auto-gen-${node_name_list[i]}-${namespace}/data/id")

        helm install "cortx-data-${node_name}-${namespace}" cortx-cloud-helm-pkg/cortx-data \
            --set cortxdata.name="cortx-data-${node_name}" \
            --set cortxdata.image="${cortxdata_image}" \
            --set cortxdata.nodeselector="${node_selector}" \
            --set cortxdata.mountblkinfo="mnt-blk-info.txt" \
            --set cortxdata.nodelistinfo="node-list-info.txt" \
            --set cortxdata.service.clusterip.name="cortx-data-clusterip-svc-${node_name}" \
            --set cortxdata.service.headless.name="cortx-data-headless-svc-${node_name}" \
            --set cortxdata.cfgmap.name="cortx-cfgmap-${namespace}" \
            --set cortxdata.cfgmap.volmountname="config001-${node_name}" \
            --set cortxdata.cfgmap.mountpath="/etc/cortx/solution" \
            --set cortxdata.sslcfgmap.name="cortx-ssl-cert-cfgmap-${namespace}" \
            --set cortxdata.sslcfgmap.volmountname="ssl-config001" \
            --set cortxdata.sslcfgmap.mountpath="/etc/cortx/solution/ssl" \
            --set cortxdata.machineid.value="${cortxdata_machineid}" \
            --set cortxdata.localpathpvc.name="cortx-data-fs-local-pvc-${node_name}" \
            --set cortxdata.localpathpvc.mountpath="${local_storage}" \
            --set cortxdata.localpathpvc.requeststoragesize="1Gi" \
            --set cortxdata.motr.numiosinst=${#cvg_index_list[@]} \
            --set cortxdata.motr.startportnum="$(extractBlock 'solution.common.motr.start_port_num')" \
            --set cortxdata.hax.port="$(extractBlock 'solution.common.hax.port_num')" \
            --set cortxdata.secretinfo="secret-info.txt" \
            --set cortxdata.serviceaccountname="${serviceAccountName}" \
            --set namespace="${namespace}" \
            -n "${namespace}"
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
    local cortxserver_image
    local hax_port
    local s3_num_inst
    local s3_start_port_num
    local s3_service_type
    local s3_service_ports_http
    local s3_service_ports_https
    cortxserver_image=$(getSolutionValue 'solution.images.cortxserver')
    s3_service_type=$(getSolutionValue 'solution.common.external_services.s3.type')
    s3_service_ports_http=$(getSolutionValue 'solution.common.external_services.s3.ports.http')
    s3_service_ports_https=$(getSolutionValue 'solution.common.external_services.s3.ports.https')
    s3_num_inst="$(getSolutionValue 'solution.common.s3.num_inst')"
    s3_start_port_num="$(getSolutionValue 'solution.common.s3.start_port_num')"
    hax_port="$(getSolutionValue 'solution.common.hax.port_num')"

    num_nodes=0
    for i in "${!node_selector_list[@]}"; do
        num_nodes=$((num_nodes+1))
        node_name=${node_name_list[i]}
        node_selector=${node_selector_list[i]}

        cortxserver_machineid=$(cat "${cfgmap_path}/auto-gen-${node_name_list[i]}-${namespace}/server/id")

        helm install "cortx-server-${node_name}-${namespace}" cortx-cloud-helm-pkg/cortx-server \
            --set cortxserver.name="cortx-server-${node_name}" \
            --set cortxserver.image="${cortxserver_image}" \
            --set cortxserver.nodeselector="${node_selector}" \
            --set cortxserver.service.clusterip.name="cortx-server-clusterip-svc-${node_name}" \
            --set cortxserver.service.headless.name="cortx-server-headless-svc-${node_name}" \
            --set cortxserver.service.loadbal.name="cortx-server-loadbal-svc-${node_name}" \
            --set cortxserver.service.loadbal.type="${s3_service_type}" \
            --set cortxserver.service.loadbal.ports.http="${s3_service_ports_http}" \
            --set cortxserver.service.loadbal.ports.https="${s3_service_ports_https}" \
            --set cortxserver.cfgmap.name="cortx-cfgmap-${namespace}" \
            --set cortxserver.cfgmap.volmountname="config001-${node_name}" \
            --set cortxserver.cfgmap.mountpath="/etc/cortx/solution" \
            --set cortxserver.sslcfgmap.name="cortx-ssl-cert-cfgmap-${namespace}" \
            --set cortxserver.sslcfgmap.volmountname="ssl-config001" \
            --set cortxserver.sslcfgmap.mountpath="/etc/cortx/solution/ssl" \
            --set cortxserver.machineid.value="${cortxserver_machineid}" \
            --set cortxserver.localpathpvc.name="cortx-server-fs-local-pvc-${node_name}" \
            --set cortxserver.localpathpvc.mountpath="${local_storage}" \
            --set cortxserver.localpathpvc.requeststoragesize="1Gi" \
            --set cortxserver.s3.numinst="${s3_num_inst}" \
            --set cortxserver.s3.startportnum="${s3_start_port_num}" \
            --set cortxserver.hax.port="${hax_port}" \
            --set cortxserver.secretinfo="secret-info.txt" \
            --set cortxserver.serviceaccountname="${serviceAccountName}" \
            --set namespace="${namespace}" \
            --namespace "${namespace}"
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
    cortxha_image=$(echo "${cortxha_image}" | cut -f2 -d'>')

    cortxha_machineid=$(cat "${cfgmap_path}/auto-gen-ha-${namespace}/id")

    ##TOOD: cortxha.serviceaccountname should extract from solution.yaml ?

    num_nodes=1
    helm install "cortx-ha-${namespace}" cortx-cloud-helm-pkg/cortx-ha \
        --set cortxha.name="cortx-ha" \
        --set cortxha.image="${cortxha_image}" \
        --set cortxha.secretinfo="secret-info.txt" \
        --set cortxha.serviceaccountname="ha-monitor" \
        --set cortxha.service.clusterip.name="cortx-ha-clusterip-svc" \
        --set cortxha.service.headless.name="cortx-ha-headless-svc" \
        --set cortxha.service.loadbal.name="cortx-ha-loadbal-svc" \
        --set cortxha.cfgmap.mountpath="/etc/cortx/solution" \
        --set cortxha.cfgmap.name="cortx-cfgmap-${namespace}" \
        --set cortxha.cfgmap.volmountname="config001" \
        --set cortxha.sslcfgmap.name="cortx-ssl-cert-cfgmap-${namespace}" \
        --set cortxha.sslcfgmap.volmountname="ssl-config001" \
        --set cortxha.sslcfgmap.mountpath="/etc/cortx/solution/ssl" \
        --set cortxha.machineid.value="${cortxha_machineid}" \
        --set cortxha.localpathpvc.name="cortx-ha-fs-local-pvc-${namespace}" \
        --set cortxha.localpathpvc.mountpath="${local_storage}" \
        --set cortxha.localpathpvc.requeststoragesize="1Gi" \
        --set namespace="${namespace}" \
        -n "${namespace}"

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
    cortxclient_image=$(echo "${cortxclient_image}" | cut -f2 -d'>')

    num_nodes=0
    for i in "${!node_selector_list[@]}"; do
        num_nodes=$((num_nodes+1))
        node_name=${node_name_list[i]}
        node_selector=${node_selector_list[i]}

        cortxclient_machineid=$(cat "${cfgmap_path}/auto-gen-${node_name_list[i]}-${namespace}/client/id")

        helm install "cortx-client-${node_name}-${namespace}" cortx-cloud-helm-pkg/cortx-client \
            --set cortxclient.name="cortx-client-${node_name}" \
            --set cortxclient.image="${cortxclient_image}" \
            --set cortxclient.nodeselector="${node_selector}" \
            --set cortxclient.secretinfo="secret-info.txt" \
            --set cortxclient.serviceaccountname="${serviceAccountName}" \
            --set cortxclient.motr.numclientinst="${num_motr_client}" \
            --set cortxclient.service.headless.name="cortx-client-headless-svc-${node_name}" \
            --set cortxclient.cfgmap.name="cortx-cfgmap-${namespace}" \
            --set cortxclient.cfgmap.volmountname="config001-${node_name}" \
            --set cortxclient.cfgmap.mountpath="/etc/cortx/solution" \
            --set cortxclient.sslcfgmap.name="cortx-ssl-cert-cfgmap-${namespace}" \
            --set cortxclient.sslcfgmap.volmountname="ssl-config001" \
            --set cortxclient.sslcfgmap.mountpath="/etc/cortx/solution/ssl" \
            --set cortxclient.machineid.value="${cortxclient_machineid}" \
            --set cortxclient.localpathpvc.name="cortx-client-fs-local-pvc-${node_name}" \
            --set cortxclient.localpathpvc.mountpath="${local_storage}" \
            --set cortxclient.localpathpvc.requeststoragesize="1Gi" \
            --set namespace="${namespace}" \
            -n "${namespace}"
    done

    printf "\nWait for CORTX Client to be ready"
    while true; do
        count=0
        while IFS= read -r line; do
            IFS=" " read -r -a pod_status <<< "${line}"
            IFS="/" read -r -a ready_status <<< "${pod_status[1]}"
            if [[ "${pod_status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
                if [[ "${pod_status[2]}" == "Error" || "${pod_status[2]}" == "Init:Error" ]]; then
                    printf "\n'%s' pod deployment did not complete. Exit early.\n" "${pod_status[0]}"
                    exit 1
                fi
                break
            fi
            count=$((count+1))
        done <<< "$(kubectl get pods --namespace="${namespace}" | grep 'cortx-client-')"

        if [[ ${num_nodes} -eq ${count} ]]; then
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
    find "$(pwd)/cortx-cloud-helm-pkg/cortx-control" -name "secret-*" -delete
    find "$(pwd)/cortx-cloud-helm-pkg/cortx-data" -name "secret-*" -delete
    find "$(pwd)/cortx-cloud-helm-pkg/cortx-server" -name "secret-*" -delete
    find "$(pwd)/cortx-cloud-helm-pkg/cortx-ha" -name "secret-*" -delete
    find "$(pwd)/cortx-cloud-helm-pkg/cortx-client" -name "secret-*" -delete

    rm -rf "${cfgmap_path}/auto-gen-secret-${namespace}"

    find "$(pwd)/cortx-cloud-helm-pkg/cortx-data-blk-data" -name "mnt-blk-*" -delete
    find "$(pwd)/cortx-cloud-helm-pkg/cortx-data-blk-data" -name "node-list-*" -delete
    find "$(pwd)/cortx-cloud-helm-pkg/cortx-data" -name "mnt-blk-*" -delete
    find "$(pwd)/cortx-cloud-helm-pkg/cortx-data" -name "node-list-*" -delete
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
    if [[ "${np}" == "${namespace}" ]]; then
        found_match_nsp=true
        break
    fi
done

# Extract storage provisioner path from the "solution.yaml" file
filter='solution.common.storage_provisioner_path'
parse_storage_prov_output=$(parseSolution ${filter})
# Get the storage provisioner var from the tuple
storage_prov_path=$(echo "${parse_storage_prov_output}" | cut -f2 -d'>')

# Get number of consul replicas and make sure it doesn't exceed the limit
num_consul_replicas=${num_worker_nodes}
if [[ "${num_worker_nodes}" -gt "${max_consul_inst}" ]]; then
    num_consul_replicas=${max_consul_inst}
fi

# Get number of kafka replicas and make sure it doesn't exceed the limit
num_kafka_replicas=${num_worker_nodes}
if [[ "${num_worker_nodes}" -gt "${max_kafka_inst}" ]]; then
    num_kafka_replicas=${max_kafka_inst}
fi

if [[ (${#namespace_list[@]} -le 1 && "${found_match_nsp}" = true) || "${namespace}" == "default" ]]; then
    deployRancherProvisioner
    deployConsul
    deployZookeeper
    deployKafka
    waitForThirdParty
fi

##########################################################
# Deploy CORTX cloud
##########################################################
# Get the storage paths to use
local_storage=$(parseSolution 'solution.common.container_path.local')
local_storage=$(echo "${local_storage}" | cut -f2 -d'>')
shared_storage=$(parseSolution 'solution.common.container_path.shared')
shared_storage=$(echo "${shared_storage}" | cut -f2 -d'>')
log_storage=$(parseSolution 'solution.common.container_path.log')
log_storage=$(echo "${log_storage}" | cut -f2 -d'>')


# Default path to CORTX configmap
cfgmap_path="./cortx-cloud-helm-pkg/cortx-configmap"

cvg_output=$(parseSolution 'solution.storage.cvg*.name')
IFS=';' read -r -a cvg_var_val_array <<< "${cvg_output}"
# Build CVG index list (ex: [cvg1, cvg2, cvg3])
cvg_index_list=[]
count=0
for cvg_var_val_element in "${cvg_var_val_array[@]}"; do
    cvg_name=$(echo "${cvg_var_val_element}" | cut -f2 -d'>')
    cvg_filter=$(echo "${cvg_var_val_element}" | cut -f1 -d'>')
    cvg_index=$(echo "${cvg_filter}" | cut -f3 -d'.')
    cvg_index_list[${count}]=${cvg_index}
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
if [[ ${num_motr_client} -gt 0 ]]; then
    deployCortxClient
fi
cleanup


# Note: It is not ideal that some of these values are hard-coded here.
#       The data comes from the helm charts and so there is no feasible
#       way of getting the values otherwise.
data_service_name="cortx-io-svc-0"  # present in cortx-platform/values.yaml... what to do?
data_service_default_user="$(extractBlock 'solution.common.s3.default_iam_users.auth_admin' || true)"
control_service_name="cortx-control-loadbal-svc"  # hard coded in script above installing help or cortx-control
control_service_default_user="cortxadmin" #hard coded in cortx-configmap/templates/_config.tpl

echo "
-----------------------------------------------------------
The CORTX cluster installation is complete.

The S3 data service is accessible through the ${data_service_name} service.
   Default IAM access key: ${data_service_default_user}
   Default IAM secret key is accessible via:
       kubectl get secrets/${cortx_secret_name} --template={{.data.s3_auth_admin_secret}} | base64 -d

The CORTX control service is accessible through the ${control_service_name} service.
   Default control username: ${control_service_default_user}
   Default control password is accessible via:
       kubectl get secrets/${cortx_secret_name} --template={{.data.csm_mgmt_admin_secret}} | base64 -d
-----------------------------------------------------------
"
