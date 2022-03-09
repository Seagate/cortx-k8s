#!/bin/bash

SCRIPT=$(readlink -f "$0")
DIR=$(dirname "${SCRIPT}")
SCRIPT_NAME=$(basename "${SCRIPT}")

# Script defaults
disk=""
solution_yaml="${CORTX_SOLUTION_CONFIG_FILE:-solution.yaml}"
persist_fs_mount_path=false
default_fs_type="ext4"

# This value will separate `/dev/sdc` or `/dev/sdc1` device paths to symlinks created under
# `/dev/cortx/sdc` or `/dev/cortx/sdc1`
symlink_block_devices=false
symlink_block_devices_separator="cortx"

function usage() {
    cat << EOF

Usage:
    ${SCRIPT_NAME} -d DISK [-s SOLUTION_CONFIG_FILE] [-p] [[-b] [-c SEPARATOR]]
    ${SCRIPT_NAME} -h

Options:
    -h              Prints this help information.

    -d <DISK>       REQUIRED. The path of the disk or device to mount for
                    secondary storage.

    -s <FILE>       The cluster solution configuration file. Can
                    also be set with the CORTX_SOLUTION_CONFIG_FILE
                    environment variable. Defaults to 'solution.yaml'.

    -p              The prereq script will attempt to update /etc/fstab
                    with an appropriate mountpoint for persistent reboots.

    -b              Create symlinks for persistent block device access, based
                    upon device paths defined in 'solution.yaml' and the
                    symlink path separator defined with the '-c' option.
                    As an example, '/dev/sdc' will have a new symlink available via
                    '/dev/cortx/sdc' for persistent access across reboots.
                    This option will also create an updated '{solution}-symlink.yaml'
                    file that should be used for subsequent deployment with
                    'deploy-cortx-cloud.sh'.

    -c              The symlink path separator used in conjunction with '-b'
                    option to create symlinks for persistent block device access.
                    Defaults to 'cortx'.

EOF
}

# Parameter parsing breaks when errant arguments are passed in prior to -* options
# Script should ignore arguments that are before any defined flags in getopts
# This should only be an error condition / edge case.
# ' ./{SCRIPT_NAME} random-string -s solution.yaml -b -c "cortx123" ' breaks getopts parsing

while getopts hd:s:pbc: opt; do
    case ${opt} in
        h )
            printf "%s\n" "${SCRIPT_NAME}"
            usage
            exit 0
            ;;
        d ) disk=${OPTARG} ;;
        s ) solution_yaml=${OPTARG} ;;
        p ) persist_fs_mount_path=true ;;
        b ) symlink_block_devices=true ;;
        c ) symlink_block_devices_separator=${OPTARG} ;;
        \?)
            usage >&2
            exit 1
            ;;
        * )
            usage >&2
            exit 1
            ;;
    esac
done

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
    echo "ERROR: Invalid input parameters"
    usage
    exit 1
fi

