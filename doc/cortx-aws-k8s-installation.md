# CORTX on AWS and Kubernetes - Quick Install Guide
This procedure uses CloudFormation to deploy a Kubernetes-based CORTX cluster in AWS.
This templates used in this guide will
- provision EC2 instances to serve as control plane and worker nodes
- Install Kubernetes and join the nodes into a cluster
- Prepare node-local storage
- Deploy CORTX on Kubernetes

The [README](../README.md) gives general setup/installations for CORTX deployments on Kubernetes.
These instructions automate the deployment steps,
with parameters available to customize the configuration.
If you already have a suitable Kubernetes cluster,
you may wish to use the steps in the README to deploy CORTX instead.

## 1. Prerequisites

The following environment should exist in AWS prior to further deployment:
 - VPC
   - Bastion subnet
     - Security group with SSH (tcp/22) open for access
     - Bastion host
       - an SSH key for passwordless access to CORTX K8s nodes
       - AWS CLI installed and configured
     - NAT GW for outgoing Internet access from the cluster (private) subnet
   - Cluster subnet
     - Private subnet for the worker and control plane nodes
     - Currently, all nodes reside in the same availability zone
     - Security group with SSH (tcp/22) access from the Bastion subnet and traffic allowed between cluster nodes
 <p align="center">
    <img src="pics/cortx-aws-k8s-before-installation.jpg">
 </p>

## 2. Cluster Setup

CORTX requires Kubernetes cluster for installation.
 - Every node must have at least 8 cores and 16 GB of RAM.
   - this configuration is sufficient for up to 5 nodes clusters
   - clusters with higher amount of nodes may require more powerful servers (15 nodes cluster was tested using 36 cores / 72 GB of RAM instances)
 - While there should be no dependencies on the underlying OS this procedure uses with CentOS 7.9 and Kubernetes 1.23
 - In the current release, the CloudFormation template will use the following storage configuration on every node:
   - OS disk (defaults to 50GB)
   - Disk for 3rd party applications required for normal CORTX installation (25GB).
     This disk is used also to store various CORTX logs - for a long-running clusters under heavy load we recommend at least 50GB of capacity for this disk
   - Disk for internal logs (currently not in use, 25GB)
   - Disks for customers' data and metadata. Here we provision 2 disks for metadata and 4 disks for data (25GB each)
   - Disks layout (device names and sizes) must be identical on all nodes in the cluster
 - Clock on all nodes must be in sync

This procedure was tested within the following limits:
- Number of nodes in the cluster: 1 - 15
- Number of Motr (data+metadata) drives per node: 3 - 21
  - A configuration of 100+ drives per node was also tested outside of AWS

Since this procedure uses an AWS key pair,
you can use a shell variable to simplify SSH commands
```
SSH_FLAGS='-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i ~/.ssh/cortx-k8s-test.pem'
```

## 3 CORTX Installation

