#!/bin/bash

SCRIPT=$(readlink -f "$0")
SCRIPT_NAME=$(basename "${SCRIPT}")
DIR=$(dirname "${SCRIPT}")

function parseSolution()
{
  "${DIR}/parse_scripts/parse_yaml.sh" "${solution_yaml}" "$1"
}

function usage() {
    cat << EOF

Usage:
    ${SCRIPT_NAME} [-s SOLUTION_CONFIG_FILE] <options>


Options:
    -h|--help              Prints this help information

    -s|--solution-config <FILE>
                           The cluster solution configuration file. Can
                           also be set with the CORTX_SOLUTION_CONFIG_FILE
                           environment variable. Defaults to 'solution.yaml'.

    -n|--nodename <NODE>   Collect logs from pods running only on given node.
                           By default logs are collected from all nodes.

    --duration <DURATION>  Maximum allowed duration Pod's support bundle
                           operation to run.  This is specified in 8601 duration
                           format.  The default is P5D (5 days).

    --size_limit <SIZE>    Maximum allowed size limit in bytes for each Pod's
                           support bundle.  Units MB and GB are supported.
                           Defaults to 500MB.

    --binlogs              Collect binary logs
    --coredumps            Collect existing core dump files
    --stacktrace           Collect existing stack trace files
    --all                  Collect binlogs, coredumps & stacktrace
EOF
}

date=$(date +%F_%H-%M)
solution_yaml="${CORTX_SOLUTION_CONFIG_FILE:-solution.yaml}"
nodename=""
modules=""
pods_found=0
size_limit="500MB"
duration="P5D"
binlogs="False"
coredumps="False"
stacktrace="False"
all="False"

while [[ $# -gt 0 ]]; do
  case $1 in
    -s|--solution-config )
      solution_yaml="$2"
      shift 2
      ;;
    -n|--nodename )
      nodename="$2"
      shift 2
      ;;
    -h|--help )
      usage
      exit 0
      ;;
    --modules )
      modules="$2"
      shift 2
      ;;
    --duration )
      duration=$2
      shift 2
      ;;
    --size_limit )
      size_limit=$2
      shift 2
      ;;
    --binlogs )
      binlogs="True"
      shift
      ;;
    --coredumps )
      coredumps="True"
      shift
      ;;
    --stacktrace )
      stacktrace="True"
      shift
      ;;
    --all ) all="True"
      shift
      ;;
    * )
      echo "ERROR: Unsupported Option \"$1\"."
      usage
      exit 1
      ;;
  esac
done

if [[ ! -f ${solution_yaml} ]]; then
    echo "ERROR: ${solution_yaml} does not exist."
    exit 1
fi

namespace=$(parseSolution 'solution.namespace')
namespace=$(echo "${namespace}" | cut -f2 -d'>')
logs_folder="logs-cortx-cloud-${date}"
outfile="${logs_folder}.tgz"
mkdir "${logs_folder}" -p
status=""

printf "######################################################\n"
printf "# ✍️  Generating logs, namespace: %s, date: %s\n" "${namespace}" "${date}"
printf "######################################################\n"


function tarPodLogs()
{
  local pod="$1"
  shift

  # save pod detail
  local log_file="${logs_folder}/${pod}.detail.txt"
  printf "================= Detail of %s =================\n\n" "${pod}" > "${log_file}"
  kubectl describe pod --namespace="${namespace}" "${pod}" >> "${log_file}"

  local log_cmd=(kubectl logs --namespace="${namespace}" "${pod}")
  local log_name="${pod}"

  if (($# > 0)); then
    # If there are remaining arguments, these are the list of cortx
    # containers.  For each, get logs.  The call "support_bundle generate"
    # for the first container.
    for container in "$@"; do
      # Get logs
      local log_file="${logs_folder}/${log_name}-${container}.logs.txt"
      printf "================= Logs of %s =================\n" "${pod} / ${container}" > "${log_file}"
      "${log_cmd[@]}" -c "${container}" >> "${log_file}"
    done

    # Get support bundle.  Use first container.
    local path="var/cortx/support_bundle"
    local name="bundle-logs-${pod}-${date}"
    local container=$1

    printf "\n ⭐ Generating support-bundle logs for pod: %s\n" "${pod}"
    # shellcheck disable=SC2016
    kubectl exec "${pod}" -c "${container}" --namespace="${namespace}" -- \
      env location="file:///${path}" \
          name="${name}" \
          modules="${modules}" \
          duration="${duration}" \
          size_limit="${size_limit}" \
          binlogs="${binlogs}" \
          coredumps="${coredumps}" \
          stacktrace="${stacktrace}" \
          all="${all}" \
      bash -c 'cortx_support_bundle generate \
        --cluster_conf_path "${CORTX_CONFSTORE_URL}" \
        --location "${location}" \
        --bundle_id "${name}" \
        --message "${name}" \
        --modules "${modules}" \
        --duration "${duration}" \
        --size_limit "${size_limit}" \
        --binlogs "${binlogs}" \
        --coredumps "${coredumps}" \
        --stacktrace "${stacktrace}" \
        --all "${all}"' || return
    kubectl cp "${pod}:${path}/${name}" "${logs_folder}/${name}" -c "${container}" --namespace="${namespace}" || return

    kubectl exec "${pod}" -c "${container}" --namespace="${namespace}" -- bash -c "rm -rf /${path}"

  else
    # There are no remaining arguments.  Get logs from default container.
    local log_file="${logs_folder}/${log_name}.logs.txt"
    printf "================= Logs of %s =================\n" "${pod}" > "${log_file}"
    "${log_cmd[@]}" >> "${log_file}"
  fi
}

while IFS= read -r line; do
  IFS=" " read -r -a pod_line <<< "${line}"
  IFS="/" read -r -a status <<< "${pod_line[2]}"
  IFS="/" read -r -a pod <<< "${pod_line[0]}"

  pod_name="${pod[0]}"
  pod_status="${status[0]}"

  if [[ ${pod_name} != "NAME" && ${pod_status} != "Evicted" ]]; then
    if [[ ${nodename} ]] && \
       [[ ${nodename} != $(kubectl get pod --namespace="${namespace}" "${pod_name}" -o jsonpath='{.spec.nodeName}' || true) ]]; then
      continue
    fi
    pods_found=$((pods_found+1))

    case ${pod_name} in
      cortx-control-* | cortx-data-* | cortx-ha-* | cortx-server-* | cortx-client-*)
        containers=$(kubectl get pods "${pod_name}" -n "${namespace}" -o jsonpath="{.spec['containers', 'initContainers'][*].name}")
        IFS=" " read -r -a containers <<< "${containers}"
        tarPodLogs "${pod_name}" "${containers[@]}" &
        ;;
      *)
        tarPodLogs "${pod_name}" &
        ;;
    esac
  fi

done <<< "$(kubectl get pods --namespace="${namespace}" || true)"

wait


echo "Creating support bundle tar file: ${outfile}"

tar cfz "${outfile}" "${logs_folder}"

if [[ ${nodename} ]] && [[ ${pods_found} == "0" ]]; then
  printf "\n❌ No pods are running on the node: \"%s\".\n" "${nodename}"
else
  printf "\n\n📦 \"%s.\" file generated" "${outfile}"
fi
rm -rf "${logs_folder}"
printf "\n✔️  All done\n\n"
