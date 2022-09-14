#!/usr/bin/env bash

# shellcheck disable=SC2312

solution_yaml=${1:-'solution.yaml'}

# Check if the file exists
if [[ ! -f ${solution_yaml} ]]; then
    echo "ERROR: ${solution_yaml} does not exist"
    exit 1
fi

setup_colors() {
  # shellcheck disable=SC2034  # Unused variables left for readability
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
  else
    NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
  fi
}

msg() {
  echo -e "${1-}"
}

alert_msg() {
    msg "${YELLOW}${1-}${NOFORMAT}"
}

msg_info() {
    msg "${CYAN}${1-}${NOFORMAT}"
}

msg_passed() {
    msg "${1-}${GREEN}PASSED${NOFORMAT}"
}

msg_failed() {
    msg "${1-}${RED}FAILED${NOFORMAT}"
}

msg_overall_passed() {
    msg_passed "OVERALL STATUS: "
}

msg_overall_failed() {
    msg_failed "OVERALL STATUS: "
}

parseSolution() {
    ./parse_scripts/parse_yaml.sh "${solution_yaml}" "$1"
}

setup_colors

if ! ./solution_validation_scripts/solution-validation.sh "${solution_yaml}"; then
    exit 1
fi

readonly release_selector="app.kubernetes.io/instance=cortx"
readonly cortx_selector="${release_selector},app.kubernetes.io/name=cortx"

namespace=$(parseSolution 'solution.namespace' | cut -f2 -d'>')
num_nodes=$(yq '.solution.storage_sets[0].nodes | length' "${solution_yaml}")
num_devices=$(yq '[.solution.storage_sets[0].storage[].devices[].[]] | length' "${solution_yaml}")
num_cvgs=$(yq '.solution.storage_sets[0].storage | length' "${solution_yaml}")
container_group_size=$(yq '.solution.storage_sets[0].container_group_size' "${solution_yaml}")
num_data_sts=$(( (num_cvgs+container_group_size-1) / container_group_size ))

readonly namespace
readonly num_nodes
readonly num_devices
readonly num_cvgs
readonly container_group_size
readonly num_data_sts

# The deployment type influences expectations about Pod, etc. counts
data_deployment=false
[[ $(parseSolution 'solution.deployment_type' | cut -f2 -d'>') == "data-only" ]] && data_deployment=true

failcount=0

#########################################################################################
# CORTX Control
#########################################################################################

alert_msg "######################################################"
alert_msg "# CORTX Control                                       "
alert_msg "######################################################"
control_selector="app.kubernetes.io/component=control,${cortx_selector}"
# Check deployments
expected_count=1
[[ ${data_deployment} == true ]] && expected_count=0
count=0
msg_info "| Checking Deployments |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    printf "%s..." "${status[0]}"
    if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get deployments --namespace="${namespace}" --selector=${control_selector} --no-headers)