For the CORTX installation, you can either:
1. Use container images hosted on the [repository](https://github.com/Seagate/cortx/pkgs/container/cortx-data)
2. Generate the cortx-data, cortx-rgw, and cortx-control container images yourself, following the guidelines [here](https://github.com/Seagate/cortx/tree/main/doc/community-build/docker/cortx-all).
   You'll also need to push the container to a publicly accessible repository.

CORTX deployment framework can be configured through a single file `cortx-k8s/k8_cortx_cloud/solution.yaml`.
The README documents the available configuration options.
The CloudFormation template will set the:
- version of the `cortx-k8s` repo to use
- container versions to use
- disk layout
- data and metadata durability
- set of worker nodes
- setup size

The memory allocation and resource utilization for the nodes (setup size) must be appropriate for the instances you are deploying to.
The c5.2xlarge instances used in this guide have too little memory for the `large` configuration,
so `small` is the default in the template.

<details>
  <summary> Click here to get more details about other configuration parameters </summary>


  ##### Data and metadata protection
  The current CORTX deployment script expects identical storage layout on all nodes.
  The template by default uses 2 volume groups (CVGs) per node.

  SNS refers to data protection, and is defined as "N+K+S"
  * N - number of data chunks
  * K - number of parity chunks or a number of failed CVGs the cluster can withstand without losing data
  * S - number of spares. Currently no spares are supported.
  * N+K should be smaller than the number of nodes multiplied by the number of CVGs per node.

  DIX refers to metadata protection. Current CORTX implementation supports replication for metadata. DIX configuration should be specified as 1+K+0, where K defines number of replicas.

  For example for a 3-node cluster with 2 CVGs the configuration could be:
```
        durability:
           sns: 4+2+0
           dix: 1+2+0
```
</details>

The `k8_cortx_cloud/templates/cloudformation/cloudformation.py`
script in this repo generates CloudFormation templates in JSON form.
The template will include as parameters the setup options,
such as instance type and disk size.
By default the script generates a template with the following configuration:
3 nodes, 2 metadata and 4 data disks per node.
Since CloudFormation has limited support for changing the cardinality of nodes and disks,
the script accepts command line arguments to customize the number of nodes, disks, and CVGs and generate a new template.
The help menu accessible by calling the script with `--help` lists available options.
To get a CloudFormation template with the default config, run

    ./cloudformation.py > template.json

A pre-generated CloudFormation template is available
[here](../k8_cortx_cloud/templates/cloudformation/3node.json)
if you'd like to use the default configuration.
You can upload the template to
[CloudFormation on the AWS console](https://console.aws.amazon.com/cloudformation)
by clicking "Create Stack".
The wizard will allow you to configure the CORTX stack before deployment.
After choosing a name for the stack,
review the list of parameters.
Most of these have default values,
but it's possible to adjust the software versions in use, disk configuration, etc. here.
After making any adjustments,
continue through the wizard and create the CloudFormation stack.
CloudFormation will now provision the required resources and start the deployment process.

> If you'd like to watch the progress of the deployment,
> you can SSH to the EC2 instances provisioned for the stack,
> then view the log produced by the deployment script by running
> `journalctl -u cloud-final`.
> Passing the `-f` option will show live progress.
> The Control Plane node will show the full Kubernetes and CORTX deployment.

Once setup is complete (the default setup should take ~15 minutes),
the stack will transition to the `CREATE_COMPLETE` state.
You can then check the Outputs tab to find the private IP address of the control plane node.

You're now ready to try out CORTX!
After the deployment finishes,
the environment should look like on this picture:

 <p align="center">
    <img src="pics/cortx-aws-k8s-after-installation.jpg">
 </p>

The `cortx-k8s` repo used for the deployment
(and the `solution.yaml` used)
can be found at `/root/cortx-k8s`.

#### 3.1 Test that all pods are running and that CORTX is ready
Using the IP listed on the CloudFormation outputs tab as `$ClusterControlPlaneIP`,

```
ssh $SSH_FLAGS centos@$ClusterControlPlaneIP
sudo -i

kubectl get pod

DataPod=`kubectl get pod --field-selector=status.phase=Running --selector cortx.io/service-type=cortx-data -o jsonpath={.items[0].metadata.name}`
kubectl exec -i $DataPod -c cortx-hax -- hctl status
```
In the hctl status output validate that all services are "started". It may take several minutes for s3server instances to move from "offline" to "started"

After this step proceed to section 4 - Using CORTX

If the pods are not coming up correctly or some of the hctl status services never switch to "started" - check solutions.yaml. Typos or mistakes in that file will result in a deployment failure.

### 3.2 Destroy CORTX cluster
To rollback the deployment and destroy the CORTX cluster run:
```
cd /root/cortx-k8s/k8_cortx_cloud/
./destroy-cortx-cloud.sh
```

### 3.3 Stop CORTX cluster
Make sure no IO is coming to the cluster before stopping it
```
cd /root/cortx-k8s/k8_cortx_cloud/
./shutdown-cortx-cloud.sh
```

### 3.4 Start CORTX cluster
In the current version the cluster will restart without IO errors only if there was no IO coming to the cluster prior to shutdown. This behavior will be improved in the future versions.

```
cd /root/cortx-k8s/k8_cortx_cloud/
./start-cortx-cloud.sh
```

### 3.5 Collect debug information for support
The following command may take several minutes. It will generate logs-cortx-cloud tar file for support
```
cd /root/cortx-k8s/k8_cortx_cloud/
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
export CSM_IP=`kubectl get svc cortx-control-loadbal-svc -ojsonpath='{.spec.clusterIP}'`

# Authenticate using CORTX credentials (as defined in solutions.yaml)
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
export SERVER_IP=`kubectl get svc | grep cortx-server-clusterip-svc | head -1 | awk '{print $3}'`

# Create an IAM user and get credentials for this user
aws --no-verify-ssl --endpoint-url https://$SERVER_IP:9443 iam create-user --user-name bob
aws --no-verify-ssl --endpoint-url https://$SERVER_IP:9443 iam create-access-key --user-name bob
aws --no-verify-ssl --endpoint-url https://$SERVER_IP:9443 iam list-users

# Create an S3 bucket and upload a file
aws --no-verify-ssl --endpoint-url http://$SERVER_IP:80 s3 ls
aws --no-verify-ssl --endpoint-url http://$SERVER_IP:80 s3 mb s3://cortx-aws-works
aws --no-verify-ssl --endpoint-url http://$SERVER_IP:80 s3 cp awscliv2.zip s3://cortx-aws-works
```

### 4.4 Test performance using s3-benchmark
```
curl -OL https://github.com/dvassallo/s3-benchmark/raw/master/build/linux-amd64/s3-benchmark
chmod +x s3-benchmark
./s3-benchmark -bucket-name s3-benchmark -endpoint http://$SERVER_IP:80
```

## 5 IPs and Ports to communicate with CORTX
| Interface | IP(s) | Port(s)
| --- | --- | --- |
| Management | cortx-control-loadbal-svc K8s service | tcp/8081
| S3 | Multiple IPs (cortx-server-clusterip-svc pods) | tcp/443, tcp/80
| IAM | Multiple IPs (cortx-server-clusterip-svc pods) | tcp/9443

## Tested by:

Feb 22, 2022: Tim Shaffer (tim.shaffer@seagate.com)
Nov 12, 2021: Rose Wambui (rose.wambui@seagate.com) and Justin Woo (justin.woo@seagate.com)
