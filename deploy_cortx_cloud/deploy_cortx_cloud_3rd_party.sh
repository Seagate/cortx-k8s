#!/bin/bash
STORAGE_CLASS=${1:-'local-path'}
NUM_WORKER_NODES=${2:-2}
printf "STORAGE_CLASS = $STORAGE_CLASS\n"
printf "NUM_WORKER_NODES = $NUM_WORKER_NODES\n"


printf "###############################\n"
printf "# Deploy Consul               #\n"
printf "###############################\n"

# Add the HashiCorp Helm Repository:
helm repo add hashicorp https://helm.releases.hashicorp.com
if [[ $STORAGE_CLASS == "local-path" ]]
then
    printf "Install Rancher Local Path Provisioner"
    # Install Rancher provisioner
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
fi
# Set default StorageClass
kubectl patch storageclass $STORAGE_CLASS \
    -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

helm install "consul" hashicorp/consul \
    --set global.name="consul" \
    --set server.storageClass=$STORAGE_CLASS \
    --set server.replicas=$NUM_WORKER_NODES

printf "###############################\n"
printf "# Deploy openLDAP             #\n"
printf "###############################\n"
# kubectl create secret generic openldap \
#     --from-literal=adminpassword=adminpassword \
#     --from-literal=users=user01,user02 \
#     --from-literal=passwords=password01,password02
# kubectl create -f open-ldap-svc.yaml
# kubectl create -f open-ldap-deployment.yaml
# kubectl scale -f open-ldap-deployment.yaml --replicas=$NUM_WORKER_NODES

# Set max number of OpenLDAP replicas to be 3
num_replicas=3
if [[ "$NUM_WORKER_NODES" -le 3 ]]; then
    num_replicas=$NUM_WORKER_NODES
fi

helm install "openldap" cortx-cloud-3rd-party-pkg/openldap \
    --set storageclass="openldap-storage" \
    --set storagesize="1Gi" \
    --set service.name="openldap-svc" \
    --set service.ip="10.105.117.12" \
    --set statefulset.name="openldap" \
    --set statefulset.replicas=$num_replicas \
    --set pv1.name="openldap-pv-0" \
    --set pv1.node="node-1" \
    --set pv1.localpath="/var/lib/ldap" \
    --set pv2.name="openldap-pv-1" \
    --set pv2.node="node-2" \
    --set pv2.localpath="/var/lib/ldap" \
    --set pv3.name="openldap-pv-2" \
    --set pv3.node="node-3" \
    --set pv3.localpath="/var/lib/ldap"

# Check if all OpenLDAP are up and running
node_count=0
while IFS= read -r line; do
    if [[ $line != *"master"* && $line != *"AGE"* ]]
    then
        if [[ $node_count -ge 3 ]]
        then
            break
        fi
        node_count=$((node_count+1))
    fi
done <<< "$(kubectl get nodes)"

# Wait for all openLDAP pods to be ready and build up openLDAP endpoint array
# which consists of "<openLDAP-pod-name> <openLDAP-endpoint-ip-addr>""
printf "Wait for openLDAP PODs to be ready"
while true; do
    openldap_ep_array=[]
    count=0

    while IFS= read -r line; do
        IFS=" " read -r -a my_array <<< "$line"
        openldap_ep_array[count]="${my_array[1]} ${my_array[6]}"
        count=$((count+1))
    done <<< "$(kubectl get pods -A -o wide | grep 'openldap-')"

    if [[ $count -eq $node_count && ${my_array[6]} != "<none>" ]]
    then
        break
    else
        printf "."
    fi
    sleep 1s
done

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
    kubectl exec -i ${my_array[0]} -- \
        sed -i "$EXPR" opt/seagate/cortx/s3/install/ldap/iam-admin.ldif

    kubectl exec -i ${my_array[0]} -- \
        ldapadd -x -D "cn=admin,dc=seagate,dc=com" \
        -w ldapadmin \
        -f opt/seagate/cortx/s3/install/ldap/ldap-init.ldif \
        -H ldap://${my_array[1]}

    kubectl exec -i ${my_array[0]} -- \
        ldapadd -x -D "cn=admin,dc=seagate,dc=com" \
        -w ldapadmin \
        -f opt/seagate/cortx/s3/install/ldap/iam-admin.ldif \
        -H ldap://${my_array[1]}

    kubectl exec -i ${my_array[0]} -- \
        ldapmodify -x -a -D cn=admin,dc=seagate,dc=com \
        -w ldapadmin \
        -f opt/seagate/cortx/s3/install/ldap/ppolicy-default.ldif \
        -H ldap://${my_array[1]}
        
    kubectl exec -i ${my_array[0]} -- \
        ldapadd -Y EXTERNAL -H ldapi:/// \
        -f opt/seagate/cortx/s3/install/ldap/syncprov_mod.ldif
        
    kubectl exec -i ${my_array[0]} -- \
        ldapadd -Y EXTERNAL -H ldapi:/// \
        -f opt/seagate/cortx/s3/install/ldap/syncprov.ldif
        
    uri_count=1
    for openldap_ep in "${openldap_ep_array[@]}"
    do
        IFS=" " read -r -a temp_array <<< "$openldap_ep"
        output=$(kubectl exec -i ${my_array[0]} -- \
                    sed "s/<sample_provider_URI_$uri_count>/${temp_array[1]}/g" \
                    $replicate_ldif_file)
        kubectl exec -i ${my_array[0]} -- bash -c "echo '$output' > $replicate_ldif_file"
        uri_count=$((uri_count+1))
    done
done

printf "###############################\n"
printf "# Deploy Zookeeper            #\n"
printf "###############################\n"
# Add Zookeeper and Kafka Repository
helm repo add bitnami https://charts.bitnami.com/bitnami

helm install zookeeper bitnami/zookeeper \
    --set replicaCount=$NUM_WORKER_NODES \
    --set auth.enabled=false \
    --set allowAnonymousLogin=true

printf "###############################\n"
printf "# Deploy Kafka                #\n"
printf "###############################\n"
helm install kafka bitnami/kafka \
    --set zookeeper.enabled=false \
    --set replicaCount=$NUM_WORKER_NODES \
    --set externalZookeeper.servers=zookeeper.default.svc.cluster.local