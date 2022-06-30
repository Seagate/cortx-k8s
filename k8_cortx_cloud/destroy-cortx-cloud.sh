#!/usr/bin/env bash

# shellcheck disable=SC2312

solution_yaml=${1:-'solution.yaml'}
force_delete=${2:-''}

if [[ "${solution_yaml}" == "--force" || "${solution_yaml}" == "-f" ]]; then
    temp=${force_delete}
    force_delete=${solution_yaml}
    solution_yaml=${temp}
    if [[ "${solution_yaml}" == "" ]]; then
        solution_yaml="solution.yaml"
    fi
fi

# Check if the file exists
if [[ ! -f ${solution_yaml} ]]
then
    echo "ERROR: ${solution_yaml} does not exist"
    exit 1
fi

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
done <<< "$(kubectl get nodes --no-headers)"

exit_early=false
if [[ ${not_ready_node_count} -gt 0 ]]; then
    echo "Number of 'NotReady' worker nodes detected in the cluster: ${not_ready_node_count}"
    echo "List of 'NotReady' worker nodes:"
    for not_ready_node in "${not_ready_node_list[@]}"; do
        echo "- ${not_ready_node}"
    done

    printf "\nContinue CORTX Cloud destruction could lead to unexpeted results.\n"
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

function parseSolution()
{
    ./parse_scripts/parse_yaml.sh ${solution_yaml} "$1"
}

namespace=$(parseSolution 'solution.namespace' | cut -f2 -d'>')

readonly pvc_consul_filter="data-.*-consul-server-"
readonly pvc_kafka_filter="data-cortx-kafka-|data-kafka-"
readonly pvc_filter="${pvc_consul_filter}|${pvc_kafka_filter}|zookeeper|openldap-data|cortx|3rd-party"

parsed_node_output=$(yq e '.solution.storage_sets[0].nodes' --output-format=csv ${solution_yaml})

# Split parsed output into an array of vars and vals
IFS=',' read -r -a parsed_node_array <<< "${parsed_node_output}"

[[ -d $(pwd)/cortx-cloud-helm-pkg/cortx-data ]] && find "$(pwd)/cortx-cloud-helm-pkg/cortx-data" -name "mnt-blk-*" -delete

node_name_list=[] # short version
count=0
# Loop the var val tuple array
for node_name in "${parsed_node_array[@]}"
do
    shorter_node_name=$(echo "${node_name}" | cut -f1 -d'.')
    node_name_list[count]=${shorter_node_name}
    count=$((count+1))
done

function uninstallHelmChart()
{
    local chart=$1
    local ns=()
    [[ -n ${2:-} ]] && ns+=("--namespace=$2")
    # Silence "release: not found" messages as those can be expected
    helm uninstall "${chart}" "${ns[@]}" 2> >(grep -v 'uninstall.*release: not found')
}

#############################################################
# Destroy CORTX Cloud functions
#############################################################
function deleteCortxClient()
{
    # backwards compatibility for cortx-server chart based on Deployments
    for node in "${node_name_list[@]}"; do
        uninstallHelmChart "cortx-client-${node}-${namespace}" "${namespace}"
    done
}

function deleteCortxHa()
{
    uninstallHelmChart "cortx-ha-${namespace}" "${namespace}"
}

function deleteCortxServer()
{
    # backwards compatibility for cortx-server chart based on Deployments
    for node in "${node_name_list[@]}"; do
        uninstallHelmChart "cortx-server-${node}-${namespace}" "${namespace}"
    done

    # backwards compatibility for cortx-server chart based on StatefulSet
    uninstallHelmChart "cortx-server-${namespace}" "${namespace}"
}

function deleteCortxData()
{
    # backwards compatibility for cortx-data chart based on Deployments
    for node in "${node_name_list[@]}"; do
        uninstallHelmChart "cortx-data-${node}-${namespace}" "${namespace}"
    done

    # backwards compatibility for cortx-data chart based on StatefulSet
    uninstallHelmChart "cortx-data-${namespace}" "${namespace}"
}

function deleteCortxControl()
{
    uninstallHelmChart "cortx-control-${namespace}" "${namespace}"
}

function deleteCortxLocalBlockStorage()
{
    printf "########################################################\n"
    printf "# Delete CORTX Local Block Storage                     #\n"
    printf "########################################################\n"
    uninstallHelmChart "cortx-data-blk-data-${namespace}" "${namespace}"
}

function deleteCortxConfigmap()
{
    #
    # These configmaps are deprecated, and removed for backwards compatibility.
    #

    cfgmap_path="./cortx-cloud-helm-pkg/cortx-configmap"

    for node in "${node_name_list[@]}"; do
        for type in data server client; do
            kubectl delete configmap \
                "cortx-${type}-machine-id-cfgmap-${node}-${namespace}" \
                --namespace="${namespace}" \
                --ignore-not-found=true
        done
        rm -rf "${cfgmap_path}/auto-gen-${node}-${namespace}"
    done

    for type in control ha; do
        kubectl delete configmap \
            "cortx-${type}-machine-id-cfgmap-${namespace}" \
            --namespace="${namespace}" \
            --ignore-not-found=true
        rm -rf "${cfgmap_path}/auto-gen-${type}-${namespace}"
    done

    # Backwards compatibility uninstall
    uninstallHelmChart "cortx-cfgmap-${namespace}" "${namespace}"
    rm -rf "${cfgmap_path}/auto-gen-cfgmap-${namespace}"

    ## Backwards compatibility check
    ## If CORTX is undeployed with a newer undeploy script, it can get into
    ## a broken state that is difficult to observe since the `svc/cortx-io-svc`
    ## will never be deleted. This explicit delete prevents that from happening.
    kubectl delete configmap "cortx-cfgmap-${namespace}" --namespace="${namespace}" --ignore-not-found=true
    kubectl delete configmap "cortx-ssl-cert-cfgmap-${namespace}" --namespace="${namespace}" --ignore-not-found=true
}

