#!/bin/bash

solution_yaml=${1:-'solution.yaml'}
solution_chk_yaml='./solution_validation_scripts/solution-check.yaml'

function parseSolution()
{
    ./parse_scripts/parse_yaml.sh "${solution_yaml}" "$1"
}

function buildRegexFromSolutionVar()
{
    # Find all the number in the string and replace it with "[0-9]+".
    # Example:
    # string="solution.storage.cvg1.devices.data.d2.device"
    # regex="solution.storage.cvg[0-9]+.devices.data.d[0-9]+.device"
    # shellcheck disable=SC2001
    echo "$1" | sed -e 's/\([0-9]\+\)/[0-9]+/g'
}

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

solution_content=$(parseSolution)
solution_chk_content=$(./parse_scripts/parse_yaml.sh ${solution_chk_yaml})

# Build a list that contains all the content in the solution.yaml file
solution_var_list=[]
count=0
solution_node_list=[]
sol_node_count=0
IFS=";" read -r -a my_array <<< "${solution_content}"
for element in "${my_array[@]}"; do
    if [[ "${element}" == "solution.nodes.node"* ]]; then
        # NOTE: this will fail if extra keys are added to nodes
        solution_node_list[${sol_node_count}]=${element}
        sol_node_count=$((sol_node_count+1))
    fi
    solution_var_list[${count}]="${element}"
    count=$((count+1))
done

# Default result value (success/failed) and string
result="success"
result_str=""

# A list that contains "cvg" section in the "solution_check.yaml" file
solution_chk_cvg_var_list=[]
sol_chk_cvg_count=0
solution_chk_node=[]
sol_chk_node_count=0

validate_data_size=false
validate_data_device=false

# Validate the following in the solution file: namespace, secrets, images, common section,
# the first cvg in storage, and the first node in nodes.
IFS=";" read -r -a my_array <<< "${solution_chk_content}"
for element in "${my_array[@]}"; do
    IFS=">" read -r -a element_array <<< "${element}"
    found=false

    if [[ "${element}" == *".node"* ]]; then
        solution_chk_node[${sol_chk_node_count}]="${element}"
        sol_chk_node_count=$((sol_chk_node_count+1))
    fi

    if [[ "${element}" == *".cvg"* ]]; then
        solution_chk_cvg_var_list[${sol_chk_cvg_count}]="${element}"
        sol_chk_cvg_count=$((sol_chk_cvg_count+1))
    fi

    for e in "${solution_var_list[@]}"; do
        IFS=">" read -r -a e_array <<< "${e}"
        if [[ "${element_array[0]}" == "${e_array[0]}" ]]; then
            found=true
            break
        fi
    done

    if [[ "${element_array[0]}" =~ solution.storage.cvg[0-9]+.devices.data.d[0-9]+.size \
            && "${element_array[1]}" == "required" ]]; then
        validate_data_size=true
    fi

    if [[ "${element_array[0]}" =~ solution.storage.cvg[0-9]+.devices.data.d[0-9]+.device \
            && "${element_array[1]}" == "required" ]]; then
        validate_data_device=true
    fi

    if [[ "${found}" = false && "${element_array[1]}" == "required" ]]; then
        # Find all the number in the string and replace it with "*".
        # shellcheck disable=SC2001
        temp_regex=$(echo "${element}" | sed -e 's/\([0-9]\+\)/*/g')
        temp_regex_val=$(echo "${temp_regex}" | cut -f1 -d'>')
        result_str="Failed to find '${temp_regex_val}' in the solution file"
        result="failed"
    fi
done

checkResult ${result} "${result_str}"

cvg_name_list=$(parseSolution 'solution.storage.cvg*.name')
# Get number of '>' show up in 'cvg_name_list' string
num_cvg=$(echo "${cvg_name_list}" | awk -F">" '{print NF-1}')
# Build a list that contains cvg info
solution_cvg_blk_list=[]
cvg_blk_list=0
for index in $(seq 1 "${num_cvg}"); do
    solution_cvg_blk_list[${cvg_blk_list}]=$(parseSolution "solution.storage.cvg${index}.*")
    cvg_blk_list=$((cvg_blk_list+1))
