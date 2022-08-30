#!/usr/bin/env bash

SCRIPT=$(readlink -f "$0")
SCRIPT_NAME=$(basename "${SCRIPT}")
solution_yaml="${CORTX_SOLUTION_CONFIG_FILE:-solution.yaml}"
force_overwrite=false

function usage()
{
  cat << EOF
** Recover contents of PVC from Non-Running CORTX Containers **

Usage: 
  ${SCRIPT_NAME} PVC [-s SOLUTION_CONFIG_FILE] [--force]

Where:
  PVC is the name of the PersistentVolumeClaim to collect
  data from.  To see all available PVCs:
  
      kubectl get pvc -n \$NAMESPACE


Options:
  -s <FILE>     The cluster solution configuration file.  Can
                also be set with the CORTX_SOLUTION_CONFIG_FILE
                environment variable.  Defaults to 'solution.yaml'

  -f|--force    Force overwrite the output file.
EOF
}

pvc=
while [[ $# -gt 0 ]]; do
  case $1 in
    -s )
      solution_yaml="$2"
      shift 2
      ;;
    -f|--force )
      force_overwrite=true
      shift 1
      ;;
    -h|--help )
      usage
      exit 0
      ;;
    * )
      if [[ $1 = -* ]]; then
        echo "ERROR: Unsupported Option \"$1\"."
        usage
        exit 1
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

namespace=$(yq '.solution.namespace' "${solution_yaml}")
busybox_image=$(yq '.solution.images.busybox' "${solution_yaml}")
datestr=$(date '+%Y%m%d.%H%M%S')
job_name="cortx-log-${pvc}-${datestr}"
tarfile="${pvc}.tgz"

if [[ -f "${tarfile}" && "${force_overwrite}" == "false" ]]; then
  printf "%s already exists. User '--force' to overwrite an existing file.\n" "${tarfile}"
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
        - image: "${busybox_image}"
          name: tar-pvc
          command:
            - sh
            - -c
            - |
              tar cfz /tmp/"${tarfile}" -C /etc "${pvc}"
              touch /tmp/tarfile_created
              until [ -f /tmp/stopme ]; do
                sleep 1
              done
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
  done < <(kubectl get pods --namespace "${namespace}" --selector=job-name="${job_name}" --no-headers)
  if [[ -z "${pod_status}" ]]; then
    printf "ERROR: %s did not tar PVC files as expected\n" "${pod_name}"
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