#############################################################
# Destroy CORTX 3rd party functions
#############################################################
function deleteOpenLdap()
{
    ## Backwards compatibility check
    ## CORTX deployment of OpenLdap stopped with v0.2.0.
    ## This function is useful for deployments prior to v0.2.0
    ## that need this cleanup method.

    kubectl get pods --namespace=default --output=name | grep '^pod/openldap-' |
    while IFS= read -r pod; do
        kubectl exec "${pod}" --namespace=default -- \
            bash -c 'rm -rf /etc/3rd-party/* /var/data/3rd-party/* /var/log/3rd-party/*'
    done

    # Note: openldap was always deployed in default namespace
    uninstallHelmChart openldap default
}

function deleteSecrets()
{
    printf "########################################################\n"
    printf "# Delete Secrets                                       #\n"
    printf "########################################################\n"
    secret_name=$(./parse_scripts/parse_yaml.sh "${solution_yaml}" "solution.secrets.name")
    if [[ -n "${secret_name}" ]]; then
        secret_name=$(echo "${secret_name}" | cut -f2 -d'>')
        kubectl delete secret "${secret_name}" --namespace="${namespace}" --ignore-not-found=true

        find "$(pwd)/cortx-cloud-helm-pkg" -name "secret-info.txt" -delete
    fi
}

function deleteDeprecated()
{
    # Delete resources that were created by a previous version of this deployment.
    deleteOpenLdap
    uninstallHelmChart consul "${namespace}"
    uninstallHelmChart kafka "${namespace}"
    uninstallHelmChart zookeeper "${namespace}"

    waitFor3rdPartyToTerminate
}

function waitFor3rdPartyToTerminate()
{
    local count
    printf "\nWait for 3rd party Pods to terminate"
    while true; do
        count=0
        while IFS= read -r line; do
            count=$(( count + 1 ))
        done < <(kubectl get pods --namespace "${namespace}" --no-headers | \
                  grep -e '^zookeeper' -e openldap -e '^consul' -e '^kafka')

        (( count == 0 )) && break || printf "."
        sleep 1s
    done
    printf ". Done.\n\n"
}

function delete3rdPartyPVCs()
{
    printf "########################################################\n"
    printf "# Delete Persistent Volume Claims                      #\n"
    printf "########################################################\n"
    while IFS= read -r volume_claim; do
        printf "Removing %s\n" "${volume_claim}"
        if [[ "${force_delete}" == "--force" || "${force_delete}" == "-f" ]]; then
            kubectl patch pvc --namespace "${namespace}" "${volume_claim}" \
                      -p '{"metadata":{"finalizers":null}}'
        fi
        kubectl delete pvc --namespace "${namespace}" "${volume_claim}" --ignore-not-found
    done < <(kubectl get pvc --no-headers --namespace="${namespace}" | grep -E "${pvc_filter}" | cut -f1 -d " ")
}

function deleteKubernetesPrereqs()
{
    # This chart has been removed, this is for backwards compatibility.
    uninstallHelmChart cortx-platform "${namespace}"

    ## Backwards compatibility check
    ## If CORTX is undeployed with a newer undeploy script, it can get into
    ## a broken state that is difficult to observe since the `svc/cortx-io-svc`
    ## will never be deleted. This explicit delete prevents that from happening.
    kubectl delete svc/cortx-io-svc --ignore-not-found=true
}

function deleteNodeDataFiles()
{
    #################################################################
    # Delete files that contain disk partitions on the worker nodes #
    #################################################################
    find "$(pwd)/cortx-cloud-helm-pkg/cortx-data-blk-data" -name "mnt-blk-*" -delete
    find "$(pwd)/cortx-cloud-helm-pkg/cortx-data-blk-data" -name "node-list-*" -delete
    if [[ -d $(pwd)/cortx-cloud-helm-pkg/cortx-data ]]; then
        find "$(pwd)/cortx-cloud-helm-pkg/cortx-data" -name "mnt-blk-*" -delete
        find "$(pwd)/cortx-cloud-helm-pkg/cortx-data" -name "node-list-*" -delete
    fi
}

#############################################################
# Delete CORTX Cloud resources
#############################################################
deleteCortxClient   # deprecated
deleteCortxHa       # deprecated
deleteCortxServer   # deprecated
deleteCortxData     # deprecated
deleteCortxControl  # deprecated
deleteSecrets
deleteCortxLocalBlockStorage
deleteCortxConfigmap  # deprecated

#############################################################
# Delete CORTX 3rd party resources
#############################################################
deleteDeprecated

# Delete remaining CORTX Cloud resources
uninstallHelmChart cortx "${namespace}"

#############################################################
# Clean up
#############################################################
delete3rdPartyPVCs
deleteKubernetesPrereqs
deleteNodeDataFiles
