#!/bin/bash

PVC_CONSUL_FILTER="data-default-consul"
PVC_KAFKA_FILTER="kafka"
PVC_ZOOKEEPER_FILTER="zookeeper"
PV_FILTER="pvc"
OPENLDAP_PVC="openldap-data"

printf "###################################\n"
printf "# Delete Kafka                    #\n"
printf "###################################\n"
helm uninstall kafka

printf "###################################\n"
printf "# Delete Zookeeper                #\n"
printf "###################################\n"
helm uninstall zookeeper

printf "########################################################\n"
printf "# Delete openLDAP                                      #\n"
printf "########################################################\n"
openldap_array=[]
count=0
while IFS= read -r line; do
    IFS=" " read -r -a my_array <<< "$line"
    openldap_array[count]="${my_array[1]}"
    count=$((count+1))
done <<< "$(kubectl get pods -A | grep 'openldap-')"

for openldap_pod_name in "${openldap_array[@]}"
do
    kubectl exec -ti $openldap_pod_name --namespace="default" -- bash -c \
        'rm -rf /etc/3rd-party/* /var/data/3rd-party/* /var/log/3rd-party/*'
done

helm uninstall "openldap"

printf "###################################\n"
printf "# Delete Consul                   #\n"
printf "###################################\n"
helm delete consul
# kubectl delete -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl delete -f cortx-cloud-3rd-party-pkg/local-path-storage.yaml

printf "###################################\n"
printf "# Delete Persistent Volume Claims #\n"
printf "###################################\n"
VOLUME_CLAIMS=$(kubectl get pvc | grep -E "$PVC_CONSUL_FILTER|$PVC_KAFKA_FILTER|$PVC_ZOOKEEPER_FILTER|$OPENLDAP_PVC|cortx" | cut -f1 -d " ")
echo $VOLUME_CLAIMS
for VOLUME_CLAIM in $VOLUME_CLAIMS
do
    printf "Removing $VOLUME_CLAIM\n"
    kubectl delete pvc $VOLUME_CLAIM
done

printf "###################################\n"
printf "# Delete Persistent Volumes       #\n"
printf "###################################\n"
PERSISTENT_VOLUMES=$(kubectl get pv | grep -E "$PVC_CONSUL_FILTER|$PVC_KAFKA_FILTER|$PVC_ZOOKEEPER_FILTER|cortx" | cut -f1 -d " ")
echo $PERSISTENT_VOLUMES
for PERSISTENT_VOLUME in $PERSISTENT_VOLUMES
do
    printf "Removing $PERSISTENT_VOLUME\n"
    kubectl delete pv $PERSISTENT_VOLUME
done
