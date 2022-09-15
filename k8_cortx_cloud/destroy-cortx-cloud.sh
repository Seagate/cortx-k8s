#!/usr/bin/env bash

# shellcheck disable=SC2312

solution_yaml=${1:-'solution.yaml'}
force_delete=${2:-''}

if [[ "${solution_yaml}" == "--force" || "${solution_yaml}" == "-f" ]]; then
    temp=${force_delete}
    force_delete=${solution_yaml}
    solution_yaml=${temp}
    if [[ -z "${solution_yaml}" ]]; then
        solution_yaml="solution.yaml"
    fi
fi

# Check if the file exists
if [[ ! -f ${solution_yaml} ]]; then
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
done < <(kubectl get nodes --no-headers)


exit_early=false
if [[ ${not_ready_node_count} -gt 0 ]]; then
    echo "Number of 'NotReady' worker nodes detected in the cluster: ${not_ready_node_count}"
    echo "List of 'NotReady' worker nodes:"
    for not_ready_node in "${not_ready_node_list[@]}"; do
        echo "- ${not_ready_node}"
    done

    printf "\nContinue CORTX Cloud destruction could lead to unexpected results.\n"
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

namespace=$(yq .solution.namespace ${solution_yaml})
readonly namespace

function uninstallHelmChart()
{
    local chart=$1
    local ns=()
    [[ -n ${2:-} ]] && ns+=("--namespace=$2")
    # Silence "release: not found" messages as those can be expected
    helm uninstall "${chart}" "${ns[@]}" 2> >(grep -v 'uninstall.*release: not found')
}

function deleteSecrets()
{
    printf "# Deleting Auto-Generated Secrets\n"
    local secret_name
    secret_name=$(yq '.solution.secrets.name | select( (. != null) )' "${solution_yaml}")
    if [[ -n "${secret_name}" ]]; then
        kubectl delete secret "${secret_name}" --namespace="${namespace}" --ignore-not-found=true
    fi
}

function deletePVCs()
{
    # PVCs are not removed by uninstalling the Charts, so manually remove them for a complete cleanup
    printf "# Deleting Persistent Volume Claims\n"
    for selector in "app.kubernetes.io/instance=cortx" "app=consul,release=cortx"; do
        if [[ "${force_delete}" == "--force" || "${force_delete}" == "-f" ]]; then
            while IFS= read -r pvc; do
                printf "  patching %s for forced removal\n" "${pvc}"
                kubectl patch "${pvc}" --namespace "${namespace}" --patch '{"metadata":{"finalizers":null}}'
            done < <(kubectl get pvc --no-headers --selector=${selector} --output=name)
        fi
        kubectl delete pvc --namespace "${namespace}" --selector=${selector} --ignore-not-found
    done
}


printf "# Uninstalling CORTX Helm Charts\n"
uninstallHelmChart cortx "${namespace}"
uninstallHelmChart cortx-block-data "${namespace}"
deleteSecrets
deletePVCs
