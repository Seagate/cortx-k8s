set -x
rm -rf /tmp/nodelist
rm -rf /tmp/cortx-s3server
rm -rf /tmp/podlist

# Clone s3 repo for replication script
cd /tmp/
git clone https://github.com/Seagate/cortx-s3server/
cd ..

touch /tmp/podlist
(kubectl get pods | grep -o openldap-[0-9]*) > /tmp/podlist

readarray -t pod_arr < /tmp/podlist
for i in "${pod_arr[@]}"
do
        echo $i
        echo "$(kubectl get pod $i -o jsonpath='{.status.podIP}')" >> /tmp/nodelist
done

for i in "${pod_arr[@]}"
do
   kubectl exec -it $i -- mkdir -p /opt/seagate/cortx/s3/install/
   kubectl cp /tmp/cortx-s3server/scripts/ldap $i:/opt/seagate/cortx/s3/install/
   kubectl cp /tmp/nodelist $i:/root/nodelist
   kubectl exec -it $i -- sed -i s/dc=s3,//g /opt/seagate/cortx/s3/install/ldap/replication/dataTemplate.ldif
   kubectl exec -it $i -- /opt/seagate/cortx/s3/install/ldap/replication/setupReplicationScript.sh -h /root/nodelist -p seagate
done