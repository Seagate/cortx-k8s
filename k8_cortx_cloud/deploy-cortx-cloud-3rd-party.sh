#!/bin/bash

storage_class='local-path'
printf "Default storage class: $storage_class\n"

# Delete old "node-list-info.txt" file
find $(pwd)/cortx-cloud-3rd-party-pkg/openldap -name "node-list-info*" -delete

max_openldap_inst=3 # Default max openldap instances
num_openldap_replicas=0 # Default the number of actual openldap instances
num_worker_nodes=0
while IFS= read -r line; do
    if [[ $line != *"master"* && $line != *"AGE"* ]]
    then
        IFS=" " read -r -a node_name <<< "$line"
        node_list_str="$num_worker_nodes $node_name"
        num_worker_nodes=$((num_worker_nodes+1))

        if [[ "$num_worker_nodes" -le "$max_openldap_inst" ]]; then
            num_openldap_replicas=$num_worker_nodes
            node_list_info_path=$(pwd)/cortx-cloud-3rd-party-pkg/openldap/node-list-info.txt
            if [[ -s $node_list_info_path ]]; then
                printf "\n" >> $node_list_info_path
            fi
            printf "$node_list_str" >> $node_list_info_path
        fi
    fi
done <<< "$(kubectl get nodes)"
printf "Number of worker nodes detected: $num_worker_nodes\n"

printf "######################################################\n"
printf "# Deploy Consul                                       \n"
printf "######################################################\n"

# Add the HashiCorp Helm Repository:
helm repo add hashicorp https://helm.releases.hashicorp.com
if [[ $storage_class == "local-path" ]]
then
    printf "Install Rancher Local Path Provisioner"
    # Install Rancher provisioner
    # kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
    kubectl create -f cortx-cloud-3rd-party-pkg/local-path-storage.yaml
fi

helm install "consul" hashicorp/consul \
    --set global.name="consul" \
    --set server.storageClass=$storage_class \
    --set server.replicas=$num_worker_nodes

printf "######################################################\n"
printf "# Deploy openLDAP                                     \n"
printf "######################################################\n"
helm install "openldap" cortx-cloud-3rd-party-pkg/openldap \
    --set openldap.servicename="openldap-svc" \
    --set openldap.storageclass="openldap-local-storage" \
    --set openldap.storagesize="5Gi" \
    --set openldap.nodelistinfo="node-list-info.txt" \
    --set openldap.numreplicas=$num_openldap_replicas

# Wait for all openLDAP pods to be ready
printf "\nWait for openLDAP PODs to be ready"
while true; do
    count=0
    while IFS= read -r line; do
        IFS=" " read -r -a pod_status <<< "$line"
        IFS="/" read -r -a ready_status <<< "${pod_status[2]}"
        if [[ "${pod_status[3]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            break
        fi
        count=$((count+1))
    done <<< "$(kubectl get pods -A | grep 'openldap')"

    if [[ $count -eq $num_openldap_replicas ]]; then
        break
    else
        printf "."
    fi
    sleep 1s
done
printf "\n\n"

printf "===========================================================\n"
printf "Setup OpenLDAP replication                                 \n"
printf "===========================================================\n"
# Run replication script
./cortx-cloud-3rd-party-pkg/openldap-replication/replication.sh

printf "######################################################\n"
printf "# Deploy Zookeeper                                    \n"
printf "######################################################\n"
# Add Zookeeper and Kafka Repository
helm repo add bitnami https://charts.bitnami.com/bitnami

helm install zookeeper bitnami/zookeeper \
    --set replicaCount=$num_worker_nodes \
    --set auth.enabled=false \
    --set allowAnonymousLogin=true \
    --set global.storageClass=$storage_class

printf "######################################################\n"
printf "# Deploy Kafka                                        \n"
printf "######################################################\n"
helm install kafka bitnami/kafka \
    --set zookeeper.enabled=false \
    --set replicaCount=$num_worker_nodes \
    --set externalZookeeper.servers=zookeeper.default.svc.cluster.local \
    --set global.storageClass=$storage_class \
    --set defaultReplicationFactor=$num_worker_nodes \
    --set offsetTopicReplicationFactor=$num_worker_nodes \
    --set transactionStateLogReplicationFactor=$num_worker_nodes \
    --set auth.enabled=false \
    --set allowAnonymousLogin=true \
    --set deleteTopicEnable=true \
    --set transactionStateLogMinIsr=2
    
printf "\nWait for CORTX 3rd party to be ready"
while true; do
    count=0
    while IFS= read -r line; do
        IFS=" " read -r -a pod_status <<< "$line"        
        IFS="/" read -r -a ready_status <<< "${pod_status[1]}"
        if [[ "${pod_status[2]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            count=$((count+1))
            break
        fi
    done <<< "$(kubectl get pods --namespace=default | grep 'consul\|kafka\|openldap\|zookeeper')"

    if [[ $count -eq 0 ]]; then
        break
    else
        printf "."
    fi    
    sleep 1s
done
printf "\n"

#################################################################
# Delete files that contain node info
#################################################################
find $(pwd)/cortx-cloud-3rd-party-pkg/openldap -name "node-list-info*" -delete