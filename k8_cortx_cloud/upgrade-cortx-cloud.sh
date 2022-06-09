#!/usr/bin/env bash

trap 'handle_error "$?" "${BASH_COMMAND:-?}" "${FUNCNAME[0]:-main}(${BASH_SOURCE[0]:-?}:${LINENO:-?})"' ERR
trap "./upgrade-cortx-cloud.sh suspend" SIGINT SIGTERM
handle_error() {
  printf "%s Unexpected error caught -- %s %s\n    at %s\n" "${RED-}✘${CLEAR-}" "$2" "${RED-}↩ $1${CLEAR-}" "$3" >&2
  exit "$1"
}

SCRIPT=$(readlink -f "$0")
DIR=$(dirname "${SCRIPT}")
SCRIPT_NAME=$(basename "${SCRIPT}")
PIDFILE=/tmp/${SCRIPT_NAME}.pid
TIMEDELAY="50"

readonly SCRIPT
readonly DIR
readonly SCRIPT_NAME

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

PIDFILE=/tmp/upgrade.sh.pid
UPGRADE_DATA_TEMPLATE="./upgrade-data-template.yaml"
UPGRADE_DATA="./upgrade-data.yaml"

# Compatibility check related constants
RULES=""

function usage() {
    cat << EOF

Usage:
    ${SCRIPT_NAME} [prepare | start | suspend | resume | status] [-p POD_TYPE] [-c COLD_UPGRADE] [-s SOLUTION_CONFIG_FILE]
    ${SCRIPT_NAME} -h

Options:
    -h              Prints help information.
    prepare         Performs pre-upgrade checks.
    start           initiates upgrade on CORTX cluster.
    suspend         suspend current SW upgrade process.
    resume          resume sw upgrade process.
    status          check the status of current SW upgrade process 
    -p <POD_TYPE>   REQUIRED. { data | control | ha | server | all }
    -s <FILE>       The cluster solution configuration file. Can
                    also be set with the CORTX_SOLUTION_CONFIG_FILE
                    environment variable. Defaults to 'solution.yaml'.
    -cold           To trigger Cold upgrade(shutdown cluster). By default Rolling upgrade
                    will be triggered.
EOF
}

function parse_solution() {
  "${DIR}/parse_scripts/parse_yaml.sh" "${SOLUTION_FILE}" "$1"
}

function validate_upgrade_images() {
    image="$1"
    if docker pull ${image} > /dev/null; then
        echo "Image ${image} downloaded successfully"
    else
        echo "Error: Download Image ${image} failed, Please Provide Valid image"
        exit 1
    fi
}

function fetch_solution_images() {
    printf "Using solution config file '%s'\n" "${SOLUTION_FILE}"
    # Fetch Upgrade Images from solution.yaml and validate them
    cortxcontrol_image=$(parse_solution 'solution.images.cortxcontrol' | cut -f2 -d'>')
    validate_upgrade_images "${cortxcontrol_image}"
    cortxha_image=$(parse_solution 'solution.images.cortxha' | cut -f2 -d'>')
    validate_upgrade_images "${cortxha_image}"
    cortxdata_image=$(parse_solution 'solution.images.cortxdata' | cut -f2 -d'>')
    validate_upgrade_images "${cortxdata_image}"
    cortxserver_image=$(parse_solution 'solution.images.cortxserver' | cut -f2 -d'>')
    validate_upgrade_images "${cortxserver_image}"
}

function Validate_upgrade_status() {
    status=true
    while IFS= read -r deployment; do
        deployment_name=${deployment}
        upgrade_status=$(yq '.cortx.deployments."'${deployment_name}'".status' "${UPGRADE_DATA}")
        if [[ "${upgrade_status}" != "Done" ]]; then
            status=false
            break
        else
            continue
        fi
    done <<< "$(kubectl get deployments --output=jsonpath="{range .items[*]}{.metadata.name}{'\n'}{end}" --namespace="${NAMESPACE}"  | grep 'cortx')"
    if ${status}
    then
        yq e '.cortx.status='\"Done\"'' -i "${UPGRADE_DATA}"
    fi

}

