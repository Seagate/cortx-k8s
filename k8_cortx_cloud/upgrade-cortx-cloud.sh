#!/usr/bin/env bash

trap 'handle_error "$?" "${BASH_COMMAND:-?}" "${FUNCNAME[0]:-main}(${BASH_SOURCE[0]:-?}:${LINENO:-?})"' ERR
handle_error() {
  printf "%s Unexpected error caught -- %s %s\n    at %s\n" "${RED-}✘${CLEAR-}" "$2" "${RED-}↩ $1${CLEAR-}" "$3" >&2
  exit "$1"
}

SCRIPT=$(readlink -f "$0")
DIR=$(dirname "${SCRIPT}")
SCRIPT_NAME=$(basename "${SCRIPT}")
PIDFILE=/tmp/${SCRIPT_NAME}.pid
TIMEDELAY="15"

readonly SCRIPT
readonly DIR
readonly SCRIPT_NAME
readonly PIDFILE

if [[ -t 1 ]]; then
    RED=$(tput setaf 1 || true)
    GREEN=$(tput setaf 2 || true)
    CYAN=$(tput setaf 6 || true)
    CLEAR=$(tput sgr0 || true)
else
    RED=
    GREEN=
    CYAN=
    CLEAR=
fi

readonly RED
readonly GREEN
readonly CYAN
readonly CLEAR

# Use a PID file to prevent concurrent upgrades.
if [[ -s ${PIDFILE} ]]; then
   echo "An upgrade is already in progress (PID $(< "${PIDFILE}")). If this is incorrect, remove file ${PIDFILE} and try again."
   exit 1
fi
printf "%s" $$ > "${PIDFILE}"
trap 'rm -f "${PIDFILE}"' EXIT

function usage() {
    cat << EOF

Usage:
    ${SCRIPT_NAME} -i IMAGE [-s SOLUTION_CONFIG_FILE]
    ${SCRIPT_NAME} -h

Options:
    -h              Prints help information.
    -p <POD_TYPE>   REQUIRED. { data | control | ha | server | all }
    -s <FILE>       The cluster solution configuration file. Can
                    also be set with the CORTX_SOLUTION_CONFIG_FILE
                    environment variable. Defaults to 'solution.yaml'.
    --shutdown      To trigger Cold upgrade(shutdown cluster). By default Rolling upgrade
                    will be triggered.
EOF
}

function parse_solution() {
  "${DIR}/parse_scripts/parse_yaml.sh" "${SOLUTION_FILE}" "$1"
}

function validate_cortx_pods_status() {
    pods_ready=true
    cortx_pods="$(kubectl get pods --namespace="${NAMESPACE}" | { grep "${cortx_pod_filter}" || true; })"
    if [[ -z ${cortx_pods} ]]; then
        printf "  no CORTX Pods were found, proceeding with image upgrade anyways\n"
    else
        while IFS= read -r line; do
            IFS=" " read -r -a pod_info <<< "${line}"
            IFS="/" read -r -a ready_counts <<< "${pod_info[1]}"
            pod_name="${pod_info[0]}"
            pod_status="${pod_info[2]}"
            ready_count="${ready_counts[0]}"
            total_count="${ready_counts[1]}"
            if [[ -n ${pod_name} ]]; then
                if [[ ${pod_status} != "Running" ]]; then
                    printf "  %s %s -> status is %s\n" "${RED}✘${CLEAR}" "${pod_name}" "${pod_status}"
                    pods_ready=false
                elif (( ready_count != total_count )); then
                    printf "  %s %s -> only %s/%s pods are ready\n" "${RED}✘${CLEAR}" "${pod_name}" "${ready_count}" "${total_count}"
                    pods_ready=false
                else
                    printf "  %s %s\n" "${GREEN}✓${CLEAR}" "${pod_name}"
                fi
            fi
        done <<< "${cortx_pods}"
    fi
    printf "\n"

    if [[ ${pods_ready} == false ]]; then
        printf "Pre-upgrade pod readiness check failed. Ensure all pods are in a healthy state, or manually shutdown the cluster, and try again.\n"
        exit 1
    fi
}

function cold_upgrade() {
    # Shutdown all CORTX Pods
    "${DIR}/shutdown-cortx-cloud.sh" "${SOLUTION_FILE}"

    update_cortx_pod "$control_pod" "$cortxcontrol_image"
    update_cortx_pod "$ha_pod" "$cortxha_image"
    upgrade_cortx_deployments 'cortx-data-' "$cortxdata_image"
    upgrade_cortx_deployments 'cortx-server-' "$cortxserver_image"

    # Start all CORTX Pods
    "${DIR}/start-cortx-cloud.sh" "${SOLUTION_FILE}"
}

function pause_cortx_pod() {
    pod_name="$1"
    kubectl rollout pause deployment "$pod_name";
}

