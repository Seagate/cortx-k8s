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
_VERSION=0.1.0
_ARGSHIFT=1

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
    echo "${_SCRIPT_NAME}: $1" > /dev/stderr
    [ $# -gt 2 ] && eval "$2" && exit "$3"
    [ $# -gt 1 ] && exit "$2"
    exit 1
}

# print log message
log() {
    echo "${_SCRIPT_NAME}: $1" > /dev/stderr
}

# print debug message if script called with verbose mode
debug() {
    [ "$_VERBOSE" ] && echo "${_SCRIPT_NAME}: $1" > /dev/stderr
}

usage() {
cat << EOF
usage: $0 [-v] [-c VALUE] [-d VALUE] [-e VALUE] [-m VALUE] [-n VALUE] [-s VALUE] [-x VALUE] [-y VALUE]

This script requires 'yq' to be available on your PATH. Visit github.com/mikefarah/yq for details.

Options:
-c   Number of desired CVGs in the generated cluster
-d   Number of desired data drives per CVG
-e   Desired size of each data drive
-m   Number of desired metadata drives per CVG (Currently hard-coded to 1)
-n   Desired size of each metadata drive
-s   The path to the solution.yaml file to be used as a template
-x   The path to the file to use for a list of nodes
-y   The path to the file to use for a list of device paths

Flags:
-v   Enable verbose mode

Standard Options:
-h   Show this help

Examples:

Generate YAML for 2 CVGs with 1 metadata drive and 52 data drives in each CVG, with both metadata and data drives of size 200Gi each:

    ./generate-cvg-yaml.sh -x test-106-nodes.txt -y test-106-devices.txt -c 2 -d 52 -s "solution9_106.yaml" -e "200Gi" -n "200Gi"

EOF
}

get_options() {
    _SILENT=
    _OPTSTRING="${_SILENT}c:d:e:m:n:s:x:y:v-:h"
    while getopts "${_OPTSTRING}" _OPTION
    do
      case "${_OPTION}" in
        h)
          usage
          exit 0;;
        c)
          _ARGSHIFT="${OPTIND}"
          NUM_CVGS=${OPTARG}
          ;;
        d)
          _ARGSHIFT="${OPTIND}"
          NUM_DATA_DRIVES=${OPTARG}
          ;;
        e)
          _ARGSHIFT="${OPTIND}"
          SIZE_DATA_DRIVE=${OPTARG}
          ;;
        m)
          _ARGSHIFT="${OPTIND}"
          NUM_METADATA_DRIVES=${OPTARG}
          ;;
        n)
          _ARGSHIFT="${OPTIND}"
          SIZE_METADATA_DRIVE=${OPTARG}
          ;;
        s)
          _ARGSHIFT="${OPTIND}"
          SOLUTION_YAML=${OPTARG}
          ;;
        x)
          _ARGSHIFT="${OPTIND}"
          NODE_LIST_FILE=${OPTARG}
          ;;
        y)
          _ARGSHIFT="${OPTIND}"
          DEVICE_PATHS_FILE=${OPTARG}
          ;;
        v)
          _ARGSHIFT="${OPTIND}"
          _VERBOSE=1
          ;;
       \?)
          # VERBOSE MODE
          # invalid option: _OPTION is set to ? (question-mark) and OPTARG is unset
          # required argument not found: _OPTION is set to ? (question-mark), OPTARG is unset and an error message is printed
          [ -z "$_SILENT" ] && usage && exit 1
          # SILENT MODE
          # invalid option: _OPTION is set to ? (question-mark) and OPTARG is set to the (invalid) option character
          [ ! -z "$_SILENT" ] && echo "illegal option -- ${OPTARG}"
          ;;
        :)
          # SILENT MODE
          # required argument not found: _OPTION is set to : (colon) and OPTARG contains the option-character in question
          echo "option requires an argument -- ${OPTARG}"
          ;;
      esac
    done
}

get_arguments() {
    _ARGS=""

    shift $(( _ARGSHIFT - 1 ))

    for _ARG in $_ARGS
    do
      if [ ! -z "$1" ]; then
        eval "$_ARG=$1"
      fi
      shift
    done
}

