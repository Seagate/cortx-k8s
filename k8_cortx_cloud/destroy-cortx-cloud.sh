#!/bin/bash

solution_yaml=${1:-'solution.yaml'}
force_delete=${2:-''}

if [[ "$solution_yaml" == "--force" || "$solution_yaml" == "-f" ]]; then
    temp=$force_delete
    force_delete=$solution_yaml
    solution_yaml=$temp
    if [[ "$solution_yaml" == "" ]]; then
        solution_yaml="solution.yaml"
    fi
fi

# Check if the file exists
if [ ! -f $solution_yaml ]
then
    echo "ERROR: $solution_yaml does not exist"
    exit 1
fi

pvc_consul_filter="data-default-consul"
pvc_kafka_filter="kafka"
pvc_zookeeper_filter="zookeeper"
pv_filter="pvc"
openldap_pvc="openldap-data"

function parseSolution()
{
    echo "$(./parse_scripts/parse_yaml.sh $solution_yaml $1)"
}

function extractBlock()
{
    echo "$(./parse_scripts/yaml_extract_block.sh $solution_yaml $1)"
}

namespace=$(parseSolution 'solution.namespace')
namespace=$(echo $namespace | cut -f2 -d'>')
parsed_node_output=$(parseSolution 'solution.nodes.node*.name')

# Split parsed output into an array of vars and vals
IFS=';' read -r -a parsed_var_val_array <<< "$parsed_node_output"

find $(pwd)/cortx-cloud-helm-pkg/cortx-data-provisioner -name "mnt-blk-*" -delete
find $(pwd)/cortx-cloud-helm-pkg/cortx-data -name "mnt-blk-*" -delete

node_name_list=[] # short version
node_selector_list=[] # long version
count=0
# Loop the var val tuple array
for var_val_element in "${parsed_var_val_array[@]}"
do
    node_name=$(echo $var_val_element | cut -f2 -d'>')
    node_selector_list[count]=$node_name
    shorter_node_name=$(echo $node_name | cut -f1 -d'.')
    node_name_list[count]=$shorter_node_name
    count=$((count+1))
    file_name="mnt-blk-info-$shorter_node_name.txt"
    data_prov_file_path=$(pwd)/cortx-cloud-helm-pkg/cortx-data-provisioner/$file_name
    data_file_path=$(pwd)/cortx-cloud-helm-pkg/cortx-data/$file_name

    # Get the node var from the tuple
    node=$(echo $var_val_element | cut -f3 -d'.')

    filter="solution.storage.cvg*.devices*.device"
    parsed_dev_output=$(parseSolution $filter)
    IFS=';' read -r -a parsed_dev_array <<< "$parsed_dev_output"
    for dev in "${parsed_dev_array[@]}"
    do
        device=$(echo $dev | cut -f2 -d'>')
        if [[ -s $data_prov_file_path ]]; then
            printf "\n" >> $data_prov_file_path
        fi
        if [[ -s $data_file_path ]]; then
            printf "\n" >> $data_file_path
        fi
        printf $device >> $data_prov_file_path
        printf $device >> $data_file_path
    done
done

count=0
namespace_list=[]
namespace_index=0
while IFS= read -r line; do
    if [[ $count -eq 0 ]]; then
        count=$((count+1))
        continue
    fi    
    IFS=" " read -r -a my_array <<< "$line"
    if [[ "${my_array[0]}" != *"kube-"* \
            && "${my_array[0]}" != "default" \
            && "${my_array[0]}" != "local-path-storage" ]]; then
        namespace_list[$namespace_index]=${my_array[0]}
        namespace_index=$((namespace_index+1))
    fi
    count=$((count+1))
done <<< "$(kubectl get namespaces)"

#############################################################
# Destroy CORTX Cloud functions
#############################################################
function deleteCortxData()
{
    printf "########################################################\n"
    printf "# Delete CORTX Data                                     \n"
    printf "########################################################\n"
    for i in "${!node_selector_list[@]}"; do
        helm uninstall "cortx-data-${node_name_list[$i]}-$namespace" -n $namespace
    done
}

function deleteCortxServices()
{
    printf "########################################################\n"
    printf "# Delete CORTX Services                                 \n"
    printf "########################################################\n"
    kubectl delete service cortx-io-svc --namespace=$namespace
}

function deleteCortxControl()
{
    printf "########################################################\n"
    printf "# Delete CORTX Control                                  \n"
    printf "########################################################\n"
    helm uninstall "cortx-control-$namespace" -n $namespace
}

