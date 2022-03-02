#!/bin/bash

# shellcheck disable=SC2312

solution_yaml=${1:-'solution.yaml'}

# Check if the file exists
if [[ ! -f ${solution_yaml} ]]; then
    echo "ERROR: ${solution_yaml} does not exist"
    exit 1
fi

failcount=0

ESC=$(printf '\033')
RED="${ESC}[0;31m"
GREEN="${ESC}[0;32m"
YELLOW="${ESC}[0;33m"
CYAN="${ESC}[0;36m"
NC="${ESC}[0m"

print_alert() {
    printf "%s%s%s" "${YELLOW}" "$1" "${NC}"
    [[ -z $2 ]] && printf "\n"
}

print_failed() {
    printf "%s%s%s" "${RED}" "$1" "${NC}"
    [[ -z $2 ]] && printf "\n"
}

print_passed() {
    printf "%s%s%s" "${GREEN}" "$1" "${NC}"
    [[ -z $2 ]] && printf "\n"
}

print_info() {
    printf "%s%s%s" "${CYAN}" "$1" "${NC}"
    [[ -z $2 ]] && printf "\n"
}

print_overall_passed() {
    printf "OVERALL STATUS: "
    print_passed "PASSED"
}

print_overall_failed() {
    printf "OVERALL STATUS: "
    print_failed "FAILED"
}

parseSolution() {
    ./parse_scripts/parse_yaml.sh "${solution_yaml}" "$1"
}

namespace=$(parseSolution 'solution.namespace')
namespace=$(echo "${namespace}" | cut -f2 -d'>')

#########################################################################################
# CORTX Control
#########################################################################################
num_nodes=1

print_alert "######################################################"
print_alert "# CORTX Control                                       "
print_alert "######################################################"
# Check deployments
count=0
print_info "| Checking Deployments |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get deployments --namespace="${namespace}" | grep 'cortx-control')"

if [[ ${num_nodes} -eq ${count} ]]; then
    printf "OVERALL STATUS: "
    print_passed "PASSED"
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check pods
count=0
print_info "| Checking Pods |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pods --namespace="${namespace}" | grep 'cortx-control-')"

if [[ ${num_nodes} -eq ${count} ]]; then
    printf "OVERALL STATUS: "
    print_passed "PASSED"
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check services load balance
count=0
print_info "| Checking Services: cortx-control-loadbal-svc |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        print_passed "PASSED"
        count=$((count+1))
    fi
done <<< "$(kubectl get services --namespace="${namespace}" | grep 'cortx-control-loadbal-')"