init() {
    get_options "$@"
    get_arguments "$@"


   # OPTIONS:
   debug " -- OPTIONS"
   debug "|"
   # $NUM_CVGS : Number of desired CVGs in the generated cluster
   debug "|   NUM_CVGS=$NUM_CVGS"
   # $NUM_DATA_DRIVES : Number of desired data drives per CVG
   debug "|   NUM_DATA_DRIVES=$NUM_DATA_DRIVES"
   # $SIZE_DATA_DRIVE : Desired size of each data drive
   debug "|   SIZE_DATA_DRIVE=$SIZE_DATA_DRIVE"
   # $NUM_METADATA_DRIVES : Number of desired metadata drives per CVG
   debug "|   NUM_METADATA_DRIVES=$NUM_METADATA_DRIVES"
   # $SIZE_METADATA_DRIVE : Desired size of each metadata drive
   debug "|   SIZE_METADATA_DRIVE=$SIZE_METADATA_DRIVE"
   # $SOLUTION_YAML : The path to the solution.yaml file to be used as a template
   debug "|   SOLUTION_YAML=$SOLUTION_YAML"
   # $NODE_LIST_FILE : The path to the file to use for a list of nodes
   debug "|   NODE_LIST_FILE=$NODE_LIST_FILE"
   # $DEVICE_PATHS_FILE : The path to the file to use for a list of device paths
   debug "|   DEVICE_PATHS_FILE=$DEVICE_PATHS_FILE"
   debug "|"

   # FLAGS:
   debug " -- FLAGS"
   debug "|"
   # $_VERBOSE : Enable verbose mode
   debug "|   _VERBOSE=$_VERBOSE"
   debug "|"
}

init "$@"

########################
##      MAIN          ##
########################
debug " -- PRE-REQS"
debug "|"

## Check for proper existence of NODE_LIST_FILE parameter
debug "|    NODE_LIST_FILE=\"${NODE_LIST_FILE}\""
if [[ "${NODE_LIST_FILE}" == "UNSET" ]]; then
  error "NODE_LIST_FILE is a required parameter and is unset." 1
fi
if [[ ! -f "${NODE_LIST_FILE}" ]]; then
  error "NODE_LIST_FILE is set but file does not exist." 1
fi

## Check for proper existence of DEVICE_PATHS_FILE parameter
debug "|    DEVICE_PATHS_FILE=\"${NODE_LIST_FILE}\""
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

## Parse nodes
debug " -- PARSED PARAMETERS"
debug "|"
debug "|    NODE_LIST_FILE:"
NODE_LIST=()
while IFS= read -r line; do
    NODE_LIST+=($line)
    debug "|      $line"
done <<< "$(cat $NODE_LIST_FILE)"

## Check for empty node list
if [[ "${#NODE_LIST[@]}" == "0" ]]; then
  error "Parsed NODE_LIST_FILE contents is empty" 1
fi

## Parse devices
DEVICE_PATHS=()
debug "|"
debug "|    DEVICE_PATH_FILE:"
while IFS= read -r line; do
    DEVICE_PATHS+=($line)
    debug "|      $line"
done <<< "$(cat $DEVICE_PATHS_FILE)"

## Check for empty device path list
if [[ "${#DEVICE_PATHS[@]}" == "0" ]]; then
  error "Parsed DEVICE_PATH_FILE contents is empty" 1
fi

printf "solution:\n" > $_YAML_BODY

## GENERATE STORAGE->CVG STANZA
_DEVICE_OFFSET=0
printf "  storage:\n" >> $_YAML_BODY
for cvg_instance in $(seq $NUM_CVGS); do
  printf "    cvg%s:\n" $cvg_instance >> $_YAML_BODY

  ## Front-pad cvg-name with leading zeroes
  _CVG_NAME=$cvg_instance
  if [[ "$_CVG_NAME" -lt "10" ]]; then
    _CVG_NAME="0$cvg_instance"
  fi

  printf "      name: cvg-%s\n" $_CVG_NAME >> $_YAML_BODY 
  printf "      type: ios\n" >> $_YAML_BODY
  printf "      devices:\n" >> $_YAML_BODY

  ##TODO (1.2) Determine if we currently can use multiple metadata drives
  printf "        metadata:\n" >> $_YAML_BODY
  printf "          device: %s\n" ${DEVICE_PATHS[$_DEVICE_OFFSET]} >> $_YAML_BODY
  ((_DEVICE_OFFSET=_DEVICE_OFFSET+1))

  printf "          size: %s\n" $SIZE_METADATA_DRIVE >> $_YAML_BODY

  printf "        data:\n" >> $_YAML_BODY
  for data_instance in $(seq 1 $NUM_DATA_DRIVES); do
    printf "          d%s:\n" $data_instance >> $_YAML_BODY
    printf "            device: %s\n" ${DEVICE_PATHS[$_DEVICE_OFFSET]} >> $_YAML_BODY
    ((_DEVICE_OFFSET=_DEVICE_OFFSET+1))

    printf "            size: %s\n" $SIZE_DATA_DRIVE >> $_YAML_BODY
  done 
done

## Generate Node stanza
printf "  nodes:\n" >> $_YAML_BODY
for node_instance in $(seq ${#NODE_LIST[@]}); do
  printf "    node%s:\n" $node_instance >> $_YAML_BODY
  printf "      name: %s\n" ${NODE_LIST[$node_instance-1]} >> $_YAML_BODY
done

yq ea 'del(select(fi==0) | .solution.storage) | del(select(fi==0) | .solution.nodes) | select(fi==0) * select(fi==1)' ${SOLUTION_YAML} ${_YAML_BODY}