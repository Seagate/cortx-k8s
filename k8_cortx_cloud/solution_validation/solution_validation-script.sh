#!/bin/bash

solution_yaml=${1:-'solution.yaml'}
solution_chk_yaml='./solution_validation/solution_check.yaml'

function parseSolution()
{
    echo "$(./parse_scripts/parse_yaml.sh $solution_yaml $1)"
}

function buildRegexFromSolutionVar()
{
    string=$1
    # Find all the number in the string and replace it with "[0-9]+".
    # Example: 
    # string="solution.storage.cvg1.devices.data.d2.device"
    # regex="solution.storage.cvg[0-9]+.devices.data.d[0-9]+.device"
    local regex=$(echo "$string" | sed -e 's/\([0-9]\+\)/[0-9]+/g')
    echo "$regex"
}

solution_content=$(parseSolution)
solution_chk_content=$(./parse_scripts/parse_yaml.sh $solution_chk_yaml)

# Build a list that contains all the content in the solution.yaml file
solution_var_list=[]
count=0
cur_cvg_name=''
IFS=";" read -r -a my_array <<< "$solution_content"
for element in "${my_array[@]}"; do
    solution_var_list[$count]="$element"
    count=$((count+1))
done

# Build a list that contains "cvg" section in the "solution_check.yaml" file
solution_chk_cvg_var_list=[]
sol_chk_cvg_count=0
IFS=";" read -r -a my_array <<< "$solution_chk_content"
for element in "${my_array[@]}"; do
    if [[ "$element" == *".cvg"* ]]; then
        solution_chk_cvg_var_list[$sol_chk_cvg_count]="$element"
        sol_chk_cvg_count=$((sol_chk_cvg_count+1))
    fi
done

result="success"
result_str=""
validate_data_size=false
validate_data_device=false
IFS=";" read -r -a my_array <<< "$solution_chk_content"
for element in "${my_array[@]}"; do
    IFS=">" read -r -a element_array <<< "$element"
    found=false
    for e in "${solution_var_list[@]}"; do
        IFS=">" read -r -a e_array <<< "$e"
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

    if [[ "$found" = false && "${element_array[1]}" == "required" ]]; then
        # Find all the number in the string and replace it with "*".
        temp_regex=$(echo "$sol_chk_e" | sed -e 's/\([0-9]\+\)/*/g')
        result_str="Failed to find $temp_regex in the solution file"
        result="failed"
    fi
done

if [[ "$result" == "failed" ]]; then
    printf "$result_str\nValidate solution file result: $result\n"
    exit 1
fi

cvg_name_list=$(parseSolution 'solution.storage.cvg*.name')
# Get number of '>' show up in 'cvg_name_list' string
num_cvg=$(echo "$cvg_name_list" | awk -F">" '{print NF-1}')
# Build a list that contains cvg info
solution_cvg_blk_list=[]
cvg_blk_list=0
for index in $(seq 1 $num_cvg); do
    solution_cvg_blk_list[$cvg_blk_list]=$(parseSolution "solution.storage.cvg$index.*")
    cvg_blk_list=$((cvg_blk_list+1))
done

# Validate cvg name, type, metadata device, metadata size exist in the solution file
num_cvgs="${#solution_cvg_blk_list[@]}"
for sol_chk_e in "${solution_chk_cvg_var_list[@]}"; do
    IFS=">" read -r -a sol_chk_array <<< "$sol_chk_e"
    regex=$(buildRegexFromSolutionVar "${sol_chk_array[0]}")
    count=0
    for sol_e in "${solution_cvg_blk_list[@]}"; do
        if [[ "$sol_e" =~ $regex || "${sol_chk_array[1]}" != "required" ]]; then
            count=$((count+1))
        fi
    done

    found=false
    if [[ "$num_cvgs" == "$count" || "${sol_chk_array[1]}" != "required" ]]; then
        found=true
    fi

    if [[ "$found" = false ]]; then
        # Find all the number in the string and replace it with "*".
        temp_regex=$(echo "$sol_chk_e" | sed -e 's/\([0-9]\+\)/*/g')
        result_str="Failed to find $temp_regex in the solution file"
        result="failed"
        break
    fi
done

if [[ "$result" == "failed" ]]; then
    printf "$result_str\nValidate solution file result: $result\n"
    exit 1
fi

# Build a list that only contains data device info in cvg
solution_cvg_blk_data_dev=[]
cvg_blk_list=0
for index in $(seq 1 $num_cvg); do
    solution_cvg_blk_data_dev[$cvg_blk_list]=$(parseSolution "solution.storage.cvg$index.devices.data.*")
    cvg_blk_list=$((cvg_blk_list+1))
done
# Validate data device and size exist in the solution file by checking the number of
# data.dX.device and the number of data.dX.size are equal
for sol_chk_e in "${solution_cvg_blk_data_dev[@]}"; do
    # Get a number of data devices
    num_data_dev=$(echo "$sol_chk_e" | awk -F".device>" '{print NF-1}')
    num_data_size=$(echo "$sol_chk_e" | awk -F".size>" '{print NF-1}')
    if [[ "$num_data_dev" -lt "$num_data_size" && "$validate_data_device" = true ]]; then
        result_str="Missing data device info in 'solution.storage.cvg*.devices.data.d*'"
        result="failed"
    elif [[ "$num_data_dev" -gt "$num_data_size" && "$validate_data_size" = true ]]; then
        result_str="Missing data size info in 'solution.storage.cvg*.devices.data.d*'"
        result="failed"
    fi
done

printf "$result_str\nValidate solution file result: $result\n"
