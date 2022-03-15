#!/bin/bash

# shellcheck disable=SC2312

set -u

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

function extractBlock()
{
    ./parse_scripts/yaml_extract_block.sh "${solution_yaml}" "$1"
}

namespace=$(parseSolution 'solution.namespace')
namespace=$(echo "${namespace}" | cut -f2 -d'>')
deployment_type=$(extractBlock 'solution.deployment_type')

readonly namespace
readonly deployment_type

if [[ ${deployment_type} != "data-only" ]]; then
    printf "########################################################\n"
    printf "# Start CORTX Control                                   \n"
    printf "########################################################\n"
    num_nodes=0
    while IFS= read -r line; do
        IFS=" " read -r -a deployments <<< "${line}"
        kubectl scale deploy "${deployments[0]}" --replicas 1 --namespace="${namespace}"
        num_nodes=$((num_nodes+1))
    done < <(kubectl get deployments --namespace="${namespace}" | grep 'cortx-control')

    printf "\nWait for CORTX Control to be ready"
    while true; do
        count=0
        while IFS= read -r line; do
            IFS=" " read -r -a pod_status <<< "${line}"
            IFS="/" read -r -a ready_status <<< "${pod_status[1]}"
            if [[ "${pod_status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
                if [[ "${pod_status[2]}" == "Error" || "${pod_status[2]}" == "Init:Error" ]]; then
                    printf "\n'%s' pod failed to start. Exit early.\n" "${pod_status[0]}"
                    exit 1
                fi
                break
            fi
            count=$((count+1))
        done < <(kubectl get pods --namespace="${namespace}" | grep 'cortx-control-')

        if [[ ${num_nodes} -eq ${count} ]]; then
            break
        else
            printf "."
        fi
        sleep 1s
    done
    printf "\n\n"
    printf "All CORTX Control pods have been started"
    printf "\n\n"
fi

printf "########################################################\n"
printf "# Start CORTX Data                                      \n"
printf "########################################################\n"
num_nodes=0
while IFS= read -r line; do
    IFS=" " read -r -a deployments <<< "${line}"
    kubectl scale deploy "${deployments[0]}" --replicas 1 --namespace="${namespace}"
    num_nodes=$((num_nodes+1))
done < <(kubectl get deployments --namespace="${namespace}" | grep 'cortx-data-')

printf "\nWait for CORTX Data to be ready"
while true; do
    count=0
    while IFS= read -r line; do
        IFS=" " read -r -a pod_status <<< "${line}"
        IFS="/" read -r -a ready_status <<< "${pod_status[1]}"
        if [[ "${pod_status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            if [[ "${pod_status[2]}" == "Error" || "${pod_status[2]}" == "Init:Error" ]]; then
                printf "\n'%s' pod failed to start. Exit early.\n" "${pod_status[0]}"
                exit 1
            fi
            break
        fi
        count=$((count+1))
    done < <(kubectl get pods --namespace="${namespace}" | grep 'cortx-data-')

    if [[ ${num_nodes} -eq ${count} ]]; then
        break
    else
        printf "."
    fi
    sleep 1s
done
printf "\n\n"
printf "All CORTX Data pods have been started"
printf "\n\n"

if [[ ${deployment_type} != "data-only" ]]; then
    printf "########################################################\n"
    printf "# Start CORTX Server                                    \n"
    printf "########################################################\n"
    num_nodes=0
    while IFS= read -r line; do
        IFS=" " read -r -a deployments <<< "${line}"
        kubectl scale deploy "${deployments[0]}" --replicas 1 --namespace="${namespace}"
        num_nodes=$((num_nodes+1))
    done < <(kubectl get deployments --namespace="${namespace}" | grep 'cortx-server-')

    printf "\nWait for CORTX Server to be ready"
    while true; do
        count=0
        while IFS= read -r line; do
            IFS=" " read -r -a pod_status <<< "${line}"
            IFS="/" read -r -a ready_status <<< "${pod_status[1]}"
            if [[ "${pod_status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
                if [[ "${pod_status[2]}" == "Error" || "${pod_status[2]}" == "Init:Error" ]]; then
                    printf "\n'%s' pod failed to start. Exit early.\n" "${pod_status[0]}"
                    exit 1
                fi
                break
            fi
            count=$((count+1))
        done < <(kubectl get pods --namespace="${namespace}" | grep 'cortx-server-')

        if [[ ${num_nodes} -eq ${count} ]]; then
            break
        else
            printf "."
        fi
        sleep 1s
    done
    printf "\n\n"
    printf "All CORTX Server pods have been started"
    printf "\n\n"

    printf "########################################################\n"
    printf "# Start CORTX HA                                        \n"
    printf "########################################################\n"
    num_nodes=0
    while IFS= read -r line; do
        IFS=" " read -r -a deployments <<< "${line}"
        kubectl scale deploy "${deployments[0]}" --replicas 1 --namespace="${namespace}"
        num_nodes=$((num_nodes+1))
    done < <(kubectl get deployments --namespace="${namespace}" | grep 'cortx-ha')

    printf "\nWait for CORTX HA to be ready"
    while true; do
        count=0
        while IFS= read -r line; do
            IFS=" " read -r -a pod_status <<< "${line}"
            IFS="/" read -r -a ready_status <<< "${pod_status[1]}"
            if [[ "${pod_status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
                if [[ "${pod_status[2]}" == "Error" || "${pod_status[2]}" == "Init:Error" ]]; then
                    printf "\n'%s' pod failed to start. Exit early.\n" "${pod_status[0]}"
                    exit 1
                fi
                break
            fi
            count=$((count+1))
        done < <(kubectl get pods --namespace="${namespace}" | grep 'cortx-ha')

        if [[ ${num_nodes} -eq ${count} ]]; then
            break
        else
            printf "."
        fi
        sleep 1s
    done
    printf "\n\n"
    printf "All CORTX HA pods have been started"
    printf "\n\n"
fi

num_motr_client=$(extractBlock 'solution.common.motr.num_client_inst')

if [[ ${num_motr_client} -gt 0 ]]; then
    printf "########################################################\n"
    printf "# Start CORTX Client                                    \n"
    printf "########################################################\n"
    num_nodes=0
    while IFS= read -r line; do
        IFS=" " read -r -a deployments <<< "${line}"
        kubectl scale deploy "${deployments[0]}" --replicas 1 --namespace="${namespace}"
        num_nodes=$((num_nodes+1))
    done < <(kubectl get deployments --namespace="${namespace}" | grep 'cortx-client-')

    printf "\nWait for CORTX Client to be ready"
    while true; do
        count=0
        while IFS= read -r line; do
            IFS=" " read -r -a pod_status <<< "${line}"
            IFS="/" read -r -a ready_status <<< "${pod_status[1]}"
            if [[ "${pod_status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
                if [[ "${pod_status[2]}" == "Error" || "${pod_status[2]}" == "Init:Error" ]]; then
                    printf "\n'%s' pod failed to start. Exit early.\n" "${pod_status[0]}"
                    exit 1
                fi
                break
            fi
            count=$((count+1))
        done < <(kubectl get pods --namespace="${namespace}" | grep 'cortx-client-')

        if [[ ${num_nodes} -eq ${count} ]]; then
            break
        else
            printf "."
        fi
        sleep 1s
    done
    printf "\n\n"
    printf "All CORTX Client pods have been started"
    printf "\n\n"
fi
