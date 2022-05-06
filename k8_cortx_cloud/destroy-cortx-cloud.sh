#!/bin/bash

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

function extractBlock()
{
    ./parse_scripts/yaml_extract_block.sh ${solution_yaml} "$1"
}

namespace=$(parseSolution 'solution.namespace')
namespace=$(echo "${namespace}" | cut -f2 -d'>')

readonly pvc_consul_filter="data-${namespace}-cortx-consul"
readonly pvc_consul_filter_old="data-${namespace}-consul"  # backwards compatibility for older deployments
readonly pvc_filter="${pvc_consul_filter}|${pvc_consul_filter_old}|kafka|zookeeper|openldap-data|cortx|3rd-party"

parsed_node_output=$(parseSolution 'solution.nodes.node*.name')

# Split parsed output into an array of vars and vals
IFS=';' read -r -a parsed_var_val_array <<< "${parsed_node_output}"

find "$(pwd)/cortx-cloud-helm-pkg/cortx-data" -name "mnt-blk-*" -delete

node_name_list=[] # short version
count=0
# Loop the var val tuple array
for var_val_element in "${parsed_var_val_array[@]}"
do
    node_name=$(echo "${var_val_element}" | cut -f2 -d'>')
    shorter_node_name=$(echo "${node_name}" | cut -f1 -d'.')
    node_name_list[count]=${shorter_node_name}
    count=$((count+1))
    file_name="mnt-blk-info-${shorter_node_name}.txt"
    data_file_path=$(pwd)/cortx-cloud-helm-pkg/cortx-data/${file_name}

    # Get the node var from the tuple
    node=$(echo "${var_val_element}" | cut -f3 -d'.')

    filter="solution.storage.cvg*.devices*.device"
    parsed_dev_output=$(parseSolution "${filter}")
    IFS=';' read -r -a parsed_dev_array <<< "${parsed_dev_output}"
    for dev in "${parsed_dev_array[@]}"
    do
        device=$(echo "${dev}" | cut -f2 -d'>')
        if [[ -s ${data_file_path} ]]; then
            printf "\n" >> "${data_file_path}"
        fi
        printf "%s" "${device}" >> "${data_file_path}"
    done
done

num_motr_client=$(extractBlock 'solution.common.motr.num_client_inst')

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
    printf "########################################################\n"
    printf "# Delete CORTX Client                                  #\n"
    printf "########################################################\n"
    for node in "${node_name_list[@]}"; do
        uninstallHelmChart "cortx-client-${node}-${namespace}" "${namespace}"
    done
}

function deleteCortxHa()
{
    printf "########################################################\n"
    printf "# Delete CORTX HA                                      #\n"
    printf "########################################################\n"
    uninstallHelmChart "cortx-ha-${namespace}" "${namespace}"
}

function deleteCortxServer()
{
    printf "########################################################\n"
    printf "# Delete CORTX Server                                  #\n"
    printf "########################################################\n"
    for node in "${node_name_list[@]}"; do
        uninstallHelmChart "cortx-server-${node}-${namespace}" "${namespace}"
    done
}

function deleteCortxData()
{
    printf "########################################################\n"
    printf "# Delete CORTX Data                                    #\n"
    printf "########################################################\n"
    for node in "${node_name_list[@]}"; do
        uninstallHelmChart "cortx-data-${node}-${namespace}" "${namespace}"
    done
}

function deleteCortxControl()
{
    printf "########################################################\n"
    printf "# Delete CORTX Control                                 #\n"
    printf "########################################################\n"
    uninstallHelmChart "cortx-control-${namespace}" "${namespace}"
}

function waitForCortxPodsToTerminate()
{
    local count
    printf "\nWait for CORTX Pods to terminate"
    while true; do
        count=0
        while IFS= read -r line; do
            count=$(( count + 1 ))
        done < <(kubectl get pods --namespace="${namespace}" --selector=release!=cortx --no-headers | grep cortx)

        (( count == 0 )) && break || printf "."
        sleep 1s
    done
    printf ". Done.\n\n"
}

function deleteCortxLocalBlockStorage()
{
    printf "########################################################\n"
    printf "# Delete CORTX Local Block Storage                     #\n"
    printf "########################################################\n"
    uninstallHelmChart "cortx-data-blk-data-${namespace}" "${namespace}"
}

function deleteCortxPVs()
{
    printf "########################################################\n"
    printf "# Delete CORTX Persistent Volumes                      #\n"
    printf "########################################################\n"
    while IFS= read -r line; do
        if [[ ${line} != *"master"* && ${line} != *"AGE"* ]]
        then
            IFS=" " read -r -a pvc_line <<< "${line}"
            if [[ ${pvc_line[5]} =~ ^${namespace}/cortx-data-fs-local-pvc* \
                    || ${pvc_line[5]} =~ ^${namespace}/cortx-control-fs-local-pvc* ]]; then
                printf "Removing %s\n" "${pvc_line[0]}"
                if [[ "${force_delete}" == "--force" || "${force_delete}" == "-f" ]]; then
                    kubectl patch pv "${pvc_line[0]}" -p '{"metadata":{"finalizers":null}}'
                fi
                kubectl delete pv "${pvc_line[0]}"
            fi
        fi
    done < <(kubectl get pv --all-namespaces)
}

