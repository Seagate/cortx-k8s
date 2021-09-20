#!/bin/bash
STORAGE_CLASS=${1:-'local-path'}
NUM_WORKER_NODES=${2:-2}
printf "STORAGE_CLASS = $STORAGE_CLASS\n"
printf "NUM_WORKER_NODES = $NUM_WORKER_NODES\n"

namespace="default"
kubectl create namespace $namespace

##########################################################
# Deploy CORTX 3rd party
##########################################################

printf "###############################\n"
printf "# Deploy Consul               #\n"
printf "###############################\n"

# Add the HashiCorp Helm Repository:
helm repo add hashicorp https://helm.releases.hashicorp.com
if [[ $STORAGE_CLASS == "local-path" ]]
then
    printf "Install Rancher Local Path Provisioner"
    # Install Rancher provisioner
    kubectl create -f cortx-cloud-3rd-party-pkg/local-path-storage.yaml
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
    --set allowAnonymousLogin=true \
    --set global.storageClass=$STORAGE_CLASS

printf "###############################\n"
printf "# Deploy Kafka                #\n"
printf "###############################\n"
helm install kafka bitnami/kafka \
    --set zookeeper.enabled=false \
    --set replicaCount=$NUM_WORKER_NODES \
    --set externalZookeeper.servers=zookeeper.default.svc.cluster.local \
    --set global.storageClass=$STORAGE_CLASS

##########################################################
# Deploy CORTX cloud
##########################################################
# GlusterFS
gluster_vol="myvol"
gluster_folder="/etc/gluster/test_folder"
pod_ctr_mount_path="/mnt/fs-local-volume/etc/gluster/test_folder/"
gluster_pv_name="gluster-default-volume"
gluster_pvc_name="gluster-claim"

printf "######################################################\n"
printf "# Deploy CORTX Local Block Storage                    \n"
printf "######################################################\n"
while IFS= read -r line; do
    if [[ $line != *"master"* && $line != *"AGE"* ]]
    then
        IFS=" " read -r -a node_name <<< "$line"
        file_path="cortx-cloud-helm-pkg/cortx-provisioner/mnt-blk-info-$node_name.txt"
        count=001
        while IFS=' ' read -r mount_path || [[ -n "$mount_path" ]]; do
            mount_base_dir=$( echo "$mount_path" | sed -e 's/\/.*\///g')
            count_str=$(printf "%03d" $count)
            count=$((count+1))
            helm_name1="cortx-data-blk-data$count_str-$node_name"
            storage_class_name1="local-blk-storage$count_str-$node_name"
            pvc1_name="cortx-data-$mount_base_dir-pvc-$node_name"
            pv1_name="cortx-data-$mount_base_dir-pv-$node_name"
            storage_size="5Gi"
            helm install $helm_name1 cortx-cloud-helm-pkg/cortx-data-blk-data \
                --set cortxblkdata.nodename=$node_name \
                --set cortxblkdata.storage.localpath=$mount_path \
                --set cortxblkdata.storage.size=$storage_size \
                --set cortxblkdata.storageclass=$storage_class_name1 \
                --set cortxblkdata.storage.pvc.name=$pvc1_name \
                --set cortxblkdata.storage.pv.name=$pv1_name \
                --set cortxblkdata.storage.volumemode="Block" \
                --set namespace=$namespace
        done < "$file_path"
    fi
done <<< "$(kubectl get nodes)"

printf "########################################################\n"
printf "# Deploy CORTX GlusterFS                                \n"
printf "########################################################\n"
# Deploy GlusterFS
node_name="node-1"
helm install "cortx-gluster-$node_name" cortx-cloud-helm-pkg/cortx-gluster \
    --set cortxgluster.name="gluster-$node_name" \
    --set cortxgluster.nodename=$node_name \
    --set cortxgluster.service.name="cortx-gluster-svc-$node_name" \
    --set cortxgluster.storagesize="1Gi" \
    --set cortxgluster.storageclass="cortx-gluster-storage" \
    --set cortxgluster.pv.path=$gluster_vol \
    --set cortxgluster.pv.name=$gluster_pv_name \
    --set cortxgluster.pvc.name=$gluster_pvc_name \
    --set cortxgluster.hostpath.etc="/mnt/fs-local-volume/etc/gluster" \
    --set cortxgluster.hostpath.logs="/mnt/fs-local-volume/var/log/gluster" \
    --set cortxgluster.hostpath.config="/mnt/fs-local-volume/var/lib/glusterd" \
    --set namespace=$namespace