if [[ ${num_nodes} -eq ${count} ]]; then
    printf "OVERALL STATUS: "
    print_passed "PASSED"
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check storage local
count=0
num_pvs_pvcs=2
print_info "| Checking Storage: Local [PVCs/PVs] |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "PVC: %s..." "${status[0]}"
        if [[ "${status[1]}" != "Bound" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pvc --namespace="${namespace}" | grep 'cortx-control-fs-local-pvc')"

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "PV: %s..." "${status[5]}"
        if [[ "${status[4]}" != "Bound" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pv --namespace="${namespace}" | grep 'cortx-control-fs-local-pvc')"

if [[ ${num_pvs_pvcs} -eq ${count} ]]; then
    printf "OVERALL STATUS: "
    print_passed "PASSED"
else
    print_overall_failed
    failcount=$((failcount+1))
fi

if [[ ${num_pvs_pvcs} -eq ${count} ]]; then
    printf "OVERALL STATUS: "
    print_passed "PASSED"
else
    print_overall_failed
    failcount=$((failcount+1))
fi

#########################################################################################
# CORTX Data
#########################################################################################
nodes_names=$(parseSolution 'solution.nodes.node*.name')
num_nodes=$(echo "${nodes_names}" | grep -o '>' | wc -l)
device_names=$(parseSolution 'solution.storage.cvg*.devices*.device')
num_devices=$(echo "${device_names}" | grep -o '>' | wc -l)

print_alert "######################################################"
print_alert "# CORTX Data                                          "
print_alert "######################################################"
# Check deployments
# Check deployments
count=0
print_info "| Checking Deployments |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get deployments --namespace="${namespace}" | grep 'cortx-data-')"

if [[ ${num_nodes} -eq ${count} ]]; then
    printf "OVERALL STATUS: "
    print_passed "PASSED"
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check pods
count=0
print_info "| Checking Pods |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pods --namespace="${namespace}" | grep 'cortx-data-')"

if [[ ${num_nodes} -eq ${count} ]]; then
    printf "OVERALL STATUS: "
    print_passed "PASSED"
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check services headless
count=0
print_info "| Checking Services: Headless |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get services --namespace="${namespace}" | grep 'cortx-data-headless-')"

if [[ ${num_nodes} -eq ${count} ]]; then
    printf "OVERALL STATUS: "
    print_passed "PASSED"
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check services cluster IP
count=0
print_info "| Checking Services: Cluster IP |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get services --namespace="${namespace}" | grep 'cortx-data-clusterip-')"

if [[ ${num_nodes} -eq ${count} ]]; then
    printf "OVERALL STATUS: "
    print_passed "PASSED"
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check storage local
count=0
num_pvs_pvcs=$(( num_nodes * 2 ))
print_info "| Checking Storage: Local [PVCs/PVs] |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "PVC: %s..." "${status[0]}"
        if [[ "${status[1]}" != "Bound" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pvc --namespace="${namespace}" | grep 'cortx-data-fs-local-pvc')"

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "PV: %s..." "${status[5]}"
        if [[ "${status[4]}" != "Bound" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pv --namespace="${namespace}" | grep 'cortx-data-fs-local-pvc')"

if [[ ${num_pvs_pvcs} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check storage block devices
count=0
num_pvs_pvcs=$(( (num_nodes * num_devices) * 2 ))
print_info "| Checking Storage: Block Devices [PVCs/PVs] |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "PVC: %s..." "${status[0]}"
        if [[ "${status[1]}" != "Bound" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pvc --namespace="${namespace}" | grep 'cortx-data-' | grep -v 'cortx-data-fs-local-pvc')"

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "PV: %s..." "${status[5]}"
        if [[ "${status[4]}" != "Bound" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pv --namespace="${namespace}" | grep 'cortx-data-' | grep -v 'cortx-data-fs-local-pvc')"

if [[ ${num_pvs_pvcs} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi

#########################################################################################
# CORTX Server
#########################################################################################
nodes_names=$(parseSolution 'solution.nodes.node*.name')
num_nodes=$(echo "${nodes_names}" | grep -o '>' | wc -l)
device_names=$(parseSolution 'solution.storage.cvg*.devices*.device')
num_devices=$(echo "${device_names}" | grep -o '>' | wc -l)

print_alert "######################################################"
print_alert "# CORTX Server                                        "
print_alert "######################################################"
# Check deployments
count=0
print_info "| Checking Deployments |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get deployments --namespace="${namespace}" | grep 'cortx-server-')"

if [[ ${num_nodes} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check pods
count=0
print_info "| Checking Pods |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pods --namespace="${namespace}" | grep 'cortx-server-')"

if [[ ${num_nodes} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check services headless
count=0
print_info "| Checking Services: Headless |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get services --namespace="${namespace}" | grep 'cortx-server-headless-')"

if [[ ${num_nodes} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check services cluster IP
count=0
print_info "| Checking Services: Cluster IP |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get services --namespace="${namespace}" | grep 'cortx-server-clusterip-')"

if [[ ${num_nodes} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check services load balance
count=0
num_load_bal=${num_nodes}
print_info "| Checking Services: cortx-server-loadbal-svc |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        print_passed "PASSED"
        count=$((count+1))
    fi
done <<< "$(kubectl get services --namespace="${namespace}" | grep 'cortx-server-loadbal-')"

if [[ ${num_load_bal} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check storage local
count=0
num_pvs_pvcs=$(( num_nodes * 2 ))
print_info "| Checking Storage: Local [PVCs/PVs] |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "PVC: %s..." "${status[0]}"
        if [[ "${status[1]}" != "Bound" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pvc --namespace="${namespace}" | grep 'cortx-server-fs-local-pvc')"

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "PV: %s..." "${status[5]}"
        if [[ "${status[4]}" != "Bound" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pv --namespace="${namespace}" | grep 'cortx-server-fs-local-pvc')"

if [[ ${num_pvs_pvcs} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi

#########################################################################################
# CORTX HA
#########################################################################################
num_nodes=1
device_names=$(parseSolution 'solution.storage.cvg*.devices*.device')
num_devices=$(echo "${device_names}" | grep -o '>' | wc -l)

print_alert "######################################################"
print_alert "# CORTX HA                                            "
print_alert "######################################################"
# Check deployments
count=0
print_info "| Checking Deployments |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get deployments --namespace="${namespace}" | grep 'cortx-ha')"

if [[ ${num_nodes} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check pods
count=0
print_info "| Checking Pods |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pods --namespace="${namespace}" | grep 'cortx-ha-')"

if [[ ${num_nodes} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check services headless
count=0
print_info "| Checking Services: Headless |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get services --namespace="${namespace}" | grep 'cortx-ha-headless-')"

if [[ ${num_nodes} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check storage local
count=0
num_pvs_pvcs=$(( num_nodes * 2 ))
print_info "| Checking Storage: Local [PVCs/PVs] |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "PVC: %s..." "${status[0]}"
        if [[ "${status[1]}" != "Bound" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pvc --namespace="${namespace}" | grep 'cortx-ha-fs-local-pvc')"

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "PV: %s..." "${status[5]}"
        if [[ "${status[4]}" != "Bound" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pv --namespace="${namespace}" | grep 'cortx-ha-fs-local-pvc')"

if [[ ${num_pvs_pvcs} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi


function extractBlock()
{
    ./parse_scripts/yaml_extract_block.sh "${solution_yaml}" "$1"
}

num_motr_client=$(extractBlock 'solution.common.motr.num_client_inst')

if [[ ${num_motr_client} -gt 0 ]]; then
    #########################################################################################
    # CORTX Client
    #########################################################################################
    nodes_names=$(parseSolution 'solution.nodes.node*.name')
    num_nodes=$(echo "${nodes_names}" | grep -o '>' | wc -l)
    device_names=$(parseSolution 'solution.storage.cvg*.devices*.device')
    num_devices=$(echo "${device_names}" | grep -o '>' | wc -l)

    print_alert "######################################################"
    print_alert "# CORTX Client                                        "
    print_alert "######################################################"

    # Check deployments
    count=0
    print_info "| Checking Deployments |"
    while IFS= read -r line; do
        IFS=" " read -r -a status <<< "${line}"
        IFS="/" read -r -a ready_status <<< "${status[1]}"
        if [[ "${status[0]}" != "" ]]; then
            printf "%s..." "${status[0]}"
            if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
                print_fail "FAILED"
                failcount=$((failcount+1))
            else
                print_passed "PASSED"
                count=$((count+1))
            fi
        fi
    done <<< "$(kubectl get deployments --namespace="${namespace}" | grep 'cortx-client')"

    if [[ ${num_nodes} -eq ${count} ]]; then
        print_overall_passed
    else
        print_overall_failed
        failcount=$((failcount+1))
    fi

    # Check pods
    count=0
    print_info "| Checking Pods |"
    while IFS= read -r line; do
        IFS=" " read -r -a status <<< "${line}"
        IFS="/" read -r -a ready_status <<< "${status[1]}"
        if [[ "${status[0]}" != "" ]]; then
            printf "%s..." "${status[0]}"
            if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
                print_fail "FAILED"
                failcount=$((failcount+1))
            else
                print_passed "PASSED"
                count=$((count+1))
            fi
        fi
    done <<< "$(kubectl get pods --namespace="${namespace}" | grep 'cortx-client-')"

    if [[ ${num_nodes} -eq ${count} ]]; then
        print_overall_passed
    else
        print_overall_failed
        failcount=$((failcount+1))
    fi

    # Check services headless
    count=0
    print_info "| Checking Services: Headless |"
    while IFS= read -r line; do
        IFS=" " read -r -a status <<< "${line}"
        if [[ "${status[0]}" != "" ]]; then
            printf "%s..." "${status[0]}"
            if [[ "${status[1]}" != "ClusterIP" ]]; then
                print_fail "FAILED"
                failcount=$((failcount+1))
            else
                print_passed "PASSED"
                count=$((count+1))
            fi
        fi
    done <<< "$(kubectl get services --namespace="${namespace}" | grep 'cortx-client-headless-')"

    if [[ ${num_nodes} -eq ${count} ]]; then
        print_overall_passed
    else
        print_overall_failed
        failcount=$((failcount+1))
    fi

    # Check storage local
    count=0
    num_pvs_pvcs=$(( num_nodes * 2 ))
    print_info "| Checking Storage: Local [PVCs/PVs] |"
    while IFS= read -r line; do
        IFS=" " read -r -a status <<< "${line}"
        if [[ "${status[0]}" != "" ]]; then
            printf "PVC: %s..." "${status[0]}"
            if [[ "${status[1]}" != "Bound" ]]; then
                print_fail "FAILED"
                failcount=$((failcount+1))
            else
                print_passed "PASSED"
                count=$((count+1))
            fi
        fi
    done <<< "$(kubectl get pvc --namespace="${namespace}" | grep 'cortx-client-fs-local-pvc')"

    while IFS= read -r line; do
        IFS=" " read -r -a status <<< "${line}"
        if [[ "${status[0]}" != "" ]]; then
            printf "PV: %s..." "${status[5]}"
            if [[ "${status[4]}" != "Bound" ]]; then
                print_fail "FAILED"
                failcount=$((failcount+1))
            else
                print_passed "PASSED"
                count=$((count+1))
            fi
        fi
    done <<< "$(kubectl get pv --namespace="${namespace}" | grep 'cortx-client-fs-local-pvc')"

    if [[ ${num_pvs_pvcs} -eq ${count} ]]; then
        print_overall_passed
    else
        print_overall_failed
        failcount=$((failcount+1))
    fi
fi

#########################################################################################
# 3rd Party
#########################################################################################
while IFS= read -r line; do
    IFS=" " read -r -a node_name <<< "${line}"
    if [[ "${node_name[0]}" != "NAME" ]]; then
        output=$(kubectl describe nodes "${node_name[0]}" | grep Taints | grep NoSchedule)
        if [[ "${output}" == "" ]]; then
            num_worker_nodes=$((num_worker_nodes+1))
        fi
    fi
done <<< "$(kubectl get nodes)"

num_nodes=${num_worker_nodes}
max_replicas=3
num_replicas=${num_nodes}
if [[ "${num_nodes}" -gt "${max_replicas}" ]]; then
    num_replicas=${max_replicas}
fi
print_alert "######################################################"
print_alert "# 3rd Party                                           "
print_alert "######################################################"

print_alert "### Kafka"
# Check StatefulSet
num_items=1
count=0
print_info "| Checking StatefulSet |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get statefulsets | grep 'kafka')"

if [[ ${num_items} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check Pods
num_items=${num_replicas}
count=0
print_info "| Checking Pods |"
while IFS= read -r line; do
        IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pods | grep 'kafka-')"

if [[ ${num_items} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check services cluster IP
num_items=1
count=0
print_info "| Checking Services: Cluster IP |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get services | grep 'kafka' | grep -v 'kafka-headless')"

if [[ ${num_items} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check services headless
num_items=1
count=0
print_info "| Checking Services: Headless |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get services | grep 'kafka-headless')"

if [[ ${num_items} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check storage local
count=0
num_pvs_pvcs=$(( num_replicas * 2 ))
print_info "| Checking Storage: Local [PVCs/PVs] |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "PVC: %s..." "${status[0]}"
        if [[ "${status[1]}" != "Bound" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pvc | grep 'kafka-')"

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "PV: %s..." "${status[5]}"
        if [[ "${status[4]}" != "Bound" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pv | grep 'kafka-')"

if [[ ${num_pvs_pvcs} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi

print_alert "### Zookeeper"
# Check StatefulSet
num_items=1
count=0
print_info "| Checking StatefulSet |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get statefulsets | grep 'zookeeper')"

if [[ ${num_items} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check Pods
num_items=${num_replicas}
count=0
print_info "| Checking Pods |"
while IFS= read -r line; do
        IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pods | grep 'zookeeper-')"

if [[ ${num_items} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check services cluster IP
num_items=1
count=0
print_info "| Checking Services: Cluster IP |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get services | grep 'zookeeper' | grep -v 'zookeeper-headless')"

if [[ ${num_items} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check services headless
num_items=1
count=0
print_info "| Checking Services: Headless |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get services | grep 'zookeeper-headless')"

if [[ ${num_items} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check storage local
count=0
num_pvs_pvcs=$(( num_replicas * 2 ))
print_info "| Checking Storage: Local [PVCs/PVs] |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "PVC: %s..." "${status[0]}"
        if [[ "${status[1]}" != "Bound" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pvc | grep 'zookeeper-')"

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "PV: %s..." "${status[5]}"
        if [[ "${status[4]}" != "Bound" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pv | grep 'zookeeper-')"

if [[ ${num_pvs_pvcs} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi

print_alert "### Consul"
# Check StatefulSet
num_items=1
count=0
print_info "| Checking StatefulSet |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get statefulsets | grep 'consul')"

if [[ ${num_items} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check DaemonSet
num_items=1
count=0
print_info "| Checking DaemonSet |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[3]}" != "${num_worker_nodes}" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get daemonsets | grep 'consul')"

if [[ ${num_items} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check Pods
num_items=$(( num_replicas + num_worker_nodes ))
count=0
print_info "| Checking Pods |"
while IFS= read -r line; do
        IFS=" " read -r -a status <<< "${line}"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pods | grep 'consul-')"

if [[ ${num_items} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check services cluster IP
num_items=1
count=0
print_info "| Checking Services: Cluster IP |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get services | grep 'consul' | grep -v 'consul-server')"

if [[ ${num_items} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check services headless
num_items=1
count=0
print_info "| Checking Services: Headless |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "%s..." "${status[0]}"
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get services | grep 'consul-server')"

if [[ ${num_items} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi

# Check storage local
count=0
num_pvs_pvcs=$(( num_replicas * 2 ))
print_info "| Checking Storage: Local [PVCs/PVs] |"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "PVC: %s..." "${status[0]}"
        if [[ "${status[1]}" != "Bound" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pvc | grep 'consul-server-')"

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "${line}"
    if [[ "${status[0]}" != "" ]]; then
        printf "PV: %s..." "${status[5]}"
        if [[ "${status[4]}" != "Bound" ]]; then
            print_fail "FAILED"
            failcount=$((failcount+1))
        else
            print_passed "PASSED"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pv | grep 'consul-server-')"

if [[ ${num_pvs_pvcs} -eq ${count} ]]; then
    print_overall_passed
else
    print_overall_failed
    failcount=$((failcount+1))
fi

printf -- "------------------------------------------\n"

if (( failcount > 0 )); then
    print_failed "${failcount} status checks failed"
    exit 1
else
    print_passed "All status checks passed"
    printf "\n"
    exit 0
fi