function deleteCortxProvisioners()
{
    printf "########################################################\n"
    printf "# Delete CORTX Data provisioner                         \n"
    printf "########################################################\n"
    for i in "${!node_selector_list[@]}"; do
        helm uninstall "cortx-data-provisioner-${node_name_list[$i]}-$namespace" -n $namespace
    done

    printf "########################################################\n"
    printf "# Delete CORTX Control provisioner                      \n"
    printf "########################################################\n"
    helm uninstall "cortx-control-provisioner-$namespace" -n $namespace
}

function waitForCortxPodsToTerminate()
{
    printf "\nWait for CORTX Pods to terminate"
    while true; do
        count=0
        cortx_pods="$(kubectl get pods --namespace=$namespace | grep 'cortx' 2>&1)"
        while IFS= read -r line; do
            if [[ "$line" == *"cortx"* ]]; then
                count=$((count+1))
            fi
        done <<< "${cortx_pods}"

        if [[ $count -eq 0 ]]; then
            break
        else
            printf "."
        fi
        sleep 1s
    done
    printf "\n\n"
}

function deleteCortxLocalBlockStorage()
{
    printf "######################################################\n"
    printf "# Delete CORTX Local Block Storage                    \n"
    printf "######################################################\n"
    helm uninstall "cortx-data-blk-data-$namespace" -n $namespace
}

function deleteCortxPVs()
{
    printf "######################################################\n"
    printf "# Delete CORTX Persistent Volumes                     \n"
    printf "######################################################\n"
    while IFS= read -r line; do
        if [[ $line != *"master"* && $line != *"AGE"* ]]
        then
            IFS=" " read -r -a pvc_line <<< "$line"
            if [[ ${pvc_line[5]} =~ ^$namespace/cortx-data-fs-local-pvc* \
                    || ${pvc_line[5]} =~ ^$namespace/cortx-control-fs-local-pvc* ]]; then
                printf "Removing ${pvc_line[0]}\n"
                if [[ "$force_delete" == "--force" || "$force_delete" == "-f" ]]; then
                    kubectl patch pv ${pvc_line[0]} -p '{"metadata":{"finalizers":null}}'
                fi
                kubectl delete pv ${pvc_line[0]}
            fi
        fi
    done <<< "$(kubectl get pv -A)"
}

function deleteCortxConfigmap()
{
    printf "########################################################\n"
    printf "# Delete CORTX Configmap                               #\n"
    printf "########################################################\n"
    cfgmap_path="./cortx-cloud-helm-pkg/cortx-configmap"
    # Delete data machine id config maps
    for i in "${!node_name_list[@]}"; do
        kubectl delete configmap "cortx-data-machine-id-cfgmap-${node_name_list[i]}-$namespace" --namespace=$namespace
        rm -rf "$cfgmap_path/auto-gen-${node_name_list[i]}-$namespace"

    done
    # Delete control machine id config map
    kubectl delete configmap "cortx-control-machine-id-cfgmap-$namespace" --namespace=$namespace
    rm -rf "$cfgmap_path/auto-gen-control-$namespace"
    # Delete CORTX config maps
    # rm -rf "$cfgmap_path/auto-gen-cfgmap-$namespace"
    kubectl delete configmap "cortx-cfgmap-$namespace" --namespace=$namespace
    rm -rf "$cfgmap_path/auto-gen-cfgmap-$namespace"

    rm -rf "$cfgmap_path/node-info-$namespace"
    rm -rf "$cfgmap_path/storage-info-$namespace"

    # Delete SSL cert config map
    ssl_cert_path="$cfgmap_path/ssl-cert"
    kubectl delete configmap "cortx-ssl-cert-cfgmap-$namespace" --namespace=$namespace
}

#############################################################
# Destroy CORTX 3rd party functions
#############################################################
function deleteKafkaZookeper()
{
    printf "########################################################\n"
    printf "# Delete Kafka                                         #\n"
    printf "########################################################\n"
    helm uninstall kafka -n "default"

    printf "########################################################\n"
    printf "# Delete Zookeeper                                     #\n"
    printf "########################################################\n"
    helm uninstall zookeeper -n "default"
}

function deleteOpenLdap()
{
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

    helm uninstall "openldap" -n "default"
}

