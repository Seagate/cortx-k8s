#!/bin/bash
set -x
rm -rf /tmp/hostlist
rm -rf /tmp/podlist

touch /tmp/podlist
(kubectl get pods | grep -o openldap-[0-9]*) > /tmp/podlist

readarray -t pod_arr < /tmp/podlist

for i in "${pod_arr[@]}"
do
  echo $i.openldap-svc.default.svc.cluster.local >> /tmp/hostlist
done

for i in "${pod_arr[@]}"
do
   kubectl cp /tmp/hostlist $i:/root/hostlist
   kubectl exec -it $i -- sh /opt/openldap-config/setupReplicationScript.sh -h /root/hostlist -p seagate1
done