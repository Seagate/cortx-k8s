#!/bin/bash

storage_class=${1:-'local-path'}
printf "Default storage class: $storage_class\n"

# Default list of worker nodes to be used to deploy OpenLDAP
openldap_worker_node_list[0]='node-1'
openldap_worker_node_list[1]='node-2'
openldap_worker_node_list[2]='node-3'
num_worker_nodes=0
while IFS= read -r line; do
    if [[ $line != *"master"* && $line != *"AGE"* ]]
    then
        IFS=" " read -r -a node_name <<< "$line"
        openldap_worker_node_list[num_worker_nodes]=$node_name
        num_worker_nodes=$((num_worker_nodes+1))
    fi
done <<< "$(kubectl get nodes)"
printf "Number of worker nodes detected: $num_worker_nodes\n"

printf "###############################\n"
printf "# Deploy Consul               #\n"
printf "###############################\n"

# Add the HashiCorp Helm Repository:
helm repo add hashicorp https://helm.releases.hashicorp.com
if [[ $storage_class == "local-path" ]]
then
    printf "Install Rancher Local Path Provisioner"
    # Install Rancher provisioner
    # kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
    kubectl create -f cortx-cloud-3rd-party-pkg/local-path-storage.yaml
fi
# # Set default StorageClass
# kubectl patch storageclass $STORAGE_CLASS \
#     -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

helm install "consul" hashicorp/consul \
    --set global.name="consul" \
    --set server.storageClass=$storage_class \
    --set server.replicas=$num_worker_nodes

printf "###############################\n"
printf "# Deploy openLDAP             #\n"
printf "###############################\n"
# Set max number of OpenLDAP replicas to be 3
num_replicas=3
if [[ "$num_worker_nodes" -le 3 ]]; then
    num_replicas=$num_worker_nodes
fi

helm install "openldap" cortx-cloud-3rd-party-pkg/openldap \
    --set storageclass="openldap-storage" \
    --set storagesize="1Gi" \
    --set service.name="openldap-svc" \
    --set service.ip="10.105.117.12" \
    --set statefulset.name="openldap" \
    --set statefulset.replicas=$num_replicas \
    --set pv1.name="openldap-pv-0" \
    --set pv1.node=${openldap_worker_node_list[0]} \
    --set pv1.localpath="/var/lib/ldap" \
    --set pv2.name="openldap-pv-1" \
    --set pv2.node=${openldap_worker_node_list[1]} \
    --set pv2.localpath="/var/lib/ldap" \
    --set pv3.name="openldap-pv-2" \
    --set pv3.node=${openldap_worker_node_list[2]} \
    --set pv3.localpath="/var/lib/ldap" \
    --set namespace="default"

# Wait for all openLDAP pods to be ready and build up openLDAP endpoint array
# which consists of "<openLDAP-pod-name> <openLDAP-endpoint-ip-addr>""
printf "\nWait for openLDAP PODs to be ready"
while true; do
    openldap_ep_array=[]
    count=0

    while IFS= read -r line; do
        IFS=" " read -r -a my_array <<< "$line"
        openldap_ep_array[count]="${my_array[1]} ${my_array[6]}"
        if [[ ${my_array[6]} == "<none>" ]]; then
            break
        fi
        count=$((count+1))
    done <<< "$(kubectl get pods -A -o wide | grep 'openldap-')"

    if [[ $count -eq $num_replicas ]]
    then
        break
    else
        printf "."
    fi
    sleep 1s
done
printf "\n\n"

num_openldap_nodes=${#openldap_ep_array[@]}
replicate_ldif_file="opt/seagate/cortx/s3/install/ldap/replicate.ldif"
if [[ $num_openldap_nodes -eq 2 ]]
then    
    replicate_ldif_file="opt/seagate/cortx/s3/install/ldap/replicate_2nodes.ldif"
fi

# Update openLDAP config
for openldap_ep in "${openldap_ep_array[@]}"
do
    IFS=" " read -r -a my_array <<< "$openldap_ep"

    SHA=$(kubectl exec -i ${my_array[0]} -- slappasswd -s ldapadmin)
    ESC_SHA=$(kubectl exec -i ${my_array[0]} -- echo $SHA | sed 's/[/]/\\\//g')
    EXPR='s/userPassword: *.*/userPassword: '$ESC_SHA'/g'
    kubectl exec -i ${my_array[0]} --namespace="default" -- \
        sed -i "$EXPR" opt/seagate/cortx/s3/install/ldap/iam-admin.ldif

    kubectl exec -i ${my_array[0]} --namespace="default" -- \
        ldapadd -x -D "cn=admin,dc=seagate,dc=com" \
        -w ldapadmin \
        -f opt/seagate/cortx/s3/install/ldap/ldap-init.ldif \
        -H ldap://${my_array[1]}

    kubectl exec -i ${my_array[0]} --namespace="default" -- \
        ldapadd -x -D "cn=admin,dc=seagate,dc=com" \
        -w ldapadmin \
        -f opt/seagate/cortx/s3/install/ldap/iam-admin.ldif \
        -H ldap://${my_array[1]}

    kubectl exec -i ${my_array[0]} --namespace="default" -- \
        ldapmodify -x -a -D cn=admin,dc=seagate,dc=com \
        -w ldapadmin \
        -f opt/seagate/cortx/s3/install/ldap/ppolicy-default.ldif \
        -H ldap://${my_array[1]}
        
    kubectl exec -i ${my_array[0]} --namespace="default" -- \
        ldapadd -Y EXTERNAL -H ldapi:/// \
        -f opt/seagate/cortx/s3/install/ldap/syncprov_mod.ldif
        
    kubectl exec -i ${my_array[0]} --namespace="default" -- \
        ldapadd -Y EXTERNAL -H ldapi:/// \
        -f opt/seagate/cortx/s3/install/ldap/syncprov.ldif
        
    uri_count=1
    for openldap_ep in "${openldap_ep_array[@]}"
    do
        IFS=" " read -r -a temp_array <<< "$openldap_ep"
        output=$(kubectl exec -i ${my_array[0]} -- \
                    sed "s/<sample_provider_URI_$uri_count>/${temp_array[1]}/g" \
                    $replicate_ldif_file)
        kubectl exec -i ${my_array[0]} --namespace="default" -- bash -c "echo '$output' > $replicate_ldif_file"
        uri_count=$((uri_count+1))
    done
done

printf "###############################\n"
printf "# Deploy Zookeeper            #\n"
printf "###############################\n"
# Add Zookeeper and Kafka Repository
helm repo add bitnami https://charts.bitnami.com/bitnami

helm install zookeeper bitnami/zookeeper \
    --set replicaCount=$num_worker_nodes \
    --set auth.enabled=false \
    --set allowAnonymousLogin=true \
    --set global.storageClass=$storage_class

printf "###############################\n"
printf "# Deploy Kafka                #\n"
printf "###############################\n"
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