function deleteSecrets()
{
    printf "########################################################\n"
    printf "# Delete Secrets                                       #\n"
    printf "########################################################\n"
    output=$(./parse_scripts/parse_yaml.sh $solution_yaml "solution.secrets*.name")
    IFS=';' read -r -a parsed_secret_name_array <<< "$output"
    for secret_name in "${parsed_secret_name_array[@]}"
    do
        secret_name=$(echo $secret_name | cut -f2 -d'>')
        kubectl delete secret $secret_name --namespace=$namespace
    done

    find $(pwd)/cortx-cloud-helm-pkg/cortx-control-provisioner -name "secret-*" -delete
    find $(pwd)/cortx-cloud-helm-pkg/cortx-control -name "secret-*" -delete
    find $(pwd)/cortx-cloud-helm-pkg/cortx-data-provisioner -name "secret-*" -delete
    find $(pwd)/cortx-cloud-helm-pkg/cortx-data -name "secret-*" -delete
}

function deleteConsul()
{
    printf "########################################################\n"
    printf "# Delete Consul                                        #\n"
    printf "########################################################\n"
    helm delete consul -n "default"
}

function waitFor3rdPartyToTerminate()
{
    printf "\nWait for 3rd party to terminate"
    while true; do
        count=0
        pods="$(kubectl get pods 2>&1)"
        while IFS= read -r line; do
            if [[ "$line" == *"kafka"* || \
                 "$line" == *"zookeeper"* || \
                 "$line" == *"openldap"* || \
                 "$line" == *"consul"* ]]; then
                count=$((count+1))
            fi
        done <<< "${pods}"

        if [[ $count -eq 0 ]]; then
            break
        else
            printf "."
        fi
        sleep 1s
    done
    printf "\n\n"
}

function delete3rdPartyPVCs()
{
    printf "########################################################\n"
    printf "# Delete Persistent Volume Claims                      #\n"
    printf "########################################################\n"
    volume_claims=$(kubectl get pvc --namespace=default | grep -E "$pvc_consul_filter|$pvc_kafka_filter|$pvc_zookeeper_filter|$openldap_pvc|cortx|3rd-party" | cut -f1 -d " ")
    echo $volume_claims
    for volume_claim in $volume_claims
    do
        printf "Removing $volume_claim\n"
        if [[ "$force_delete" == "--force" || "$force_delete" == "-f" ]]; then
            kubectl patch pvc $volume_claim -p '{"metadata":{"finalizers":null}}'
        fi
        kubectl delete pvc $volume_claim
    done

    volume_claims=$(kubectl get pvc --namespace=$namespace | grep -E "$pvc_consul_filter|$pvc_kafka_filter|$pvc_zookeeper_filter|$openldap_pvc|cortx|3rd-party" | cut -f1 -d " ")
    echo $volume_claims
    for volume_claim in $volume_claims
    do
        printf "Removing $volume_claim\n"
        if [[ "$force_delete" == "--force" || "$force_delete" == "-f" ]]; then
            kubectl patch pvc $volume_claim -p '{"metadata":{"finalizers":null}}'
        fi
        kubectl delete pvc $volume_claim
    done

    if [[ $namespace != 'default' ]]; then
        volume_claims=$(kubectl get pvc --namespace=$namespace | grep -E "$pvc_consul_filter|$pvc_kafka_filter|$pvc_zookeeper_filter|$openldap_pvc|cortx|3rd-party" | cut -f1 -d " ")
        echo $volume_claims
        for volume_claim in $volume_claims
        do
            printf "Removing $volume_claim\n"
            if [[ "$force_delete" == "--force" || "$force_delete" == "-f" ]]; then
                kubectl patch pvc $volume_claim -p '{"metadata":{"finalizers":null}}'
            fi
            kubectl delete pvc $volume_claim
        done
    fi
}

function delete3rdPartyPVs()
{
    printf "########################################################\n"
    printf "# Delete Persistent Volumes                            #\n"
    printf "########################################################\n"
    persistent_volumes=$(kubectl get pv --namespace=default | grep -E "$pvc_consul_filter|$pvc_kafka_filter|$pvc_zookeeper_filter|cortx|3rd-party" | cut -f1 -d " ")
    echo $persistent_volumes
    for persistent_volume in $persistent_volumes
    do
        printf "Removing $persistent_volume\n"    
        if [[ "$force_delete" == "--force" || "$force_delete" == "-f" ]]; then
            kubectl patch pv $persistent_volume -p '{"metadata":{"finalizers":null}}'
        fi
        kubectl delete pv $persistent_volume
    done

    if [[ $namespace != 'default' ]]; then
        persistent_volumes=$(kubectl get pv --namespace=$namespace | grep -E "$pvc_consul_filter|$pvc_kafka_filter|$pvc_zookeeper_filter|cortx|3rd-party" | cut -f1 -d " ")
        echo $persistent_volumes
        for persistent_volume in $persistent_volumes
        do
            printf "Removing $persistent_volume\n"        
            if [[ "$force_delete" == "--force" || "$force_delete" == "-f" ]]; then
                kubectl patch pv $persistent_volume -p '{"metadata":{"finalizers":null}}'
            fi
            kubectl delete pv $persistent_volume
        done
    fi
}

