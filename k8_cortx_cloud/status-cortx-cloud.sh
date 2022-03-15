#!/bin/bash

# shellcheck disable=SC2312

set -u

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

extractBlock() {
    ./parse_scripts/yaml_extract_block.sh "${solution_yaml}" "$1"
}

setup_colors

namespace=$(parseSolution 'solution.namespace' | cut -f2 -d'>')
num_nodes=$(parseSolution 'solution.nodes.node*.name' | grep -o '>' | wc -l)
num_devices=$(parseSolution 'solution.storage.cvg*.devices*.device' | grep -o '>' | wc -l)

readonly namespace
readonly num_nodes
readonly num_devices

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
# Check deployments
expected_count=1
[[ ${data_deployment} == true ]] && expected_count=0
count=0
msg_info "| Checking Deployments |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get deployments --namespace="${namespace}" | grep 'cortx-control')

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
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get pods --namespace="${namespace}" | grep 'cortx-control-')

if [[ ${expected_count} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check services load balancer
count=0
msg_info "| Checking Services: cortx-control-loadbal-svc |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get services --namespace="${namespace}" | grep 'cortx-control-loadbal-')

if [[ ${expected_count} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check storage local
count=0
num_pvs_pvcs=2
[[ ${data_deployment} == true ]] && num_pvs_pvcs=0
msg_info "| Checking Storage: Local [PVCs/PVs] |"
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
done < <(kubectl get pvc --namespace="${namespace}" | grep 'cortx-control-fs-local-pvc')

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "PV: %s..." "${status[5]}"
        if [[ "${status[4]}" != "Bound" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get pv --namespace="${namespace}" | grep 'cortx-control-fs-local-pvc')

if [[ ${num_pvs_pvcs} -eq ${count} ]]; then
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
# Check deployments
count=0
msg_info "| Checking Deployments |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get deployments --namespace="${namespace}" | grep 'cortx-data-')

if [[ ${num_nodes} -eq ${count} ]]; then
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
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get pods --namespace="${namespace}" | grep 'cortx-data-')

if [[ ${num_nodes} -eq ${count} ]]; then
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
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get services --namespace="${namespace}" | grep 'cortx-data-headless-')

if [[ ${num_nodes} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check services cluster IP
count=0
msg_info "| Checking Services: Cluster IP |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get services --namespace="${namespace}" | grep 'cortx-data-clusterip-')

if [[ ${num_nodes} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check storage local
count=0
num_pvs_pvcs=$(( num_nodes * 2 ))
msg_info "| Checking Storage: Local [PVCs/PVs] |"
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
done < <(kubectl get pvc --namespace="${namespace}" | grep 'cortx-data-fs-local-pvc')

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "PV: %s..." "${status[5]}"
        if [[ "${status[4]}" != "Bound" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get pv --namespace="${namespace}" | grep 'cortx-data-fs-local-pvc')

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
done < <(kubectl get pvc --namespace="${namespace}" | grep 'cortx-data-' | grep -v 'cortx-data-fs-local-pvc')

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "PV: %s..." "${status[5]}"
        if [[ "${status[4]}" != "Bound" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get pv --namespace="${namespace}" | grep 'cortx-data-' | grep -v 'cortx-data-fs-local-pvc')

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
# Check deployments
expected_count=${num_nodes}
[[ ${data_deployment} == true ]] && expected_count=0
count=0
msg_info "| Checking Deployments |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get deployments --namespace="${namespace}" | grep 'cortx-server-')

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
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get pods --namespace="${namespace}" | grep 'cortx-server-')

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
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get services --namespace="${namespace}" | grep 'cortx-server-headless-')

if [[ ${expected_count} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check services cluster IP
count=0
msg_info "| Checking Services: Cluster IP |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get services --namespace="${namespace}" | grep 'cortx-server-clusterip-')

if [[ ${expected_count} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check services load balancer
count=0
msg_info "| Checking Services: cortx-server-loadbal-svc |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        msg_passed
        count=$((count+1))
    fi
done < <(kubectl get services --namespace="${namespace}" | grep 'cortx-server-loadbal-')

if [[ ${expected_count} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check storage local
count=0
num_pvs_pvcs=$(( num_nodes * 2 ))
[[ ${data_deployment} == true ]] && num_pvs_pvcs=0
msg_info "| Checking Storage: Local [PVCs/PVs] |"
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
done < <(kubectl get pvc --namespace="${namespace}" | grep 'cortx-server-fs-local-pvc')

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "PV: %s..." "${status[5]}"
        if [[ "${status[4]}" != "Bound" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get pv --namespace="${namespace}" | grep 'cortx-server-fs-local-pvc')

if [[ ${num_pvs_pvcs} -eq ${count} ]]; then
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
# Check deployments
expected_count=1
[[ ${data_deployment} == true ]] && expected_count=0
count=0
msg_info "| Checking Deployments |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get deployments --namespace="${namespace}" | grep 'cortx-ha')

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
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get pods --namespace="${namespace}" | grep 'cortx-ha-')

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
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get services --namespace="${namespace}" | grep 'cortx-ha-headless-')

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
done < <(kubectl get pvc --namespace="${namespace}" | grep 'cortx-ha-fs-local-pvc')

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "PV: %s..." "${status[5]}"
        if [[ "${status[4]}" != "Bound" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get pv --namespace="${namespace}" | grep 'cortx-ha-fs-local-pvc')

if [[ ${num_pvs_pvcs} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi


num_motr_client=$(extractBlock 'solution.common.motr.num_client_inst')

if [[ ${num_motr_client} -gt 0 ]]; then
    #########################################################################################
    # CORTX Client
    #########################################################################################
    alert_msg "######################################################"
    alert_msg "# CORTX Client                                        "
    alert_msg "######################################################"

    # Check deployments
    count=0
    msg_info "| Checking Deployments |"
    while IFS= read -r line; do
        IFS=" " read -r -a status <<< "${line}"
        IFS="/" read -r -a ready_status <<< "${status[1]}"
        if [[ "${status[0]}" != "" ]]; then
            printf "%s..." "${status[0]}"
            if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
                msg_failed
                failcount=$((failcount+1))
            else
                msg_passed
                count=$((count+1))
            fi
        fi
    done < <(kubectl get deployments --namespace="${namespace}" | grep 'cortx-client')

    if [[ ${num_nodes} -eq ${count} ]]; then
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
        if [[ "${status[0]}" != "" ]]; then
            printf "%s..." "${status[0]}"
            if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
                msg_failed
                failcount=$((failcount+1))
            else
                msg_passed
                count=$((count+1))
            fi
        fi
    done < <(kubectl get pods --namespace="${namespace}" | grep 'cortx-client-')

    if [[ ${num_nodes} -eq ${count} ]]; then
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
        if [[ "${status[0]}" != "" ]]; then
            printf "%s..." "${status[0]}"
            if [[ "${status[1]}" != "ClusterIP" ]]; then
                msg_failed
                failcount=$((failcount+1))
            else
                msg_passed
                count=$((count+1))
            fi
        fi
    done < <(kubectl get services --namespace="${namespace}" | grep 'cortx-client-headless-')

    if [[ ${num_nodes} -eq ${count} ]]; then
        msg_overall_passed
    else
        msg_overall_failed
        failcount=$((failcount+1))
    fi

    # Check storage local
    count=0
    num_pvs_pvcs=$(( num_nodes * 2 ))
    msg_info "| Checking Storage: Local [PVCs/PVs] |"
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
    done < <(kubectl get pvc --namespace="${namespace}" | grep 'cortx-client-fs-local-pvc')

    while IFS= read -r line; do
        IFS=" " read -r -a status <<< "${line}"
        if [[ "${status[0]}" != "" ]]; then
            printf "PV: %s..." "${status[5]}"
            if [[ "${status[4]}" != "Bound" ]]; then
                msg_failed
                failcount=$((failcount+1))
            else
                msg_passed
                count=$((count+1))
            fi
        fi
    done < <(kubectl get pv --namespace="${namespace}" | grep 'cortx-client-fs-local-pvc')

    if [[ ${num_pvs_pvcs} -eq ${count} ]]; then
        msg_overall_passed
    else
        msg_overall_failed
        failcount=$((failcount+1))
    fi
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
# Check StatefulSet
num_items=1
count=0
msg_info "| Checking StatefulSet |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get statefulsets | grep 'kafka')

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
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get pods | grep 'kafka-')

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
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get services | grep 'kafka' | grep -v 'kafka-headless')

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
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get services | grep 'kafka-headless')

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
done < <(kubectl get pvc | grep 'kafka-')

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "PV: %s..." "${status[5]}"
        if [[ "${status[4]}" != "Bound" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get pv | grep 'kafka-')

if [[ ${num_pvs_pvcs} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

alert_msg "### Zookeeper"
# Check StatefulSet
num_items=1
count=0
msg_info "| Checking StatefulSet |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get statefulsets | grep 'zookeeper')

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
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get pods | grep 'zookeeper-')

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
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get services | grep 'zookeeper' | grep -v 'zookeeper-headless')

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
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get services | grep 'zookeeper-headless')

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
done < <(kubectl get pvc | grep 'zookeeper-')

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "PV: %s..." "${status[5]}"
        if [[ "${status[4]}" != "Bound" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get pv | grep 'zookeeper-')

if [[ ${num_pvs_pvcs} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

alert_msg "### Consul"
# Check StatefulSet
num_items=1
count=0
msg_info "| Checking StatefulSet |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get statefulsets | grep 'consul')

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
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[3]}" != "${num_worker_nodes}" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get daemonsets | grep 'consul')

if [[ ${num_items} -eq ${count} ]]; then
    msg_overall_passed
else
    msg_overall_failed
    failcount=$((failcount+1))
fi

# Check Pods
num_items=$(( num_replicas + num_worker_nodes ))
count=0
msg_info "| Checking Pods |"
while IFS= read -r line; do
        IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get pods | grep 'consul-')

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
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get services | grep 'consul' | grep -v 'consul-server')

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
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get services | grep 'consul-server')

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
done < <(kubectl get pvc | grep 'consul-server-')

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "PV: %s..." "${status[5]}"
        if [[ "${status[4]}" != "Bound" ]]; then
            msg_failed
            failcount=$((failcount+1))
        else
            msg_passed
            count=$((count+1))
        fi
    fi
done < <(kubectl get pv | grep 'consul-server-')

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