function deleteCortxConfigmap()
{
    printf "########################################################\n"
    printf "# Delete CORTX Configmap                               #\n"
    printf "########################################################\n"
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
function deleteKafkaZookeper()
{
    printf "########################################################\n"
    printf "# Delete Kafka                                         #\n"
    printf "########################################################\n"
    uninstallHelmChart kafka "${namespace}"

    printf "########################################################\n"
    printf "# Delete Zookeeper                                     #\n"
    printf "########################################################\n"
    uninstallHelmChart zookeeper "${namespace}"
}

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

        find "$(pwd)/cortx-cloud-helm-pkg/cortx-control" -name "secret-*" -delete
        find "$(pwd)/cortx-cloud-helm-pkg/cortx-data" -name "secret-*" -delete
        find "$(pwd)/cortx-cloud-helm-pkg/cortx-server" -name "secret-*" -delete
        find "$(pwd)/cortx-cloud-helm-pkg/cortx-ha" -name "secret-*" -delete
        find "$(pwd)/cortx-cloud-helm-pkg/cortx-client" -name "secret-*" -delete
    fi
}

function deleteDeprecated()
{
    deleteOpenLdap
    deleteConsul
}

function deleteConsul()
{
    printf "########################################################\n"
    printf "# Delete Consul                                        #\n"
    printf "########################################################\n"
    uninstallHelmChart consul "${namespace}"
}

function deleteCortx()
{
    printf "########################################################\n"
    printf "# Delete CORTX                                         #\n"
    printf "########################################################\n"
    uninstallHelmChart cortx "${namespace}"
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
                  grep -e kafka -e zookeeper -e openldap -e '^consul' -e '^cortx-consul' 2>&1)

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
    volume_claims=$(kubectl get pvc --namespace="${namespace}" | grep -E "${pvc_filter}" | cut -f1 -d " ")
    [[ -n ${volume_claims} ]] && echo "${volume_claims}"
    for volume_claim in ${volume_claims}
    do
        printf "Removing %s\n" "${volume_claim}"
        if [[ "${force_delete}" == "--force" || "${force_delete}" == "-f" ]]; then
            kubectl patch pvc --namespace "${namespace}" "${volume_claim}" \
                      -p '{"metadata":{"finalizers":null}}'
        fi
        kubectl delete pvc --namespace "${namespace}" "${volume_claim}"
    done
}

function delete3rdPartyPVs()
{
    printf "########################################################\n"
    printf "# Delete Persistent Volumes                            #\n"
    printf "########################################################\n"
    persistent_volumes=$(kubectl get pv | grep -E "${pvc_filter}" | cut -f1 -d " ")
    [[ -n ${persistent_volumes} ]] && echo "${persistent_volumes}"
    for persistent_volume in ${persistent_volumes}
    do
        printf "Removing %s\n" "${persistent_volume}"
        if [[ "${force_delete}" == "--force" || "${force_delete}" == "-f" ]]; then
            kubectl patch pv "${persistent_volume}" -p '{"metadata":{"finalizers":null}}'
        fi
        kubectl delete pv "${persistent_volume}"
    done
}

function deleteKubernetesPrereqs()
{
    printf "########################################################\n"
    printf "# Delete Cortx Kubernetes Prereqs                      #\n"
    printf "########################################################\n"
    uninstallHelmChart cortx-platform "${namespace}"

    ## Backwards compatibility check
    ## If CORTX is undeployed with a newer undeploy script, it can get into
    ## a broken state that is difficult to observe since the `svc/cortx-io-svc`
    ## will never be deleted. This explicit delete prevents that from happening.
    kubectl delete svc/cortx-io-svc --ignore-not-found=true
}

function cleanup()
{
    #################################################################
    # Delete files that contain disk partitions on the worker nodes #
    #################################################################
    # Split parsed output into an array of vars and vals
    IFS=';' read -r -a parsed_var_val_array <<< "${parsed_node_output}"
    # Loop the var val tuple array
    for var_val_element in "${parsed_var_val_array[@]}"
    do
        node_name=$(echo "${var_val_element}" | cut -f2 -d'>')
        shorter_node_name=$(echo "${node_name}" | cut -f1 -d'.')
        file_name="mnt-blk-info-${shorter_node_name}.txt"
        rm "$(pwd)/cortx-cloud-helm-pkg/cortx-data/${file_name}"
    done

    find "$(pwd)/cortx-cloud-helm-pkg/cortx-data-blk-data" -name "mnt-blk-*" -delete
    find "$(pwd)/cortx-cloud-helm-pkg/cortx-data-blk-data" -name "node-list-*" -delete
    find "$(pwd)/cortx-cloud-helm-pkg/cortx-data" -name "mnt-blk-*" -delete
    find "$(pwd)/cortx-cloud-helm-pkg/cortx-data" -name "node-list-*" -delete
}

#############################################################
# Destroy CORTX Cloud
#############################################################
if [[ ${num_motr_client} -gt 0 ]]; then
    deleteCortxClient
fi
deleteCortxHa
deleteCortxServer
deleteCortxData
deleteCortxControl
waitForCortxPodsToTerminate
deleteSecrets
deleteCortxLocalBlockStorage
deleteCortxPVs
deleteCortxConfigmap

#############################################################
# Destroy CORTX 3rd party
#############################################################

deleteKafkaZookeper
deleteDeprecated
deleteCortx
waitFor3rdPartyToTerminate
delete3rdPartyPVCs
delete3rdPartyPVs

#############################################################
# Clean up
#############################################################
deleteKubernetesPrereqs
cleanup
