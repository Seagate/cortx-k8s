#!/bin/bash

USAGE="USAGE: bash $(basename "$0") [--rootdnpassword <rootdnpassword>]
       [--help | -h]
where:
  --rootdnpassword    openldap root user password
  --help              help
"

ROOTDN_PASSWORD=

while test $# -gt 0
do
  case "$1" in
    --rootdnpassword ) shift;
        ROOTDN_PASSWORD=$1
        ;;
    --help | -h )
        echo "$USAGE"
        exit 1
        ;;
  esac
  shift
done

if [ -z $ROOTDN_PASSWORD ]
then
  echo $USAGE
  exit 1
fi

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
  retry_count=1
  while [ ! -z "$(kubectl exec -it $i -- ldapsearch -w $ROOTDN_PASSWORD -x -D cn=admin,cn=config -b cn=config -h localhost 2>/dev/null | grep -o "Can't contact LDAP server (-1)")" ] || [[ "$(kubectl exec -it $i -- ldapsearch -w $ROOTDN_PASSWORD -x -D cn=admin,cn=config -b olcOverlay={1}ppolicy,olcDatabase={2}mdb,cn=config -h localhost 2>/dev/null | grep numEntries:* | awk '{print $3}' | tr -d '\r')" != "1" ]]
  do
    if [ $retry_count -eq 11 ]
    then
      exit 1
    fi
    echo "Retry: $retry_count"
    echo "Waiting for ldap service on $i ..."
    sleep 2
    retry_count=$((retry_count+1))
  done
  echo "Ldap is up on $i"
  kubectl cp /tmp/hostlist $i:/root/hostlist
  kubectl exec -it $i -- cat /root/hostlist
  kubectl exec -it $i -- sh /opt/openldap-config/setupReplicationScript.sh -h /root/hostlist -p $ROOTDN_PASSWORD
done