#!/bin/bash

FAILED='\033[0;31m'       #RED
PASSED='\033[0;32m'       #GREEN
ALERT='\033[0;33m'        #YELLOW
INFO='\033[0;36m'        #CYAN
NC='\033[0m'              #NO COLOUR

function parseSolution()
{
    echo "$(./parse_scripts/parse_yaml.sh solution.yaml $1)"
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
    IFS=" " read -r -a deployment_status <<< "$line"
    IFS="/" read -r -a ready_status <<< "${deployment_status[1]}"
    if [[ "${deployment_status[0]}" != "" ]]; then
        printf "${deployment_status[0]}..."
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
    IFS=" " read -r -a pod_status <<< "$line"
    IFS="/" read -r -a ready_status <<< "${pod_status[1]}"
    if [[ "${pod_status[0]}" != "" ]]; then
        printf "${pod_status[0]}..."
        if [[ "${pod_status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
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
    IFS=" " read -r -a service_status <<< "$line"
    if [[ "${service_status[0]}" != "" ]]; then
        printf "${service_status[0]}..."
        if [[ "${service_status[1]}" != "ClusterIP" ]]; then
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
    IFS=" " read -r -a service_status <<< "$line"
    if [[ "${service_status[0]}" != "" ]]; then
        printf "${service_status[0]}..."
        if [[ "${service_status[1]}" != "ClusterIP" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
        fi
        count=$((count+1))
    fi

done <<< "$(kubectl get services --namespace=$namespace | grep 'cortx-control-clusterip-')"

if [[ $num_nodes -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

# Check services node port
count=0
printf "${INFO}| Checking Services: Node Port |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a service_status <<< "$line"
    if [[ "${service_status[0]}" != "" ]]; then
        printf "${service_status[0]}..."
        if [[ "${service_status[1]}" != "NodePort" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
            count=$((count+1))
        fi
    fi

done <<< "$(kubectl get services --namespace=$namespace | grep 'cortx-control-nodeport-')"

if [[ $num_nodes -eq $count ]]; then
    printf "OVERALL STATUS: ${PASSED}PASSED${NC}\n"
else
    printf "OVERALL STATUS: ${FAILED}FAILED${NC}\n"
fi

#########################################################################################
# CORTX Data
#########################################################################################
nodes_names=$(parseSolution 'solution.nodes.node*.name')
num_nodes=$(echo $nodes_names | grep -o '>' | wc -l)

printf "${ALERT}######################################################${NC}\n"
printf "${ALERT}# CORTX Data                                          ${NC}\n"
printf "${ALERT}######################################################${NC}\n"
# Check deployments
count=0
printf "${INFO}| Checking Deployments |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a deployment_status <<< "$line"
    IFS="/" read -r -a ready_status <<< "${deployment_status[1]}"
    if [[ "${deployment_status[0]}" != "" ]]; then
        printf "${deployment_status[0]}..."
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
    IFS=" " read -r -a pod_status <<< "$line"
    IFS="/" read -r -a ready_status <<< "${pod_status[1]}"
    if [[ "${pod_status[0]}" != "" ]]; then
        printf "${pod_status[0]}..."
        if [[ "${pod_status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
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
    IFS=" " read -r -a service_status <<< "$line"
    if [[ "${service_status[0]}" != "" ]]; then
        printf "${service_status[0]}..."
        if [[ "${service_status[1]}" != "ClusterIP" ]]; then
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
    IFS=" " read -r -a service_status <<< "$line"
    if [[ "${service_status[0]}" != "" ]]; then
        printf "${service_status[0]}..."
        if [[ "${service_status[1]}" != "ClusterIP" ]]; then
            printf "${FAILED}FAILED${NC}\n"
        else
            printf "${PASSED}PASSED${NC}\n"
        fi
        count=$((count+1))
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
    IFS=" " read -r -a service_status <<< "$line"
    if [[ "${service_status[0]}" != "" ]]; then
        printf "${service_status[0]}..."
        if [[ "${service_status[1]}" != "LoadBalancer" ]]; then
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