function deleteStorageProvisioner()
{
    rancher_prov_path="$(pwd)/cortx-cloud-3rd-party-pkg/auto-gen-rancher-provisioner"
    rancher_prov_file="$rancher_prov_path/local-path-storage.yaml"
    kubectl delete -f $rancher_prov_file
    rm -rf $rancher_prov_path
}

function helmChartCleanup()
{
    print_header=true
    helm_ls_header=true
    while IFS= read -r line; do
        IFS=" " read -r -a my_array <<< "$line"
        if [[ "$helm_ls_header" = true ]]; then
            helm_ls_header=false
            continue
        fi
        if [[ "$print_header" = true ]]; then
            printf "Helm chart cleanup:\n"
            print_header=false
        fi
        helm uninstall ${my_array[0]} -n "default"
    done <<< "$(helm ls | grep 'consul\|cortx\|kafka\|openldap\|zookeeper')"
}

function deleteKubernetesPrereqs()
{
    printf "########################################################\n"
    printf "# Delete Cortx Kubernetes Prereqs                      #\n"
    printf "########################################################\n"
    helm delete cortx-platform
}

function deleteCortxNamespace()
{
    # Delete CORTX namespace
    if [[ "$namespace" != "default" ]]; then
        helm delete cortx-ns-$namespace
    fi

}

function cleanup()
{
    #################################################################
    # Delete files that contain disk partitions on the worker nodes #
    #################################################################
    # Split parsed output into an array of vars and vals
    IFS=';' read -r -a parsed_var_val_array <<< "$parsed_node_output"
    # Loop the var val tuple array
    for var_val_element in "${parsed_var_val_array[@]}"
    do
        node_name=$(echo $var_val_element | cut -f2 -d'>')
        shorter_node_name=$(echo $node_name | cut -f1 -d'.')
        file_name="mnt-blk-info-$shorter_node_name.txt"
        rm $(pwd)/cortx-cloud-helm-pkg/cortx-data-provisioner/$file_name
        rm $(pwd)/cortx-cloud-helm-pkg/cortx-data/$file_name
    done
    
    find $(pwd)/cortx-cloud-helm-pkg/cortx-data-blk-data -name "mnt-blk-*" -delete
    find $(pwd)/cortx-cloud-helm-pkg/cortx-data-blk-data -name "node-list-*" -delete
    find $(pwd)/cortx-cloud-helm-pkg/cortx-data -name "mnt-blk-*" -delete
    find $(pwd)/cortx-cloud-helm-pkg/cortx-data -name "node-list-*" -delete
    find $(pwd)/cortx-cloud-helm-pkg/cortx-data-provisioner -name "mnt-blk-*" -delete
    find $(pwd)/cortx-cloud-helm-pkg/cortx-data-provisioner -name "node-list-*" -delete
}

#############################################################
# Destroy CORTX Cloud
#############################################################

deleteCortxData
deleteCortxServices
deleteCortxControl
deleteCortxProvisioners
waitForCortxPodsToTerminate
deleteSecrets
deleteCortxLocalBlockStorage
deleteCortxPVs
deleteCortxConfigmap

#############################################################
# Destroy CORTX 3rd party
#############################################################
found_match_np=false
for np in "${namespace_list[@]}"; do
    if [[ "$np" == "$namespace" ]]; then
        found_match_np=true
        break
    fi
done

if [[ (${#namespace_list[@]} -le 1 && "$found_match_np" = true) || "$namespace" == "default" ]]; then
    deleteKafkaZookeper
    deleteOpenLdap
    deleteConsul
    waitFor3rdPartyToTerminate
    delete3rdPartyPVCs
    delete3rdPartyPVs
fi

#############################################################
# Clean up
#############################################################
deleteKubernetesPrereqs
if [[ (${#namespace_list[@]} -le 1 && "$found_match_np" = true) || "$namespace" == "default" ]]; then
    deleteStorageProvisioner
    
    helmChartCleanup    
fi
deleteCortxNamespace
cleanup