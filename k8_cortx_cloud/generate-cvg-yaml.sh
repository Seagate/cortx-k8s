#!/usr/bin/env bash

##
## Generated using npmjs.com/package/generator-bash
##

######
## TODO
######
## 1.1: Investigate more optimal YAML generation via yq
## 1.2: Determine if we currently can use multiple metadata drives

_SCRIPT_NAME=$0

NUM_CVGS=1
NUM_DATA_DRIVES=1
SIZE_DATA_DRIVE="5Gi"
NUM_METADATA_DRIVES=1
SIZE_METADATA_DRIVE="5Gi"
SOLUTION_YAML="solution.yaml"
NODE_LIST_FILE="UNSET"
DEVICE_PATHS_FILE="UNSET"
_VERBOSE=

_YAML_BODY="./tmp-yaml-body.yaml"

# print error message [ execute command ] and exit [ with defined status ]
error() {
    echo "${_SCRIPT_NAME}: $1" >&2
    (( $# > 2)) && eval "$2" && exit "$3"
    (( $# > 1 )) && exit "$2"
    exit 1
}

# print log message
log() {
    echo "${_SCRIPT_NAME}: $1" >&2
}

# print debug message if script called with verbose mode
debug() {
    [[ ${_VERBOSE} == 1 ]] && echo "${_SCRIPT_NAME}: $1" >&2
}

usage() {
cat << EOF
usage: $0 [-v] [-c VALUE] [-d VALUE] [-e VALUE] [-m VALUE] [-n VALUE] [-s VALUE] [-x VALUE] [-y VALUE]

This script requires 'yq' to be available on your PATH. Visit github.com/mikefarah/yq for details.

Options:
-c | --cvgs          Number of desired CVGs in the generated cluster
-d | --data          Number of desired data drives per CVG
-e | --datasize      Desired size of each data drive
-m | --metadata      Number of desired metadata drives per CVG (Currently hard-coded to 1)
-n | --metadatasize  Desired size of each metadata drive
-s | --solution      The path to the solution.yaml file to be used as a template
-x | --nodes         The path to the file to use for a list of nodes
-y | --devices       The path to the file to use for a list of device paths

Flags:
-v   Enable verbose mode

Standard Options:
-h   Show this help

Examples:

Generate YAML for 2 CVGs with 1 metadata drive and 52 data drives in each CVG, with both metadata and data drives of size 200Gi each (these commands are functionally identical):

    ./generate-cvg-yaml.sh -x nodes.txt -y devices.txt -c 2 -d 52 -s "solution9_106.yaml" -e "200Gi" -n "200Gi"

    ./generate-cvg-yaml.sh --nodes nodes.txt --devices devices.txt --cvgs 2 --data 52 --solution "solution9_106.yaml" --datasize "200Gi" --metadatasize "200Gi"

EOF
}

# Referenced via https://betterdev.blog/minimal-safe-bash-script-template/
get_options() {

  while :; do
    case "${1-}" in
    -h | --help)
      usage
      exit 0
      ;;
    -v | --verbose)
      _VERBOSE=1
      shift
      ;;
    -c | --cvgs) # Number of desired CVGs in the generated cluster
      NUM_CVGS="${2-}"
      shift
      ;;
    -d | --data) # Number of desired data drives per CVG
      NUM_DATA_DRIVES="${2-}"
      shift
      ;;
    -e | --datasize) # Desired size of each data drive
      SIZE_DATA_DRIVE="${2-}"
      shift
      ;;
    -m | --metadata) # Number of desired metadata drives per CVG (Currently hard-coded to 1)
      #NUM_METADATA_DRIVES="${2-}"
      NUM_METADATA_DRIVES="1"
      shift
      ;;
    -n | --metadatasize) # Desired size of each metadata drive
      SIZE_METADATA_DRIVE="${2-}"
      shift
      ;;
    -s | --solution) # The path to the solution.yaml file to be used as a template
      SOLUTION_YAML="${2-}"
      shift
      ;;
    -x | --nodes) # The path to the file to use for a list of nodes
      NODE_LIST_FILE="${2-}"
      shift
      ;;
    -y | --devices) # The path to the file to use for a list of device paths
      DEVICE_PATHS_FILE="${2-}"
      shift
      ;;
    -?*)
      error "Unknown option: $1"
      exit
      ;;
    *) break ;;
    esac
    shift
  done

  # check required params and arguments
  [[ -z "${NODE_LIST_FILE-}" ]] && die "Missing required parameter: --nodes"
  [[ -z "${DEVICE_PATHS_FILE-}" ]] && die "Missing required parameter: --devices"

  return 0

}

init() {
   get_options "$@"

   # OPTIONS:
   debug " -- OPTIONS"
   debug "|"
   # NUM_CVGS : Number of desired CVGs in the generated cluster
   debug "|   NUM_CVGS=${NUM_CVGS}"
   # NUM_DATA_DRIVES : Number of desired data drives per CVG
   debug "|   NUM_DATA_DRIVES=${NUM_DATA_DRIVES}"
   # SIZE_DATA_DRIVE : Desired size of each data drive
   debug "|   SIZE_DATA_DRIVE=${SIZE_DATA_DRIVE}"
   # NUM_METADATA_DRIVES : Number of desired metadata drives per CVG
   debug "|   NUM_METADATA_DRIVES=${NUM_METADATA_DRIVES}"
   # SIZE_METADATA_DRIVE : Desired size of each metadata drive
   debug "|   SIZE_METADATA_DRIVE=${SIZE_METADATA_DRIVE}"
   # SOLUTION_YAML : The path to the solution.yaml file to be used as a template
   debug "|   SOLUTION_YAML=${SOLUTION_YAML}"
   # NODE_LIST_FILE : The path to the file to use for a list of nodes
   debug "|   NODE_LIST_FILE=${NODE_LIST_FILE}"
   # DEVICE_PATHS_FILE : The path to the file to use for a list of device paths
   debug "|   DEVICE_PATHS_FILE=${DEVICE_PATHS_FILE}"
   debug "|"

   # FLAGS:
   debug " -- FLAGS"
   debug "|"
   # _VERBOSE : Enable verbose mode
   debug "|   _VERBOSE=${_VERBOSE}"
   debug "|"
}

