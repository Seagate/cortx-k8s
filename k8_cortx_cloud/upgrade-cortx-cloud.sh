#!/usr/bin/env bash

set -euo pipefail

trap 'handle_error "$?" "${BASH_COMMAND:-?}" "${FUNCNAME[0]:-main}(${BASH_SOURCE[0]:-?}:${LINENO:-?})"' ERR
handle_error() {
  printf "%s Unexpected error caught -- %s %s\n    at %s\n" "${RED-}✘${CLEAR-}" "$2" "${RED-}↩ $1${CLEAR-}" "$3" >&2
  exit "$1"
}

SCRIPT=$(readlink -f "$0")
DIR=$(dirname "${SCRIPT}")
SCRIPT_NAME=$(basename "${SCRIPT}")
PIDFILE=/tmp/${SCRIPT_NAME}.pid

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
    -i <IMAGE>      REQUIRED. The name of the container image to upgrade to.
                    This image may be any of the three CORTX container images
                    (cortx-data, cortx-rgw, cortx-control).  Specifying any
                    one of these images will pull all three images of the
                    same version and apply them to the appropriate
                    Deployments / StatefulSets. 
    -s <FILE>       The cluster solution configuration file. Can
                    also be set with the CORTX_SOLUTION_CONFIG_FILE
                    environment variable. Defaults to 'solution.yaml'.
EOF
}

function parse_solution() {
  "${DIR}/parse_scripts/parse_yaml.sh" "${SOLUTION_FILE}" "$1"
}

UPGRADE_IMAGE=
SOLUTION_FILE="${CORTX_SOLUTION_CONFIG_FILE:-solution.yaml}"

while getopts hi:s: opt; do
    case ${opt} in
        h )
            printf "%s\n" "${SCRIPT_NAME}"
            usage
            exit 0
            ;;
        i ) UPGRADE_IMAGE=${OPTARG} ;;
        s ) SOLUTION_FILE=${OPTARG} ;;
        * )
            usage >&2
            exit 1
            ;;
    esac
done
shift "$((OPTIND-1))"

readonly UPGRADE_IMAGE
readonly SOLUTION_FILE

if [[ -z ${UPGRADE_IMAGE} ]]; then
    printf "\nERROR: Required option IMAGE is missing.\n"
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

# Validate if All Pods are running
pods_ready=true

readonly cortx_pod_filter="cortx-control-\|cortx-data-\|cortx-ha-\|cortx-server-\|cortx-client-"
readonly cortx_deployment_filter="cortx-control\|cortx-data-\|cortx-ha\|cortx-server\|cortx-client-"

printf "\n%s\n" "${CYAN-}Checking Pod readiness:${CLEAR-}"

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

# Shutdown all CORTX Pods
"${DIR}/shutdown-cortx-cloud.sh" "${SOLUTION_FILE}"

cortx_deployments="$(kubectl get deployments,statefulset --namespace="${NAMESPACE}" --output=jsonpath="{range .items[*]}{.metadata.name}{'\n'}{end}" | { grep "${cortx_deployment_filter}" || true; })"
if [[ -z ${cortx_deployments} ]]; then
    printf "No CORTX Deployments were found so the image upgrade cannot be performed. The cluster will be restarted.\n"
else
    RGW_IMAGE="${UPGRADE_IMAGE/cortx-*:/cortx-rgw:}"
    DATA_IMAGE="${UPGRADE_IMAGE/cortx-*:/cortx-data:}"
    CONTROL_IMAGE="${UPGRADE_IMAGE/cortx-*:/cortx-control:}"

    printf "Updating CORTX Deployments to use:\n"
    printf "   %s\n" "${RGW_IMAGE}"
    printf "   %s\n" "${DATA_IMAGE}"
    printf "   %s\n" "${CONTROL_IMAGE}"
    printf "\n"

    k8s_controller="deployment"
    while IFS= read -r deployment; do
        case "${deployment}" in
        cortx-server-*) 
            IMAGE="${RGW_IMAGE}"
            k8s_controller="statefulset"
            ;;
        cortx-data-*|cortx-client-*)
            IMAGE="${DATA_IMAGE}"
            k8s_controller="deployment"
            ;;
        cortx-control|cortx-ha)
            IMAGE="${CONTROL_IMAGE}"
            k8s_controller="deployment"
            ;;
        *) 
            printf "NO MATCH FOR %s.  Skipping upgrade of image.\n" "${deployment}"
            continue
            ;;
        esac

        printf "Updating CORTX component %s to use image %s\n" "${deployment}" "${IMAGE}"
        kubectl set image --namespace="${NAMESPACE}" ${k8s_controller} "${deployment}" "*=${IMAGE}"

    done <<< "${cortx_deployments}"
    printf "\n"
fi

# Start all CORTX Pods
"${DIR}/start-cortx-cloud.sh" "${SOLUTION_FILE}"
