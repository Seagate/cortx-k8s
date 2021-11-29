#!/bin/bash

function parseSolution()
{
  echo "$(./parse_scripts/parse_yaml.sh $solution_yaml $1)"
}

date=$(date +%F_%H-%M)
solution_yaml=${1:-'solution.yaml'}
namespace=$(parseSolution 'solution.namespace')
namespace=$(echo $namespace | cut -f2 -d'>')
logs_folder="logs-cortx-cloud-${date}"
mkdir $logs_folder -p
status=""

printf "######################################################\n"
printf "# ✍️  Generating logs, namespace: ${namespace}, date: ${date}\n"
printf "######################################################\n"

# 1 -> pod
# 2 -> container?
function saveLogs()
{
  log_file=""
  logs_output=""
  if [ "${2}" != "" ]; then
    printf "\n🔍 Logging pod: ${1}, container: ${2}"
    log_file="./${logs_folder}/${1}-${2}.logs.txt"
    logs_output=$(kubectl logs ${1} -c ${2})
  else
    printf "\n🔍 Logging pod: ${1}"
    log_file="./${logs_folder}/${1}.logs.txt"
    logs_output=$(kubectl logs ${1})
  fi
  if [ "${logs_output}" != "" ]; then
    echo "================= Logs of ${1} =================" > $log_file
    printf "\n${logs_output}" >> $log_file
    tar rf $logs_folder.tar $log_file
    rm $log_file
  fi
}

function savePodDetail()
{
  log_file="./${logs_folder}/${1}.detail.txt"
  logs_output=$(kubectl describe pod ${1})
  if [ "${logs_output}" != "" ]; then
    echo "================= Detail of ${1} =================" > $log_file
    printf "\n${logs_output}" >> $log_file
    tar rf $logs_folder.tar $log_file
    rm $log_file
  fi
}

function getInnerLogs()
{
  path="/var/cortx/support_bundle"
  name="logs-${date}-${1}"
  logs_output=$(kubectl exec ${1} -- cortx_support_bundle generate -t file://${path} -b ${name} -m ${name})
  kubectl cp $1:$path/$name ./${logs_folder}
  kubectl exec ${1} --namespace="${namespace}" -- bash -c "rm -rf ${path}"
}

while IFS= read -r line; do
  IFS=" " read -r -a pod_status <<< "$line"
  IFS="/" read -r -a status <<< "${pod_status[2]}"
  IFS="/" read -r -a pod <<< "${pod_status[0]}"

  if [ "$pod" != "NAME" -a "$status" != "Evicted" ]; then
    if [[ $pod =~ "cortx-control-pod" ]]; then
      containers=$(kubectl get pods ${pod} -n ${namespace} -o jsonpath='{.spec.containers[*].name}')
      containers=($containers)
      for item in "${containers[@]}";
      do
        saveLogs $pod "${item}"
      done
      savePodDetail $pod
      getInnerLogs $pod
    elif [[ $pod =~ "cortx-data-pod" ]]; then
      containers=$(kubectl get pods ${pod} -n ${namespace} -o jsonpath='{.spec.containers[*].name}')
      containers=($containers)
      for item in "${containers[@]}";
      do
        saveLogs $pod "${item}"
      done
      savePodDetail $pod
      getInnerLogs $pod
    else
      saveLogs $pod
      savePodDetail $pod
    fi
  fi

done <<< "$(kubectl get pods)"

printf "\n\n📦 \"$logs_folder.tar\" file generated"
rm -rf ${logs_folder}
printf "\n✔️  All done\n\n"
