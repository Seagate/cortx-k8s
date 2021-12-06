#!/usr/bin/env bash

##
## Generated using npmjs.com/package/generator-bash
##


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
Options:
-c, --num-cvgs              Number of desired CVGs in the generated cluster
-d, --num-data-drives       Number of desired data drives per CVG
-e, --size-data-drives      Desired size of each data drive
-m, --num-metadata-drives   Number of desired metadata drives per CVG
-n, --size-metadata-drives  Desired size of each metadata drive
-s, --solution-yaml         The path to the solution.yaml file to be used as a template
-x, --node-list-file        The path to the file to use for a list of nodes
-y, --device-path-file      The path to the file to use for a list of device paths

Flags:
-v, --verbose  Enable verbose mode

Standard Options:
--help     Show this help
--version  Show script version
EOF
}

get_options() {
    _SILENT=
    _OPTSTRING="${_SILENT}c:d:e:m:n:s:x:y:v-:"
    while getopts "${_OPTSTRING}" _OPTION
    do
      case "${_OPTION}" in
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
        -)
          case "${OPTARG}" in
            help) usage && exit 0;;
            version) echo "$_VERSION" && exit 0;;
            verbose)
              _VERBOSE=1
              _ARGSHIFT="${OPTIND}"
              ;;
            num-cvgs)
              eval NUM_CVGS="\$$OPTIND"; OPTIND=$(( OPTIND + 1 ))
              _ARGSHIFT="${OPTIND}"
              if [ -z "$NUM_CVGS" ] && [ -z "$_SILENT" ]; then
                error "option requires an argument -- ${OPTARG}" usage 1
              fi
              ;;
            num-cvgs=*)
              NUM_CVGS=${OPTARG#*=}
              _ARGSHIFT="${OPTIND}"
              if [ -z "$NUM_CVGS" ] && [ -z "$_SILENT" ]; then
              _OPTNAME=${OPTARG%=$NUM_CVGS}
                error "option requires an argument -- ${_OPTNAME}" usage 1
              fi
              ;;
            num-data-drives)
              eval NUM_DATA_DRIVES="\$$OPTIND"; OPTIND=$(( OPTIND + 1 ))
              _ARGSHIFT="${OPTIND}"
              if [ -z "$NUM_DATA_DRIVES" ] && [ -z "$_SILENT" ]; then
                error "option requires an argument -- ${OPTARG}" usage 1
              fi
              ;;
            num-data-drives=*)
              NUM_DATA_DRIVES=${OPTARG#*=}
              _ARGSHIFT="${OPTIND}"
              if [ -z "$NUM_DATA_DRIVES" ] && [ -z "$_SILENT" ]; then
              _OPTNAME=${OPTARG%=$NUM_DATA_DRIVES}
                error "option requires an argument -- ${_OPTNAME}" usage 1
              fi
              ;;
            size-data-drives)
              eval SIZE_DATA_DRIVE="\$$OPTIND"; OPTIND=$(( OPTIND + 1 ))
              _ARGSHIFT="${OPTIND}"
              if [ -z "$SIZE_DATA_DRIVE" ] && [ -z "$_SILENT" ]; then
                error "option requires an argument -- ${OPTARG}" usage 1
              fi
              ;;
            size-data-drives=*)
              SIZE_DATA_DRIVE=${OPTARG#*=}
              _ARGSHIFT="${OPTIND}"
              if [ -z "$SIZE_DATA_DRIVE" ] && [ -z "$_SILENT" ]; then
              _OPTNAME=${OPTARG%=$SIZE_DATA_DRIVE}
                error "option requires an argument -- ${_OPTNAME}" usage 1
              fi
              ;;
            num-metadata-drives)
              eval NUM_METADATA_DRIVES="\$$OPTIND"; OPTIND=$(( OPTIND + 1 ))
              _ARGSHIFT="${OPTIND}"
              if [ -z "$NUM_METADATA_DRIVES" ] && [ -z "$_SILENT" ]; then
                error "option requires an argument -- ${OPTARG}" usage 1
              fi
              ;;
            num-metadata-drives=*)
              NUM_METADATA_DRIVES=${OPTARG#*=}
              _ARGSHIFT="${OPTIND}"
              if [ -z "$NUM_METADATA_DRIVES" ] && [ -z "$_SILENT" ]; then
              _OPTNAME=${OPTARG%=$NUM_METADATA_DRIVES}
                error "option requires an argument -- ${_OPTNAME}" usage 1
              fi
              ;;
            size-metadata-drives)
              eval SIZE_METADATA_DRIVE="\$$OPTIND"; OPTIND=$(( OPTIND + 1 ))
              _ARGSHIFT="${OPTIND}"
              if [ -z "$SIZE_METADATA_DRIVE" ] && [ -z "$_SILENT" ]; then
                error "option requires an argument -- ${OPTARG}" usage 1
              fi
              ;;
            size-metadata-drives=*)
              SIZE_METADATA_DRIVE=${OPTARG#*=}
              _ARGSHIFT="${OPTIND}"
              if [ -z "$SIZE_METADATA_DRIVE" ] && [ -z "$_SILENT" ]; then
              _OPTNAME=${OPTARG%=$SIZE_METADATA_DRIVE}
                error "option requires an argument -- ${_OPTNAME}" usage 1
              fi
              ;;
            solution-yaml)
              eval SOLUTION_YAML="\$$OPTIND"; OPTIND=$(( OPTIND + 1 ))
              _ARGSHIFT="${OPTIND}"
              if [ -z "$SOLUTION_YAML" ] && [ -z "$_SILENT" ]; then
                error "option requires an argument -- ${OPTARG}" usage 1
              fi
              ;;
            solution-yaml=*)
              SOLUTION_YAML=${OPTARG#*=}
              _ARGSHIFT="${OPTIND}"
              if [ -z "$SOLUTION_YAML" ] && [ -z "$_SILENT" ]; then
              _OPTNAME=${OPTARG%=$SOLUTION_YAML}
                error "option requires an argument -- ${_OPTNAME}" usage 1
              fi
              ;;
            node-list-file)
              eval NODE_LIST_FILE="\$$OPTIND"; OPTIND=$(( OPTIND + 1 ))
              _ARGSHIFT="${OPTIND}"
              if [ -z "$NODE_LIST_FILE" ] && [ -z "$_SILENT" ]; then
                error "option requires an argument -- ${OPTARG}" usage 1
              fi
              ;;
            node-list-file=*)
              NODE_LIST_FILE=${OPTARG#*=}
              _ARGSHIFT="${OPTIND}"
              if [ -z "$NODE_LIST_FILE" ] && [ -z "$_SILENT" ]; then
              _OPTNAME=${OPTARG%=$NODE_LIST_FILE}
                error "option requires an argument -- ${_OPTNAME}" usage 1
              fi
              ;;
            device-path-file)
              eval DEVICE_PATHS_FILE="\$$OPTIND"; OPTIND=$(( OPTIND + 1 ))
              _ARGSHIFT="${OPTIND}"
              if [ -z "$DEVICE_PATHS_FILE" ] && [ -z "$_SILENT" ]; then
                error "option requires an argument -- ${OPTARG}" usage 1
              fi
              ;;
            device-path-file=*)
              DEVICE_PATHS_FILE=${OPTARG#*=}
              _ARGSHIFT="${OPTIND}"
              if [ -z "$DEVICE_PATHS_FILE" ] && [ -z "$_SILENT" ]; then
              _OPTNAME=${OPTARG%=$DEVICE_PATHS_FILE}
                error "option requires an argument -- ${_OPTNAME}" usage 1
              fi
              ;;
            *)
              if [ "$OPTERR" = 1 ] && [ -z "$_SILENT" ]; then
                error "illegal option -- ${OPTARG}" usage 1
              fi
              ;;
            esac;;
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
if [[ "${NODE_LIST_FILE}" == "UNSET" ]]; then
  error "NODE_LIST_FILE is a required parameter and is unset." 1