num_nodes=1

printf "Wait for GlusterFS endpoint to be ready"
while true; do
    count=0
    while IFS= read -r line; do
        IFS=" " read -r -a service_status <<< "$line"
        IFS="/" read -r -a ready_status <<< "${pod_status[1]}"
        if [[ "${service_status[2]}" == "<none>" ]]; then
            break
        fi
        count=$((count+1))
    done <<< "$(kubectl get endpoints -A | grep 'gluster-')"

    if [[ $num_nodes -eq $count ]]; then
        break
    else
        printf "."
    fi
    sleep 1s
done
printf "\n"

printf "Wait for GlusterFS pod to be ready"
while true; do
    count=0
    while IFS= read -r line; do
        IFS=" " read -r -a pod_status <<< "$line"
        IFS="/" read -r -a ready_status <<< "${pod_status[2]}"
        if [[ "${pod_status[3]}" != "Running" || "${ready_status[0]}" != "${ready_status[1]}" ]]; then
            break
        fi
        count=$((count+1))
    done <<< "$(kubectl get pods -A | grep 'gluster-')"

    if [[ $num_nodes -eq $count ]]; then
        break
    else
        printf "."
    fi
    sleep 1s
done
printf "\n"

# Build Gluster endpoint array
gluster_ep_array=[]
count=0
while IFS= read -r line; do
    IFS=" " read -r -a my_array <<< "$line"
    gluster_ep_array[count]=$line
    count=$((count+1))
done <<< "$(kubectl get pods -A -o wide | grep 'gluster-')"

gluster_and_host_name_arr=[]
# Loop through all gluster endpoint array and find endoint IP address
# and gluster node name
count=0
first_gluster_node_name=''
first_gluster_ip=''
replica_list=''
for gluster_ep in "${gluster_ep_array[@]}"
do
    IFS=" " read -r -a my_array <<< "$gluster_ep"
    gluster_ep_ip=${my_array[6]}
    gluster_node_name=${my_array[1]}
    gluster_and_host_name_arr[count]="${gluster_ep_ip} ${gluster_node_name}"
    if [[ "$count" == 0 ]]; then
        first_gluster_node_name=$gluster_node_name
        first_gluster_ip=$gluster_ep_ip
    else
        kubectl exec -i $first_gluster_node_name --namespace=$namespace -- gluster peer probe $gluster_ep_ip
    fi
    replica_list+="$gluster_ep_ip:$gluster_folder "
    count=$((count+1))
done