done

# Validate cvg name, type, metadata device, metadata size exist in the solution file
num_cvgs="${#solution_cvg_blk_list[@]}"
for sol_chk_e in "${solution_chk_cvg_var_list[@]}"; do
    IFS=">" read -r -a sol_chk_array <<< "${sol_chk_e}"
    regex=$(buildRegexFromSolutionVar "${sol_chk_array[0]}")
    count=0
    for sol_e in "${solution_cvg_blk_list[@]}"; do
        if [[ "${sol_e}" =~ ${regex} || "${sol_chk_array[1]}" != "required" ]]; then
            count=$((count+1))
        fi
    done

    found=false
    if [[ "${num_cvgs}" == "${count}" || "${sol_chk_array[1]}" != "required" ]]; then
        found=true
    fi

    if [[ "${found}" = false ]]; then
        # Find all the number in the string and replace it with "*".
        # shellcheck disable=SC2001
        temp_regex=$(echo "${sol_chk_e}" | sed -e 's/\([0-9]\+\)/*/g')
        temp_regex_val=$(echo "${temp_regex}" | cut -f1 -d'>')
        result_str="Failed to find '${temp_regex_val}' in the solution file"
        result="failed"
        break
    fi
done

checkResult ${result} "${result_str}"

# Build a list that only contains data device info in cvg
solution_cvg_blk_data_dev=[]
cvg_blk_list=0
for index in $(seq 1 "${num_cvg}"); do
    solution_cvg_blk_data_dev[${cvg_blk_list}]=$(parseSolution "solution.storage.cvg${index}.devices.data.*")
    cvg_blk_list=$((cvg_blk_list+1))
done

# Validate data device and size exist in the solution file by checking the number of
# data.dX.device and the number of data.dX.size are equal
for sol_chk_e in "${solution_cvg_blk_data_dev[@]}"; do
    # Get a number of data devices
    num_data_dev=$(echo "${sol_chk_e}" | awk -F".device>" '{print NF-1}')
    num_data_size=$(echo "${sol_chk_e}" | awk -F".size>" '{print NF-1}')
    if [[ "${num_data_dev}" -lt "${num_data_size}" && "${validate_data_device}" = true ]]; then
        result_str="Missing data device info in 'solution.storage.cvg*.devices.data.d*'"
        result="failed"
    elif [[ "${num_data_dev}" -gt "${num_data_size}" && "${validate_data_size}" = true ]]; then
        result_str="Missing data size info in 'solution.storage.cvg*.devices.data.d*'"
        result="failed"
    fi
done

checkResult ${result} "${result_str}"

total_num_nodes="${#solution_node_list[@]}"
# Validate node names in the solution file
for sol_chk_e in "${solution_chk_node[@]}"; do
    found=false
    IFS=">" read -r -a sol_chk_array <<< "${sol_chk_e}"
    regex=$(buildRegexFromSolutionVar "${sol_chk_array[0]}")
    for element in "${solution_node_list[@]}"; do
        if [[ "${element}" =~ ${regex} || "${sol_chk_array[1]}" != "required" ]]; then
            found=true
        fi
    done

    if [[ "${found}" = false ]]; then
        # Find all the number in the string and replace it with "*".
        # shellcheck disable=SC2001
        temp_regex=$(echo "${sol_chk_e}" | sed -e 's/\([0-9]\+\)/*/g')
        temp_regex_val=$(echo "${temp_regex}" | cut -f1 -d'>')
        result_str="Failed to find '${temp_regex_val}' in the solution file"
        result="failed"
        break
    fi
done

checkResult ${result} "${result_str}"

sns_var_val=$(parseSolution 'solution.common.storage_sets.durability.sns')
dix_var_val=$(parseSolution 'solution.common.storage_sets.durability.dix')
sns_val=$(echo "${sns_var_val}" | cut -f2 -d'>')
dix_val=$(echo "${dix_var_val}" | cut -f2 -d'>')

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