# Validate symlink_block_devices_separator is a valid path string
# Examples:
# 'cortx' is acceptable
# 'c&rtx#' is not
results=$(echo "${symlink_block_devices_separator}"  | grep -x -E -e  '[-_A-Za-z0-9]+(/[-_A-Za-z0-9]*)*')
if [[ "${results}" == "" ]]; then
    echo "ERROR: Invalid input parameters - the symlink_block_devices_separator '-c' must be a valid path-compatible string."
    usage
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
    if [ "${1}" == "" ]
    then
        echo "ERROR: Invalid input parameters"
        echo "Input YAML file is an empty string"
        echo "[<yaml path filter> OPTIONAL] = ${2}"
        usage
        exit 1
    fi

    # Check if the file exists
    if [ ! -f ${1} ]
    then
        echo "ERROR: ${1} does not exist"
        usage
        exit 1
    fi

    # Store the parsed output in a single string
    PARSED_OUTPUT=$(parseYaml ${1})
    # Remove any additional indent '.' characters
    PARSED_OUTPUT=$(echo ${PARSED_OUTPUT//../.})

    # Star with empty output
    OUTPUT=""

    # Check if we need to do any filtering
    if [ "${2}" == "" ]
    then
        OUTPUT=${PARSED_OUTPUT}
    else
        # Split parsed output into an array of vars and vals
        IFS=';' read -r -a PARSED_VAR_VAL_ARRAY <<< "${PARSED_OUTPUT}"
        # Loop the var val tuple array
        for VAR_VAL_ELEMENT in "${PARSED_VAR_VAL_ARRAY[@]}"
        do
            # Get the var and val from the tuple
            VAR=$(echo ${VAR_VAL_ELEMENT} | cut -f1 -d'>')
            # Check is the filter matches the var
            if [[ ${VAR} == ${2} ]]
            then
                # If the OUTPUT is empty set it otherwise append
                if [ "${OUTPUT}" == "" ]
                then
                    OUTPUT=${VAR_VAL_ELEMENT}
                else
                    OUTPUT=${OUTPUT}";"${VAR_VAL_ELEMENT}
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
        echo y | mkfs.${default_fs_type} $disk
        mount -t ${default_fs_type} $disk $fs_mount_path
    fi

    ###################################################################
    ### CORTX-27775 - PART 1
    ### THIS CODE BLOCK PERSISTS THE MOUNT POINT IN /etc/fstab
    ### THIS FIX RESOLVES REBOOT ISSUES WITH PREREQ STORAGE AND REBOOTS
    ###################################################################
    # If -p (persistence flag) was passed in from command line
    if [[ "${persist_fs_mount_path}" == "true" ]]; then
        printf "Persistence of %s at %s enabled:\n" ${disk} ${fs_mount_path}

        local backup_chars
        local blk_uuid
        local exists_in_fstab

        # Check if we are running on busybox / using busybox's blkid binary,
        # as it does not support the commands below
        if (( "$(blkid --version)" != "" )); then
            # As the disk passed in will either already have been mounted by the user or by the script,
            # the blkid command will return the UUID of the mounted filesystem either way
            blk_uuid=$(blkid ${disk} -o export | grep UUID | awk '{split($0,a,"="); print a[2]}')
            if [[ "${blk_uuid}" != "" ]]; then
                # Check /etc/fstab for presence of requested disk or filesystem mount path
                if ! grep -e "${blk_uuid}" -e "${fs_mount_path}" /etc/fstab; then
                    # /etc/fstab does not contain a mountpoint for the desired disk and path
                    backup_chars=$(date +%s)
                    printf "\tBacking up existing '/etc/fstab' to '/etc/fstab.%s.backup'\n" "${backup_chars}"
                    cp /etc/fstab "/etc/fstab.${backup_chars}.backup"
                    printf "UUID=%s  %s      %s   defaults 0 0\n" ${blk_uuid} ${fs_mount_path} ${default_fs_type} >> /etc/fstab
                    printf "\t'/etc/fstab' has been updated to persist %s at %s.\n\tIt should be manually verified for correctness prior to system reboot.\n\n" ${disk} ${fs_mount_path}
                else
                    # /etc/fstab contains a mountpoint for the desired disk and path
                    printf "\t'/etc/fstab' already contains a mountpoint entry for %s at path %s.\n\tIf this is not expected, it should be manually edited.\n\n" ${disk} ${fs_mount_path}
                fi
            fi
        else
            printf "This script is attempting to use an unsupported 'blkid' binary. Please use a compatible util-linux version of 'blkid' instead."
        fi
    fi
    ###################################################################
    ### END CORTX-27775 - PART 1
    ###################################################################

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

function join_array()
{
  local IFS="$1"
  shift
  echo "$*"
}


## Function 'symlinkBlockDevices' - enabled via the '-b' flag
## ----------------------------------------------------------
##      Create symlinks for persistent block device access, based
##      upon device paths defined in 'solution.yaml' and the
##      symlink path separator defined with the '-c' option.
##      As an example, '/dev/sdc' will have a new symlink available via
##      '/dev/cortx/sdc' for persistent access across reboots.
##      This option will also create an updated '{solution}-symlink.yaml'
##      file that should be used for subsequent deployment with
##      'deploy-cortx-cloud.sh'.
##
##      Background
##      - This implementation is meant to be invoked from a control-plane
##        node with local kubectl access and requires parsing node information
##        from solution.yaml
##      - An alternative implementation would be to be run on the individual
##        node itself, using NODE_NAME=$(hostname) with no need for looping
##        through nodes defined in solution.yaml, but requiring local kubectl access.
function symlinkBlockDevices()
{
    printf "####################################################\n"
    printf "# Create Block Device Symlinks                      \n"
    printf "####################################################\n"

    # Local variables
    local filter
    local node_list=()
    local device_paths=()
    local job_template="$(pwd)/cortx-cloud-3rd-party-pkg/templates/job-symlink-block-devices.yaml.template"
    local template_vars='${NODE_NAME}:${NODE_SHORT_NAME}:${DEVICE_PATHS}:${SYMLINK_PATH_SEPARATOR}:${CORTX_IMAGE}'
    local job_file="jobs-symlink-block-devices-$(hostname -s).yaml"

    # Template replacement variable
    export SYMLINK_PATH_SEPARATOR=${symlink_block_devices_separator}

    # Retrieve CORTX container image specified in solution.yaml
    filter="solution.images.cortxcontrol"
    cortx_image_yaml=$(parseSolution ${solution_yaml} ${filter})
    export CORTX_IMAGE="${cortx_image_yaml#*>}"

    # Create comma-separated string from the device paths in solution.yaml
    filter="solution.storage.cvg*.devices*.device"
    device_output=$(parseSolution ${solution_yaml} ${filter})
    IFS=';' read -r -a device_array <<< "${device_output}"
    for device_path in "${device_array[@]}"
    do
        device_paths+=(${device_path#*>})
    done
    # Template replacement variable
    export DEVICE_PATHS=$(join_array "," "${device_paths[@]}")

    # Prepare local templated Job definition
    rm -f ${job_file}

    # Iterate over the defined nodes in solution.yaml
    filter="solution.nodes.node*.name"
    node_output=$(parseSolution ${solution_yaml} ${filter})
    IFS=';' read -r -a node_array <<< "${node_output}"
    for node_element in "${node_array[@]}"
    do
        # Template replacement variable
        export NODE_NAME="${node_element#*>}"
        export NODE_SHORT_NAME="${NODE_NAME%%.*}"

        # Generate templated Job definition
        envsubst "${template_vars}" < "${job_template}" >> ${job_file}
        printf "\n---\n" >> ${job_file}

        # Delete previous jobs that may exist for this specific node
        kubectl delete jobs -l "cortx.io/task=symlink-block-devices" -l "kubernetes.io/hostname=${NODE_NAME}" --ignore-not-found
    done

    # Apply templated Job definitions to Kubernetes
    kubectl apply -f ${job_file}

    # Wait for all Jobs to complete successfully
    printf "Waiting for 'symlink-block-devices' Jobs to complete successfully...\n"
    sleep 10
    kubectl wait jobs -l "cortx.io/task=symlink-block-devices" --for="condition=Complete" --timeout=30s

    ##  If timeout, wait again
    if (( $? != 0 )); then
        printf "Timed out waiting for Jobs to complete successfully. Will attempt to wait again...\n"
        kubectl wait jobs -l "cortx.io/task=symlink-block-devices" --for="condition=Complete" --timeout=30s

        ##  If timeout again, fail and exit out of installer with user directives.
        if (( $? != 0 )); then
            printf "Timed out waiting for Jobs to complete successfully again. Corrective user action should be taken.\n"
            exit 1
        fi
    fi

    # Update solution.yaml used as input with new symlink_block_device_paths
    # and output to {solution}-symlink.yaml and notify user to use new
    # {solution}-symlink.yaml for input to `deploy-cortx-cloud.sh`
    SYMLINK_SOLUTION_YAML="${solution_yaml%.yaml}-symlink.yaml"
    printf "Saving an updated solution.yaml file at %s\n" ${SYMLINK_SOLUTION_YAML}
    printf "Use this new file when running 'deploy-cortx-cloud.sh' in the future to use your symlinked block devices.\n"
    sed "s#/dev#/dev/${SYMLINK_PATH_SEPARATOR}#g" ${solution_yaml} > ${SYMLINK_SOLUTION_YAML}
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

    ###################################################################
    ### CORTX-27775 - PART 2
    ###################################################################
    if [[ "${symlink_block_devices}" == "true" ]]; then
        symlinkBlockDevices
    fi
    ###################################################################
    ### END CORTX-27775 - PART 2
    ###################################################################
fi

# Perform the following functions if the 'disk' is provided
if [[ "$disk" != "" ]]; then
    cleanupFolders
    increaseResources
    prepCortxDeployment
fi
