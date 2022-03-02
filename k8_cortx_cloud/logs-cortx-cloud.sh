#!/bin/bash

SCRIPT=$(readlink -f "$0")
DIR=$(dirname "${SCRIPT}")

function parseSolution()
{
  "${DIR}/parse_scripts/parse_yaml.sh" "${solution_yaml}" "$1"
}

function usage() {
  echo -e "\n** Generate CORTX Cluster Support Bundle **\n"
  echo -e "Usage: \`sh $0 [-n NODENAME] [-s SOLUTION_CONFIG_FILE]\`\n"
  echo "Optional Arguments:"
  echo "    -s|--solution-config FILE_PATH : path of solution configuration file."
  echo "                                     default file path is ${solution_yaml}."
  echo "    -n|--nodename NODENAME: collects logs from pods running only on given node".
  echo "                            collects logs from all the nodes by default."
  exit 1
}

date=$(date +%F_%H-%M)
solution_yaml="${DIR}/solution.yaml"
pods_found=0
while [[ $# -gt 0 ]]; do
  case $1 in
    -s|--solution-config )
      declare solution_yaml="$2"
      ;;
    -n|--nodename )
      declare nodename="$2"
      ;;
    * )
      echo "ERROR: Unsupported Option \"$1\"."
      usage
      ;;
  esac
  shift 2
done
namespace=$(parseSolution 'solution.namespace')
namespace=$(echo "${namespace}" | cut -f2 -d'>')
logs_folder="logs-cortx-cloud-${date}"
mkdir "${logs_folder}" -p
status=""

printf "######################################################\n"
printf "# ✍️  Generating logs, namespace: %s, date: %s\n" "${namespace}" "${date}"
printf "######################################################\n"

function saveLogs()
{
  local pod="$1"
  local container="$2"  # optional
  local log_cmd=(kubectl logs "${pod}")
  local log_name="${pod}"

  printf "\n🔍 Logging pod: %s" "${pod}"
  if [[ -n ${container} ]]; then
    printf ", container: %s" "${container}"
    log_name+="-${container}"
    log_cmd+=(-c "${container}")
  fi

  local log_file="${logs_folder}/${log_name}.logs.txt"

  printf "================= Logs of %s =================\n" "${pod}" > "${log_file}"
  "${log_cmd[@]}" >> "${log_file}"

  tar --append --file "${logs_folder}".tar "${log_file}"
  rm "${log_file}"
}

function savePodDetail()
{
  local pod="$1"
  local log_file="${logs_folder}/${pod}.detail.txt"

  printf "================= Detail of %s =================\n\n" "${pod}" > "${log_file}"
  kubectl describe pod "${pod}" >> "${log_file}"

  tar --append --file "${logs_folder}.tar" "${log_file}"
  rm "${log_file}"
}

function getInnerLogs()
{
  local pod="$1"
  local container_arg=()
  [[ -n $2 ]] && container_arg+=(--container "$2")
  local path="/var/cortx/support_bundle"
  local name="bundle-logs-${pod}-${date}"

  printf "\n ⭐ Generating support-bundle logs for pod: %s\n" "${pod}"
  kubectl exec "${pod}" "${container_arg[@]}" --namespace="${namespace}" -- \
    cortx_support_bundle generate \
      --cluster_conf_path yaml:///etc/cortx/cluster.conf \
      --location file://${path} \
      --bundle_id "${name}" \
      --message "${name}"
  kubectl cp "${pod}:${path}/${name}" "${logs_folder}/${name}" "${container_arg[@]}" --namespace="${namespace}"
  tar --append --file "${logs_folder}.tar" "${logs_folder}/${name}"
  kubectl exec "${pod}" "${container_arg[@]}" --namespace="${namespace}" -- bash -c "rm -rf ${path}"
}

while IFS= read -r line; do
  IFS=" " read -r -a pod_line <<< "${line}"
  IFS="/" read -r -a status <<< "${pod_line[2]}"
  IFS="/" read -r -a pod <<< "${pod_line[0]}"

  pod_name="${pod[0]}"
  pod_status="${status[0]}"

  if [[ ${pod_name} != "NAME" && ${pod_status} != "Evicted" ]]; then
    if [[ ${nodename} ]] && \
       [[ ${nodename} != $(kubectl get pod "${pod_name}" -o jsonpath={.spec.nodeName} || true) ]]; then
      continue
    fi
    pods_found=$((pods_found+1))

    case ${pod_name} in
      cortx-control-* | cortx-data-* | cortx-ha-* | cortx-server-*)
        containers=$(kubectl get pods "${pod_name}" -n "${namespace}" -o jsonpath='{.spec.containers[*].name}')
        IFS=" " read -r -a containers <<< "${containers}"
        for item in "${containers[@]}";
        do
          saveLogs "${pod_name}" "${item}"
        done
        savePodDetail "${pod[0]}"
        getInnerLogs "${pod[0]}" "${containers[0]}"
        ;;
      *)
        saveLogs "${pod_name}"
        savePodDetail "${pod_name}"
        ;;
    esac
  fi

done <<< "$(kubectl get pods || true)"

if [[ ${nodename} ]] && [[ ${pods_found} == "0" ]]; then
  printf "\n❌ No pods are running on the node: \"%s\".\n" "${nodename}"
else
  printf "\n\n📦 \"%s.tar\" file generated" "${logs_folder}"
fi
rm -rf "${logs_folder}"
printf "\n✔️  All done\n\n"