if [[ ${expected_count} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check pods
expected_count=$(helm get values cortx --all --namespace "${namespace}" --output yaml | yq .control.replicaCount)
[[ ${data_deployment} == true ]] && expected_count=0
count=0
msg_info "| Checking Pods |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    printf "%s..." "${status[0]}"
    if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get pods --namespace="${namespace}" --selector=${control_selector} --no-headers)

if [[ ${expected_count} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check services
expected_count=1
[[ ${data_deployment} == true ]] && expected_count=0
count=0
msg_info "| Checking Services: cortx-control |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    printf "%s..." "${status[0]}"
    msg_passed
    count=$((count+1))
done < <(kubectl get services --namespace="${namespace}" --selector=${control_selector} --no-headers)

if [[ ${expected_count} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

#########################################################################################
# CORTX Data
#########################################################################################

alert_msg "######################################################"
alert_msg "# CORTX Data                                          "
alert_msg "######################################################"
data_selector="app.kubernetes.io/component=data,${cortx_selector}"
# Check StatefulSet
count=0
expected_count=${num_data_sts}
msg_info "| Checking StatefulSet |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    printf "%s..." "${status[0]}"
    if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get statefulsets --namespace="${namespace}" --selector=${data_selector} --no-headers)

if [[ ${expected_count} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check pods
count=0
expected_count=$(( num_nodes * num_data_sts))
msg_info "| Checking Pods |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    printf "%s..." "${status[0]}"
    if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get pods --namespace="${namespace}" --selector=${data_selector} --no-headers)

if [[ ${expected_count} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check services headless
count=0
expected_count=1
msg_info "| Checking Services: Headless |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    printf "%s..." "${status[0]}"
    if [[ "${status[1]}" != "ClusterIP" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get services --namespace="${namespace}" --selector=${data_selector} --no-headers)

if [[ ${expected_count} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check storage local
count=0
num_pvs_pvcs=$(( num_nodes * num_data_sts * 2 ))
msg_info "| Checking Storage: Local [PVCs/PVs] |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    printf "PVC: %s..." "${status[0]}"
    if [[ "${status[1]}" != "Bound" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get pvc --namespace="${namespace}" --selector=${data_selector} --no-headers | grep ^data)

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    printf "PV: %s..." "${status[5]}"
    if [[ "${status[4]}" != "Bound" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get pv --no-headers | grep "${namespace}/data-cortx-data-g[0-9]\+-[0-9]\+")

if [[ ${num_pvs_pvcs} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check storage block devices
count=0
num_pvs_pvcs=$(( (num_nodes * num_devices) * 2 ))
msg_info "| Checking Storage: Block Devices [PVCs/PVs] |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "PVC: %s..." "${status[0]}"
        if [[ "${status[1]}" != "Bound" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get pvc --namespace="${namespace}" --selector=${data_selector} --no-headers | grep '^block-.*-cortx-data-')

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    printf "PV: %s..." "${status[5]}"
    if [[ "${status[4]}" != "Bound" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get pv --no-headers | grep "${namespace}/block-.*-cortx-data-")

if [[ ${num_pvs_pvcs} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

#########################################################################################
# CORTX Server
#########################################################################################
alert_msg "######################################################"
alert_msg "# CORTX Server                                        "
alert_msg "######################################################"
server_selector="app.kubernetes.io/component=server,${cortx_selector}"
expected_count=0
# Check StatefulSet
[[ ${data_deployment} != true ]] && expected_count=1
count=0
msg_info "| Checking StatefulSet |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    printf "%s..." "${status[0]}"
    if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get statefulsets --namespace="${namespace}" --selector=${server_selector} --no-headers)

if [[ ${expected_count} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check pods
server_instances_per_node=$(parseSolution 'solution.common.s3.instances_per_node' | cut -f2 -d'>')
[[ ${data_deployment} != true ]] && expected_count=$((num_nodes * server_instances_per_node))
count=0
msg_info "| Checking Pods |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    printf "%s..." "${status[0]}"
    if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get pods --namespace="${namespace}" --selector=${server_selector} --no-headers)

if [[ ${expected_count} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check services headless
[[ ${data_deployment} != true ]] && expected_count=1
count=0
msg_info "| Checking Services: Headless |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    printf "%s..." "${status[0]}"
    if [[ "${status[1]}" != "ClusterIP" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get services --namespace="${namespace}" --selector=${server_selector} --no-headers | grep -- -headless)

if [[ ${expected_count} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check services
[[ ${data_deployment} != true ]] && expected_count=1
expected_type=$(parseSolution 'solution.common.external_services.s3.type' | cut -f2 -d'>')
max_count=$(parseSolution 'solution.common.external_services.s3.count' | cut -f2 -d'>')
count=0
msg_info "| Checking Services: cortx-server-N |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    printf "%s..." "${status[0]}"
    if [[ "${status[1]}" != "${expected_type}" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get services --namespace="${namespace}" --no-headers --selector ${server_selector} | grep -v -- -headless)

if (( count >= expected_count && count <= max_count )); then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check storage local
count=0
[[ ${data_deployment} != true ]] && expected_count=$((num_nodes * server_instances_per_node * 2))
msg_info "| Checking Storage: Local [PVCs/PVs] |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    printf "PVC: %s..." "${status[0]}"
    if [[ "${status[1]}" != "Bound" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get pvc --namespace="${namespace}" --selector=${server_selector} --no-headers)

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    printf "PV: %s..." "${status[5]}"
    if [[ "${status[4]}" != "Bound" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get pv --no-headers | grep "${namespace}/data-cortx-server-[0-9]")

if [[ ${expected_count} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

#########################################################################################
# CORTX HA
#########################################################################################

alert_msg "######################################################"
alert_msg "# CORTX HA                                            "
alert_msg "######################################################"
ha_selector="app.kubernetes.io/component=ha,${cortx_selector}"

# Check deployments
expected_count=1
[[ ${data_deployment} == true ]] && expected_count=0
count=0
msg_info "| Checking Deployments |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    printf "%s..." "${status[0]}"
    if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get deployments --namespace="${namespace}" --selector=${ha_selector} --no-headers)

if [[ ${expected_count} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check pods
count=0
msg_info "| Checking Pods |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    printf "%s..." "${status[0]}"
    if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get pods --namespace="${namespace}" --selector=${ha_selector} --no-headers)

if [[ ${expected_count} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check services headless
count=0
msg_info "| Checking Services: Headless |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    printf "%s..." "${status[0]}"
    if [[ "${status[1]}" != "ClusterIP" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get services --namespace="${namespace}" --selector=${ha_selector} --no-headers)

if [[ ${expected_count} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check storage local
count=0
num_pvs_pvcs=$(( expected_count * 2 ))
[[ ${data_deployment} == true ]] && num_pvs_pvcs=0
msg_info "| Checking Storage: Local [PVCs/PVs] |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    printf "PVC: %s..." "${status[0]}"
    if [[ "${status[1]}" != "Bound" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get pvc --namespace="${namespace}" --selector=${ha_selector} --no-headers)

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    printf "PV: %s..." "${status[5]}"
    if [[ "${status[4]}" != "Bound" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get pv --no-headers | grep "${namespace}/cortx-ha")

if [[ ${num_pvs_pvcs} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi


num_motr_client=$(parseSolution 'solution.common.motr.num_client_inst' | cut -f2 -d'>')

#########################################################################################
# CORTX Client
#########################################################################################
client_selector="app.kubernetes.io/component=client,${cortx_selector}"

alert_msg "######################################################"
alert_msg "# CORTX Client                                        "
alert_msg "######################################################"

# Check StatefulSet
count=0
expected_count=0
(( num_motr_client > 0 )) && expected_count=1
msg_info "| Checking StatefulSet |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    printf "%s..." "${status[0]}"
    if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get statefulsets --namespace="${namespace}" --selector=${client_selector} --no-headers)

if [[ ${expected_count} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check pods
count=0
expected_count=0
(( num_motr_client > 0 )) && expected_count=${num_nodes}
msg_info "| Checking Pods |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    printf "%s..." "${status[0]}"
    if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get pods --namespace="${namespace}" --selector=${client_selector} --no-headers)

if [[ ${expected_count} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check services headless
count=0
expected_count=0
(( num_motr_client > 0 )) && expected_count=1
msg_info "| Checking Services: Headless |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    printf "%s..." "${status[0]}"
    if [[ "${status[1]}" != "ClusterIP" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get services --namespace="${namespace}" --selector=${client_selector} --no-headers)

if [[ ${expected_count} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

#########################################################################################
# 3rd Party
#########################################################################################
num_worker_nodes=0
while IFS= read -r line; do
    IFS=" " read -r -a node_name <<< "${line}"
    output=$(kubectl describe nodes "${node_name[0]}" | grep Taints | grep NoSchedule)
    if [[ "${output}" == "" ]]; then
        num_worker_nodes=$((num_worker_nodes+1))
    fi
done < <(kubectl get nodes --no-headers)

expected_count=${num_worker_nodes}
max_replicas=3
num_replicas=${expected_count}
if [[ "${expected_count}" -gt "${max_replicas}" ]]; then
    num_replicas=${max_replicas}
fi
alert_msg "######################################################"
alert_msg "# 3rd Party                                           "
alert_msg "######################################################"

alert_msg "### Kafka"
kafka_selector="${release_selector},app.kubernetes.io/component=kafka"
# Check StatefulSet
num_items=1
count=0
msg_info "| Checking StatefulSet |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    printf "%s..." "${status[0]}"
    if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get statefulsets --namespace="${namespace}" --selector=${kafka_selector} --no-headers)

if [[ ${num_items} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check Pods
num_items=${num_replicas}
count=0
msg_info "| Checking Pods |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    printf "%s..." "${status[0]}"
    if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get pods --namespace="${namespace}" --selector=${kafka_selector} --no-headers)

if [[ ${num_items} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check services cluster IP
num_items=1
count=0
msg_info "| Checking Services: Cluster IP |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    printf "%s..." "${status[0]}"
    if [[ "${status[1]}" != "ClusterIP" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get services --namespace="${namespace}" --selector=${kafka_selector} --no-headers | grep -v -- -kafka-headless)

if [[ ${num_items} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check services headless
num_items=1
count=0
msg_info "| Checking Services: Headless |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    printf "%s..." "${status[0]}"
    if [[ "${status[1]}" != "ClusterIP" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get services --namespace="${namespace}" --selector=${kafka_selector} --no-headers | grep -- -kafka-headless)

if [[ ${num_items} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check storage local
count=0
num_pvs_pvcs=$(( num_replicas * 2 ))
msg_info "| Checking Storage: Local [PVCs/PVs] |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    printf "PVC: %s..." "${status[0]}"
    if [[ "${status[1]}" != "Bound" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get pvc --namespace="${namespace}" --selector=${kafka_selector} --no-headers)

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    printf "PV: %s..." "${status[5]}"
    if [[ "${status[4]}" != "Bound" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get pv --no-headers | grep "${namespace}/data-.*kafka-")

if [[ ${num_pvs_pvcs} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

alert_msg "### Zookeeper"
zookeeper_selector="${release_selector},app.kubernetes.io/component=zookeeper"
# Check StatefulSet
num_items=1
count=0
msg_info "| Checking StatefulSet |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    printf "%s..." "${status[0]}"
    if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get statefulsets --namespace="${namespace}" --selector=${zookeeper_selector} --no-headers)

if [[ ${num_items} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check Pods
num_items=${num_replicas}
count=0
msg_info "| Checking Pods |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    printf "%s..." "${status[0]}"
    if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get pods --namespace="${namespace}" --selector=${zookeeper_selector} --no-headers)

if [[ ${num_items} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check services cluster IP
num_items=1
count=0
msg_info "| Checking Services: Cluster IP |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    printf "%s..." "${status[0]}"
    if [[ "${status[1]}" != "ClusterIP" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get services --namespace="${namespace}" --selector=${zookeeper_selector} --no-headers | grep -v -- -zookeeper-headless)

if [[ ${num_items} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check services headless
num_items=1
count=0
msg_info "| Checking Services: Headless |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    printf "%s..." "${status[0]}"
    if [[ "${status[1]}" != "ClusterIP" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get services --namespace="${namespace}" --selector=${zookeeper_selector} --no-headers | grep -- -zookeeper-headless)

if [[ ${num_items} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check storage local
count=0
num_pvs_pvcs=$(( num_replicas * 2 ))
msg_info "| Checking Storage: Local [PVCs/PVs] |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    printf "PVC: %s..." "${status[0]}"
    if [[ "${status[1]}" != "Bound" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get pvc --namespace="${namespace}" --selector=${zookeeper_selector} --no-headers)

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    printf "PV: %s..." "${status[5]}"
    if [[ "${status[4]}" != "Bound" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get pv --no-headers | grep "${namespace}/data-.*zookeeper-")

if [[ ${num_pvs_pvcs} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

alert_msg "### Consul"
consul_selector="release=cortx,app=consul"
# Check StatefulSet
num_items=1
count=0
msg_info "| Checking StatefulSet |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    printf "%s..." "${status[0]}"
    if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get statefulsets --namespace="${namespace}" --selector=${consul_selector} --no-headers)

if [[ ${num_items} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check DaemonSet
num_items=1
count=0
msg_info "| Checking DaemonSet |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    printf "%s..." "${status[0]}"
    if [[ "${status[3]}" != "${num_worker_nodes}" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get daemonsets --namespace="${namespace}" --selector=${consul_selector} --no-headers)

if [[ ${num_items} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check Pods
num_items="${num_replicas}"
count=0
msg_info "| Checking Pods |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    printf "%s..." "${status[0]}"
    if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get pods --namespace="${namespace}" --selector="${consul_selector}",component=server --no-headers)

if [[ ${num_items} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check services cluster IP
num_items=1
count=0
msg_info "| Checking Services: DNS Cluster IP |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    printf "%s..." "${status[0]}"
    if [[ "${status[1]}" != "ClusterIP" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get services --namespace="${namespace}" --selector ${consul_selector},component==dns --no-headers)

if [[ ${num_items} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check services headless
num_items=1
count=0
msg_info "| Checking Services: Server Headless |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    printf "%s..." "${status[0]}"
    if [[ "${status[1]}" != "ClusterIP" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get services --namespace="${namespace}" --selector ${consul_selector},component==server --no-headers)

if [[ ${num_items} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check storage local
count=0
num_pvs_pvcs=$(( num_replicas * 2 ))
msg_info "| Checking Storage: Server Local [PVCs/PVs] |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    printf "PVC: %s..." "${status[0]}"
    if [[ "${status[1]}" != "Bound" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get pvc --namespace="${namespace}" --selector=${consul_selector},component=server --no-headers)

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    printf "PV: %s..." "${status[5]}"
    if [[ "${status[4]}" != "Bound" ]]; then
        msg_failed
        failcount=$((failcount+1))
    else
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get pv --no-headers | grep "${namespace}/data-.*consul-server-")

if [[ ${num_pvs_pvcs} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

printf -- "------------------------------------------\n"

if (( failcount > 0 )); then
    msg "${RED}${failcount} status checks failed${NOFORMAT}\n\n"
    exit 1
else
    msg "${GREEN}All status checks passed${NOFORMAT}\n\n"
    exit 0
fi
