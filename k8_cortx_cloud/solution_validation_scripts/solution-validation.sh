#!/bin/bash

solution_yaml=${1:-'solution.yaml'}
solution_chk_yaml='./solution_validation_scripts/solution-check.yaml'

function checkResult()
{
    local result=$1
    local result_str=$2

    if [[ ${result} == "failed" ]]; then
        printf "%s\nValidate solution file result: %s\n" "${result_str}" "${result}"
        exit 1
    fi
}

if [[ ! -f ${solution_yaml} ]]; then
    echo "ERROR: ${solution_yaml} does not exist"
    exit 1
fi

### CORTX-29861 yq validation replacement
### Test for the generic existence of required elements in solution.yaml
### This is done by deeply merging the input solution.yaml as an overlay onto the solution-check.yaml file.
### Any keys that have a resultant value of "required" after the merge signify that key is missing in the input solution.yaml file
### CAVEAT: This method does not currently account for optional keys or either/or requirements (IE secrets.name OR secrets.content),
### which the prior method did not cover either.

# shellcheck disable=SC2016
invalid_paths="$(yq ea '. as $item ireduce({}; . *d $item) | .. | select(. == "required") | path | [join(".")]' "${solution_chk_yaml}" "${solution_yaml}")"

if [[ "${invalid_paths}" != "[]" ]]; then
    echo "---"
    echo "VALIDATION FAILURE:"
    echo "The following paths are required and currently undefined in ${solution_yaml}:"
    echo "${invalid_paths}"
    echo "---"
    exit 1
fi
### CORTX-29861 yq validation replacement [/end]

# Warn for keys/sections that have been removed and are no longer required
# shellcheck disable=SC2312
if [[ $(yq '.solution.common | has("container_path")' "${solution_yaml}") == "true" ]]; then
    echo "WARNING: section 'solution.common.container_path' has been removed in v0.9.0. Custom container paths are not supported. You can remove it from your solution file."
fi

### CORTX-29861 Temporary namespace length limitation enforced
### This can be removed once namespaces of nominal length (20+ characters) have been validated repeatedly.
observed_namespace_length=$(yq '.solution.namespace | length' "${solution_yaml}")
maximum_namespace_length=20

if [[ "${observed_namespace_length}" -gt "${maximum_namespace_length}" ]]; then
    result_str="The maximum length of the targeted Kubernetes namespace is currently limited to ${maximum_namespace_length} characters. The specified namespace in ${solution_yaml} has a length of ${observed_namespace_length} characters."
    result="failed"
fi
### CORTX-29861 Temporary namespace length limitation enforced [/end]

num_storage_sets=$(yq e '.solution.storage_sets | length' "${solution_yaml}")
if [[ "${num_storage_sets}" -gt "1" ]]; then
    echo "WARNING: Only 1 Storage Set is currently supported by CORTX."
    echo "WARNING: The first Storage Set in the provided solution configuration file will be used and additional Storage Sets will be ignored."
fi

num_cvgs=$(yq e '.solution.storage_sets[0].storage | length' "${solution_yaml}")
total_num_nodes=$(yq '.solution.storage_sets[0].nodes | length' "${solution_yaml}")

sns_val=$(yq e '.solution.storage_sets[0].durability.sns' "${solution_yaml}")
dix_val=$(yq e '.solution.storage_sets[0].durability.dix' "${solution_yaml}")

# Validate SNS
sns_total=0
IFS="+" read -r -a sns_val_array <<< "${sns_val}"
for val in "${sns_val_array[@]}"; do
    sns_total=$((sns_total+val))
done

# The SNS=(N+K+S) should not exceed the total number of CVGs in the cluster (the number
# of CVGs in the solution file multiplies by the number of worker nodes in the cluster)
total_num_cvgs_in_cluster=$(( num_cvgs * total_num_nodes ))
if [[ "${sns_total}" -gt "${total_num_cvgs_in_cluster}" ]]; then
    result_str="The sum of SNS (${sns_total}) is greater than the total number of CVGs (${total_num_cvgs_in_cluster}) in the cluster"
    result="failed"
fi

checkResult ${result} "${result_str}"

# Validate DIX
dix_total=0
IFS="+" read -r -a dix_val_array <<< "${dix_val}"
for val in "${dix_val_array[@]}"; do
    dix_total=$((dix_total+val))
done

if [[ "${dix_total}" -gt "${total_num_nodes}" ]]; then
    result_str="The sum of DIX (${dix_total}) is greater than the total number of worker nodes (${total_num_nodes}) in the cluster"
    result="failed"
fi

checkResult ${result} "${result_str}"