function cold_upgrade() {

    fetch_solution_images
    # Shutdown all CORTX Pods
    "${DIR}/shutdown-cortx-cloud.sh" "${SOLUTION_FILE}"

    cortx_deployments="$(kubectl get deployments --output=jsonpath="{range .items[*]}{.metadata.name}{'\n'}{end}" --namespace="${NAMESPACE}" | grep 'cortx')"
    if [[ -z ${cortx_deployments} ]]; then
        printf "No CORTX Deployments were found so the image upgrade cannot be performed. The cluster will be restarted.\n"
    else
        while IFS= read -r deployment; do
            upgrade_image="$(fetch_upgrade_image "${deployment}")"
            kubectl set image deployment "${deployment}" *="${upgrade_image}" --namespace="${NAMESPACE}";
            kubectl set env deployment/"${deployment}" UPGRADE_MODE="COLD" --namespace="${NAMESPACE}"
        done <<< "${cortx_deployments}"
        printf "\n"
    fi

    # Start all CORTX Pods
    "${DIR}/start-cortx-cloud.sh" "${SOLUTION_FILE}"
}

function rolling_upgrade() {
    if [[ "${PROCESS}" == "start" ]] || [[ "${PROCESS}" == "prepare" ]]; then
            if [[ -z "${POD_TYPE}" ]]; then
                printf "\nERROR: Required option POD_TYPE is missing.\n"
                usage
                exit 1
            fi
    fi
    case "${PROCESS}" in
        prepare )
            if [[ "${POD_TYPE}" == "all" ]]; then
                POD_TYPE="cortx"
            fi
            prepare_upgrade "${POD_TYPE}"
            ;;
        start )
            fetch_solution_images
            if [[ "${POD_TYPE}" == "all" ]]; then
                POD_TYPE="cortx"
            fi
            start_upgrade "${POD_TYPE}"
            Validate_upgrade_status
            ;;
        suspend )
            suspend_upgrade
            ;;
        resume )
            resume_upgrade
            Validate_upgrade_status
            ;;
        status )
            status_upgrade
            ;;
        * )
            echo -e "Invalid argument provided"
            usage
            exit 1
            ;;
    esac
}

function fetch_upgrade_image() {
    deployment_name="$1"
    if [[ "${deployment_name}" == *"control"* ]]; then
        echo "${cortxcontrol_image}"
    elif [[ "${deployment_name}" == *"ha"* ]]; then
        echo "${cortxha_image}"
    elif [[ "${deployment_name}" == *"server"* ]]; then
        echo "${cortxserver_image}"
    elif [[ "${deployment_name}" == *"data"* ]]; then
        echo "${cortxdata_image}"
    fi
}

function prepare_upgrade_data() {
    cp "${UPGRADE_DATA_TEMPLATE}" "${UPGRADE_DATA}"
    deployments=""
    while IFS= read -r deployment; do
        deployment_name=${deployment}
        if [ "${deployments}" == "" ]
            then
            deployments="${deployment_name}:"$'\n'"  status: default"$'\n'"  version: null"
            else
            deployments="${deployments}"$'\n'"${deployment_name}:"$'\n'"  status: default"$'\n'"  version: null"
        fi
    done <<< "$(kubectl get deployments --output=jsonpath="{range .items[*]}{.metadata.name}{'\n'}{end}" --namespace="${NAMESPACE}" | grep 'cortx')"
    ./parse_scripts/yaml_insert_block.sh "${UPGRADE_DATA}" "${deployments}" 4 "cortx.deployments"
    yq e ".cortx.type=\"$1\"" -i "${UPGRADE_DATA}"
    yq e '.cortx.status='\"Default\"'' -i "${UPGRADE_DATA}"
}

