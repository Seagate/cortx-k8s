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
    ${SCRIPT_NAME} [-s SOLUTION_CONFIG_FILE]
    ${SCRIPT_NAME} -h
Options:
    -h              Prints help information.
    -p <POD_TYPE>   { data | control | ha | server | all }
    -s <FILE>       The cluster solution configuration file. Can
                    also be set with the CORTX_SOLUTION_CONFIG_FILE
                    environment variable. Defaults to 'solution.yaml'.
EOF
}

function parse_solution() {
  "${DIR}/parse_scripts/parse_yaml.sh" "${SOLUTION_FILE}" "$1"
}

function validate_cortx_pods_status() {

    pods_ready=true

    readonly cortx_pod_filter="cortx-control-\|cortx-data-\|cortx-ha-\|cortx-server-\|cortx-client-"

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

function pause_deployment_pod() {
    printf "Pausing "$1"..\n";
    kubectl rollout pause deployment "$1";
}

function resume_deployment_pod() {
    printf "Pausing "$1"..\n";
    kubectl rollout pause deployment "$1";
}

function update_deployment_pod() {
    printf "Updating "$1" pod configuration..\n";
    kubectl set env deployment/"$1" UPGRADE_TYPE="Rolling" --containers="*";
    kubectl set image deployment "$1" "*=$2";
}

function upgrade_control_pod() {
    # Upgrade Control Pod
    cortxcontrol_image=$(parse_solution 'solution.images.cortxcontrol' | cut -f2 -d'>')

    pause_deployment_pod cortx-control;
    update_deployment_pod cortx-control "${cortxcontrol_image}"
    resume_deployment_pod cortx-control;
    sleep $TIMEDELAY;
    printf "Control Pod Upgraded\n";
}

function upgrade_ha_pod() {
    # Upgrad HA Pod
    cortxha_image=$(parse_solution 'solution.images.cortxha' | cut -f2 -d'>')

    pause_deployment_pod cortx-ha;
    update_deployment_pod cortx-ha "${cortxha_image}"
    resume_deployment_pod cortx-ha;
    sleep $TIMEDELAY;
    printf "HA Pod Upgraded\n";
}

function upgrade_data_pod() {
    # Upgrad Data Pods
    cortxdata_image=$(parse_solution 'solution.images.cortxdata' | cut -f2 -d'>')

    while IFS= read -r line; do
        IFS=" " read -r -a deployments <<< "$line"

        pause_deployment_pod "${deployments[0]}";
        update_deployment_pod "${deployments[0]}" "${cortxdata_image}"
        resume_deployment_pod "${deployments[0]}";
        sleep $TIMEDELAY;
        printf ""${deployments[0]}" Pod Upgraded\n";
    done <<< "$(kubectl get deployments |grep 'cortx-data-')"
}

function upgrade_server_pod() {
    # Upgrade Server Pods
    cortxserver_image=$(parse_solution 'solution.images.cortxserver' | cut -f2 -d'>')

    while IFS= read -r line; do
        IFS=" " read -r -a deployments <<< "$line"

        pause_deployment_pod "${deployments[0]}";
        update_deployment_pod "${deployments[0]}" "${cortxdata_image}"
        resume_deployment_pod "${deployments[0]}";
        sleep $TIMEDELAY;
        printf ""${deployments[0]}" Pod Upgraded\n";
    done <<< "$(kubectl get deployments |grep 'cortx-server-')"
}

SOLUTION_FILE="${CORTX_SOLUTION_CONFIG_FILE:-solution.yaml}"
POD_TYPE=

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
    * )
        echo -e "Invalid argument provided : $1"
        usage
        exit 1
        ;;
    esac
    shift 1
done

if [[ -z ${SOLUTION_FILE} ]]; then
    printf "\nERROR: Required option SOLUTION_CONFIG_FILE is missing.\n"
    usage
    exit 1
fi

if [[ -z ${POD_TYPE} ]]; then
    printf "\nERROR: Required option POD_TYPE is missing.\n"
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

# Validate if All CORTX Pods are running before initiating upgrade
printf "\n%s\n" "${CYAN-}Checking Pod readiness:${CLEAR-}"
validate_cortx_pods_status

case $POD_TYPE in
    control )
        upgrade_control_pod
        ;;
    ha )
        upgrade_ha_pod
        ;;
    data )
        upgrade_data_pod
        ;;
    server )
        upgrade_server_pod
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
