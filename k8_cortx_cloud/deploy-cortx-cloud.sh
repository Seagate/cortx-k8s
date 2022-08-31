#!/usr/bin/env bash

# shellcheck disable=SC2312

# Check required dependencies
if ! ./parse_scripts/check_yq.sh; then
    exit 1
fi

readonly solution_yaml=${1:-'solution.yaml'}
readonly custom_values_file=${CORTX_DEPLOY_CUSTOM_VALUES_FILE:-}
readonly cfgmap_path="./cortx-cloud-helm-pkg/cortx-configmap"
cortx_secret_fields=("kafka_admin_secret"
                     "consul_admin_secret"
                     "common_admin_secret"
                     "s3_auth_admin_secret"
                     "csm_auth_admin_secret"
                     "csm_mgmt_admin_secret")
readonly cortx_secret_fields
readonly cortx_localblockstorage_storageclassname=${CORTX_DEPLOY_CUSTOM_BLOCK_STORAGE_CLASS:-"cortx-local-block-storage"}
readonly cortx_localblockstorage_skipdeployment=${CORTX_DEPLOY_CUSTOM_BLOCK_STORAGE_CLASS:-}

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

    # Check for existence of custom values file
    if [[ -n ${custom_values_file} ]]; then
        if [[ ! -f ${custom_values_file} ]]; then
            printf "ERROR: custom values file %s does not exist\n" "${custom_values_file}"
            exit 1
        fi
        printf "Custom values file: %s\n" "${custom_values_file}"
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
    if ! ./solution_validation_scripts/solution-validation.sh "${solution_yaml}"; then
        exit 1
    fi
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
        | .existingSecret = \"${cortx_secret_name}\"
        | .existingCertificateSecret = \"${cortx_external_ssl_secret}\"" > "${values_file}"

    # Configure all cortx-setup containers for console component logging
    yq -i '.global.cortx.setupLoggingDetail = "component"' "${values_file}"

    # shellcheck disable=SC2016
    yq -i eval-all '
        select(fi==0) ref $to | select(fi==1) ref $from
        | with($to.consul;
            .server *= $from.solution.common.resource_allocation.consul.server
            | .client = $from.solution.common.resource_allocation.consul.client
            | .*.image = $from.solution.images.consul)
        | $to' "${values_file}" "${solution_yaml}"

    # shellcheck disable=SC2016
    yq -i eval-all '
        select(fi==0) ref $to | select(fi==1) ref $from
        | $from.solution.images.[]
        |= capture("(?P<registry>.*?)/(?P<repository>.*):(?P<tag>.*)")
        | $from.solution.images
        | $to.kafka.image           = .kafka
        | $to.kafka.zookeeper.image = .zookeeper
        | $to.control.image         = .cortxcontrol
        | $to.ha.image              = .cortxha
        | $to.server.image          = .cortxserver
        | $to.data.image            = .cortxdata
        | $to.client.image          = .cortxclient
        | $to' "${values_file}" "${solution_yaml}"

    yq -i ".consul.server.replicas = ${num_consul_replicas}" "${values_file}"

    # shellcheck disable=SC2016
    yq -i eval-all '
        select(fi==0) ref $to | select(fi==1) ref $from
        | with($to.kafka;
            .resources = $from.solution.common.resource_allocation.kafka.resources
            | .persistence.size = $from.solution.common.resource_allocation.kafka.storage_request_size
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
        | with($to.server;
            .auth.adminUser = $from.solution.common.s3.default_iam_users.auth_user
            | .auth.adminAccessKey = $from.solution.common.s3.default_iam_users.auth_admin
            | .maxStartTimeout = $from.solution.common.s3.max_start_timeout
            | .extraConfiguration = $from.solution.common.s3.extra_configuration
            | .rgw.resources = $from.solution.common.resource_allocation.server.rgw.resources)
        | $to' "${values_file}" "${solution_yaml}"

    yq -i "
        .server.enabled = ${components[server]}
        | .ha.enabled = ${components[ha]}
        | .control.enabled = ${components[control]}
        | .client.enabled = ${components[client]}" "${values_file}"

    # shellcheck disable=SC2016
    yq -i ".storageSets = (
        load(\"${solution_yaml}\")
        | .solution.storage_sets |
        (.[].container_group_size | key) = \"containerGroupSize\"
        | del(.[].nodes))" "${values_file}"

    local hax_service_protocol
    local s3_service_type
    local s3_service_ports_http
    local s3_service_ports_https
    hax_service_protocol=$(getSolutionValue 'solution.common.hax.protocol')
    s3_service_type=$(getSolutionValue 'solution.common.external_services.s3.type')
    s3_service_count=$(getSolutionValue 'solution.common.external_services.s3.count')
    s3_service_ports_http=$(getSolutionValue 'solution.common.external_services.s3.ports.http')
    s3_service_ports_https=$(getSolutionValue 'solution.common.external_services.s3.ports.https')

    local s3_service_nodeports_http
    local s3_service_nodeports_https
    s3_service_nodeports_http=$(getSolutionValue 'solution.common.external_services.s3.nodePorts.http')
    s3_service_nodeports_https=$(getSolutionValue 'solution.common.external_services.s3.nodePorts.https')
    [[ -n ${s3_service_nodeports_http} ]] && yq -i ".server.service.nodePorts.http = ${s3_service_nodeports_http}" "${values_file}"
    [[ -n ${s3_service_nodeports_https} ]] && yq -i ".server.service.nodePorts.https = ${s3_service_nodeports_https}" "${values_file}"

    yq -i "
        with(.server.service; (
            .type = \"${s3_service_type}\"
            | .instanceCount = ${s3_service_count}
            | .ports.http = ${s3_service_ports_http}
            | .ports.https = ${s3_service_ports_https}))" "${values_file}"

    # shellcheck disable=SC2016
    yq -i eval-all '
        select(fi==0) ref $to | select(fi==1) ref $from
        | with($to.control;
            .service.type                    = $from.solution.common.external_services.control.type
            | .service.ports.https             = $from.solution.common.external_services.control.ports.https
            | .agent.resources.requests.memory = $from.solution.common.resource_allocation.control.agent.resources.requests.memory
            | .agent.resources.requests.cpu    = $from.solution.common.resource_allocation.control.agent.resources.requests.cpu
            | .agent.resources.limits.memory   = $from.solution.common.resource_allocation.control.agent.resources.limits.memory
            | .agent.resources.limits.cpu      = $from.solution.common.resource_allocation.control.agent.resources.limits.cpu)
        | $to' "${values_file}" "${solution_yaml}"

    local control_service_nodeports_https
    control_service_nodeports_https=$(getSolutionValue 'solution.common.external_services.control.nodePorts.https')
    [[ -n ${control_service_nodeports_https} ]] && yq -i ".control.service.nodePorts.https = ${control_service_nodeports_https}" "${values_file}"

    local data_node_count
    data_node_count=$(yq ".solution.storage_sets[0].nodes | length" "${solution_yaml}")
    local server_instances_per_node
    local total_server_pods
    server_instances_per_node=$(yq ".solution.common.s3.instances_per_node" "${solution_yaml}")
    total_server_pods=$(( data_node_count * server_instances_per_node ))

    # shellcheck disable=SC2016
    yq -i eval-all '
        select(fi==0) ref $to | select(fi==1) ref $from
        | with($to.ha;
            .faultTolerance.resources   = $from.solution.common.resource_allocation.ha.fault_tolerance.resources
            | .healthMonitor.resources    = $from.solution.common.resource_allocation.ha.health_monitor.resources
            | .k8sMonitor.resources       = $from.solution.common.resource_allocation.ha.k8s_monitor.resources)
        | $to' "${values_file}" "${solution_yaml}"

    yq -i ".server.replicaCount = ${total_server_pods}" "${values_file}"

    data_replicas=${data_node_count}
    [[ ${components[data]} == false ]] && data_replicas=0

    ### TODO [FUTURE] Determine how we want to sub-select nominated nodes for Data Pod scheduling.
    ### 1. Should we apply the labels through this script?
    ### 2. Should we require the labels to be applied prior to execution of this script?
    ### 3. Should we use a nodeSelector that uses the "in"/set operators?

     yq -i "
        .hare.hax.ports.http.protocol = \"${hax_service_protocol}\"
        | with(.data;
            .replicaCount = ${data_replicas}
            | .blockDevicePersistence.storageClass = \"${cortx_localblockstorage_storageclassname}\")" "${values_file}"

    # shellcheck disable=SC2016
    yq -i eval-all '
        select(fi==0) ref $to | select(fi==1) ref $from
        | with($to.hare.hax;
            .ports.http.port = $from.solution.common.hax.port_num
            | .resources     = $from.solution.common.resource_allocation.hare.hax.resources)
        | with($to.data;
            .extraConfiguration = $from.solution.common.motr.extra_configuration
            | .ios.resources      = $from.solution.common.resource_allocation.data.motr.resources
            | .confd.resources    = $from.solution.common.resource_allocation.data.confd.resources)
        | $to' "${values_file}" "${solution_yaml}"

    client_replicas=${data_node_count}
    [[ ${components[client]} == false ]] && client_replicas=0

    yq -i "
        .client.replicaCount = ${client_replicas}
        | .client.instanceCount = ${num_motr_client}" "${values_file}"

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

    printf "\nContinue CORTX Cloud deployment could lead to unexpected results.\n"
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

# Split parsed output into an array of vars and vals
IFS=',' read -r -a parsed_node_array < <(yq e '.solution.storage_sets[0].nodes' --output-format=csv "${solution_yaml}")

tainted_worker_node_list=[]
num_tainted_worker_nodes=0
not_found_node_list=[]
num_not_found_nodes=0
# Validate the solution file. Check that nodes listed in the solution file
# aren't tainted and allow scheduling.
for node_name in "${parsed_node_array[@]}";
do
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

    values=(-f "${values_file}")
     [[ -f ${custom_values_file} ]] && values+=(-f "${custom_values_file}")

    helm install cortx ../charts/cortx \
        "${values[@]}" \
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
            .nodes                             = $from.solution.storage_sets[0].nodes
            | .blockDevicePaths                = [$from.solution.storage_sets[0].storage[].devices[].[]])
        | $to' "${cortx_block_data_values_file}" "${solution_yaml}"

    helm install cortx-block-data ../charts/cortx-block-data \
        -f ${cortx_block_data_values_file} \
        --namespace "${namespace}" \
        --create-namespace \
        || exit $?
}