function update_cortx_pod() {
    pod_name="$1"
    upgrade_image="$2"
    kubectl patch deployment "$pod_name" --type json -p='[{"op": "add", "path": "/spec/template/spec/initContainers/0/env/-", "value": {"name": "COLD_UPGRADE", "value": "False"}}]';
    kubectl set image deployment "$pod_name" "*=$upgrade_image";
}

function resume_cortx_pod() {
    pod_name="$1"
    kubectl rollout resume deployment "$pod_name";
    sleep $TIMEDELAY;
}

function upgrade_cortx_deployments() {
    pod_filter="$1"
    upgrade_image="$2"
    while IFS= read -r line; do
        IFS=" " read -r -a deployments <<< "$line"
        upgrade_pod "${deployments[0]}" "$upgrade_image"
    done <<< "$(kubectl get deployments |grep "$pod_filter")"
}

function upgrade_pod() { 
    pod_name=$1
    upgrade_image=$2
    pause_cortx_pod $pod_name
    update_cortx_pod $pod_name $upgrade_image
    resume_cortx_pod $pod_name 
}

function rolling_upgrade() {
    case $POD_TYPE in
    control )
        upgrade_pod $control_pod $cortxcontrol_image
        ;;
    ha )
        upgrade_pod $ha_pod $cortxha_image
        ;;
    data )
        upgrade_cortx_deployments 'cortx-data-' $cortxdata_image
        ;;
    server )
        upgrade_cortx_deployments 'cortx-server-' $cortxserver_image
        ;;
    all )
        upgrade_pod $control_pod $cortxcontrol_image
        upgrade_pod $ha_pod $cortxha_image
        upgrade_cortx_deployments 'cortx-data-' $cortxdata_image
        upgrade_cortx_deployments 'cortx-server-' $cortxserver_image
        ;;
    * )
        echo -e "Invalid argument provided : $1"
        usage
        exit 1
        ;;
    esac
}

POD_TYPE=
UPGRADE_TYPE="Rolling"
SOLUTION_FILE="${CORTX_SOLUTION_CONFIG_FILE:-solution.yaml}"

while [ $# -gt 0 ];  do
    case $1 in
    -h )
        printf "%s\n" "${SCRIPT_NAME}"
        usage
        exit 0
        ;;
    -p )
        shift 1
        POD_TYPE=$1
        ;;
    -s )
        shift 1
        SOLUTION_FILE=$1
        ;;
    --shutdown )
        UPGRADE_TYPE="Cold"
        ;;
    * )
        echo -e "Invalid argument provided : $1"
        usage
        exit 1
        ;;
    esac
    shift 1
done

readonly POD_TYPE
readonly SOLUTION_FILE

if [[ -z ${POD_TYPE} ]]; then
    printf "\nERROR: Required option POD_TYPE is missing.\n"
    usage
    exit 1
fi

if [[ -z ${SOLUTION_FILE} ]]; then
    printf "\nERROR: Required option SOLUTION_CONFIG_FILE is missing.\n"
    usage
    exit 1
fi

if [[ ! -s ${SOLUTION_FILE} ]]; then
    printf "\nERROR: SOLUTION_CONFIG_FILE '%s' does not exist or is empty.\n" "${SOLUTION_FILE}"
    exit 1
fi

NAMESPACE=$(parse_solution 'solution.namespace' | cut -f2 -d'>')
if [[ -z ${NAMESPACE} ]]; then
    printf "\nERROR: Required field 'solution.namespace' not found in SOLUTION_CONFIG_FILE '%s'.\n" "${SOLUTION_FILE}"
    exit 1
fi

printf "Using solution config file '%s'\n" "${SOLUTION_FILE}"
cortxcontrol_image=$(parse_solution 'solution.images.cortxcontrol' | cut -f2 -d'>')
cortxha_image=$(parse_solution 'solution.images.cortxha' | cut -f2 -d'>')
cortxdata_image=$(parse_solution 'solution.images.cortxdata' | cut -f2 -d'>')
cortxserver_image=$(parse_solution 'solution.images.cortxserver' | cut -f2 -d'>')

readonly cortx_pod_filter="cortx-control-\|cortx-data-\|cortx-ha-\|cortx-server-\|cortx-client-"
readonly cortx_deployment_filter="cortx-control\|cortx-data-\|cortx-ha\|cortx-server-\|cortx-client-"
readonly control_pod="cortx-control"
readonly ha_pod="cortx-ha"

case $UPGRADE_TYPE in
    Cold )
        cold_upgrade
        ;;
    Rolling )
        # Validate if All CORTX Pods are running before initiating upgrade
        printf "\n%s\n" "${CYAN-}Checking Pod readiness:${CLEAR-}"
        validate_cortx_pods_status
        rolling_upgrade
        ;;
    * )
        echo -e "Invalid argument provided : $1"
        usage
        exit 1
        ;;
esac

# Validate if All CORTX Pods are running After upgrade is successful
printf "\n%s\n" "${CYAN-}Checking Pod readiness:${CLEAR-}"
validate_cortx_pods_status