len_array=${#gluster_ep_array[@]}
if [[ ${#gluster_ep_array[@]} -ge 2 ]]
then
    # Create replica gluster volumes
    kubectl exec -i $first_gluster_node_name --namespace=$namespace -- gluster volume create $gluster_vol replica $len_array $replica_list force
else
    # Add gluster volume
    kubectl exec -i $first_gluster_node_name --namespace=$namespace -- gluster volume create $gluster_vol $first_gluster_ip:$gluster_folder force
fi

# Start gluster volume
echo y | kubectl exec -i $first_gluster_node_name --namespace=$namespace --namespace=$namespace -- gluster volume start $gluster_vol

printf "########################################################\n"
printf "# Deploy CORTX provisioner                              \n"
printf "########################################################\n"
num_nodes=0
while IFS= read -r line; do
    if [[ $line != *"master"* && $line != *"AGE"* ]]; then
        IFS=" " read -r -a node_name <<< "$line"
        num_nodes=$((num_nodes+1))
        helm install "cortx-provisioner-$node_name" cortx-cloud-helm-pkg/cortx-provisioner \
            --set cortxprov.name="cortx-provisioner-pod-$node_name" \
            --set cortxprov.nodename=$node_name \
            --set cortxprov.mountblkinfo="mnt-blk-info-$node_name.txt" \
            --set cortxprov.service.name="cortx-data-clusterip-svc-$node_name" \
            --set cortxgluster.pv.name=$gluster_pv_name \
            --set cortxgluster.pv.mountpath=$pod_ctr_mount_path \
            --set cortxgluster.pvc.name=$gluster_pvc_name \
            --set cortxprov.localpathpvc.name="cortx-data-fs-local-pvc-$node_name" \
            --set cortxprov.localpathpvc.mountpath="/data" \
            --set cortxprov.localpathpvc.requeststoragesize="1Gi" \
            --set namespace=$namespace
    fi
done <<< "$(kubectl get nodes)"

printf "Wait for CORTX Provisioner to complete"
while true; do
    count=0
    while IFS= read -r line; do
        IFS=" " read -r -a pod_status <<< "$line"
        if [[ "${pod_status[2]}" != "Completed" ]]; then
            break
        fi
        count=$((count+1))
    done <<< "$(kubectl get pods --namespace=$namespace | grep 'cortx-provisioner-pod-')"

    if [[ $num_nodes -eq $count ]]; then
        break
    else
        printf "."
    fi
    sleep 1s
done
printf "\n"

# Delete CORTX Provisioner Services
while IFS= read -r line; do
    if [[ $line != *"master"* && $line != *"AGE"* ]]; then
        IFS=" " read -r -a node_name <<< "$line"
        num_nodes=$((num_nodes+1))
        kubectl delete service "cortx-data-clusterip-svc-$node_name" --namespace=$namespace
    fi
done <<< "$(kubectl get nodes)"

printf "########################################################\n"
printf "# Deploy CORTX data                                     \n"
printf "########################################################\n"
num_nodes=0
while IFS= read -r line; do
    if [[ $line != *"master"* && $line != *"AGE"* ]]; then
        IFS=" " read -r -a node_name <<< "$line"
        num_nodes=$((num_nodes+1))
        helm install "cortx-data-$node_name" cortx-cloud-helm-pkg/cortx-data \
            --set cortxdata.name="cortx-data-pod-$node_name" \
            --set cortxdata.nodename=$node_name \
            --set cortxdata.mountblkinfo="mnt-blk-info-$node_name.txt" \
            --set cortxdata.service.name="cortx-data-clusterip-svc-$node_name" \
            --set cortxgluster.pv.name=$gluster_pv_name \
            --set cortxgluster.pv.mountpath=$pod_ctr_mount_path \
            --set cortxgluster.pvc.name=$gluster_pvc_name \
            --set cortxdata.cfgmap.mountpath="/etc/cortx-config" \
            --set cortxdata.cfgmap.ctr1.name="cortx-data-cfgmap001-$node_name" \
            --set cortxdata.cfgmap.ctr1.volmountname="config001-$node_name" \
            --set cortxdata.cfgmap.ctr2.name="cortx-data-cfgmap002-$node_name" \
            --set cortxdata.cfgmap.ctr2.volmountname="config002-$node_name" \
            --set cortxdata.cfgmap.ctr3.name="cortx-data-cfgmap003-$node_name" \
            --set cortxdata.cfgmap.ctr3.volmountname="config003-$node_name" \
            --set cortxdata.cfgmap.ctr4.name="cortx-data-cfgmap004-$node_name" \
            --set cortxdata.cfgmap.ctr4.volmountname="config004-$node_name" \
            --set cortxdata.cfgmap.ctr5.name="cortx-data-cfgmap005-$node_name" \
            --set cortxdata.cfgmap.ctr5.volmountname="config005-$node_name" \
            --set cortxdata.cfgmap.ctr6.name="cortx-data-cfgmap006-$node_name" \
            --set cortxdata.cfgmap.ctr6.volmountname="config006-$node_name" \
            --set cortxdata.cfgmap.ctr7.name="cortx-data-cfgmap007-$node_name" \
            --set cortxdata.cfgmap.ctr7.volmountname="config007-$node_name" \
            --set cortxdata.cfgmap.ctr8.name="cortx-data-cfgmap008-$node_name" \
            --set cortxdata.cfgmap.ctr8.volmountname="config008-$node_name" \
            --set cortxdata.cfgmap.ctr9.name="cortx-data-cfgmap009-$node_name" \
            --set cortxdata.cfgmap.ctr9.volmountname="config009-$node_name" \
            --set cortxdata.localpathpvc.name="cortx-data-fs-local-pvc-$node_name" \
            --set cortxdata.localpathpvc.mountpath="/data" \
            --set namespace=$namespace
    fi
done <<< "$(kubectl get nodes)"

printf "Wait for CORTX data to complete"
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
printf "\n"
