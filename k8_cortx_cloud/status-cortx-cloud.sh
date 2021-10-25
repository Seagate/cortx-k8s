#!/bin/bash

solution_yaml=${1:-'solution.yaml'}

# Check if the file exists
if [ ! -f $solution_yaml ]
then
    echo "ERROR: $solution_yaml does not exist"
    exit 1
fi

FAILED='\033[0;31m'       #RED
PASSED='\033[0;32m'       #GREEN
ALERT='\033[0;33m'        #YELLOW
INFO='\033[0;36m'        #CYAN
NC='\033[0m'              #NO COLOUR

function parseSolution()
{
    echo "$(./parse_scripts/parse_yaml.sh $solution_yaml $1)"
}

namespace=$(parseSolution 'solution.namespace')
namespace=$(echo $namespace | cut -f2 -d'>')

#########################################################################################
# CORTX Control
#########################################################################################
num_nodes=1
printf "${ALERT}######################################################${NC}\n"
printf "${ALERT}# CORTX Control                                       ${NC}\n"
printf "${ALERT}######################################################${NC}\n"
# Check deployments
count=0
printf "${INFO}| Checking Deployments |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "${status[0]}..."
        if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get deployments --namespace=$namespace | grep 'cortx-control-pod')"

if [[ $num_nodes -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check pods
count=0
printf "${INFO}| Checking Pods |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "${status[0]}..."
        if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pods --namespace=$namespace | grep 'cortx-control-pod-')"

if [[ $num_nodes -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check services headless
count=0
printf "${INFO}| Checking Services: Headless |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "${status[0]}..."
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get services --namespace=$namespace | grep 'cortx-control-headless-')"

if [[ $num_nodes -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check services cluster IP
count=0
printf "${INFO}| Checking Services: Cluster IP |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "${status[0]}..."
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get services --namespace=$namespace | grep 'cortx-control-clusterip-')"

if [[ $num_nodes -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check services load balance
count=0
printf "${INFO}| Checking Services: Load Balancer |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "${status[0]}..."
        if [[ "${status[1]}" != "LoadBalancer" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get services --namespace=$namespace | grep 'cortx-control-loadbal-')"

if [[ $num_nodes -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check storage local
count=0
num_pvs_pvcs=2
printf "${INFO}| Checking Storage: Local [PVCs/PVs] |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "PVC: ${status[0]}..."
        if [[ "${status[1]}" != "Bound" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pvc --namespace=$namespace | grep 'cortx-control-fs-local-pvc')"

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "PV: ${status[5]}..."
        if [[ "${status[4]}" != "Bound" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pv --namespace=$namespace | grep 'cortx-control-fs-local-pvc')"

if [[ $num_pvs_pvcs -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check storage shared
count=0
num_pvs_pvcs=2
printf "${INFO}| Checking Storage: Shared [PVCs/PVs] |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "PVC: ${status[0]}..."
        if [[ "${status[1]}" != "Bound" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pvc --namespace=$namespace | grep 'gluster-claim')"

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "PV: ${status[5]}..."
        if [[ "${status[4]}" != "Bound" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pv --namespace=$namespace | grep 'gluster-claim')"

if [[ $num_pvs_pvcs -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

#########################################################################################
# CORTX Data
#########################################################################################
nodes_names=$(parseSolution 'solution.nodes.node*.name')
num_nodes=$(echo $nodes_names | grep -o '>' | wc -l)
device_names=$(parseSolution 'solution.storage.cvg*.devices*.device')
num_devices=$(echo $device_names | grep -o '>' | wc -l)

printf "${ALERT}######################################################${NC}\n"
printf "${ALERT}# CORTX Data                                          ${NC}\n"
printf "${ALERT}######################################################${NC}\n"
# Check deployments
count=0
printf "${INFO}| Checking Deployments |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "${status[0]}..."
        if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get deployments --namespace=$namespace | grep 'cortx-data-pod-')"

if [[ $num_nodes -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check pods
count=0
printf "${INFO}| Checking Pods |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "${status[0]}..."
        if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pods --namespace=$namespace | grep 'cortx-data-pod-')"

if [[ $num_nodes -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check services headless
count=0
printf "${INFO}| Checking Services: Headless |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "${status[0]}..."
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get services --namespace=$namespace | grep 'cortx-data-headless-')"

if [[ $num_nodes -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check services cluster IP
count=0
printf "${INFO}| Checking Services: Cluster IP |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "${status[0]}..."
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get services --namespace=$namespace | grep 'cortx-data-clusterip-')"

if [[ $num_nodes -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check services load balance
count=0
printf "${INFO}| Checking Services: Load Balancer |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "${status[0]}..."
        if [[ "${status[1]}" != "LoadBalancer" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get services --namespace=$namespace | grep 'cortx-data-loadbal-')"

if [[ $num_nodes -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check storage local
count=0
num_pvs_pvcs=$(($num_nodes*2))
printf "${INFO}| Checking Storage: Local [PVCs/PVs] |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "PVC: ${status[0]}..."
        if [[ "${status[1]}" != "Bound" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pvc --namespace=$namespace | grep 'cortx-data-fs-local-pvc')"

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "PV: ${status[5]}..."
        if [[ "${status[4]}" != "Bound" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pv --namespace=$namespace | grep 'cortx-data-fs-local-pvc')"

if [[ $num_pvs_pvcs -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check storage shared
count=0
num_pvs_pvcs=2
printf "${INFO}| Checking Storage: Shared [PVCs/PVs] |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "PVC: ${status[0]}..."
        if [[ "${status[1]}" != "Bound" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pvc --namespace=$namespace | grep 'gluster-claim')"

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "PV: ${status[5]}..."
        if [[ "${status[4]}" != "Bound" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pv --namespace=$namespace | grep 'gluster-claim')"

if [[ $num_pvs_pvcs -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check storage block devices
count=0
num_pvs_pvcs=$((($num_nodes*$num_devices)*2))
printf "${INFO}| Checking Storage: Block Devices [PVCs/PVs] |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "PVC: ${status[0]}..."
        if [[ "${status[1]}" != "Bound" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pvc --namespace=$namespace | grep 'cortx-data-' | grep -v 'cortx-data-fs-local-pvc')"

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "PV: ${status[5]}..."
        if [[ "${status[4]}" != "Bound" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pv --namespace=$namespace | grep 'cortx-data-' | grep -v 'cortx-data-fs-local-pvc')"

if [[ $num_pvs_pvcs -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

#########################################################################################
# 3rd Party
#########################################################################################
while IFS= read -r line; do
    IFS=" " read -r -a node_name <<< "$line"
    if [[ "$node_name" != "NAME" ]]; then
        output=$(kubectl describe nodes $node_name | grep Taints | grep NoSchedule)
        if [[ "$output" == "" ]]; then
            node_list_str="$num_worker_nodes $node_name"
            num_worker_nodes=$((num_worker_nodes+1))
        fi
    fi
done <<< "$(kubectl get nodes)"

num_nodes=$num_worker_nodes
max_replicas=3
num_replicas=$num_nodes
if [[ "$num_nodes" -gt "$max_replicas" ]]; then
    num_replicas=$max_replicas
fi
printf "${ALERT}######################################################${NC}\n"
printf "${ALERT}# 3rd Party                                           ${NC}\n"
printf "${ALERT}######################################################${NC}\n"
printf "${ALERT}### OpenLDAP${NC}\n"
# Check StatefulSet
num_items=1
count=0
printf "${INFO}| Checking StatefulSet |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "${status[0]}..."
        if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get statefulsets | grep 'openldap')"

if [[ $num_items -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check Pods
num_items=$num_replicas
count=0
printf "${INFO}| Checking Pods |${NC}\n"
while IFS= read -r line; do
        IFS=" " read -r -a status <<< "$line"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "${status[0]}..."
        if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pods | grep 'openldap-')"

if [[ $num_items -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check services cluster IP
num_items=1
count=0
printf "${INFO}| Checking Services: Cluster IP |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "${status[0]}..."
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get services | grep 'openldap-svc')"

if [[ $num_items -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check storage local
count=0
num_pvs_pvcs=$((($num_replicas*2)*3))
printf "${INFO}| Checking Storage: Local [PVCs/PVs] |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "PVC: ${status[0]}..."
        if [[ "${status[1]}" != "Bound" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pvc | grep '3rd-party-openldap')"

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "PV: ${status[5]}..."
        if [[ "${status[4]}" != "Bound" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pv | grep '3rd-party-openldap')"

if [[ $num_pvs_pvcs -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

printf "${ALERT}### Kafka${NC}\n"
# Check StatefulSet
num_items=1
count=0
printf "${INFO}| Checking StatefulSet |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "${status[0]}..."
        if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get statefulsets | grep 'kafka')"

if [[ $num_items -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check Pods
num_items=$num_replicas
count=0
printf "${INFO}| Checking Pods |${NC}\n"
while IFS= read -r line; do
        IFS=" " read -r -a status <<< "$line"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "${status[0]}..."
        if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pods | grep 'kafka-')"

if [[ $num_items -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check services cluster IP
num_items=1
count=0
printf "${INFO}| Checking Services: Cluster IP |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "${status[0]}..."
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get services | grep 'kafka' | grep -v 'kafka-headless')"

if [[ $num_items -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check services headless
num_items=1
count=0
printf "${INFO}| Checking Services: Headless |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "${status[0]}..."
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get services | grep 'kafka-headless')"

if [[ $num_items -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check storage local
count=0
num_pvs_pvcs=$(($num_replicas*2))
printf "${INFO}| Checking Storage: Local [PVCs/PVs] |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "PVC: ${status[0]}..."
        if [[ "${status[1]}" != "Bound" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pvc | grep 'kafka-')"

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "PV: ${status[5]}..."
        if [[ "${status[4]}" != "Bound" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pv | grep 'kafka-')"

if [[ $num_pvs_pvcs -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

printf "${ALERT}### Zookeeper${NC}\n"
# Check StatefulSet
num_items=1
count=0
printf "${INFO}| Checking StatefulSet |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "${status[0]}..."
        if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get statefulsets | grep 'zookeeper')"

if [[ $num_items -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check Pods
num_items=$num_replicas
count=0
printf "${INFO}| Checking Pods |${NC}\n"
while IFS= read -r line; do
        IFS=" " read -r -a status <<< "$line"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "${status[0]}..."
        if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pods | grep 'zookeeper-')"

if [[ $num_items -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check services cluster IP
num_items=1
count=0
printf "${INFO}| Checking Services: Cluster IP |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "${status[0]}..."
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get services | grep 'zookeeper' | grep -v 'zookeeper-headless')"

if [[ $num_items -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check services headless
num_items=1
count=0
printf "${INFO}| Checking Services: Headless |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "${status[0]}..."
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get services | grep 'zookeeper-headless')"

if [[ $num_items -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check storage local
count=0
num_pvs_pvcs=$(($num_replicas*2))
printf "${INFO}| Checking Storage: Local [PVCs/PVs] |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "PVC: ${status[0]}..."
        if [[ "${status[1]}" != "Bound" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pvc | grep 'zookeeper-')"

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "PV: ${status[5]}..."
        if [[ "${status[4]}" != "Bound" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pv | grep 'zookeeper-')"

if [[ $num_pvs_pvcs -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

printf "${ALERT}### Consul${NC}\n"
# Check StatefulSet
num_items=1
count=0
printf "${INFO}| Checking StatefulSet |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "${status[0]}..."
        if [[ "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get statefulsets | grep 'consul')"

if [[ $num_items -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check DaemonSet
num_items=1
count=0
printf "${INFO}| Checking DaemonSet |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "${status[0]}..."
        if [[ "${status[3]}" != "$num_worker_nodes" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get daemonsets | grep 'consul')"

if [[ $num_items -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check Pods
num_items=$(($num_replicas+$num_worker_nodes))
count=0
printf "${INFO}| Checking Pods |${NC}\n"
while IFS= read -r line; do
        IFS=" " read -r -a status <<< "$line"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "${status[0]}..."
        if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pods | grep 'consul-')"

if [[ $num_items -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check services cluster IP
num_items=2
count=0
printf "${INFO}| Checking Services: Cluster IP |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "${status[0]}..."
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get services | grep 'consul' | grep -v 'consul-server')"

if [[ $num_items -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check services headless
num_items=1
count=0
printf "${INFO}| Checking Services: Headless |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "${status[0]}..."
        if [[ "${status[1]}" != "ClusterIP" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get services | grep 'consul-server')"

if [[ $num_items -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check storage local
count=0
num_pvs_pvcs=$(($num_replicas*2))
printf "${INFO}| Checking Storage: Local [PVCs/PVs] |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "PVC: ${status[0]}..."
        if [[ "${status[1]}" != "Bound" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pvc | grep 'consul-server-')"

while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    if [[ "${status[0]}" != "" ]]; then
        printf "PV: ${status[5]}..."
        if [[ "${status[4]}" != "Bound" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi
done <<< "$(kubectl get pv | grep 'consul-server-')"

if [[ $num_pvs_pvcs -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi
