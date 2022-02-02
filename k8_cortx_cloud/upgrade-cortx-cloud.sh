#!/bin/bash

BASEPATH=$(dirname $0)
MAXNODES=$(kubectl get nodes | awk -v col=1 '{print $col}' | tail -n+2 | wc -l)
NAMESPACE="default"
TIMEDELAY="30"
FAILED='\033[0;31m'       #RED
PASSED='\033[0;32m'       #GREEN
INFO='\033[0;36m'        #CYAN
NC='\033[0m'              #NO COLOUR
REDEFPODS=false
UPGRADEPIDFILE=/var/run/upgrade.sh.pid

#check if file exits with pid in it. Throw error if PID is present
if [ -s "$UPGRADEPIDFILE" ]; then
   echo "Upgrade is already being performed on the cluster."
   exit 1
fi

# Create a file with current PID to indicate that process is running.
echo $$ > "$UPGRADEPIDFILE"

function show_usage {
    echo -e "usage: $(basename $0) [-i UPGRADE-IMAGE]"
    echo -e "Where:"
    echo -e "..."
    echo -e "-i : Upgrade With specified Cortx Image"
    exit 1
}

function print_header {
    echo -e "--------------------------------------------------------------------------"
    echo -e "$1"
    echo -e "--------------------------------------------------------------------------"
}

while [ $# -gt 0 ];  do
    case $1 in
    -i )
        shift 1
        UPGRADE_IMAGE=$1
        ;;
    * )
        echo -e "Invalid argument provided : $1"
        show_usage
        exit 1
        ;;
    esac
    shift 1
done

[ -z $UPGRADE_IMAGE ] && echo -e "ERROR: Missing Upgrade Image tag. Please Provide Image TAG for Upgrade" && show_usage

# Validate if All Pods are running
printf "${INFO}| Checking Pods Status |${NC}\n"
while IFS= read -r line; do
    IFS=" " read -r -a status <<< "$line"
    IFS="/" read -r -a ready_status <<< "${status[1]}"
    if [[ "${status[0]}" != "" ]]; then
        printf "${status[0]}..."
        if [[ "${status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            printf "${FAILED}FAILED${NC}\n"
            exit 1;
        else
            printf "${PASSED}PASSED${NC}\n"
        fi
    fi
done <<< "$(kubectl get pods --namespace=$namespace | grep 'cortx-control-\|cortx-data-\|cortx-ha-\|cortx-server-\|cortx-client-')"

# Shutdown all cortx PODs
"$BASEPATH"/shutdown-cortx-cloud.sh

# Update image in control POD
kubectl set image deployment cortx-control cortx-setup=$UPGRADE_IMAGE cortx-motr-fsm=$UPGRADE_IMAGE cortx-csm-agent=$UPGRADE_IMAGE cortx-bgscheduler=$UPGRADE_IMAGE  cortx-utils-message=$UPGRADE_IMAGE;

# Update image in HA POD
kubectl set image deployment cortx-ha  cortx-setup=$UPGRADE_IMAGE cortx-ha-fault-tolerance=$UPGRADE_IMAGE cortx-ha-health-monitor=$UPGRADE_IMAGE cortx-ha-k8s-monitor=$UPGRADE_IMAGE;

# Update image in Data PODS
while IFS= read -r line; do
    IFS=" " read -r -a deployments <<< "$line"
    data_containers="$(kubectl get deployments "${deployments[0]}" -n default -o jsonpath='{.spec.template.spec.containers[*].name}')"
    data_containers_list=($data_containers)
    for container in "${data_containers_list[@]}"
    do
        kubectl set image deployment "${deployments[0]}"  $container=$UPGRADE_IMAGE;
    done
    kubectl set image deployment "${deployments[0]}" cortx-setup=$UPGRADE_IMAGE;
done <<< "$(kubectl get deployments |grep 'cortx-data-')"

# Update image in Server PODS
while IFS= read -r line; do
    IFS=" " read -r -a deployments <<< "$line"
    server_containers="$(kubectl get deployments "${deployments[0]}" -n default -o jsonpath='{.spec.template.spec.containers[*].name}')"
    server_containers_list=($server_containers)
    for container in "${server_containers_list[@]}"
    do
        kubectl set image deployment "${deployments[0]}"  $container=$UPGRADE_IMAGE;
    done
    kubectl set image deployment "${deployments[0]}" cortx-setup=$UPGRADE_IMAGE;
done <<< "$(kubectl get deployments |grep 'cortx-server-')"

# Start all cortx PODs
"$BASEPATH"/start-cortx-cloud.sh

# Ensure PID file is removed after upgrade is performed.
rm -f $UPGRADEPIDFILE

