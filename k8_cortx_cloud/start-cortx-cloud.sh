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
deployment_type=$(parseSolution 'solution.deployment_type' | cut -f2 -d'>')
num_nodes=$(yq '.solution.storage_sets[0].nodes | length' "${solution_yaml}")

readonly namespace
readonly deployment_type
readonly num_nodes

if [[ ${deployment_type} != "data-only" ]]; then
    printf "########################################################\n"
    printf "# Start CORTX Control                                   \n"
    printf "########################################################\n"
    expected_count=1
    kubectl scale deploy cortx-control --replicas ${expected_count} --namespace="${namespace}"

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

        if [[ ${expected_count} -eq ${count} ]]; then
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
kubectl scale statefulset cortx-data --replicas "${num_nodes}" --namespace="${namespace}"

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

    server_instances_per_node="$(parseSolution 'solution.common.s3.instances_per_node' | cut -f2 -d'>')"
    total_server_pods=$(( num_nodes * server_instances_per_node ))

    readonly server_instances_per_node
    readonly total_server_pods

    readonly server_selector="app.kubernetes.io/component=server"
    while IFS= read -r line; do
        IFS=" " read -r -a deployments <<< "${line}"
        kubectl scale statefulset "${deployments[0]}" --replicas ${total_server_pods} --namespace="${namespace}"
    done < <(kubectl get statefulsets --namespace="${namespace}" --selector=${server_selector} --no-headers)

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
        done < <(kubectl get pods --namespace="${namespace}" --selector=${server_selector} --no-headers)

        if [[ ${total_server_pods} -eq ${count} ]]; then
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
    expected_count=1
    kubectl scale deploy cortx-ha --replicas ${expected_count} --namespace="${namespace}"

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

        if [[ ${expected_count} -eq ${count} ]]; then
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

num_motr_client=$(parseSolution 'solution.common.motr.num_client_inst' | cut -f2 -d'>')

if [[ ${num_motr_client} -gt 0 ]]; then
    printf "########################################################\n"
    printf "# Start CORTX Client                                    \n"
    printf "########################################################\n"
    expected_count=0
    while IFS= read -r line; do
        IFS=" " read -r -a deployments <<< "${line}"
        kubectl scale deploy "${deployments[0]}" --replicas 1 --namespace="${namespace}"
        expected_count=$((expected_count+1))
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

        if [[ ${expected_count} -eq ${count} ]]; then
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