init "$@"

########################
##      MAIN          ##
########################
debug " -- PRE-REQS"
debug "|"

## Check for proper existence of required NODE_LIST_FILE parameter
debug "|    NODE_LIST_FILE=\"${NODE_LIST_FILE}\""
if [[ "${NODE_LIST_FILE}" == "UNSET" ]]; then
  error "NODE_LIST_FILE is a required parameter and is unset." 1
fi
if [[ ! -f "${NODE_LIST_FILE}" ]]; then
  error "NODE_LIST_FILE is set but file does not exist." 1
fi

## Check for proper existence of required DEVICE_PATHS_FILE parameter
debug "|    DEVICE_PATHS_FILE=\"${DEVICE_PATHS_FILE}\""
if [[ "${DEVICE_PATHS_FILE}" == "UNSET" ]]; then
  error "DEVICE_PATHS_FILE is a required parameter and is unset." 1
fi
if [[ ! -f "${DEVICE_PATHS_FILE}" ]]; then
  error "DEVICE_PATHS_FILE  is set but file does not exist." 1
fi

## Check for jq/yq pre-reqs
YQ_AVAILABLE="$(which yq)"
debug "|    YQ_AVAILABLE=\"${YQ_AVAILABLE}\""
if [[ "${YQ_AVAILABLE}" == "" ]]; then
  error "'yq' is required for this script to run successfully. Visit github.com/mikefarah/yq for details." 1
fi

## Parse nodes - line delimited
debug " -- PARSED PARAMETERS"
debug "|"
debug "|    NODE_LIST_FILE:"
NODE_LIST=()
while IFS= read -r line; do
    NODE_LIST+=("${line}")
    debug "|      ${line}"
done < "${NODE_LIST_FILE}"

## Check for empty node list
if [[ "${#NODE_LIST[@]}" == "0" ]]; then
  error "Parsed NODE_LIST_FILE contents is empty" 1
fi

## Parse devices - line delimited
DEVICE_PATHS=()
debug "|"
debug "|    DEVICE_PATHS_FILE:"
while IFS= read -r line; do
    DEVICE_PATHS+=("${line}")
    debug "|      ${line}"
done < "${DEVICE_PATHS_FILE}"

## Check for empty device path list
if [[ "${#DEVICE_PATHS[@]}" == "0" ]]; then
  error "Parsed DEVICE_PATHS_FILE contents is empty" 1
fi

cp "${SOLUTION_YAML}" "${_YAML_BODY}"

yq -i e "del(.solution.storage_sets[0].storage[]) | del(.solution.storage_sets[0].nodes[])" ${_YAML_BODY} 

_DEVICE_OFFSET=0

## Generate CVGs stanza 
for ((cvg_instance = 1 ; cvg_instance <= NUM_CVGS ; cvg_instance++)); do

    ## Front-pad cvg-name with leading zeroes
    padding="00"
    _CVG_NAME="${padding:${#cvg_instance}:${#padding}}${cvg_instance}"
    _CVG_INDEX=$((cvg_instance-1))

    yq -i  e " with(.solution.storage_sets[0].storage[${_CVG_INDEX}] ; (
            .name = \"cvg-${_CVG_NAME}\"
            | .type = \"ios\" 
            | .devices = {} )) " "${_YAML_BODY}"

    # Generate metadata drive stanza
    yq -i  e " with(.solution.storage_sets[0].storage[${_CVG_INDEX}].devices.metadata ; (
            .device = \"${DEVICE_PATHS[${_DEVICE_OFFSET}]}\"
            | .size = \"${SIZE_METADATA_DRIVE}\" )) " "${_YAML_BODY}"
    ((_DEVICE_OFFSET=_DEVICE_OFFSET+1))

    # Generate data drive stanzas
    for ((data_instance = 0 ; data_instance < NUM_DATA_DRIVES ; data_instance++)); do
      yq -i  e " with(.solution.storage_sets[0].storage[${_CVG_INDEX}].devices.data[${data_instance}] ; (
            .device = \"${DEVICE_PATHS[${_DEVICE_OFFSET}]}\"
            | .size = \"${SIZE_DATA_DRIVE}\" )) " "${_YAML_BODY}"
      ((_DEVICE_OFFSET=_DEVICE_OFFSET+1))
    done

done

## Generate Nodes stanza
for ((node_instance = 1 ; node_instance <= ${#NODE_LIST[@]} ; node_instance++)); do
  yq -i e ".solution.storage_sets[0].nodes += \"${NODE_LIST[${node_instance}-1]}\" " ${_YAML_BODY}
done

# Dump to stdout with pretty-printed arrays etc.
yq -P e "." ${_YAML_BODY}

rm ${_YAML_BODY}
