# **CORTX on minikube - Quick Install Guide**

*Note: This setup is for a single node cluster tested using Centos 7.9*

## 1. Minimum Requirements:

* **RAM**: 10GB
* **Processor**: 6
* **NIC**: 1
* **OS Disk**: 1 disk of 20GB
* **Data Disks**: 5 disks of 10GB each
* **Metadata disks**: 2 disks of 10GB each
* **Container or virtual machine manager**, such as: Docker, Hyperkit, Hyper-V, KVM, Parallels, Podman, VirtualBox, or VMware Fusion/Workstation


**2. Install Kubectl**


```
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version
```

**3. Install Helm (A package manager for K8s):**

```
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
```

**4. Install and start minikube:**

```
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
minikube start --driver=none
```

Note minikube may fail to start in some setup due to driver issue, if this happens you can install the drivers here -> Drivers | minikube [(k8s.io)](https://minikube.sigs.k8s.io/docs/drivers/)

Note if encounter this error "Exiting due to GUEST_MISSING_CONNTRACK: Sorry, Kubernetes 1.23.3 requires conntrack to be installed in root's path", run `sudo yum install conntrack` first.

**5. Clone Cortx-K8s framework**

```
git clone -b v0.7.0 https://github.com/Seagate/cortx-k8s
cd cortx-k8s/k8_cortx_cloud/
```

<!-- Note: This was tested on the following commit id
```
commit 8b842371eb4a3317b23cec6b2ddf74d40d4ad0ef
Author: Keith Pine <keith.pine@seagate.com>
Date:   Wed Feb 16 14:36:31 2022 -0800
``` -->

### 5.1  Update the solution.yaml file.

- Update the node name in `solution.yaml` with the name of the node you get from `kubectl get node` command. 

    ```
    nodes:
      node1:
        name: control-plane.minikube.internal

    ```

- Locate and change the setup_size to small:
    ```
    setup_size: small
    ```

- Update the device name and size for all the cvg(s).
    
    - You can use the following command to find your disk-names:
    
    ```
    # lsblk
    NAME            MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
    sda               8:0    0   25G  0 disk 
    ├─sda1            8:1    0    1G  0 part /boot
    └─sda2            8:2    0   24G  0 part 
      ├─centos-root 253:0    0 21.5G  0 lvm  /
      └─centos-swap 253:1    0  2.5G  0 lvm  
    sdb               8:16   0   10G  0 disk /mnt/fs-local-volume
    sdc               8:32   0   10G  0 disk 
    sdd               8:48   0   10G  0 disk 
    sde               8:64   0   10G  0 disk 
    sdf               8:80   0   10G  0 disk 
    sdg               8:96   0   10G  0 disk 
    sdh               8:112  0   10G  0 disk 
    sr0              11:0    1 1024M  0 rom  
    ```
    
    For example, in the below snippet we have added `/dev/sdb`, `/dev/sdc`, `/dev/sdd`, `/dev/sde`, `/dev/sdf`, and `/dev/sdg` as the storage devices with size `10Gi`.
    
    ```
    storage:
        cvg1:
          name: cvg-01
          type: ios
          devices:
            metadata:
              device: /dev/sdb
              size: 10Gi
            data:
              d1:
                device: /dev/sdc
                size: 10Gi
              d2:
                device: /dev/sdd
                size: 10Gi
        cvg2:
          name: cvg-02
          type: ios
          devices:
            metadata:
              device: /dev/sde
              size: 10Gi
            data:
              d1:
                device: /dev/sdf
                size: 10Gi
              d2:
                device: /dev/sdg
                size: 10Gi
    ```
    
**5.2 Execute pre-installation script.**

```
sudo ./prereq-deploy-cortx-cloud.sh /dev/disk-name-not-used-in-yaml 
```

*Note: `/dev/disk-name-not-used-in-yaml` should be replaced by a disk that is not used in `solution.yaml` or by the OS. From the above example we would use `/dev/sdh`.*


**5.3 Deploy CORTX**

```
./deploy-cortx-cloud.sh
```

*Deployment may take several minutes to complete.*

**This step completes CORTX installation**

**5.4 Test that all pods are running and that CORTX is ready**

```
kubectl get pod
```

Below is the output of a successful deployment:

```
# kubectl get pod
NAME                                READY   STATUS    RESTARTS   AGE
consul-client-sxkmc                 1/1     Running   0          7m12s
consul-server-0                     1/1     Running   0          7m11s
cortx-control-b575878f8-g2k9c       4/4     Running   0          5m48s
cortx-data-car-c94bdd86c-bqjnh      4/4     Running   0          4m37s
cortx-ha-58b494c59d-ft9n6           3/3     Running   0          46s
cortx-server-car-758675d6fc-ss2f8   5/5     Running   0          2m9s
kafka-0                             1/1     Running   0          6m27s
openldap-0                          1/1     Running   0          7m8s
zookeeper-0                         1/1     Running   0          6m49s
```

Once you get the above output we need to check the cluster status as follows:

```
DataPod=`kubectl get pod --field-selector=status.phase=Running --selector cortx.io/service-type=cortx-data -o jsonpath={.items[0].metadata.name}`
kubectl exec $DataPod -c cortx-hax -- hctl status
```

For example, after a successful deployment the output from the above command should be as follows (`hax`, `s3server`, `ioservice` and `confd` are started):

```
# kubectl exec -i $DataPod -c cortx-hax -- hctl status
Byte_count:
    critical_byte_count : 0
    damaged_byte_count : 0
    degraded_byte_count : 0
    healthy_byte_count : 0
Data pool:
    # fid name
    0x6f00000000000001:0x33 'storage-set-1__sns'
Profile:
    # fid name: pool(s)
    0x7000000000000001:0x50 'Profile_the_pool': 'storage-set-1__sns' 'storage-set-1__dix' None
Services:
    cortx-server-headless-svc-car 
    [started]  hax        0x7200000000000001:0x29  inet:tcp:cortx-server-headless-svc-car@22001
    [started]  s3server   0x7200000000000001:0x2c  inet:tcp:cortx-server-headless-svc-car@22501
    cortx-data-headless-svc-car  (RC)
    [started]  hax        0x7200000000000001:0x7   inet:tcp:cortx-data-headless-svc-car@22001
    [started]  ioservice  0x7200000000000001:0xa   inet:tcp:cortx-data-headless-svc-car@21001
    [started]  ioservice  0x7200000000000001:0x17  inet:tcp:cortx-data-headless-svc-car@21002
    [started]  confd      0x7200000000000001:0x24  inet:tcp:cortx-data-headless-svc-car@21003

```

*Note: It may take several minutes for s3server instances to move from "offline" to "started"*

*If the pods are not coming up correctly or any of the service are not getting `[started]` - check your `solution.yaml` for typos or mistakes which could result in a deployment failure.*

**5.5 Delete CORTX Cluster**

To rollback to step 5.3 and delete the CORTX cluster run the below command:

```
./destroy-cortx-cloud.sh
```

**6. Using CORTX**

Use CORTX CSM (Management API) to provision an S3 account

**6.1 Login to the management**

```
export CSM_IP=`kubectl get svc cortx-control-loadbal-svc -ojsonpath='{.spec.clusterIP}'`

curl -i -d '{"username": "cortxadmin", "password": "Cortxadmin@123"}' https://$CSM_IP:8081/api/v2/login --insecure | grep Bearer
```

*Copy the bearer token for the next command*

**6.2 Create an S3 account.**

```
curl --insecure \
  -H 'Authorization: Bearer <bearer-token>' \
  -d '{  "account_name": "testUser", "account_email": "*****@gmail.com", "password": "Account@1" }' \
  https://$CSM_IP:8081/api/v2/s3_accounts
```

- Results from the above command

```
{"account_name": "testUser", "account_email": "*****@gmail.com", "account_id": "507040439091", "canonical_id": "92b845b0de8a4532a0d3a15a1540e43ffc1ec5a02662430ea76dce69d3e770fb", "access_key": "AKIA*******************CKw", "secret_key": "U1pU****************************cGL"}
```

**7. Install and configure AWS CLI to use IAM and S3 APIs**

```
sudo yum install -y unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

*Your credentials are what you got after creating an s3 account above.*

```
export AWS_ACCESS_KEY_ID=AKIA*******************CKw
export AWS_SECRET_ACCESS_KEY=U1pU****************************cGL
export AWS_DEFAULT_REGION=us-east-1
```

- Find the S3 server endpoint for IO

```
export DATA_IP=`kubectl get svc cortx-io-svc -ojsonpath='{.spec.clusterIP}'`
```

- Use the AWS CLI for IO. 

```
aws --no-verify-ssl --endpoint-url http://$DATA_IP:80 s3 ls
aws --no-verify-ssl --endpoint-url http://$DATA_IP:80 s3 mb s3://cortx-minukube-works

dd if=/dev/zero of=minikubetest bs=1M count=10
aws --no-verify-ssl --endpoint-url http://$DATA_IP:80 s3 cp minikubetest s3://cortx-minukube-works
aws --no-verify-ssl --endpoint-url http://$DATA_IP:80 s3 ls
```


### Tested by:

This document was tested on the following version: [v0.7.0](https://github.com/Seagate/cortx-k8s/releases/tag/v0.7.0)

- Jun 15, 2022: Patrick Hession (patrick.hession@seagate.com) using CentOS 7.9 in VMWare Workstation 16 Pro.

This document was tested on the following version: [v0.6.0](https://github.com/Seagate/cortx-k8s/releases/tag/v0.6.0)

- May 20, 2022: Patrick Hession (patrick.hession@seagate.com) using CentOS 7.9 on Red Hat CloudForms.

This document was tested on the following version: [v0.0.22](https://github.com/Seagate/cortx-k8s/releases/tag/v0.0.22)

- Mar 12, 2022: Bo Wei (bo.b.wei@seagate.com) using CentOS 7.9 on Red Hat CloudForms.

- Feb 23, 2022: Sayed Alfhad Shah(fahadshah2411@gmail.com), Rinku Kothiya(rinku.kothiya@seagate.com) and Rose Wambui(rose.wambui@seagate.com)
