#!/usr/bin/env bash

STARTUP_TIMEOUT=120s

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


printf "Starting job %s\n" "${job_name}"

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

function exit_msg()
{
  msg=$1
  errcode=$2
  echo "${msg}"
  exit "${errcode}"
}

function delete_job()
{
  kubectl delete job "${job_name}" --namespace "${namespace}"
}

trap delete_job EXIT

# Get pod name
printf "Waiting for pod to start\n"
kubectl wait --for=condition=ready --selector=job-name="${job_name}" --namespace="${namespace}" --timeout="${STARTUP_TIMEOUT}" pod || exit 1

pod_name=
while IFS= read -r line; do
  IFS=" " read -r -a my_array <<< "${line}"
  pod_name="${my_array[0]}"
done < <(kubectl get pods --namespace "${namespace}" --selector=job-name="${job_name}" --no-headers) || true

if [[ -z "${pod_name}" ]]; then
  printf "Could not get pod name from kubectl get pods. Exiting."
  exit 1
fi

printf "Waiting for tar to complete.\n"
kubectl exec --namespace "${namespace}" "${pod_name}" -- sh -c 'until [ -f /tmp/tarfile_created ]; do sleep 1; done' || exit_msg "Failed waiting for job to complete" 1

# Get logs, save to .tgz
printf "Copying PVC contents to %s.\n" "${tarfile}"
kubectl cp "${pod_name}":tmp/"${tarfile}" "${tarfile}"
kubectl exec "${pod_name}" -- touch /tmp/stopme
