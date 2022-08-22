#!/bin/bash

pvc=$1
namespace="${2:-default}"

function help()
{
    echo "$0 <pvc> [<namespace>]"
    exit 1
}

if [ -z "${pvc}" ]; then help; fi

job_name="cortx-log-${pvc}"

cat << EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: "${job_name}"
  namespace: "${namespace}"
spec:
  backoffLimit: 1
  template:
    spec:
      containers:
        - image: busybox
          name: "${job_name}"
          command:
            - sh
            - -c
            - tar cz -C /etc "${pvc}" | base64
          volumeMounts:
            - mountPath: "/etc/${pvc}"
              name: data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: "${pvc}"
      restartPolicy: Never
EOF


# Wait for job to complete
pod_status="starting"
while [ "${pod_status}" != "Completed" ]; do
    sleep 1
    while IFS= read -r line; do
        IFS=" " read -r -a my_array <<< "${line}"
        pod_name="${my_array[0]}"
        pod_status="${my_array[2]}"
        echo "Waiting for job to complete (${pod_name}  ${pod_status})"
    done <<< "$(kubectl get pod --namespace ${namespace} | grep ^${job_name})"
done


# Get logs, save to .tgz
outfile="${pvc}.tgz"
echo "Saving logs to ${outfile}"
kubectl logs "${pod_name}" --namespace ${namespace} | base64 -d > ${outfile}

# Delete the job
kubectl delete job "${job_name}" --namespace "${namespace}"
