#!/bin/bash

disk=${1:-''}
solution_yaml=${2:-'solution.yaml'}

if [[ "$disk" == *".yaml"* ]]; then
    temp=$disk
    disk=$solution_yaml
    solution_yaml=$temp
    if [[ "$disk" == "solution.yaml" ]]; then
        disk=""
    fi
fi

# Check if the file exists
if [ ! -f $solution_yaml ]
then
    echo "ERROR: $solution_yaml does not exist"
    exit 1
fi

get_nodes=$(kubectl get nodes 2>&1)
is_master_node=true
if [[ "$get_nodes" == *"was refused"* ]]; then
    is_master_node=false
fi

if [[ "$disk" == "" && "$is_master_node" = false ]]
then
    echo "Invalid input paramters"
    echo "./prereq-deploy-cortx-cloud.sh <disk-partition> [<solution-yaml-file>]"
    exit 1
fi

function parseYaml
{
    s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
    sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
    awk -F$fs '{
        indent = length($1)/2;
        vname[indent] = $2;
        for (i in vname) {if (i > indent) {delete vname[i]}}
        if (length($3) > 0) {
            vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])(".")}
            printf("%s%s>%s;",vn, $2, $3);
        }
    }'
}

function parseSolution()
{
    # Check that all of the required parameters have been passed in
    if [ "$solution_yaml" == "" ]
    then
        echo "Invalid input parameters"
        echo "<input yaml file>             = $solution_yaml"
        echo "[<yaml path filter> OPTIONAL] = $2"
        exit 1
    fi

    # Check if the file exists
    if [ ! -f $solution_yaml ]
    then
        echo "ERROR: $solution_yaml does not exist"
        exit 1
    fi

    # Store the parsed output in a single string
    PARSED_OUTPUT=$(parseYaml $solution_yaml)
    # Remove any additional indent '.' characters
    PARSED_OUTPUT=$(echo ${PARSED_OUTPUT//../.})

    # Star with empty output
    OUTPUT=""

    # Check if we need to do any filtering
    if [ "$2" == "" ]
    then
        OUTPUT=$PARSED_OUTPUT
    else
        # Split parsed output into an array of vars and vals
        IFS=';' read -r -a PARSED_VAR_VAL_ARRAY <<< "$PARSED_OUTPUT"
        # Loop the var val tuple array
        for VAR_VAL_ELEMENT in "${PARSED_VAR_VAL_ARRAY[@]}"
        do
            # Get the var and val from the tuple
            VAR=$(echo $VAR_VAL_ELEMENT | cut -f1 -d'>')
            # Check is the filter matches the var
            if [[ $VAR == $2 ]]
            then
                # If the OUTPUT is empty set it otherwise append
                if [ "$OUTPUT" == "" ]
                then
                    OUTPUT=$VAR_VAL_ELEMENT
                else
                    OUTPUT=$OUTPUT";"$VAR_VAL_ELEMENT
                fi
            fi
        done
    fi

    # Return the parsed output
    echo $OUTPUT
}

function cleanupFolders()
{
    printf "####################################################\n"
    printf "# Clean up                                          \n"
    printf "####################################################\n"
    # cleanup
    #WL: Not sure if /var/data/3rd-party is needed.  Need to test by
    #    removing this in coordination with prep3rdPartyDirs below
    rm -rf /var/data/3rd-party/*
    rm -rf $fs_mount_path/local-path-provisioner/*
}

function increaseResources()
{
    # Increase Resources
    sysctl -w vm.max_map_count=30000000;
}

function prepCortxDeployment()
{
    printf "####################################################\n"
    printf "# Prep for CORTX deployment                         \n"
    printf "####################################################\n"

    if [[ $(findmnt -m $fs_mount_path) ]];then
        echo "$fs_mount_path already mounted..."
    else
        mkdir -p $fs_mount_path
        echo y | mkfs.ext4 $disk
        mount -t ext4 $disk $fs_mount_path
    fi

    # Prep for Rancher Local Path Provisioner deployment
    echo "Create folder '$fs_mount_path/local-path-provisioner'"
    mkdir -p $fs_mount_path/local-path-provisioner
    count=0
    while true; do
        if [[ -d $fs_mount_path/local-path-provisioner || $count -gt 5 ]]; then
            break
        else
            echo "Create folder '$fs_mount_path/local-path-provisioner' failed. Retry..."
            mkdir -p $fs_mount_path/local-path-provisioner
        fi
        count=$((count+1))
        sleep 1s
    done
}


# WL: Note: Not sure if this needs to be here.  I need to test
#     with these removed.
function prep3rdPartyDirs()
{
    mkdir -p /var/data/3rd-party
    mkdir -p /var/log/3rd-party
}

function installHelm()
{
    printf "####################################################\n"
    printf "# Install helm                                      \n"
    printf "####################################################\n"
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
}

# Extract storage provisioner path from the "solution.yaml" file
filter='solution.common.storage_provisioner_path'
parse_storage_prov_output=$(parseSolution $solution_yaml $filter)
# Get the storage provisioner var from the tuple
fs_mount_path=$(echo $parse_storage_prov_output | cut -f2 -d'>')

namespace=$(parseSolution $solution_yaml 'solution.namespace')
namespace=$(echo $namespace | cut -f2 -d'>')

# Install helm this is a master node
if [[ "$is_master_node" = true ]]; then
    installHelm
fi

# Perform the following functions if the 'disk' is provided
if [[ "$disk" != "" ]]; then
    cleanupFolders
    increaseResources
    prepCortxDeployment
    prep3rdParyDirs
fi
