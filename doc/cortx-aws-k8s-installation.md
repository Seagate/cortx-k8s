# CORTX on AWS and Kubernetes - Quick Install Guide
This procedure should work for any Kubernetes cluster. We recommend to go through the entire document even if you're not planning to deploy CORTX in AWS.
Actual CORTX deployment into an existing Kubernetes cluster is covered in section 3.

## 1. Prerequisites

The following environment should exist in AWS prior to further deployment:
 - VPC
   - Bastion subnet
     - Security group with SSH (tcp/22) open for access
     - Bastion host
       - as of now an SSH key is required for access to private Github repository (https://github.com/Seagate/cortx-k8s), it will be resolved soon
       - an SSH key for passwordless access to CORTX K8s nodes
       - AWS CLI installed and configured
     - NAT GW for outgoing Internet access from the cluster (private) subnet
   - Cluster subnet
     - Security group with SSH (tcp/22) access from the Bastion subnet
 <p align="center">
    <img src="pics/cortx-aws-k8s-before-installation.jpg">
 </p>

 We recommend to execute the following steps from the Bastion host

## 2. Kubernetes cluster provisioning

CORTX requires Kubernetes cluster for installation.
 - Every node must have at least 8 cores and 16 GB of RAM.
   - this configuration is sufficient for up to 5 nodes clusters
   - clusters with higher amount of nodes may require more powerful servers (15 nodes cluster was tested using 36 cores / 72 GB of RAM instances)
 - While there should be no dependencies on the underlying OS this procedure was tested with CentOS 7.9 and Kubernetes 1.23
 - In the current release, every node should have the following storage configuration:
   - OS disk (in the example below we'll provision 50GB)
   - Disk for 3rd party applications required for normal CORTX installation (25GB in this procedure).
     This disk is used also to store various CORTX logs - for a long-running clusters under heavy load we recommend at least 50GB of capacity for this disk
   - Disk for internal logs (currently not in use, 25GB in the example below)
   - Disks for customers' data and metadata. In this demo we'll provision 2 disks for metadata and 4 disks for data (25GB each)
   - Disks layout (device names and sizes) must be identical on all nodes in the cluster
 - Clock on all nodes must be in sync

This procedure was tested within the following limits:
- Number of nodes in the cluster: 1 - 15
- Number of Motr (data+metadata) drives per node: 3 - 21 
  - A configuration of 100+ drives per node was also tested outside of AWS

If you already have a suitable Kubernetes cluster please proceed to step 3 - CORTX Deployment

### 2.1 Define basic cluster configuration
```
# Number of nodes in the Kubernetes cluster 
ClusterNodes=3
# Name tag for all EC2 instances and EBS volumes provisioned for this CORTX cluster
ClusterTag=cortx-k8s-cl03
# AWS Subnet ID for cluster provisioning
SubnetId=subnet-070838693db278eab
# Security Group ID for the cluster
SecurityGroupId=sg-0585145ff6b831b77
# CentOS 7.9 AMI ID. See https://wiki.centos.org/Cloud/AWS 
AmiID=ami-08d2d8b00f270d03b
# Instance type
InstanceType=c5.2xlarge
# Key pair name for all instances
KeyPair=cortx-k8s-test
# Define SSH flags for connectivity from the bastion host to CORTX nodes
SSH_FLAGS='-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i ~/.ssh/cortx-k8s-test.pem'

mkdir $ClusterTag
cd $ClusterTag
```

### 2.2 Launch new instances 
This command will launch specified number of EC2 c5.2xlarge instances with CentOS 7.9 and required storage configuration
```
aws ec2 run-instances --image-id $AmiID --count $ClusterNodes --instance-type $InstanceType --subnet-id $SubnetId --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":50,\"DeleteOnTermination\":true}}, {\"DeviceName\":\"/dev/sdb\",\"Ebs\":{\"VolumeSize\":25,\"DeleteOnTermination\":true}}, {\"DeviceName\":\"/dev/sdc\",\"Ebs\":{\"VolumeSize\":25,\"DeleteOnTermination\":true}}, {\"DeviceName\":\"/dev/sdd\",\"Ebs\":{\"VolumeSize\":25,\"DeleteOnTermination\":true}}, {\"DeviceName\":\"/dev/sde\",\"Ebs\":{\"VolumeSize\":25,\"DeleteOnTermination\":true}}, {\"DeviceName\":\"/dev/sdf\",\"Ebs\":{\"VolumeSize\":25,\"DeleteOnTermination\":true}}, {\"DeviceName\":\"/dev/sdg\",\"Ebs\":{\"VolumeSize\":25,\"DeleteOnTermination\":true}}, {\"DeviceName\":\"/dev/sdh\",\"Ebs\":{\"VolumeSize\":25,\"DeleteOnTermination\":true}}, {\"DeviceName\":\"/dev/sdi\",\"Ebs\":{\"VolumeSize\":25,\"DeleteOnTermination\":true}}]" --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value='$ClusterTag'}]' 'ResourceType=volume,Tags=[{Key=Name,Value='$ClusterTag'}]'    --key-name $KeyPair --security-group-ids $SecurityGroupId
```

Wait until all instances get into Running state.

### 2.3 Additional preparations for Kubernetes setup
```
# List of all private IPs 
ClusterIPs=`aws ec2 describe-instances --filters Name=tag:Name,Values=$ClusterTag Name=instance-state-name,Values=running --query "Reservations[*].Instances[*].{IP:PrivateIpAddress}" --output text | tr '\n' ' '`
# List of all Instance IDs 
ClusterInstances=`aws ec2 describe-instances --filters Name=tag:Name,Values=$ClusterTag Name=instance-state-name,Values=running --query "Reservations[*].Instances[*].InstanceId" --output text`
# Designate one of the instances as a ControlPlane node
ClusterControlPlaneInstance=`echo $ClusterInstances | awk '{print $1}'`

# Tag all cluster nodes based on their role
for inst in $ClusterInstances; do echo $inst; aws ec2 create-tags --resources $inst --tags Key=CortxClusterControlPlane,Value=false; done
aws ec2 create-tags --resources $ClusterControlPlaneInstance --tags Key=CortxClusterControlPlane,Value=true

ClusterControlPlaneIP=`aws ec2 describe-instances --filters Name=tag:Name,Values=$ClusterTag Name=tag:CortxClusterControlPlane,Values=true Name=instance-state-name,Values=running --query "Reservations[*].Instances[*].{IP:PrivateIpAddress}" --output text`

# Disable source/destination checking - required for Calico networking in AWS
for inst in $ClusterInstances; do echo $inst; aws ec2 modify-instance-attribute --instance-id=$inst --no-source-dest-check; done

```

### 2.4 Install required SW packages
```
# Update the Operating System
for ip in $ClusterIPs; do echo $ip; ssh $SSH_FLAGS centos@$ip sudo yum update -y </dev/null & done
```

```
#Update /etc/hosts on all worker nodes
aws ec2 describe-instances --filters Name=tag:Name,Values=$ClusterTag Name=instance-state-name,Values=running --query "Reservations[*].Instances[*].{IP:PrivateIpAddress,Name:PrivateDnsName}" --output text | tr '\.' ' ' | awk '{print $1"."$2"."$3"."$4" "$5" "$5"."$6"."$7"."$8}' > hosts.addon.$ClusterTag

for ip in $ClusterIPs; do echo $ip; scp $SSH_FLAGS hosts.addon.$ClusterTag centos@$ip:/tmp; ssh $SSH_FLAGS centos@$ip "cat /etc/hosts /tmp/hosts.addon.$ClusterTag > /tmp/hosts.$ClusterTag; sudo cp /tmp/hosts.$ClusterTag /etc/hosts"; done
```

Install Docker
```
# Install Docker
for ip in $ClusterIPs; do echo $ip; ssh $SSH_FLAGS centos@$ip "sudo yum install -y yum-utils; sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo; sudo yum -y install docker-ce docker-ce-cli containerd.io; sudo systemctl start docker; sudo systemctl enable docker; sudo usermod -aG docker centos" </dev/null & done
```

#### 2.4.1 Optional: pull container images to overcome Docker Hub rate limits
Docker hub sets pull rate limits for anonymous requests which may cause issues with the future installation. You may need an account on Docker Hub to pull required public images on all worker nodes.
Use the following command to do so (replace username and password)
```
for ip in $ClusterIPs; do ssh $SSH_FLAGS centos@$ip docker login --username=<Docker username> --password <Docker password>; docker pull hashicorp/consul:1.10.0; docker pull busybox; docker pull docker.io/calico/apiserver:v3.20.2; docker pull docker.io/calico/node:v3.20.2; docker pull docker.io/gluster/gluster-centos:latest;  docker pull docker.io/calico/pod2daemon-flexvol:v3.20.2; docker pull docker.io/calico/typha:v3.20.2; docker pull docker.io/calico/cni:v3.20.2; docker pull docker.io/calico/kube-controllers:v3.20.2; docker pull docker.io/gluster/gluster-centos:latest" & done
```


### 2.5 Prepare for Kubernetes installation
```
cat <<EOF | tee modules-k8s.conf
br_netfilter
EOF

cat <<EOF | tee sysctl-k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

for ip in $ClusterIPs; do echo $ip; scp $SSH_FLAGS *-k8s.conf centos@$ip: ; ssh $SSH_FLAGS centos@$ip "sudo cp modules-k8s.conf /etc/modules-load.d/k8s.conf; sudo cp sysctl-k8s.conf /etc/sysctl.d/k8s.conf; sudo sysctl --system"; done
```

```
cat <<EOF | tee kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF

for ip in $ClusterIPs; do echo $ip; scp $SSH_FLAGS kubernetes.repo centos@$ip: ; ssh $SSH_FLAGS centos@$ip "sudo cp kubernetes.repo /etc/yum.repos.d/kubernetes.repo; sudo setenforce 0; sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config; sudo yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes; sudo systemctl enable --now kubelet" </dev/null & done
```

### 2.6 Install Kubernetes
```
cat <<EOF | tee kubeadm-config.yaml
kind: ClusterConfiguration
apiVersion: kubeadm.k8s.io/v1beta3
kubernetesVersion: v1.23.0
networking:
  podSubnet: 192.168.0.0/16
---
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
cgroupDriver: cgroupfs
EOF



scp $SSH_FLAGS kubeadm-config.yaml centos@$ClusterControlPlaneIP: ; ssh $SSH_FLAGS centos@$ClusterControlPlaneIP sudo kubeadm init --config kubeadm-config.yaml
```
At this stage a single node Kubernetes cluster should be provisioned. Copy "kubeadm join" command at the end of the kubeadm init output - it will be required later

### 2.7 Complete Kubernetes post-installation tasks and deploy Calico
```
ssh $SSH_FLAGS centos@$ClusterControlPlaneIP "mkdir -p .kube; sudo cp -i /etc/kubernetes/admin.conf .kube/config; sudo chown $(id -u):$(id -g) .kube/config"
```

```
#Install Calico CNI
ssh $SSH_FLAGS centos@$ClusterControlPlaneIP "kubectl create -f https://docs.projectcalico.org/manifests/tigera-operator.yaml; kubectl create -f https://docs.projectcalico.org/manifests/custom-resources.yaml"
```

```
# Allow pods scheduling on the ControlPlane node
ssh $SSH_FLAGS centos@$ClusterControlPlaneIP kubectl taint nodes --all node-role.kubernetes.io/master-
```

### 2.8 Join all worker nodes to the cluster
<b>Replace "kubadm join" command below with the parameters provided by kubeadm init at the end of stage 2.6</b>
```
for ip in `aws ec2 describe-instances --filters Name=tag:Name,Values=$ClusterTag Name=tag:CortxClusterControlPlane,Values=false Name=instance-state-name,Values=running --query "Reservations[*].Instances[*].{IP:PrivateIpAddress}" --output text`; do echo $ip; ssh $SSH_FLAGS centos@$ip sudo kubeadm join 10.0.1.35:6443 --token lp3nor.gw9waj1z1w63ufkf --discovery-token-ca-cert-hash sha256:522da6716b32a05ebcc5df58739ad32d2e81e44e0c9becaeec9ea78430d15c8f </dev/null &  done
```

At this stage the Kubernetes cluster should be fully operational

## 3 Install CORTX 

**NOTE**: For this setup, you can opt:-
1.  To use container images hosted on the [repostitory](https://github.com/Seagate/cortx/pkgs/container/cortx-all)

2. Generate the cortx-all container image yourself, following the guidelines [here](https://github.com/Seagate/cortx/tree/main/doc/community-build/docker/cortx-all)

    - Generate the image on the bastion host.

    - Save the docker image.
      ```
      docker save --output cortx-all.tar cortx-all
      ```
    - Copy the image to all other nodes in the cluster.
      ```
      for ip in $ClusterIPs; do echo $ip; scp $SSH_FLAGS cortx-all.tar centos@$ip: ; done
      ```
    - The image is in a zipped format, load/unzip the image in all the nodes:

      ```
      for ip in $ClusterIPs; do echo $ip; ssh $SSH_FLAGS centos@$ip  docker load -i cortx-all.tar & done
      ```
    - (Optional) Check if the images are present on all nodes

      ```
       for ip in $ClusterIPs; do echo $ip; ssh $SSH_FLAGS centos@$ip  docker images cortx-all & done
      ```

### 3.1 Clone Cortx-K8s framework
```
git clone -b stable https://github.com/Seagate/cortx-k8s.git
```
### 3.2 Update cluster configuration
CORTX deployment framework can be configured through a single file  cortx-k8s/k8_cortx_cloud/solution.yaml
Key configuration changes: list of worker nodes, Kubernetes namespace and disks layout

AWS EC2 instances provisioned on step 2.2 have 2 metadata and 4 data disks defined.

#### 3.2.1 Generate lists of nodes and devices
```
# Generate list of cluster nodes
aws ec2 describe-instances --filters Name=tag:Name,Values=$ClusterTag Name=instance-state-name,Values=running --query "Reservations[*].Instances[*].{IP:PrivateDnsName}" --output text > nodes.txt

#Generate list of non-OS drives, assume all instances have the same set of drives. 
ssh $SSH_FLAGS centos@$ClusterControlPlaneIP lsblk | grep -v nvme0n1 | grep nvme | sort | awk '{print $1,$4}' > devices1.txt
```

```
#Assign first disk for 3rd party applications and logs
export LogsDevice=`head -1 devices1.txt | awk '{print $1}'`

#Identify size of the drive, assumes all drives have the same size
export DiskSize=`tail -1 devices1.txt | awk '{print $2}'`i

grep -v $LogsDevice devices1.txt | awk '{print "/dev/"$1}' > devices.txt
```

#### 3.2.2 Update solution.yaml
The following command will configure 2 CVGs with 1 metadata and 2 data drives. Update this command according to the actual configuration. 
Note: number of CVGs should be equal to the amount of Motr instances (see num_inst parameter in the solution.yaml)
```
mv ./cortx-k8s/k8_cortx_cloud/solution.yaml ./cortx-k8s/k8_cortx_cloud/solution.yaml.orig

# Update list of disks and list of nodes in the solutions.yaml file.
./cortx-k8s/k8_cortx_cloud/generate-cvg-yaml.sh --nodes nodes.txt --devices devices.txt --cvgs 2 --data 2 --solution ./cortx-k8s/k8_cortx_cloud/solution.yaml.orig  --datasize $DiskSize --metadatasize $DiskSize > ./cortx-k8s/k8_cortx_cloud/solution.yaml
```
#### 3.2.2.1 Update the images tag.

- If you are using your own generated cortx-all image, update the image tag on the solution.yaml file:

- Example;
```
 images:
    cortxcontrolprov: cortx-all:2.0.0-0
    cortxcontrol: cortx-all:2.0.0-0
    cortxdataprov: cortx-all:2.0.0-0
    cortxdata: cortx-all:2.0.0-0
  ```

#### 3.2.3 Advanced configuration options
<details>
  <summary> Click here to get more details about other configuration parameters </summary>


  ##### Data and metadata protection
  Current CORTX deployment script expects identical storage layout on all nodes. In the example above we're adding 2 volume groups (CVGs) per node.

  SNS refers to data protection, and is defined as "N+K+S"
  * N - number of data chunks
  * K - number of parity chunks or a number of failed CVGs the cluster can withstand without loosing data 
  * S - number of spares. Currently no spares are supported. 
  * N+K should be smaller than the number of nodes multiplied by the number of CVGs per node.

  DIX refers to metadata protection. Current CORTX implementation supports replication for metadata. DIX configuration should be specified as 1+K+0, where K defines number of replicas.

  For example for a 3-node cluster with 2 CVGs the configuration could be:
```
        durability:
           sns: 4+2+0
           dix: 1+2+0
```
  
  ##### Number of S3 and Motr instances
  With the VM-based setup (like in this AWS example) number of Motr instances should be set to 25-33% of the total CPU cores. This value should be rounded down to the nearest Prime Number.
  In this demo we're using AWS c5.2xlarge instances with 8 cores, so the default solution.yaml sets number of instances to 2. This number could be increased on a host with more cores.

</details>

### 3.3 Copy updated framework to all worker nodes
This step will not be required in the future version
```
for ip in $ClusterIPs; do echo $ip; scp $SSH_FLAGS -r cortx-k8s centos@$ip: ; done
``` 

### 3.4 Execute pre-installation script on all worker nodes
This step will not be required in the future version
It will configure storage for the 3rd party applications and make additional preparations for the future installation.
AWS EC2 instances provisioned on step 2.2 have 1 disk for 3rd party apps (/dev/nvme7n1)

```
for ip in $ClusterIPs; do echo $ip; ssh $SSH_FLAGS centos@$ip "cd cortx-k8s/k8_cortx_cloud; sudo ./prereq-deploy-cortx-cloud.sh /dev/$LogsDevice" </dev/null & done
```

#### 3.4.1 Install Helm on the cluster control plane
Current script version doesn't deploy Helm - it will be fixed later.
```
ssh $SSH_FLAGS centos@$ClusterControlPlaneIP "curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3; chmod 700 get_helm.sh; ./get_helm.sh"
```

### 3.5 Deploy CORTX
> **NOTE**: For Motr + Hare only cortx cluster make number of s3 instance as 0 (solution -> common -> s3 -> num_inst) in cortx-k8s/k8_cortx_cloud/solution.yaml
```
ssh $SSH_FLAGS centos@$ClusterControlPlaneIP "cd cortx-k8s/k8_cortx_cloud/; ./deploy-cortx-cloud.sh"

```
<b> This step completes CORTX installation </b>

At this stage the environment should look like on this picture:
 <p align="center">
    <img src="pics/cortx-aws-k8s-after-installation.jpg">
 </p>

#### 3.5.1 Test that all pods are running and that CORTX is ready
```

ssh $SSH_FLAGS centos@$ClusterControlPlaneIP

kubectl get pod

DataPod=`kubectl get pod | grep cortx-data-pod | grep Running | awk '{print $1}' | head -1`
kubectl exec -i $DataPod -c cortx-motr-hax -- hctl status
```
In the hctl status output validate that all services are "started". It may take several minutes for s3server instances to move from "offline" to "started"

After this step proceed to section 4 - Using CORTX

If the pods are not coming up correctly or some of the hctl status services never switch to "started" - check solutions.yaml. Typos or mistakes in that file will result in a deployment failure.

### 3.6 Destroy CORTX cluster
To rollback step 3.5 and destroy the CORTX cluster run:
ssh $SSH_FLAGS centos@$ClusterControlPlaneIP "cd cortx-k8s/k8_cortx_cloud/; ./destroy-cortx-cloud.sh"

### 3.7 Stop CORTX cluster
Make sure no IO is coming to the cluster before stopping it
```
cd cortx-k8s/k8_cortx_cloud/
./shutdown-cortx-cloud.sh
```

### 3.8 Start CORTX cluster
In the current version the cluster will restart without IO errors only if there was no IO coming to the cluster prior to shutdown. This behavior will be improved in the future versions.

```
cd cortx-k8s/k8_cortx_cloud/
./start-cortx-cloud.sh
```

### 3.9 Collect debug information for support
The following command may take several minutes. It will generate logs-cortx-cloud tar file for support
```
cd cortx-k8s/k8_cortx_cloud/
./logs-cortx-cloud.sh
```

## 4 Using CORTX
We recommend to run the following commands on the Kubernetes control plane node
```
ssh $SSH_FLAGS centos@$ClusterControlPlaneIP

```

### 4.1 Use CORTX CSM (Management API) to provision an S3 account
```
# Define CSM IP in the cluster
export CSM_IP=`kubectl get svc cortx-control-clusterip-svc -ojsonpath='{.spec.clusterIP}'`

# Authenticate using CORTX credentials (as defined in solutions.yaml on step 3.2)
curl -v -d '{"username": "cortxadmin", "password": "Cortxadmin@123"}' https://$CSM_IP:8081/api/v2/login --insecure

# Create an S3 account. Replace Bearer authorization with the token returned by the login command 
curl -H 'Authorization: Bearer 286dd2db4c65427cbd961aa96ea257da' -d '{  "account_name": "gts3account",   "account_email": "gt@seagate.com",   "password": "Account1!", "access_key": "gregoryaccesskey", "secret_key": "gregorysecretkey" }' https://$CSM_IP:8081/api/v2/s3_accounts --insecure

```

### 4.2 Install and configure AWS CLI to use IAM and S3 APIs
```
sudo yum install -y unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```
```
# Export credentials for the S3 root account - these credentials were defined on step 4.1
export AWS_ACCESS_KEY_ID=gregoryaccesskey
export AWS_SECRET_ACCESS_KEY=gregorysecretkey
export AWS_DEFAULT_REGION=us-east-1
```

### 4.3 Use CORTX IAM and S3 functionality
CORTX S3 and IAM interfaces are available through multiple IPs (one IP per worker node). An external load balancer can be used to aggregate all traffic
```
# Define one of the data IPs in the cluster 
export DATA_IP=`kubectl get svc | grep cortx-data-clusterip-svc | head -1 | awk '{print $3}'`

# Create an IAM user and get credentials for this user
aws --no-verify-ssl --endpoint-url https://$DATA_IP:9443 iam create-user --user-name bob
aws --no-verify-ssl --endpoint-url https://$DATA_IP:9443 iam create-access-key --user-name bob
aws --no-verify-ssl --endpoint-url https://$DATA_IP:9443 iam list-users

# Create an S3 bucket and upload a file 
aws --no-verify-ssl --endpoint-url http://$DATA_IP:80 s3 ls
aws --no-verify-ssl --endpoint-url http://$DATA_IP:80 s3 mb s3://cortx-aws-works
aws --no-verify-ssl --endpoint-url http://$DATA_IP:80 s3 cp awscliv2.zip s3://cortx-aws-works
```

### 4.4 Test performance using s3-benchmark
```
curl -OL https://github.com/dvassallo/s3-benchmark/raw/master/build/linux-amd64/s3-benchmark
chmod +x s3-benchmark
./s3-benchmark -bucket-name s3-benchmark -endpoint http://$DATA_IP:80
```

## 5 IPs and Ports to communicate with CORTX
| Interface | IP(s) | Port(s)
| --- | --- | --- |
| Management | cortx-control-clusterip-svc K8s service | tcp/8081
| S3 | Multiple IPs (cortx-data-clusterip-svc pods) | tcp/443, tcp/80
| IAM | Multiple IPs (cortx-data-clusterip-svc pods) | tcp/9443

Tested by:

Nov 12, 2021: Rose Wambui (rose.wambui@seagate.com) and Justin Woo (justin.woo@seagate.com) 
