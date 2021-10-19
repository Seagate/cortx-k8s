#!/bin/bash

function parseSolution()
{
    echo "$(./parse_scripts/parse_yaml.sh solution.yaml $1)"
}

namespace=$(parseSolution 'solution.namespace')
namespace=$(echo $namespace | cut -f2 -d'>')

printf "########################################################\n"
printf "# Start CORTX Control                                   \n"
printf "########################################################\n"
num_nodes=0
while IFS= read -r line; do
    IFS=" " read -r -a deployments <<< "$line"
    kubectl scale deploy "${deployments[0]}" --replicas 1 --namespace=$namespace
    num_nodes=$((num_nodes+1))
done <<< "$(kubectl get deployments --namespace=$namespace | grep 'cortx-control-pod')"

printf "\nWait for CORTX Control to be ready"
while true; do
    count=0
    while IFS= read -r line; do
        IFS=" " read -r -a pod_status <<< "$line"
        IFS="/" read -r -a ready_status <<< "${pod_status[1]}"
        if [[ "${pod_status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            break
        fi
        count=$((count+1))
    done <<< "$(kubectl get pods --namespace=$namespace | grep 'cortx-control-pod-')"

    if [[ $num_nodes -eq $count ]]; then
        break
    else
        printf "."
    fi
    sleep 1s
done
printf "\n\n"
printf "All CORTX Control pods have been started"
printf "\n\n"

printf "########################################################\n"
printf "# Start CORTX Data                                      \n"
printf "########################################################\n"
num_nodes=0
while IFS= read -r line; do
    IFS=" " read -r -a deployments <<< "$line"
    kubectl scale deploy "${deployments[0]}" --replicas 1 --namespace=$namespace
    num_nodes=$((num_nodes+1))
done <<< "$(kubectl get deployments --namespace=$namespace | grep 'cortx-data-pod-')"

printf "\nWait for CORTX Data to be ready"
while true; do
    count=0
    while IFS= read -r line; do
        IFS=" " read -r -a pod_status <<< "$line"
        IFS="/" read -r -a ready_status <<< "${pod_status[1]}"
        if [[ "${pod_status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            break
        fi
        count=$((count+1))
    done <<< "$(kubectl get pods --namespace=$namespace | grep 'cortx-data-pod-')"

    if [[ $num_nodes -eq $count ]]; then
        break
    else
        printf "."
    fi
    sleep 1s
done
printf "\n\n"
printf "All CORTX Data pods have been started"
printf "\n\n"