function Wait_for_deployment_to_be_ready() {
    pods_ready=true
    cortx_pods="$(kubectl get pods --namespace="${NAMESPACE}" | { grep "${1}" || true; })"
    if [[ -z ${cortx_pods} ]]; then
        printf "  no CORTX Pods were found\n"
        exit 1
    else
        while IFS= read -r line; do
            IFS=" " read -r -a pod_info <<< "${line}"
            IFS="/" read -r -a ready_counts <<< "${pod_info[1]}"
            pod_name="${pod_info[0]}"
            pod_status="${pod_info[2]}"
            ready_count="${ready_counts[0]}"
            total_count="${ready_counts[1]}"
            sleep 20;
            if [[ -n ${pod_name} ]]; then
                if [[ ${pod_status} != "Running" && ${pod_status} != "Terminating" ]]; then
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
        yq e '.cortx.deployments."'${deployment_name}'".status= '\"Failed\"'' -i "${UPGRADE_DATA}"
        printf "pod readiness check failed. Ensure %s is in a healthy state, or manually shutdown the cluster, and try again.\n" "${deployment_name}"
        exit 1
    fi
}

function compare_versions() {
    current_version=$1
    upgrade_version=$2
    if [[ "${current_version}" == "${upgrade_version}" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

function initiate_upgrade() {
    # Mark Cortx Upgrade as in progress in upgrade-data.yaml
    yq e '.cortx.status='\"In-Progress\"'' -i "${UPGRADE_DATA}"

    # starts Upgrade on all cortx deployments by fetching their names from upgrade-data.yaml
    while IFS= read -r deployment; do
        deployment_name=${deployment}
        upgrade_status=$(yq '.cortx.deployments."'${deployment_name}'".status' "${UPGRADE_DATA}")
        current_version=$(yq '.cortx.deployments."'${deployment_name}'".version' "${UPGRADE_DATA}")
        upgrade_image="$(fetch_upgrade_image "${deployment_name}")"
        upgrade_version=$(docker run "${upgrade_image}" cat /opt/seagate/cortx/RELEASE.INFO | grep VERSION | awk '{print $2}' | tr -d '"')
        check_version=$(compare_versions "${current_version}" "${upgrade_version}")
        if [[ "${upgrade_status}" == "Done" && "${check_version}" == "true" ]]; then
            echo "Deployment ${deployment_name} is already upgrade to version ${upgrade_version}"
        else
            printf "\nStarting Upgrade for %s\n" "${deployment_name}"

            yq e '.cortx.deployments."'${deployment_name}'".status= '\"In-Progress\"'' -i "${UPGRADE_DATA}"
            kubectl rollout pause deployment "${deployment_name}" --namespace="${NAMESPACE}";
            kubectl set image deployment "${deployment_name}" *="${upgrade_image}" --namespace="${NAMESPACE}";
            kubectl set env deployment/"${deployment_name}" UPGRADE_MODE="ROLLING" --namespace="${NAMESPACE}";
            kubectl rollout resume deployment "${deployment_name}" --namespace="${NAMESPACE}";
            yq e '.cortx.deployments."'${deployment_name}'".status= '\"Done\"'' -i "${UPGRADE_DATA}"
            yq e '.cortx.deployments."'${deployment_name}'".version= '\"${upgrade_version}\"'' -i "${UPGRADE_DATA}"
            sleep "${TIMEDELAY}"
            Wait_for_deployment_to_be_ready "${deployment_name}"

            printf "\nUpgrade Successful for %s\n" "${deployment_name}"
        fi
    done <<< "$(kubectl get deployments --output=jsonpath="{range .items[*]}{.metadata.name}{'\n'}{end}" --namespace="${NAMESPACE}" | grep "$1")"
}

function prepare_upgrade() {
    POD_TYPE=$1
    if [[ "${POD_TYPE}" == "cortx" ]] || [[ "${POD_TYPE}" == "control" ]]; then
        control_image="$(parse_solution 'solution.images.cortxcontrol' | cut -f2 -d'>')"
        RULES=""
        get_compatibility_clauses "${control_image}"
        control_nodes="cortx-control"
        check_version_compatibility "${control_nodes}"
    fi
    if [[ "${POD_TYPE}" == "cortx" ]] || [[ "${POD_TYPE}" == "data" ]]; then
        data_image="$(parse_solution 'solution.images.cortxdata' | cut -f2 -d'>')"
        RULES=""
        get_compatibility_clauses "${data_image}"
        data_nodes="$(kubectl get svc -n "${NAMESPACE}" | grep "cortx-data-headless-svc-*" | awk '{print $1}')"
        check_version_compatibility "${data_nodes}"
    fi
    if [[ "${POD_TYPE}" == "cortx" ]] || [[ "${POD_TYPE}" == "server" ]]; then
        server_image=$(parse_solution 'solution.images.cortxserver' | cut -f2 -d'>')
        RULES=""
        get_compatibility_clauses "${server_image}"
        server_nodes="$(kubectl get svc -n "${NAMESPACE}" | grep "cortx-server-headless-svc-*" | awk '{print $1}')"
        check_version_compatibility "${server_nodes}"
    fi
    if [[ "${POD_TYPE}" == "cortx" ]] || [[ "${POD_TYPE}" == "ha" ]]; then
        ha_image="$(parse_solution 'solution.images.cortxha' | cut -f2 -d'>')"
        RULES=""
        get_compatibility_clauses "${ha_image}"
        ha_nodes="$(kubectl get svc -n "${NAMESPACE}" | grep "cortx-ha-headless-svc-*" | awk '{print $1}')"
        check_version_compatibility "${ha_nodes}"
    fi
}

function get_compatibility_clauses() {
    REQUIRES="$(docker inspect --format='{{ index .Config.Labels "org.opencontainers.image.version"}}' "$1")"
    IFS=',' read -ra  newarr <<< "${REQUIRES}"
    for val in "${newarr[@]}";
    do
      val=${val//[[:blank:]]/}
      RULES+='"'${val}'",'
    done
    RULES='{"requires":['"${RULES%?}"']}'
}

function check_version_compatibility() {
  echo -e "\n--------------------------------------"
  while IFS= read -r node; do
    echo -e "Checking Version Compatibility for ${node}:"
    HOSTNAME=$(hostname)
    PORT="$(parse_solution 'solution.common.external_services.control.nodePorts.https' | cut -f2 -d'>')"
    version_compatibility_endpoint="https://${HOSTNAME}:${PORT}/api/v2/version/compatibility/node/${node}"
    response="$(curl -k -XPOST "${version_compatibility_endpoint}" -d "${RULES}" -s | jq)"
    HTTP_CODE="$(curl -k --write-out '%{http_code}' -XPOST "${version_compatibility_endpoint}" -d "${RULES}" -o '/dev/null' -s)"
    if  [ "${HTTP_CODE}" = "200" ]; then
      status="$(jq .compatible <<< "${response}")"
      if [ "${status}" = "true" ]; then
        echo "${node} is compatible for update"
      else
        reason="$(jq .reason <<< "${response}")"
        echo "${node} not compatible because ${reason}"
        exit 1
      fi 
    else
      error_message="$(jq .message <<< "${response}")"
      echo "${error_message}"
      exit 1
    fi
done <<< "$1"
}

function start_upgrade() {
    # Use a PID file to prevent concurrent upgrades.
    if [[ -s ${PIDFILE} ]]; then
       echo "An upgrade is already in progress (PID $(< "${PIDFILE}")). If this is incorrect, remove file "${PIDFILE}" and try again."
       exit 1
    fi
    printf "%s" $$ > "${PIDFILE}"

    # Create Upgrade-data.yaml file to have all deployments and their upgrade status with respect to each delpoyment If not already present.
    if [[ -s "${UPGRADE_DATA}" ]]; then
        upgrade_status=$(yq '.cortx.status' "${UPGRADE_DATA}")
        if [[ "${upgrade_status}" == "Done" ]]; then
            rm -f "${UPGRADE_DATA}"
            # Create Upgrade-data.yaml file to have all deployments and their upgrade status with respect to each delpoyment.
            prepare_upgrade_data "${1}"
            initiate_upgrade "${1}"
        else
            # start Upgrade
            yq e ".cortx.type=\"${1}\"" -i "${UPGRADE_DATA}"
            initiate_upgrade "${1}"
        fi
    else
        prepare_upgrade_data "${1}"
        # start Upgrade
        initiate_upgrade "${1}"
    fi

    # Delete PID file if after upgrade is successful
    rm -f "${PIDFILE}"
}

function suspend_upgrade() {
    if [[ -s "${PIDFILE}" ]]; then
        upgrade_pid="$(cat "${PIDFILE}")"
       # Delete PID file if Upgrade suspended
        rm -f "${PIDFILE}"
    else
        echo "Upgrade Process Not found on the system, Suspend cannot be performed.."
        exit 1
    fi
    yq e '.cortx.status='\"Suspended\"'' -i "${UPGRADE_DATA}"
    printf "Upgrade suspended\n"
    kill -TSTP "${upgrade_pid}"
}

function resume_upgrade() {
    # Use a PID file to prevent concurrent resume process.
    if [[ -s "${PIDFILE}" ]]; then
       echo "An upgrade is already in progress (PID $(< "${PIDFILE}")). If this is incorrect, remove file "${PIDFILE}" and try again."
       exit 1
    else
        printf "%s" $$ > "${PIDFILE}"
    fi
    fetch_solution_images
    # Resume Upgrade process by fetching left replicas from upgrade-data.yaml for each deployment
    POD_TYPE="$(yq '.cortx.type' "${UPGRADE_DATA}")"
    initiate_upgrade "${POD_TYPE}"

    # Delete PID file if after upgrade is successful
    rm -f "${PIDFILE}"
}

function status_upgrade() {
    if [[ -s "${UPGRADE_DATA}" ]]; then
       upgrade_status=$(yq '.cortx.status' "${UPGRADE_DATA}")
    else
        printf "Error: While fetching Upgrade status, upgrade-data.yaml not found\n"
        exit 1
    fi
    if [[ "${upgrade_status}" == "Done" ]]; then
        printf "Upgrade has been performed on all nodes\n"
    else
        printf "Upgrade is in %s state" "${upgrade_status}"
    fi
}

PROCESS="start"
UPGRADE_TYPE="Rolling"
POD_TYPE=
SOLUTION_FILE="${CORTX_SOLUTION_CONFIG_FILE:-solution.yaml}"
readonly SOLUTION_FILE
while [ $# -gt 0 ];  do
    case $1 in
    prepare )
        PROCESS="prepare"
        ;;
    start )
        PROCESS="start"
        ;;
    suspend )
        PROCESS="suspend"
        ;;
    resume )
        PROCESS="resume"
        ;;
    status )
        PROCESS="status"
        ;;
    -p )
        shift 1
        POD_TYPE="${1}"
        ;;
    -cold )
        UPGRADE_TYPE="Cold"
        ;;
    -s )
        shift 1
        SOLUTION_FILE="${1}"
        ;;
    * )
        printf "Invalid argument provided : %s" "${1}"
        usage
        exit 1
        ;;
    esac
    shift 1
done

if [[ -z "${SOLUTION_FILE}" ]]; then
    printf "\nERROR: Required option SOLUTION_CONFIG_FILE is missing.\n"
    usage
    exit 1
fi

if [[ ! -s "${SOLUTION_FILE}" ]]; then
    printf "\nERROR: SOLUTION_CONFIG_FILE '%s' does not exist or is empty.\n" "${SOLUTION_FILE}"
    exit 1
fi

NAMESPACE=$(parse_solution 'solution.namespace' | cut -f2 -d'>')
if [[ -z "${NAMESPACE}" ]]; then
    printf "\nERROR: Required field 'solution.namespace' not found in SOLUTION_CONFIG_FILE '%s'.\n" "${SOLUTION_FILE}"
    exit 1
fi

case "${UPGRADE_TYPE}" in
    Cold )
        cold_upgrade
        ;;
    Rolling )
        rolling_upgrade
        ;;
    * )
        echo "Invalid Upgrade_type provided"
        usage
        exit 1
        ;;
esac