fi

if [[ "${DEVICE_PATHS_FILE}" == "UNSET" ]]; then
  error "DEVICE_PATHS_FILE is a required parameter and is unset." 1
fi

##TODO Check for jq/yq pre-reqs

## PARSE NODES
NODE_LIST=()
while IFS= read -r line; do
    NODE_LIST+=($line)
done <<< "$(cat $NODE_LIST_FILE)"
##TODO Check for empty node list

## PARSE DEVICES
DEVICE_PATHS=()
while IFS= read -r line; do
    DEVICE_PATHS+=($line)
done <<< "$(cat $DEVICE_PATHS_FILE)"
##TODO Check for empty device path list

YAML_BODY="./tmp-yaml-body.yaml"
rm $YAML_BODY

printf "solution:\n" >> $YAML_BODY

## GENERATE STORAGE->CVG STANZA
printf "  storage:\n" >> $YAML_BODY
for cvg_instance in $(seq $NUM_CVGS); do
  printf "    cvg%s:\n" $cvg_instance >> $YAML_BODY
  printf "      name: cvg-%s\n" $cvg_instance >> $YAML_BODY ##TODO front this with 001,002 to 099 to 106 formatting
  printf "      type: ios\n" >> $YAML_BODY
  printf "      devices:\n" >> $YAML_BODY

  ##TODO Determine if we currently can use multiple metadata drives
  printf "        metadata:\n" >> $YAML_BODY
  printf "          device: %s\n" ${DEVICE_PATHS[0]} >> $YAML_BODY
  printf "          size: %s\n" $SIZE_METADATA_DRIVE >> $YAML_BODY

  printf "        data:\n" >> $YAML_BODY
  for data_instance in $(seq 1 $NUM_DATA_DRIVES); do
    printf "          d%s:\n" $data_instance >> $YAML_BODY
    printf "            device: %s\n" ${DEVICE_PATHS[$data_instance]} >> $YAML_BODY
    printf "            size: %s\n" $SIZE_DATA_DRIVE >> $YAML_BODY
  done 
done

## GENERATE NODE STANZA
printf "  nodes:\n" >> $YAML_BODY
for node_instance in $(seq ${#NODE_LIST[@]}); do
  printf "    node%s:\n" $node_instance >> $YAML_BODY
  printf "      name: %s\n" ${NODE_LIST[$node_instance-1]} >> $YAML_BODY
done

#cat $YAML_BODY

yq ea 'del(select(fi==0) | .solution.storage) | del(select(fi==0) | .solution.nodes) | select(fi==0) * select(fi==1)' \
  ${SOLUTION_YAML} ${YAML_BODY}

rm $YAML_BODY