function deleteStaleAutoGenFolders()
{
    # Delete all stale auto gen folders
    rm -rf "$(pwd)/cortx-cloud-helm-pkg/cortx-configmap"
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

    # This is a global variable
    # If common.ssl.external_secret is not defined, this will be empty, which is ok
    cortx_external_ssl_secret=$(getSolutionValue "solution.common.ssl.external_secret")
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

function cleanup()
{
    # DEPRECATED: These files are no longer used during deploy, but the cleanup step is left behind
    # to clean up as much as possible going forward.
    # Delete files that contain disk partitions on the worker nodes and the node info
    # and left-over secret data
    [[ -d $(pwd)/cortx-cloud-helm-pkg ]] && find "$(pwd)/cortx-cloud-helm-pkg" -type f \( -name 'mnt-blk-*' -o -name 'node-list-*' -o -name secret-info.txt \) -delete

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

    printf "\nNow waiting for all CORTX resources to become available, press Ctrl-C to quit...\n\n"

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
        for statefulset in $(kubectl get statefulset --selector app.kubernetes.io/component=data,app.kubernetes.io/instance=cortx --no-headers --output custom-columns=NAME:metadata.name); do
            (waitForAllDeploymentsAvailable "${CORTX_DEPLOY_DATA_TIMEOUT:-10m}" "statefulset/${statefulset}") &
            pids+=($!)
        done
    fi

    if [[ ${components[server]} == true ]]; then
        (waitForAllDeploymentsAvailable "${CORTX_DEPLOY_SERVER_TIMEOUT:-10m}" statefulset/cortx-server) &
        pids+=($!)
    fi

    if [[ ${components[client]} == true ]]; then
        (waitForAllDeploymentsAvailable "${CORTX_DEPLOY_CLIENT_TIMEOUT:-10m}" statefulset/cortx-client) &
        pids+=($!)
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

##########################################################
# Deploy CORTX cloud pre-requisites
##########################################################
deleteStaleAutoGenFolders
deployKubernetesPrereqs
deployRancherProvisioner
if [[ -z ${cortx_localblockstorage_skipdeployment} ]]; then
    deployCortxLocalBlockStorage
fi
deployCortxSecrets

##########################################################
# Deploy CORTX cloud
##########################################################
deployCortx
cleanup

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
