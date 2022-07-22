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
    expected_count=$(helm get values cortx -n "${namespace}" | yq .control.replicaCount)
    kubectl scale deploy cortx-control --replicas "${expected_count}" --namespace="${namespace}"

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
readonly data_selector="app.kubernetes.io/component=data,app.kubernetes.io/instance=cortx"
num_data_sts=0
for statefulset in $(kubectl get statefulset --selector "${data_selector}" --no-headers --namespace="${namespace}" --output custom-columns=NAME:metadata.name); do
    kubectl scale statefulset "${statefulset}" --replicas "${num_nodes}" --namespace="${namespace}"
    ((num_data_sts+=1))
done

printf "\nWait for CORTX Data to be ready"
expected_count=$((num_nodes * num_data_sts))
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

    if [[ ${expected_count} -eq ${count} ]]; then
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

    readonly server_selector="app.kubernetes.io/component=server,app.kubernetes.io/instance=cortx"
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

if kubectl get statefulset cortx-client --namespace="${namespace}" &> /dev/null; then
    printf "########################################################\n"
    printf "# Start CORTX Client                                    \n"
    printf "########################################################\n"

    replica_count=${num_nodes}
    kubectl scale statefulset cortx-client --replicas "${replica_count}" --namespace="${namespace}"

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

        if [[ ${replica_count} -eq ${count} ]]; then
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
