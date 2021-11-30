#!/bin/bash

SCRIPT=$(readlink -f "$0")
DIR=$(dirname "$SCRIPT")

function parseSolution()
{
  echo "$(./parse_scripts/parse_yaml.sh $solution_yaml $1)"
}

date=$(date +%F_%H-%M)
solution_yaml='solution.yaml'
pods_found=0
while [ $# -gt 0 ]; do
  case $1 in
    -s|--solution-config )
      declare solution_yaml="$2"
      ;;
    -n|--nodename )
      declare nodename="$2"
      ;;
    * )
      ;;
  esac
  shift
done
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
  name="bundle-logs-${1}-${date}"
  printf "\n ⭐ Generating support-bundle logs for pod: ${1}\n"
  kubectl exec ${1} --namespace="${namespace}" -- cortx_support_bundle generate -t file://${path} -b ${name} -m ${name}
  kubectl cp $1:$path/$name $logs_folder/$name
  tar rf $logs_folder.tar $logs_folder/$name
  kubectl exec ${1} --namespace="${namespace}" -- bash -c "rm -rf ${path}"
}

while IFS= read -r line; do
  IFS=" " read -r -a pod_status <<< "$line"
  IFS="/" read -r -a status <<< "${pod_status[2]}"
  IFS="/" read -r -a pod <<< "${pod_status[0]}"

  if [ "$pod" != "NAME" -a "$status" != "Evicted" ]; then
    if [ "$nodename" ] && \
       [ "$nodename" != $(kubectl get pod ${pod} -o jsonpath={.spec.nodeName}) ]; then
      continue
    fi
    pods_found=$((pods_found+1))

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

if [ "$nodename" ] && [ "$pods_found" == "0" ]; then
  printf "\n❌ No pods are running on the node: \"%s\"." $nodename
  printf "\n   Please try with another nodename.\n"
else
  printf "\n\n📦 \"$logs_folder.tar\" file generated"
fi
rm -rf ${logs_folder}
printf "\n✔️  All done\n\n"
