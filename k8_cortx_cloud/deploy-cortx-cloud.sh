#!/usr/bin/env bash

# shellcheck disable=SC2312

# Check required dependencies
if ! ./parse_scripts/check_yq.sh; then
    exit 1
fi

readonly solution_yaml=${1:-'solution.yaml'}
readonly cfgmap_path="./cortx-cloud-helm-pkg/cortx-configmap"
cortx_secret_fields=("kafka_admin_secret"
                     "consul_admin_secret"
                     "common_admin_secret"
                     "s3_auth_admin_secret"
                     "csm_auth_admin_secret"
                     "csm_mgmt_admin_secret")
readonly cortx_secret_fields

# Enabled/disabled flags for components
declare -A components

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

    # The deployment type determines which components are enabled
    components=(
        [client]=true
        [control]=true
        [data]=true
        [ha]=true
        [server]=true
    )

    local deployment_type
    deployment_type=$(getSolutionValue 'solution.deployment_type')
    case ${deployment_type} in
        standard)
            printf "Deployment type: %s\n" "${deployment_type}"
            ;;

        data-only)
            printf "Deployment type: %s\n" "${deployment_type}"
            for c in control ha server; do
                components["${c}"]=false
            done
            ;;

        *)
            printf "Invalid deployment type '%s'\n" "${deployment_type}"
            exit 1
            ;;
    esac

    ((num_motr_client < 1)) && components[client]=false

    readonly components

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
    set -eu

    local -r values_file="$1"

    #
    # Values for third-party Charts, and previous cortx-configmap Helm Chart
    #

    # Initialize
    yq --null-input "
        (.global.storageClass, .consul.server.storageClass) = \"local-path\"
        | (.cortxcontrol.localpathpvc.mountpath,
           .cortxha.localpathpvc.mountpath,
           .cortxserver.localpathpvc.mountpath) = \"${local_storage}\"
        | .configmap.cortxSecretName = \"${cortx_secret_name}\"" > "${values_file}"

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
        | with($to.cortxserver;
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

    yq -i "
        .cortxserver.enabled = ${components[server]}
        | .cortxha.enabled = ${components[ha]}
        | .cortxcontrol.enabled = ${components[control]}" "${values_file}"

    # shellcheck disable=SC2016
    yq -i eval-all '
        select(fi==0) ref $to | select(fi==1) ref $from
        | $to.configmap.cortxMotr.extraConfiguration = $from.solution.common.motr.extra_configuration
        | $to' "${values_file}" "${solution_yaml}"

    for node in "${node_name_list[@]}"; do
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

    local uuid

    # UUIDs are selectively enabled based on deployment type
    for c in control ha; do
        if [[ ${components["${c}"]} == true ]]; then
            uuid=$(< "${cfgmap_path}/auto-gen-${c}-${namespace}/id")
            yq -i ".cortx${c}.machineid.value = \"${uuid}\"" "${values_file}"
            yq -i eval-all "
                select(fi==0) ref \$to | select(fi==1).solution.common.storage_sets.name as \$name
                | \$to.configmap.clusterStorageSets.[\$name].${c}Uuid=\"${uuid}\"
                | \$to" "${values_file}" "${solution_yaml}"
        fi
    done

    if [[ ${components["client"]} == true ]]; then
        for node in "${node_name_list[@]}"; do
            uuid=$(< "${cfgmap_path}/auto-gen-${node}-${namespace}/client/id")
            yq -i eval-all "
                select(fi==0) ref \$to | select(fi==1).solution.common.storage_sets.name as \$name
                | \$to.configmap.clusterStorageSets.[\$name].nodes.${node}.clientUuid=\"${uuid}\"
                | \$to" "${values_file}" "${solution_yaml}"
        done
    fi

    ## cortx-data Pods, managed by a StatefulSet, have deterministically
    ## generated metadata. Inject that metadata into the ConfigMap here.
    ## During Helm Chart unification, this block can be interned into
    ## Helm logic.
    local count
    local storage_set_name
    storage_set_name=$(yq ".solution.common.storage_sets.name" "${solution_yaml}")
    for (( count=0; count < data_node_count; count++ )); do
        # Build out FQDN of cortx-data Pods
        # StatefulSets create pod names of "{statefulset-name}-{index}", with index starting at 0
        local pod_name="${cortxdata_data_pod_prefix}-${count}"
        local pod_fqdn="${pod_name}.${cortxdata_service_headless_name}.${namespace}.svc.${cluster_domain}"

        ### cortx-k8s should generate a list item with the following information:
        ### - name: Pod short name
        ### - hostname: Pod FQDN
        ### - id: Initially write this as FQDN and Provisioner stores in gconf as md5-hashed version
        ### - type: "server_node"

        ### TODO CORTX-29861 Parameterize port names for dynamic Motr endpoint generation
        yq -i "
            with(.configmap; (
            .clusterStorageSets.[\"${storage_set_name}\"].nodes.${pod_name}.dataUuid=\"${pod_fqdn}\"
            | .cortxHare.haxDataEndpoints += [\"tcp://${pod_fqdn}:22001\"]
            | .cortxMotr.confdEndpoints += [\"tcp://${pod_fqdn}:22002\"]
            | .cortxMotr.iosEndpoints += [\"tcp://${pod_fqdn}:21001\"]))" "${values_file}"
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
            | .cortxMotr.confd.resources            = $from.solution.common.resource_allocation.data.confd.resources)
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

    local s3_service_nodeports_http
    local s3_service_nodeports_https
    s3_service_nodeports_http=$(getSolutionValue 'solution.common.external_services.s3.nodePorts.http')
    s3_service_nodeports_https=$(getSolutionValue 'solution.common.external_services.s3.nodePorts.https')
    [[ -n ${s3_service_nodeports_http} ]] && yq -i ".cortxserver.service.nodePorts.http = ${s3_service_nodeports_http}" "${values_file}"
    [[ -n ${s3_service_nodeports_https} ]] && yq -i ".cortxserver.service.nodePorts.https = ${s3_service_nodeports_https}" "${values_file}"

    yq -i "
        with(.platform; (
            .podSecurityPolicy.create = ${createPodSecurityPolicy}
            | .services.hax.protocol = \"${hax_service_protocol}\"
            | .services.hax.port = ${hax_service_port}))
        | with(.cortxserver.service; (
            .type = \"${s3_service_type}\"
            | .count = ${s3_service_count}
            | .ports.http = ${s3_service_ports_http}
            | .ports.https = ${s3_service_ports_https}))" "${values_file}"

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

    ## cortx-server Pods, managed by a StatefulSet, have deterministically
    ## generated metadata. Inject that metadata into the ConfigMap here.
    ## During Helm Chart unification, this block can be interned into
    ## Helm logic.
    local count
    local storage_set_name
    storage_set_name=$(yq ".solution.common.storage_sets.name" "${solution_yaml}")
    for (( count=0; count < total_server_pods; count++ )); do
        # Build out FQDN of cortx-server Pods
        # StatefulSets create pod names of "{statefulset-name}-{index}", with index starting at 0
        local pod_name="cortx-server-${count}"
        local pod_fqdn="${pod_name}.cortx-server-headless.${namespace}.svc.cluster.local"

        ### cortx-k8s should generate a list item with the following information:
        ### - name: Pod short name
        ### - hostname: Pod FQDN
        ### - id: Initially write this as FQDN and Provisioner stores in gconf as md5-hashed version
        ### - type: "server_node"

        ### TODO CORTX-29861 Parameterize port names for dynamic Motr endpoint generation (28968 F/UP)

        yq -i "
            .configmap.clusterStorageSets.[\"${storage_set_name}\"].nodes.${pod_name}.serverUuid=\"${pod_fqdn}\"
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

    # shellcheck disable=SC2016
    yq -i eval-all '
        select(fi==0) ref $to | select(fi==1) ref $from
        | with($to.cortxserver;
            .image           = $from.solution.images.cortxserver
            | .cfgmap.volmountname = "config001"
            | .hax.port      = $from.solution.common.hax.port_num
            | .rgw.resources = $from.solution.common.resource_allocation.server.rgw.resources
            | .hax.resources = $from.solution.common.resource_allocation.hare.hax.resources)
        | $to' "${values_file}" "${solution_yaml}"

    yq -i ".cortxserver.replicas = ${total_server_pods}" "${values_file}"

    set +eu
}

num_motr_client=$(extractBlock 'solution.common.motr.num_client_inst')

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

# Create arrays of node short names and node FQDNs
node_name_list=[] # short version. Ex: ssc-vm-g3-rhev4-1490
node_selector_list=[] # long version. Ex: ssc-vm-g3-rhev4-1490.colo.seagate.com
count=0

for var_val_element in "${parsed_var_val_array[@]}"
do
    node_name=$(echo "${var_val_element}" | cut -f2 -d'>')
    node_selector_list[count]=${node_name}
    shorter_node_name=$(echo "${node_name}" | cut -f1 -d'.')
    node_name_list[count]=${shorter_node_name}
    count=$((count+1))
done

##########################################################
# Extract & establish required cluster-wide constants
##########################################################

## This is currently required as part of CORTX-28968 et al for cross-Chart synchronization.
## Once Helm Charts are unified, these will become defaulted values.yaml properties.
default_values_file="../charts/cortx/values.yaml"

cortxdata_service_headless_name=$(yq ".configmap.cortxMotr.headlessServiceName" "${default_values_file}")
readonly cortxdata_service_headless_name

cortxdata_data_pod_prefix=$(yq ".configmap.cortxMotr.statefulSetName" "${default_values_file}")
readonly cortxdata_data_pod_prefix

cortx_localblockstorage_storageclassname=$(yq ".platform.storage.localBlock.storageClassName" "${default_values_file}")
readonly cortx_localblockstorage_storageclassname

cluster_domain=$(yq ".configmap.clusterDomain" "${default_values_file}")
readonly cluster_domain

server_instances_per_node=$(yq ".solution.common.s3.instances_per_node" "${solution_yaml}")
data_node_count=${#node_name_list[@]}
total_server_pods=$(( data_node_count * server_instances_per_node ))

readonly server_instances_per_node
readonly data_node_count
readonly total_server_pods

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

##########################################################
# CORTX cloud deploy functions
##########################################################
function deployCortxLocalBlockStorage()
{
    printf "######################################################\n"
    printf "# Deploy CORTX Local Block Storage                    \n"
    printf "######################################################\n"

    local -r cortx_block_data_values_file=cortx-block-data-values.yaml

    yq --null-input "
        .cortxblkdata.storageClassName=\"${cortx_localblockstorage_storageclassname}\"
        "  > "${cortx_block_data_values_file}"

    # shellcheck disable=SC2016
    yq -i eval-all '
        select(fi==0) ref $to | select(fi==1) ref $from
        | with($to.cortxblkdata;
            .nodes                             = [$from.solution.nodes.*.name]
            | .blockDevicePaths                = [$from.solution.storage.*.devices.data.*]
            | .blockDevicePaths                += [$from.solution.storage.*.devices.metadata])
        | $to' "${cortx_block_data_values_file}" "${solution_yaml}"

    helm install "cortx-data-blk-data-${namespace}" cortx-cloud-helm-pkg/cortx-data-blk-data \
        -f ${cortx_block_data_values_file} \
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

    for c in control ha; do
        [[ ${components["${c}"]} == true ]] && id_paths+=("${cfgmap_path}/auto-gen-${c}-${namespace}")
    done

    for c in client data; do
        if [[ ${components["${c}"]} == true ]]; then
            for node in "${node_name_list[@]}"; do
                 id_paths+=("${cfgmap_path}/auto-gen-${node}-${namespace}/${c}")
            done
        fi
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
    local timeout=$1
    local resource=$2

    local -i rc=0
    local -i start=${SECONDS}
    kubectl rollout status --watch --timeout="${timeout}" --namespace "${namespace}" "${resource}" || rc=$?
    local -i elapsed=$((SECONDS - start))

    if ((rc == 0)); then
        echo "Rollout of ${resource} finished after ${elapsed} seconds"
    else
        echo "ERROR: Rollout of ${resource} timed out after ${elapsed} seconds"
    fi

    return ${rc}
}

function deployCortxData()
{
    [[ ${components[data]} == false ]] && return

    printf "########################################################\n"
    printf "# Deploy CORTX Data                                     \n"
    printf "########################################################\n"
    cortxdata_image=$(parseSolution 'solution.images.cortxdata')
    cortxdata_image=$(echo "${cortxdata_image}" | cut -f2 -d'>')

    ### TODO CORTX-29861 Determine how we want to sub-select nominated nodes for Data Pod scheduling.
    ### 1. Should we apply the labels through this script?
    ### 2. Should we required the labels to be applied prior to execution of this script?
    ### 3. Should we use a nodeSelector that uses the "in"/set operators?

    local -r cortx_data_values_file=cortx-data-values.yaml

    yq --null-input "
        .cortxdata.replicas=\"${data_node_count}\"
        "  > "${cortx_data_values_file}"

    # shellcheck disable=SC2016
    yq -i eval-all '
        select(fi==0) ref $to | select(fi==1) ref $from
        | with($to.cortxdata;
            .nodes                             = [$from.solution.nodes.*.name]
            | .blockDevicePaths                = [$from.solution.storage.*.devices.data.*]
            | .blockDevicePaths                += [$from.solution.storage.*.devices.metadata])
        | $to' "${cortx_data_values_file}" "${solution_yaml}"

    # shellcheck disable=SC2016
    yq -i eval-all '
        select(fi==0) ref $to | select(fi==1) ref $from
        | with($to.cortxdata;
             .hax.resources              = $from.solution.common.resource_allocation.hare.hax.resources
            | .motr.resources             = $from.solution.common.resource_allocation.data.motr.resources
            | .confd.resources            = $from.solution.common.resource_allocation.data.confd.resources)
        | $to' "${cortx_data_values_file}" "${solution_yaml}"

    helm install "cortx-data-${namespace}" cortx-cloud-helm-pkg/cortx-data \
        -f ${cortx_data_values_file} \
        --set cortxdata.image="${cortxdata_image}" \
        --set cortxdata.storageClassName="${cortx_localblockstorage_storageclassname}" \
        --set cortxdata.service.headless.name="${cortxdata_service_headless_name}" \
        --set cortxdata.localpathpvc.mountpath="${local_storage}" \
        --set cortxdata.hax.port="$(extractBlock 'solution.common.hax.port_num')" \
        --set cortxdata.secretname="${global_cortx_secret_name}" \
        --set cortxdata.motr.numiosinst=${#cvg_index_list[@]} \
        -n "${namespace}" \
        || exit $?

    printf "\n\n"
}

function deployCortxClient()
{
    [[ ${components[client]} == false ]] && return

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
}

function cleanup()
{
    # DEPRECATED: These files are no longer used during deploy, but the cleanup step is left behind
    # to clean up as much as possible going forward.
    # Delete files that contain disk partitions on the worker nodes and the node info
    # and left-over secret data
    find "$(pwd)/cortx-cloud-helm-pkg" -type f \( -name 'mnt-blk-*' -o -name 'node-list-*' -o -name secret-info.txt \) -delete

    # Delete left-over machine IDs and any other auto-gen data
    rm -rf "${cfgmap_path}"
}

function killBackgroundJobs() {
    printf "\nCtrl-C was detected, quitting now..."
    for pid in $(jobs -p); do
        # A job may quit by the time we try to kill it, so filter out error messages
        kill -TERM "${pid}" 2>/dev/null
    done
    exit 2
}

function waitForClusterReady()
{
    set -u

    printf "Now waiting for all CORTX resources to become available, press Ctrl-C to quit...\n\n"

    trap killBackgroundJobs INT

    local pids=()

    if [[ ${components[control]} == true ]]; then
        (waitForAllDeploymentsAvailable "${CORTX_DEPLOY_CONTROL_TIMEOUT:-10m}" deployment/cortx-control) &
        pids+=($!)
    fi

    if [[ ${components[ha]} == true ]]; then
        (waitForAllDeploymentsAvailable "${CORTX_DEPLOY_HA_TIMEOUT:-4m}" deployment/cortx-ha) &
        pids+=($!)
    fi

    if [[ ${components[data]} == true ]]; then
        (waitForAllDeploymentsAvailable "${CORTX_DEPLOY_DATA_TIMEOUT:-10m}" "statefulset/cortx-data") &
        pids+=($!)
    fi

    if [[ ${components[server]} == true ]]; then
        (waitForAllDeploymentsAvailable "${CORTX_DEPLOY_SERVER_TIMEOUT:-10m}" statefulset/cortx-server) &
        pids+=($!)
    fi

    if [[ ${components[client]} == true ]]; then
        for node in "${node_name_list[@]}"; do
            (waitForAllDeploymentsAvailable "${CORTX_DEPLOY_CLIENT_TIMEOUT:-10m}" "deployment/cortx-client-${node}") &
            pids+=($!)
        done
    fi

    local -i rc=0
    for pid in "${pids[@]}"; do
        wait "${pid}" || rc=$?
    done

    trap - INT

    set +u

    return ${rc}
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
deployCortxData
deployCortxClient
cleanup

# Note: It is not ideal that some of these values are hard-coded here.
#       The data comes from the helm charts and so there is no feasible
#       way of getting the values otherwise.
data_service_name="cortx-server-0"  # present in cortx values.yaml... what to do?
data_service_default_user="$(extractBlock 'solution.common.s3.default_iam_users.auth_admin' || true)"
control_service_name="cortx-control-loadbal-svc"  # hard coded in script above installing help or cortx-control
control_service_default_user="cortxadmin" #hard coded in cortx-configmap/templates/_config.tpl

cat << EOF

-----------------------------------------------------------

Thanks for installing CORTX Community Object Storage!

** Please wait while CORTX Kubernetes resources are being deployed. **
EOF

if [[ ${components[server]} == true ]]; then
    cat << EOF

The S3 data service is accessible through the ${data_service_name} service.
   Default IAM access key: ${data_service_default_user}
   Default IAM secret key is accessible via:
      kubectl get secrets/${cortx_secret_name} --namespace ${namespace} \\
        --template={{.data.s3_auth_admin_secret}} | base64 -d
EOF
fi

if [[ ${components[control]} == true ]]; then
    cat << EOF

The CORTX control service is accessible through the ${control_service_name} service.
   Default control username: ${control_service_default_user}
   Default control password is accessible via:
      kubectl get secrets/${cortx_secret_name} --namespace ${namespace} \\
        --template={{.data.csm_mgmt_admin_secret}} | base64 -d
EOF
fi

cat << EOF

-----------------------------------------------------------

EOF

if [[ ${CORTX_DEPLOY_NO_WAIT:-false} == true ]]; then
    exit
fi

ec=0
waitForClusterReady || ec=$?

if ((ec != 0)); then
    printf "\nERROR: A timeout occurred while waiting for one or more resources during the CORTX cluster installation.\n"
    exit ${ec}
fi

printf "\nThe CORTX cluster installation is complete.\n"
