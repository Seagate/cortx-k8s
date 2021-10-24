#!/bin/bash

solution_yaml=${1:-'solution.yaml'}

# Check if the file exists
if [ ! -f $solution_yaml ]
then
    echo "ERROR: $solution_yaml does not exist"
    exit 1
fi

function parseSolution()
{
    echo "$(./parse_scripts/parse_yaml.sh $solution_yaml $1)"
}

namespace=$(parseSolution 'solution.namespace')
namespace=$(echo $namespace | cut -f2 -d'>')

printf "########################################################\n"
printf "# Shutdown CORTX Data                                   \n"
printf "########################################################\n"

while IFS= read -r line; do
    IFS=" " read -r -a deployments <<< "$line"
    kubectl scale deploy "${deployments[0]}" --replicas 0 --namespace=$namespace
done <<< "$(kubectl get deployments --namespace=$namespace | grep 'cortx-control-pod')"

printf "\nWait for CORTX Control to be shutdown"
while true; do
    output=$(kubectl get pods --namespace=$namespace | grep 'cortx-control-pod-')
    if [[ "$output" == "" ]]; then
        break
    else
        printf "."
    fi
    sleep 1s
done
printf "\n\n"
printf "All CORTX Control pods have been shutdown"
printf "\n\n"

printf "########################################################\n"
printf "# Shutdown CORTX Data                                   \n"
printf "########################################################\n"

while IFS= read -r line; do
    IFS=" " read -r -a deployments <<< "$line"
    kubectl scale deploy "${deployments[0]}" --replicas 0 --namespace=$namespace
done <<< "$(kubectl get deployments --namespace=$namespace | grep 'cortx-data-pod-')"

printf "\nWait for CORTX Data to be shutdown"
while true; do
    output=$(kubectl get pods --namespace=$namespace | grep 'cortx-data-pod-')
    if [[ "$output" == "" ]]; then
        break
    else
        printf "."
    fi
    sleep 1s
done
printf "\n\n"
printf "All CORTX Data pods have been shutdown"
printf "\n\n"