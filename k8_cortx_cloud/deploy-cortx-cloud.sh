#!/usr/bin/env bash

# shellcheck disable=SC2312

# Check required dependencies
if ! ./parse_scripts/check_yq.sh; then
    exit 1
fi

readonly solution_yaml=${1:-'solution.yaml'}
readonly storage_class='local-path'
readonly cfgmap_path="./cortx-cloud-helm-pkg/cortx-configmap"
cortx_secret_fields=("kafka_admin_secret"
                     "consul_admin_secret"
                     "common_admin_secret"
                     "s3_auth_admin_secret"
                     "csm_auth_admin_secret"
                     "csm_mgmt_admin_secret")
readonly cortx_secret_fields

function parseSolution()
{
    ./parse_scripts/parse_yaml.sh "${solution_yaml}" "$1"
}

function extractBlock()
{
    yq ".$1" "${solution_yaml}"
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

buildValues() {
    set -e

    local -r values_file="$1"

    #
    # Values for third-party Charts, and previous cortx-configmap Helm Chart
    #

    # Initialize
    yq --null-input "
        (.global.storageClass, .consul.server.storageClass) = \"${storage_class}\"
        | (.cortxcontrol.localpathpvc.mountpath, .cortxha.localpathpvc.mountpath) = \"${local_storage}\"
        | .configmap.cortxSecretName = \"${cortx_secret_name}\"
        | .cortxcontrol.machineid.value = \"$(cat "${cfgmap_path}/auto-gen-control-${namespace}/id")\"
        | .cortxha.machineid.value = \"$(cat "${cfgmap_path}/auto-gen-ha-${namespace}/id")\""  > "${values_file}"

    # shellcheck disable=SC2016
    yq -i eval-all '
        select(fi==0) ref $to | select(fi==1) ref $from
        | with($to.consul;
            .server *= $from.solution.common.resource_allocation.consul.server
            | .client = $from.solution.common.resource_allocation.consul.client
            | .*.image = $from.solution.images.consul)
        | $to' "${values_file}" "${solution_yaml}"

    yq -i ".consul.server.replicas = ${num_consul_replicas}" "${values_file}"

    # shellcheck disable=SC2016
    yq -i eval-all '
        select(fi==0) ref $to | select(fi==1) ref $from
        | with($to.kafka;
            .image = ($from.solution.images.kafka | capture("(?P<registry>.*?)/(?P<repository>.*):(?P<tag>.*)"))
            | .resources = $from.solution.common.resource_allocation.kafka.resources
            | .persistence.size = $from.solution.common.resource_allocation.kafka.storage_request_size
            | .zookeeper.image = ($from.solution.images.zookeeper | capture("(?P<registry>.*?)/(?P<repository>.*):(?P<tag>.*)"))
            | .zookeeper.resources = $from.solution.common.resource_allocation.zookeeper.resources
            | .zookeeper.persistence.size = $from.solution.common.resource_allocation.zookeeper.storage_request_size)
        | $to' "${values_file}" "${solution_yaml}"

    yq -i "
        with(.kafka; (
            .replicaCount,
            .defaultReplicationFactor,
            .offsetsTopicReplicationFactor,
            .transactionStateLogReplicationFactor,
            .zookeeper.replicaCount) = ${num_kafka_replicas})" "${values_file}"

    # shellcheck disable=SC2016
    yq -i eval-all '
        select(fi==0) ref $to | select(fi==1) ref $from
        | with($to.configmap.cortxRgw;
            .authAdmin = $from.solution.common.s3.default_iam_users.auth_admin
            | .authUser = $from.solution.common.s3.default_iam_users.auth_user
            | .maxStartTimeout = $from.solution.common.s3.max_start_timeout
            | .extraConfiguration = $from.solution.common.s3.extra_configuration)
        | $to' "${values_file}" "${solution_yaml}"

    # shellcheck disable=SC2016
    yq -i eval-all '
        select(fi==0) ref $to | select(fi==1) ref $from
        | $to.configmap.cortxStoragePaths = $from.solution.common.container_path
        | $to' "${values_file}" "${solution_yaml}"

    # shellcheck disable=SC2016
    yq -i eval-all '
        select(fi==0) ref $to | select(fi==1) ref $from
        | $to.configmap.cortxVersion = ($from.solution.images.cortxdata | capture(".*?/.*:(?P<tag>.*)") | .tag)
        | $to' "${values_file}" "${solution_yaml}"

    # shellcheck disable=SC2016
    yq -i eval-all '
        select(fi==0) ref $to | select(fi==1) ref $from
        | $to.configmap.cortxIoService.ports = $from.solution.common.external_services.s3.ports
        | $to' "${values_file}" "${solution_yaml}"

    if [[ ${deployment_type} == "data-only" ]]; then
        yq -i "(
            .configmap.cortxRgw.enabled,
            .cortxha.enabled,
            .cortxcontrol.enabled) = false" "${values_file}"
    fi

    # shellcheck disable=SC2016
    yq -i eval-all '
        select(fi==0) ref $to | select(fi==1) ref $from
        | $to.configmap.cortxMotr.extraConfiguration = $from.solution.common.motr.extra_configuration
        | $to' "${values_file}" "${solution_yaml}"

    for node in "${node_name_list[@]}"; do
        yq -i "
            with(.configmap; (
                .cortxHare.haxDataEndpoints += [\"tcp://cortx-data-headless-svc-${node}:22001\"]
                | .cortxMotr.confdEndpoints += [\"tcp://cortx-data-headless-svc-${node}:22002\"]
                | .cortxMotr.iosEndpoints += [\"tcp://cortx-data-headless-svc-${node}:21001\"]))" "${values_file}"

        if ((num_motr_client > 0)); then
            yq -i "
                .configmap.cortxMotr.clientEndpoints += [\"tcp://cortx-client-headless-svc-${node}:21201\"]
                | .configmap.cortxHare.haxClientEndpoints += [\"tcp://cortx-client-headless-svc-${node}:22001\"]" "${values_file}"
        fi
    done

    ((num_motr_client > 0)) && yq -i ".configmap.cortxMotr.clientInstanceCount = ${num_motr_client}" "${values_file}"

    # shellcheck disable=SC2016
    yq -i eval-all '
        select(fi==0) ref $to | select(fi==1) ref $from | $from.solution.common.storage_sets.name as $name
        | $to.configmap.clusterStorageSets.[$name].durability = $from.solution.common.storage_sets.durability
        | $to' "${values_file}" "${solution_yaml}"

    # UUIDs are selectively enabled based on deployment type
    for type in control ha; do
        local id_path="${cfgmap_path}/auto-gen-${type}-${namespace}/id"
        if [[ -f ${id_path} ]]; then
            yq -i eval-all "
                select(fi==0) ref \$to | select(fi==1).solution.common.storage_sets.name as \$name
                | \$to.configmap.clusterStorageSets.[\$name].${type}Uuid=\"$(< "${id_path}")\"
                | \$to" "${values_file}" "${solution_yaml}"
        fi
    done

    for node in "${node_name_list[@]}"; do
        local auto_gen_path="${cfgmap_path}/auto-gen-${node}-${namespace}"
        for type in data client; do
            local id_path="${auto_gen_path}/${type}/id"
            if [[ -f ${id_path} ]]; then
                yq -i eval-all "
                    select(fi==0) ref \$to | select(fi==1).solution.common.storage_sets.name as \$name
                    | \$to.configmap.clusterStorageSets.[\$name].nodes.${node}.${type}Uuid=\"$(< "${id_path}")\"
                    | \$to" "${values_file}" "${solution_yaml}"
            fi
        done
    done

    # Populate the cluster storage volumes
    for cvg_index in "${cvg_index_list[@]}"; do
        cvg_path="solution.storage.${cvg_index}"
        yq -i eval-all "
            select(fi==0) ref \$to | select(fi==1).${cvg_path} ref \$cvg
            | with(\$to.configmap.clusterStorageVolumes.[\$cvg.name];
                .type = \$cvg.type
                | .metadataDevices = [\$cvg.devices.metadata.device]
                | .dataDevices = [\$cvg.devices.data.d*.device])
            | \$to" "${values_file}" "${solution_yaml}"
    done

    # shellcheck disable=SC2016
    yq -i eval-all '
        select(fi==0) ref $to | select(fi==1) ref $from
        | with($to.configmap;
            .cortxControl.agent.resources           = $from.solution.common.resource_allocation.control.agent.resources
            | .cortxHare.hax.resources              = $from.solution.common.resource_allocation.hare.hax.resources
            | .cortxMotr.motr.resources             = $from.solution.common.resource_allocation.data.motr.resources
            | .cortxMotr.confd.resources            = $from.solution.common.resource_allocation.data.confd.resources
            | .cortxRgw.rgw.resources               = $from.solution.common.resource_allocation.server.rgw.resources)
        | $to' "${values_file}" "${solution_yaml}"

    ## PodSecurityPolicies are Cluster-scoped, so Helm doesn't handle it smoothly
    ## in the same chart as Namespace-scoped objects.
    local podSecurityPolicyName="cortx"
    local createPodSecurityPolicy="true"
    local output
    output=$(kubectl get psp --no-headers ${podSecurityPolicyName} 2>/dev/null | wc -l || true)
    if [[ ${output} == "1" ]]; then
        createPodSecurityPolicy="false"
    fi

    local hax_service_port
    local hax_service_protocol
    local s3_service_type
    local s3_service_ports_http
    local s3_service_ports_https
    hax_service_protocol=$(getSolutionValue 'solution.common.hax.protocol')
    hax_service_port=$(getSolutionValue 'solution.common.hax.port_num')
    s3_service_type=$(getSolutionValue 'solution.common.external_services.s3.type')
    s3_service_count=$(getSolutionValue 'solution.common.external_services.s3.count')
    s3_service_ports_http=$(getSolutionValue 'solution.common.external_services.s3.ports.http')
    s3_service_ports_https=$(getSolutionValue 'solution.common.external_services.s3.ports.https')

    [[ ${deployment_type} == "data-only" ]] && s3_service_count=0

    local s3_service_nodeports_http
    local s3_service_nodeports_https
    s3_service_nodeports_http=$(getSolutionValue 'solution.common.external_services.s3.nodePorts.http')
    s3_service_nodeports_https=$(getSolutionValue 'solution.common.external_services.s3.nodePorts.https')
    [[ -n ${s3_service_nodeports_http} ]] && yq -i ".platform.services.io.nodePorts.http = ${s3_service_nodeports_http}" "${values_file}"
    [[ -n ${s3_service_nodeports_https} ]] && yq -i ".platform.services.io.nodePorts.https = ${s3_service_nodeports_https}" "${values_file}"

    yq -i "
        with(.platform; (
            .podSecurityPolicy.create = ${createPodSecurityPolicy}
            | .services.hax.protocol = \"${hax_service_protocol}\"
            | .services.hax.port = ${hax_service_port}
            | .services.io.type = \"${s3_service_type}\"
            | .services.io.count = ${s3_service_count}
            | .services.io.ports.http = ${s3_service_ports_http}
            | .services.io.ports.https = ${s3_service_ports_https}))" "${values_file}"

    # shellcheck disable=SC2016
    yq -i eval-all '
        select(fi==0) ref $to | select(fi==1) ref $from
        | with($to.cortxcontrol;
            .image                             = $from.solution.images.cortxcontrol
            | .service.loadbal.type            = $from.solution.common.external_services.control.type
            | .service.loadbal.ports.https     = $from.solution.common.external_services.control.ports.https
            | .agent.resources.requests.memory = $from.solution.common.resource_allocation.control.agent.resources.requests.memory
            | .agent.resources.requests.cpu    = $from.solution.common.resource_allocation.control.agent.resources.requests.cpu
            | .agent.resources.limits.memory   = $from.solution.common.resource_allocation.control.agent.resources.limits.memory
            | .agent.resources.limits.cpu      = $from.solution.common.resource_allocation.control.agent.resources.limits.cpu)
        | $to' "${values_file}" "${solution_yaml}"

    local control_service_nodeports_https
    control_service_nodeports_https=$(getSolutionValue 'solution.common.external_services.control.nodePorts.https')
    [[ -n ${control_service_nodeports_https} ]] && yq -i ".cortxcontrol.service.loadbal.nodePorts.https = ${control_service_nodeports_https}" "${values_file}"


    ### TODO CORTX-28968
    local count=0
    for (( count=0; count<${total_server_pods}; count++ )); do
        # Build out FQDN of server pods 
        # StatefulSets create pod names of "{statefulset-name}-{index}", with index starting at 0
        local pod_name="${cortxserver_server_pod_prefix}-${count}"
        local pod_fqdn="${pod_name}.${cortxserver_service_headless_name}.${namespace}.svc.${cluster_domain}"
        ### TODO CORTX-28968 Observe switch below based on setting of Pod hostname
        ### Must match with setting in config-map/_cluster.tpl:84 as well ($serverName)
        # Use below when hostname of pod is only short name
        local md5hash=$(echo -n "${pod_name}" | md5sum | awk '{print $1}')
        # Use below when hostname of pod is fqdn
        # local md5hash=$(echo -n "${pod_fqdn}" | md5sum | awk '{print $1}')
        ### Per https://github.com/Seagate/cortx-prvsnr/pull/6366/files#diff-143c717074b09aed81d7a3fd89a90e273676caf9d68a8d0053f506182188d780R87
        ### cortx-k8s should generate a list item with the following information:
        ### - name: should be able to be pod short name
        ### - hostname: should be fqdn
        ### - id: we initially write this as FQDN and provisioner stores in gconf as md5 hashed version
        ### - type: server_node
        ### Once CORTX-30726 is merged and available, we will no longer have to do any hashing work at the cortx-k8s level

        local storage_set_name=$(yq ".solution.common.storage_sets.name" "${solution_yaml}")

        yq -i "
            .configmap.clusterStorageSets.[\"${storage_set_name}\"].nodes.${pod_name}.serverUuid=\"${md5hash}\"
            | .configmap.cortxMotr.rgwEndpoints += [\"tcp://${pod_fqdn}:21001\"]
            | .configmap.cortxHare.haxServerEndpoints += [\"tcp://${pod_fqdn}:22001\"]" "${values_file}"

    done
    # shellcheck disable=SC2016
    yq -i eval-all '
        select(fi==0) ref $to | select(fi==1) ref $from
        | with($to.cortxha;
            .image                         = $from.solution.images.cortxha
            | .fault_tolerance.resources   = $from.solution.common.resource_allocation.ha.fault_tolerance.resources
            | .health_monitor.resources    = $from.solution.common.resource_allocation.ha.health_monitor.resources
            | .k8s_monitor.resources       = $from.solution.common.resource_allocation.ha.k8s_monitor.resources)
        | $to' "${values_file}" "${solution_yaml}"

    set +e
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

deployment_type=$(getSolutionValue 'solution.deployment_type')
case ${deployment_type} in
    standard|data-only) printf "Deployment type: %s\n" "${deployment_type}" ;;
    *)                  printf "Invalid deployment type '%s'\n" "${deployment_type}" ; exit 1 ;;
esac

printf "\n"

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

##########################################################
# Extract & establish required cluster-wide constants
### TODO CORTX-28968 Define these elements as reasonable defaults in eventual values.yaml
##########################################################

global_cortx_secret_name=""

###TODO CORTX-28968 This can be replaced with yq query
cortxserver_service_headless_name="cortx-server"
readonly cortxserver_service_headless_name

###TODO CORTX-28968 This can be replaced with yq query
cortxserver_server_pod_prefix="cortx-server"
readonly cortxserver_server_pod_prefix

###TODO CORTX-28968 This can be replaced with yq query
cluster_domain="cluster.local"
readonly cluster_domain

###TODO CORTX-28968 This can be replaced with yq query
server_instances_per_node="$(getSolutionValue 'solution.common.s3.instances_per_node')"
data_node_count=${#node_name_list[@]}
total_server_pods=$(( data_node_count * server_instances_per_node ))

readonly server_instances_per_node
readonly data_node_count
readonly total_server_pods

### TODO CORTX-28968 remove below debug statement
echo ""
echo "###########################################################################"
echo "Total Server Pods: ${total_server_pods}"
echo "###########################################################################"
echo ""

##########################################################
# Begin CORTX on k8s deployment
##########################################################

##########################################################
# Deploy CORTX k8s pre-reqs
##########################################################
function deployKubernetesPrereqs()
{
    # Add Helm repository dependencies
    helm repo add hashicorp https://helm.releases.hashicorp.com
    helm repo add bitnami https://charts.bitnami.com/bitnami

    # Installing a chart from the filesystem requires fetching the dependencies
    helm dependency build ../charts/cortx
}


##########################################################
# Deploy CORTX 3rd party
##########################################################
function deployRancherProvisioner()
{
    local image

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

        kubectl apply -f "${rancher_prov_file}"
    fi
}

function deployCortx()
{
    printf "######################################################\n"
    printf "# Deploy CORTX                                        \n"
    printf "######################################################\n"

    local -r values_file=cortx-values.yaml

    # Due to large number of options being set, we generate a values.yaml
    # file for Helm, instead of passing in each option with `--set`.
    buildValues ${values_file}

    helm install cortx ../charts/cortx \
        -f ${values_file} \
        --namespace "${namespace}" \
        --create-namespace \
        --wait \
        || exit $?

    # Restarting Consul at this time causes havoc. Disabling this for now until
    # Consul supports configuring automountServiceAccountToken (a PR is planned
    # to add support).

    # # Patch generated ServiceAccounts to prevent automounting ServiceAccount tokens
    # kubectl patch serviceaccount/cortx-consul-client \
    #     -p '{"automountServiceAccountToken": false}' \
    #     --namespace "${namespace}"
    # kubectl patch serviceaccount/cortx-consul-server \
    #     -p '{"automountServiceAccountToken": false}' \
    #     --namespace "${namespace}"

    # # Rollout a new deployment version of Consul pods to use updated Service Account settings
    # kubectl rollout restart statefulset/cortx-consul-server --namespace "${namespace}"
    # kubectl rollout restart daemonset/cortx-consul-client --namespace "${namespace}"

    # ##TODO This needs to be maintained during upgrades etc...
}

function waitForThirdParty()
{
    printf "\nWait for CORTX 3rd party to be ready"
    while true; do
        count=0
        while IFS= read -r line; do
            IFS=" " read -r -a pod_status <<< "${line}"
            IFS="/" read -r ready total <<< "${pod_status[1]}"
            if [[ "${pod_status[2]}" != "Running" || "${ready}" != "${total}" ]]; then
                count=$((count+1))
                break
            fi
        done <<< "$(kubectl get pods --namespace="${namespace}" --no-headers | grep '^cortx-consul\|^cortx-kafka\|^cortx-zookeeper')"

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
        --namespace "${namespace}" \
        --create-namespace \
        || exit $?
}

function deleteStaleAutoGenFolders()
{
    # Delete all stale auto gen folders
    for gen in \
        auto-gen-cfgmap \
        auto-gen-control \
        auto-gen-ha \
        auto-gen-secret \
        node-info \
        storage-info; do
        rm -rf "$(pwd)/cortx-cloud-helm-pkg/cortx-configmap/${gen}-${namespace}"
    done
    for node_name in "${node_name_list[@]}"; do
        rm -rf "$(pwd)/cortx-cloud-helm-pkg/cortx-configmap/auto-gen-${node_name}-${namespace}"
    done
}

function generateMachineId()
{
    local uuid
    uuid="$(uuidgen --random)"
    echo "${uuid//-}"
}

function generateMachineIds()
{
    printf "########################################################\n"
    printf "# Generating CORTX Pod Machine IDs                      \n"
    printf "########################################################\n"

    local id_paths=()

    if [[ ${deployment_type} != "data-only" ]]; then
        id_paths+=(
            "${cfgmap_path}/auto-gen-control-${namespace}"
            "${cfgmap_path}/auto-gen-ha-${namespace}"
        )
    fi

    for node in "${node_name_list[@]}"; do
        local auto_gen_path="${cfgmap_path}/auto-gen-${node}-${namespace}"

        id_paths+=("${auto_gen_path}/data")
        ((num_motr_client > 0)) && id_paths+=("${auto_gen_path}/client")
    done

    for path in "${id_paths[@]}"; do
        mkdir -p "${path}"
        generateMachineId > "${path}/id"
    done
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
    # Parse secret from the solution file and create all secret files
    # in the "auto-gen-secret" folder
    local secret_auto_gen_path="${cfgmap_path}/auto-gen-secret-${namespace}"
    mkdir -p "${secret_auto_gen_path}"
    cortx_secret_name=$(getSolutionValue "solution.secrets.name")  # This is a global variable
    if [[ -n "${cortx_secret_name}" ]]; then
        # Process secrets from solution.yaml
        for field in "${cortx_secret_fields[@]}"; do
            fcontent=$(getSolutionValue "solution.secrets.content.${field}")
            if [[ -z ${fcontent} ]]; then
                # No data for this field.  Generate a password.
                fcontent=$(pwgen)
                printf "Generated secret for %s\n" "${field}"
            fi
            printf "%s" "${fcontent}" > "${secret_auto_gen_path}/${field}"
        done

        if ! kubectl create secret generic "${cortx_secret_name}" \
            --from-file="${secret_auto_gen_path}" \
            --namespace="${namespace}"; then
            printf "Exit early.  Failed to create Secret '%s'\n" "${cortx_secret_name}"
            exit 1
        fi
    else
        cortx_secret_name="$(getSolutionValue "solution.secrets.external_secret")"
        printf "Installing CORTX with existing Secret %s.\n" "${cortx_secret_name}"
    fi

    global_cortx_secret_name="${cortx_secret_name}"
    data_secret_path="./cortx-cloud-helm-pkg/cortx-data/secret-info.txt"
    printf "%s" "${cortx_secret_name}" > ${data_secret_path}

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
    NAMESPACE=$1
    shift

    START=${SECONDS}
    (while true; do sleep 1; echo -n "."; done)&
    DOTPID=$!
    # expand var now, not later
    # shellcheck disable=SC2064
    trap "silentKill ${DOTPID}" 0

    # Initial wait
    FAIL=0

    ### CORTX-28968 - moved from `kubectl wait` to `kubectl rollout status` in support of StatefulSets
    if ! kubectl rollout status --watch --timeout="${TIMEOUT}" -n "${NAMESPACE}" "$@"; then
        # Secondary wait
        if ! kubectl rollout status --watch --timeout="${TIMEOUT}" -n "${NAMESPACE}" "$@"; then
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
            --set cortxdata.service.clusterip.name="cortx-data-clusterip-svc-${node_name}" \
            --set cortxdata.service.headless.name="cortx-data-headless-svc-${node_name}" \
            --set cortxdata.cfgmap.volmountname="config001-${node_name}" \
            --set cortxdata.machineid.value="${cortxdata_machineid}" \
            --set cortxdata.localpathpvc.name="cortx-data-fs-local-pvc-${node_name}" \
            --set cortxdata.localpathpvc.mountpath="${local_storage}" \
            --set cortxdata.motr.numiosinst=${#cvg_index_list[@]} \
            --set cortxdata.motr.startportnum="$(extractBlock 'solution.common.motr.start_port_num')" \
            --set cortxdata.hax.port="$(extractBlock 'solution.common.hax.port_num')" \
            --set cortxdata.motr.resources.requests.memory="$(extractBlock 'solution.common.resource_allocation.data.motr.resources.requests.memory')" \
            --set cortxdata.motr.resources.requests.cpu="$(extractBlock 'solution.common.resource_allocation.data.motr.resources.requests.cpu')" \
            --set cortxdata.motr.resources.limits.memory="$(extractBlock 'solution.common.resource_allocation.data.motr.resources.limits.memory')" \
            --set cortxdata.motr.resources.limits.cpu="$(extractBlock 'solution.common.resource_allocation.data.motr.resources.limits.cpu')" \
            --set cortxdata.confd.resources.requests.memory="$(extractBlock 'solution.common.resource_allocation.data.confd.resources.requests.memory')" \
            --set cortxdata.confd.resources.requests.cpu="$(extractBlock 'solution.common.resource_allocation.data.confd.resources.requests.cpu')" \
            --set cortxdata.confd.resources.limits.memory="$(extractBlock 'solution.common.resource_allocation.data.confd.resources.limits.memory')" \
            --set cortxdata.confd.resources.limits.cpu="$(extractBlock 'solution.common.resource_allocation.data.confd.resources.limits.cpu')" \
            --set cortxdata.hax.resources.requests.memory="$(extractBlock 'solution.common.resource_allocation.hare.hax.resources.requests.memory')" \
            --set cortxdata.hax.resources.requests.cpu="$(extractBlock 'solution.common.resource_allocation.hare.hax.resources.requests.cpu')" \
            --set cortxdata.hax.resources.limits.memory="$(extractBlock 'solution.common.resource_allocation.hare.hax.resources.limits.memory')" \
            --set cortxdata.hax.resources.limits.cpu="$(extractBlock 'solution.common.resource_allocation.hare.hax.resources.limits.cpu')" \
            -n "${namespace}" \
            || exit $?
    done

    # Wait for all cortx-data deployments to be ready
    printf "\nWait for CORTX Data to be ready"
    ### TODO CORTX-28968 revisit for clarity once implemented
    ### Cannot pass list of items to `rollout status`; it only works on a single item
    ### However, these independent waits can most likely be removed.
    ### Investigate further.
    #local deployments=()
    #for i in "${!node_selector_list[@]}"; do
    #    deployments+=("deployment/cortx-data-${node_name_list[i]}")
    #done
    #if ! waitForAllDeploymentsAvailable "${CORTX_DEPLOY_DATA_TIMEOUT:-300s}" \
    #                                    "CORTX Data" "${namespace}" \
    #                                    "${deployments[@]}"; then
    #    echo "Failed.  Exiting script."
    #    exit 1
    #fi

    printf "\n\n"
}


function deployCortxServer()
{
    if [[ ${deployment_type} == "data-only" ]]; then
        return
    fi

    printf "########################################################\n"
    printf "# Deploy CORTX Server                                   \n"
    printf "########################################################\n"
    local cortxserver_image
    local hax_port
    local s3_service_type
    local s3_service_ports_http
    local s3_service_ports_https
    cortxserver_image=$(getSolutionValue 'solution.images.cortxserver')
    s3_service_type=$(getSolutionValue 'solution.common.external_services.s3.type')
    s3_service_ports_http=$(getSolutionValue 'solution.common.external_services.s3.ports.http')
    s3_service_ports_https=$(getSolutionValue 'solution.common.external_services.s3.ports.https')
    hax_port="$(getSolutionValue 'solution.common.hax.port_num')"

    helm install "cortx-server-${namespace}" cortx-cloud-helm-pkg/cortx-server \
        --set cortxserver.image="${cortxserver_image}" \
        --set cortxserver.replicas="${total_server_pods}" \
        --set cortxserver.service.headless.name="${cortxserver_service_headless_name}" \
        --set cortxserver.service.loadbal.type="${s3_service_type}" \
        --set cortxserver.service.loadbal.ports.http="${s3_service_ports_http}" \
        --set cortxserver.service.loadbal.ports.https="${s3_service_ports_https}" \
        --set cortxserver.cfgmap.volmountname="config001-${node_name}" \
        --set cortxserver.localpathpvc.name="cortx-server-fs-local-pvc-${node_name}" \
        --set cortxserver.localpathpvc.mountpath="${local_storage}" \
        --set cortxserver.hax.port="${hax_port}" \
        --set cortxserver.secretname="${global_cortx_secret_name}" \
        --set cortxserver.serviceaccountname="${serviceAccountName}" \
        --set cortxserver.rgw.resources.requests.memory="$(extractBlock 'solution.common.resource_allocation.server.rgw.resources.requests.memory')" \
        --set cortxserver.rgw.resources.requests.cpu="$(extractBlock 'solution.common.resource_allocation.server.rgw.resources.requests.cpu')" \
        --set cortxserver.rgw.resources.limits.memory="$(extractBlock 'solution.common.resource_allocation.server.rgw.resources.limits.memory')" \
        --set cortxserver.rgw.resources.limits.cpu="$(extractBlock 'solution.common.resource_allocation.server.rgw.resources.limits.cpu')" \
        --set cortxserver.hax.resources.requests.memory="$(extractBlock 'solution.common.resource_allocation.hare.hax.resources.requests.memory')" \
        --set cortxserver.hax.resources.requests.cpu="$(extractBlock 'solution.common.resource_allocation.hare.hax.resources.requests.cpu')" \
        --set cortxserver.hax.resources.limits.memory="$(extractBlock 'solution.common.resource_allocation.hare.hax.resources.limits.memory')" \
        --set cortxserver.hax.resources.limits.cpu="$(extractBlock 'solution.common.resource_allocation.hare.hax.resources.limits.cpu')" \
        --namespace "${namespace}" \
        || exit $?

    printf "\nWait for CORTX Server to be ready\n"
    # Wait for all cortx-data deployments to be ready
    if ! waitForAllDeploymentsAvailable "${CORTX_DEPLOY_SERVER_TIMEOUT:-300s}" \
                                        "CORTX Server" "${namespace}" \
                                        "statefulset/cortx-server"; then

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
            --set cortxclient.motr.numclientinst="${num_motr_client}" \
            --set cortxclient.service.headless.name="cortx-client-headless-svc-${node_name}" \
            --set cortxclient.cfgmap.volmountname="config001-${node_name}" \
            --set cortxclient.machineid.value="${cortxclient_machineid}" \
            --set cortxclient.localpathpvc.name="cortx-client-fs-local-pvc-${node_name}" \
            --set cortxclient.localpathpvc.mountpath="${local_storage}" \
            -n "${namespace}" \
            || exit $?
    done

    printf "\nWait for CORTX Client to be ready\n"
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
    # Delete files that contain disk partitions on the worker nodes and the node info
    # and left-over secret data
    find "$(pwd)/cortx-cloud-helm-pkg" -type f \( -name 'mnt-blk-*' -o -name 'node-list-*' -o -name secret-info.txt \) -delete

    # Delete left-over machine IDs and any other auto-gen data
    rm -rf "${cfgmap_path}"
}

# Extract storage provisioner path from the "solution.yaml" file
storage_prov_path=$(parseSolution solution.common.storage_provisioner_path | cut -f2 -d'>')

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

# Get the storage paths to use
local_storage=$(parseSolution 'solution.common.container_path.local' | cut -f2 -d'>')
readonly local_storage

cvg_output=$(parseSolution 'solution.storage.cvg*.name')
IFS=';' read -r -a cvg_var_val_array <<< "${cvg_output}"
# Build CVG index list (ex: [cvg1, cvg2, cvg3])
cvg_index_list=[]
count=0
for cvg_var_val_element in "${cvg_var_val_array[@]}"; do
    cvg_filter=$(echo "${cvg_var_val_element}" | cut -f1 -d'>')
    cvg_index=$(echo "${cvg_filter}" | cut -f3 -d'.')
    cvg_index_list[${count}]=${cvg_index}
    count=$((count+1))
done

num_motr_client=$(extractBlock 'solution.common.motr.num_client_inst')

##########################################################
# Deploy CORTX cloud pre-requisites
##########################################################
deleteStaleAutoGenFolders
deployKubernetesPrereqs
deployRancherProvisioner
deployCortxLocalBlockStorage
deployCortxSecrets
generateMachineIds

##########################################################
# Deploy CORTX cloud
##########################################################
deployCortx
waitForThirdParty
deployCortxData
deployCortxServer
if [[ ${num_motr_client} -gt 0 ]]; then
    deployCortxClient
fi
cleanup

# Note: It is not ideal that some of these values are hard-coded here.
#       The data comes from the helm charts and so there is no feasible
#       way of getting the values otherwise.
data_service_name="cortx-io-svc-0"  # present in cortx values.yaml... what to do?
data_service_default_user="$(extractBlock 'solution.common.s3.default_iam_users.auth_admin' || true)"
control_service_name="cortx-control-loadbal-svc"  # hard coded in script above installing help or cortx-control
control_service_default_user="cortxadmin" #hard coded in cortx-configmap/templates/_config.tpl

echo "
-----------------------------------------------------------

The CORTX cluster installation is complete."

if [[ ${deployment_type} != "data-only" ]]; then
    echo "
The S3 data service is accessible through the ${data_service_name} service.
   Default IAM access key: ${data_service_default_user}
   Default IAM secret key is accessible via:
       kubectl get secrets/${cortx_secret_name} --namespace ${namespace} \\
                  --template={{.data.s3_auth_admin_secret}} | base64 -d

The CORTX control service is accessible through the ${control_service_name} service.
   Default control username: ${control_service_default_user}
   Default control password is accessible via:
       kubectl get secrets/${cortx_secret_name} --namespace ${namespace} \\
                  --template={{.data.csm_mgmt_admin_secret}} | base64 -d"
fi

printf "\n-----------------------------------------------------------\n"
