#!/usr/bin/env bash

# shellcheck disable=SC2312

solution_yaml=${1:-'solution.yaml'}

# Check if the file exists
if [[ ! -f ${solution_yaml} ]]
then
    echo "ERROR: ${solution_yaml} does not exist"
    exit 1
fi

function parseSolution()
{
    ./parse_scripts/parse_yaml.sh "${solution_yaml}" "$1"
}

namespace=$(parseSolution 'solution.namespace' | cut -f2 -d'>')
readonly namespace

printf "########################################################\n"
printf "# Shutdown CORTX Control                                \n"
printf "########################################################\n"

while IFS= read -r line; do
    IFS=" " read -r -a deployments <<< "${line}"
    kubectl scale deploy "${deployments[0]}" --replicas 0 --namespace="${namespace}"
done < <(kubectl get deployments --namespace="${namespace}" | grep 'cortx-control')

printf "\nWait for CORTX Control to be shutdown"
while true; do
    output=$(kubectl get pods --namespace="${namespace}" | grep 'cortx-control-')
    if [[ "${output}" == "" ]]; then
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
    IFS=" " read -r -a deployments <<< "${line}"
    kubectl scale deploy "${deployments[0]}" --replicas 0 --namespace="${namespace}"
done < <(kubectl get deployments --namespace="${namespace}" | grep 'cortx-data-')

printf "\nWait for CORTX Data to be shutdown"
while true; do
    output=$(kubectl get pods --namespace="${namespace}" | grep 'cortx-data-')
    if [[ "${output}" == "" ]]; then
        break
    else
        printf "."
    fi
    sleep 1s
done
printf "\n\n"
printf "All CORTX Data pods have been shutdown"
printf "\n\n"

printf "########################################################\n"
printf "# Shutdown CORTX Server                                 \n"
printf "########################################################\n"

while IFS= read -r line; do
    IFS=" " read -r -a deployments <<< "${line}"
    kubectl scale statefulset "${deployments[0]}" --replicas 0 --namespace="${namespace}"
done < <(kubectl get statefulset --namespace="${namespace}" | grep 'cortx-server')

printf "\nWait for CORTX Server to be shutdown"
while true; do
    output=$(kubectl get pods --namespace="${namespace}" | grep 'cortx-server-')
    if [[ "${output}" == "" ]]; then
        break
    else
        printf "."
    fi
    sleep 1s
done
printf "\n\n"
printf "All CORTX Server pods have been shutdown"
printf "\n\n"

printf "########################################################\n"
printf "# Shutdown CORTX HA                                     \n"
printf "########################################################\n"

while IFS= read -r line; do
    IFS=" " read -r -a deployments <<< "${line}"
    kubectl scale deploy "${deployments[0]}" --replicas 0 --namespace="${namespace}"
done < <(kubectl get deployments --namespace="${namespace}" | grep 'cortx-ha')

printf "\nWait for CORTX HA to be shutdown"
while true; do
    output=$(kubectl get pods --namespace="${namespace}" | grep 'cortx-ha-')
    if [[ "${output}" == "" ]]; then
        break
    else
        printf "."
    fi
    sleep 1s
done
printf "\n\n"
printf "All CORTX HA pods have been shutdown"
printf "\n\n"

num_motr_client=$(parseSolution 'solution.common.motr.num_client_inst' | cut -f2 -d'>')

if [[ ${num_motr_client} -gt 0 ]]; then
    printf "########################################################\n"
    printf "# Shutdown CORTX Client                                 \n"
    printf "########################################################\n"

    while IFS= read -r line; do
        IFS=" " read -r -a deployments <<< "${line}"
        kubectl scale deploy "${deployments[0]}" --replicas 0 --namespace="${namespace}"
    done < <(kubectl get deployments --namespace="${namespace}" | grep 'cortx-client-')

    printf "\nWait for CORTX Client to be shutdown"
    while true; do
        output=$(kubectl get pods --namespace="${namespace}" | grep 'cortx-client-')
        if [[ "${output}" == "" ]]; then
            break
        else
            printf "."
        fi
        sleep 1s
    done
    printf "\n\n"
    printf "All CORTX Client pods have been shutdown"
    printf "\n\n"
fi
