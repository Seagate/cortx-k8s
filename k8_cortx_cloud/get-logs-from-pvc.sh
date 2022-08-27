#!/bin/bash

function usage()
{
  echo -e "\n** Recover contents of PVC from Non-Running CORTX Containers **\n"
  echo -e "Usage: \`sh $0 [PVC]\`\n"
  echo "Optional Arguments:"
  echo "    -n|--namespace NAMESPACE: K8s namespace that PVC is in (default=default)"
  echo "    -f|--force:  Force overwrite of output file"
  exit 1
}

pvc=
namespace=default
force_overwrite=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--namespace )
      namespace="$2"
      shift 2
      ;;
    -f|--force )
      force_overwrite=true
      shift 1
      ;;
    * )
      if [[ $1 = -* ]]; then
        echo "ERROR: Unsupported Option \"$1\"."
        usage
      elif [[ -z "${pvc}" ]]; then
        pvc=$1
      fi
      shift 1
      ;;
  esac
done

if [[ -z "${pvc}" ]]; then
  echo "ERROR: Specify PVC."
  exit 1
fi

datestr=$(date '+%Y%m%d.%H%M%S')
job_name="cortx-log-${pvc}-${datestr}"
tarfile="${pvc}.tgz"

if [[ -f "${tarfile}" && "${force_overwrite}" == "false" ]]; then
  printf "%s already exists. -f to overwrite.\n" "${tarfile}"
  exit 1
fi


cat << EOF | kubectl apply -f - || true
apiVersion: batch/v1
kind: Job
metadata:
  name: "${job_name}"
  namespace: "${namespace}"
spec:
  template:
    spec:
      containers:
        - image: busybox
          name: tar-pvc
          command:
            - sh
            - -c
            - tar cfz /tmp/"${tarfile}" -C /etc "${pvc}"; \
              touch /tmp/tarfile_created; \
              while [ ! -f /tmp/stopme ]; do sleep 1; done
          volumeMounts:
            - mountPath: "/etc/${pvc}"
              name: data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: "${pvc}"
      restartPolicy: OnFailure
EOF


# Get pod name
pod_status="Starting"
while [[ "${pod_status}" != "Running" ]]; do
  sleep 1
  while IFS= read -r line; do
    IFS=" " read -r -a my_array <<< "${line}"
    pod_name="${my_array[0]}"
    pod_status="${my_array[2]}"
    echo "Waiting for job to complete (${pod_name}  ${pod_status})"
  done <<< "$(kubectl get pod --namespace "${namespace}" | grep "^${job_name}")" || true
  if [[ -z "${pod_status}" ]]; then
    printf "ERROR: %s did not tar PVC files as expected\n" % "${pod_name}"
    exit 1
  fi
done

# Wait for tar process to complete
tar_complete="false"
while [[ "${tar_complete}" == "false" ]]; do
  sleep 1
  kubectl exec "${pod_name}" -- ls /tmp/tarfile_created &> /dev/null && tar_complete=true
done

# Get logs, save to .tgz
echo "Copying PVC contents to ${tarfile}"
kubectl cp "${pod_name}":tmp/"${tarfile}" "${tarfile}"
kubectl exec "${pod_name}" -- touch /tmp/stopme

# Delete the job
kubectl delete job "${job_name}" --namespace "${namespace}"
