#!/usr/bin/env python3

import sys
import json
import string
import argparse


def template():
    return {
        "AWSTemplateFormatVersion": "2010-09-09",
        "Description": "AWS CloudFormation Template for CORTX on Kubernetes. See https://github.com/Seagate/cortx-k8s/blob/main/doc/cortx-aws-k8s-installation.md for details.",
        "Parameters": {
            "SetupSize": {
                "Description": "Resource utilization to configure. \"large\" aggressively allocates memory, and requires larger amounts of RAM on nodes.",
                "Type": "String",
                "Default": "small",
                "AllowedValues": [
                    "small",
                    "large",
                ],
            },

            "DiskSizeOS": {
                "Description": "Size of OS disk in GiB.",
                "Type": "Number",
                "Default": "50"
            },
            "DiskSizeApplication": {
                "Description": "Size of disk in GiB for 3rd party applications required for normal CORTX installation. This disk is used also to store various CORTX logs -- for a long-running clusters under heavy load we recommend at least 50GB of capacity for this disk",
                "Type": "Number",
                "Default": "25"
            },
            "DiskSizeLog": {
                "Description": "Size of disk in GiB for internal logs. (Not used)",
                "Type": "Number",
                "Default": "25"
            },
            "DiskSizeMotr": {
                "Description": "Size of Motr data and metadata disks in GiB.",
                "Type": "Number",
                "Default": "25"
            },

            "VersionDeploymentRepo": {
                "Description": "Version of cortx-k8s repo to build from. Can be either a branch or tagged release.",
                "Type": "String",
                # See note below on prereq script before version bump
                "Default": "v0.0.22"
            },
            "ImageCORTXControl": {
                "Type": "String",
                "Default": "ghcr.io/seagate/cortx-all:2.0.0-642-custom-ci"
            },
            "ImageCORTXData": {
                "Type": "String",
                "Default": "ghcr.io/seagate/cortx-all:2.0.0-642-custom-ci"
            },
            "ImageCORTXServer": {
                "Type": "String",
                "Default": "ghcr.io/seagate/cortx-all:2.0.0-642-custom-ci"
            },
            "ImageCORTXHA": {
                "Type": "String",
                "Default": "ghcr.io/seagate/cortx-all:2.0.0-642-custom-ci"
            },
            "ImageCORTXClient": {
                "Type": "String",
                "Default": "ghcr.io/seagate/cortx-all:2.0.0-642-custom-ci"
            },
            "ImageOpenLDAP": {
                "Type": "String",
                "Default": "ghcr.io/seagate/symas-openldap:2.4.58"
            },
            "ImageConsul": {
                "Type": "String",
                "Default": "ghcr.io/seagate/consul:1.10.0"
            },
            "ImageKafka": {
                "Type": "String",
                "Default": "ghcr.io/seagate/kafka:3.0.0-debian-10-r7"
            },
            "ImageZookeeper": {
                "Type": "String",
                "Default": "ghcr.io/seagate/zookeeper:3.7.0-debian-10-r182"
            },
            "ImageRancher": {
                "Type": "String",
                "Default": "ghcr.io/seagate/local-path-provisioner:v0.0.20"
            },
            "ImageBusybox": {
                "Type": "String",
                "Default": "ghcr.io/seagate/busybox:latest"
            },

            "DurabilitySNS": {
                "Description": "Durability for data, of the form N+K+S.",
                "Type": "String",
                "Default": "1+0+0"
            },
            "DurabilityDIX": {
                "Description": "Durability for metadata, of the form N+K+S.",
                "Type": "String",
                "Default": "1+0+0"
            },

            "Subnet": {
                "Description": "Name of a private subnet for the cluster. Note that all nodes will reside in the same availability zone.",
                "Type": "AWS::EC2::Subnet::Id",
            },
            "SecurityGroup": {
                "Description": "Name of an existing security group with SSH (tcp/22) access from the bastion subnet.",
                "Type": "AWS::EC2::SecurityGroup::Id",
            },
            "KeyPair": {
                "Description": "Name of an existing EC2 key pair to enable SSH access to the nodes.",
                "Type": "AWS::EC2::KeyPair::KeyName",
            },
            "InstanceType": {
                "Description": "EC2 instance type.",
                "Type": "String",
                "Default": "c5.2xlarge",
                "AllowedValues": [
                    "c5.2xlarge",
                    "c5.4xlarge",
                    "c5.9xlarge"
                ],
                "ConstraintDescription": "must be a valid EC2 instance type. c5.2xlarge is sufficient for 3 node clusters."
            },

            "KubernetesToken": {
                "Description": "Token to use to bootstrap the Kubernetes cluster. Can be generated in advance by running `kubeadm token generate` on your local machine.",
                "Default": "abcdef.1234567890abcdef",
                "Type": "String",
                "AllowedPattern": "[a-z0-9]{6}\\.[a-z0-9]{16}"
            }
        },
        "Mappings": {
            "RegionMap": {
                "us-east-2": {"AMI": "ami-00f8e2c955f7ffa9b"},
                "us-east-1": {"AMI": "ami-00e87074e52e6c9f9"},
                "us-west-1": {"AMI": "ami-08d2d8b00f270d03b"},
                "us-west-2": {"AMI": "ami-0686851c4e7b1a8e1"},
                "af-south-1": {"AMI": "ami-0b761332115c38669"},
                "ap-east-1": {"AMI": "ami-09611bd6fa5dd0e3d"},
                "ap-south-1": {"AMI": "ami-0ffc7af9c06de0077"},
                "ap-northeast-1": {"AMI": "ami-0ddea5e0f69c193a4"},
                "ap-northeast-2": {"AMI": "ami-0e4214f08b51e23cc"},
                "ap-southeast-1": {"AMI": "ami-0adfdaea54d40922b"},
                "ap-southeast-2": {"AMI": "ami-03d56f451ca110e99"},
                "ca-central-1": {"AMI": "ami-0a7c5b189b6460115"},
                "eu-central-1": {"AMI": "ami-08b6d44b4f6f7b279"},
                "eu-west-1": {"AMI": "ami-04f5641b0d178a27a"},
                "eu-west-2": {"AMI": "ami-0b22fcaf3564fb0c9"},
                "eu-west-3": {"AMI": "ami-072ec828dae86abe5"},
                "eu-south-1": {"AMI": "ami-0fe3899b62205176a"},
                "eu-north-1": {"AMI": "ami-0358414bac2039369"},
                "me-south-1": {"AMI": "ami-0ac17dcdd6f6f4eb6"},
                "sa-east-1": {"AMI": "ami-02334c45dd95ca1fc"}
            }
        },
        "Resources": {
            "NodeTemplate": {
                "Type": "AWS::EC2::LaunchTemplate",
                "Properties": {
                    "LaunchTemplateData": {
                        "ImageId": {
                            "Fn::FindInMap": [
                                "RegionMap",
                                {"Ref": "AWS::Region"},
                                "AMI"]
                        },
                        "InstanceType": {"Ref": "InstanceType"},
                        "KeyName": {"Ref": "KeyPair"},
                        "BlockDeviceMappings": [
                            {
                                "DeviceName": "/dev/sda1",
                                "Ebs": {
                                    "VolumeSize": {"Ref": "DiskSizeOS"},
                                    "DeleteOnTermination": True
                                }
                            }, {
                                "DeviceName": "/dev/sdb",
                                "Ebs": {
                                    "VolumeSize": {"Ref": "DiskSizeApplication"},
                                    "DeleteOnTermination": True
                                }
                            }, {
                                "DeviceName": "/dev/sdc",
                                "Ebs": {
                                    "VolumeSize": {"Ref": "DiskSizeLog"},
                                    "DeleteOnTermination": True
                                }
                            }
                        ]
                    }
                }
            },
        },
        "Outputs": {
            "ClusterControlPlane": {
                "Description": "IP of the k8s control plane node",
                "Value": {"Fn::GetAtt": ["ControlPlaneENI", "PrimaryPrivateIpAddress"]}
            }
        }
    }


def eni():
    return {
        "Type": "AWS::EC2::NetworkInterface",
        "Properties": {
            "SourceDestCheck": "false",
            "GroupSet": [{"Ref": "SecurityGroup"}],
            "SubnetId": {"Ref": "Subnet"}
        }
    }


def node(eni_name, userdata):
    return {
        "Type": "AWS::EC2::Instance",
        "Properties": {
            "LaunchTemplate": {
                "LaunchTemplateId": {
                    "Ref": "NodeTemplate"},
                "Version": {
                    "Fn::GetAtt": [
                        "NodeTemplate",
                        "LatestVersionNumber"]}},
            "NetworkInterfaces": [
                {"NetworkInterfaceId": {"Ref": eni_name}, "DeviceIndex": "0"}],
            "UserData": {
                "Fn::Base64": {
                    "Fn::Join": [
                        "\n",
                        userdata + ["DEPLOY_SUCCESS=true"]]
                }
            }
        },
        "CreationPolicy" : {
            "ResourceSignal" : {
                "Timeout" : "PT30M"
            }
        }
    }


def prepare(name):
    return [
        "#!/bin/bash",
        "set -xeuo pipefail",
        "env",
        "cd /root",

        "yum update -y",
        "yum install -y yum-utils git wget nvme-cli python3",

        "wget --no-verbose https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-py3-latest.tar.gz",
        "tar -xf aws-cfn-bootstrap-py3-latest.tar.gz",
        "(cd aws-cfn-bootstrap-2.0/ && python3 setup.py install)",
        "DEPLOY_SUCCESS=false",
        "function signal_cloudformation() {",
        {"Fn::Sub": "/usr/local/bin/cfn-signal --stack ${{AWS::StackName}} --resource {} --region ${{AWS::Region}} --success $DEPLOY_SUCCESS".format(name)},
        "}",
        "trap signal_cloudformation EXIT",

        "wget --no-verbose https://github.com/mikefarah/yq/releases/download/v4.19.1/yq_linux_amd64 -O /usr/bin/yq",
        "chmod +x /usr/bin/yq",

        "cat <<EOF | tee /etc/modules-load.d/containerd.conf",
        "overlay",
        "br_netfilter",
        "EOF",
        "modprobe overlay",
        "modprobe br_netfilter",

        "cat <<EOF | tee /etc/sysctl.d/99-kubernetes-cri.conf",
        "net.bridge.bridge-nf-call-iptables  = 1",
        "net.ipv4.ip_forward = 1",
        "net.bridge.bridge-nf-call-ip6tables = 1",
        "EOF",
        "sysctl --system",

        "yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo",
        "yum install -y containerd.io",
        "mkdir -p /etc/containerd",
        "containerd config default > /etc/containerd/config.toml",
        "systemctl enable containerd",
        "systemctl restart containerd",

        "cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo",
        "[kubernetes]",
        "name=Kubernetes",
        "baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\\$basearch",
        "enabled=1",
        "gpgcheck=1",
        # https://cloud.google.com/compute/docs/troubleshooting/known-issues#keyexpired
        "repo_gpgcheck=0",
        "gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg",
        "exclude=kubelet kubeadm kubectl",
        "EOF",

        "setenforce 0",
        "sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config",

        "yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes",
        "systemctl enable --now kubelet",

        # magic!
        # https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/nvme-ebs-volumes.html
        "cat <<EOF | tee /etc/udev/rules.d/99-ebs-names.rules",
        'ACTION=="add", KERNEL=="nvme[0-9]*n[0-9]*", ENV{DEVTYPE}=="disk", ATTRS{model}=="Amazon Elastic Block Store", PROGRAM="/bin/sh -c \'set -eo pipefail; /sbin/nvme id-ctrl -b /dev/%k | cut -b 3073-3075\'", SYMLINK+="%c"',
        'ACTION=="add", KERNEL=="nvme[0-9]*n[0-9]*p[0-9]*", ENV{DEVTYPE}=="partition", ATTRS{model}=="Amazon Elastic Block Store", PROGRAM="/bin/sh -c \'set -eo pipefail; /sbin/nvme id-ctrl -b /dev/%k | cut -b 3073-3075\'", SYMLINK+="%c%n"',
        'EOF',
        'udevadm control --reload-rules',
        'udevadm trigger -c add -s block',
    ]


def k8s_init():
    return [
        "cat <<EOF | tee kubeadm-config.yaml",
        "kind: ClusterConfiguration",
        "apiVersion: kubeadm.k8s.io/v1beta3",
        "kubernetesVersion: v1.23.0",
        "networking:",
        "  podSubnet: 192.168.0.0/16",
        "---",
        "kind: KubeletConfiguration",
        "apiVersion: kubelet.config.k8s.io/v1beta1",
        "cgroupDriver: cgroupfs",
        "---",
        "apiVersion: kubeadm.k8s.io/v1beta3",
        "kind: InitConfiguration",
        "bootstrapTokens:",
        {"Fn::Sub": "- token: \"${KubernetesToken}\""},
        "EOF",
        "kubeadm init --config kubeadm-config.yaml",

        "export KUBECONFIG=/etc/kubernetes/admin.conf",
        "mkdir -p /root/.kube",
        "cp /etc/kubernetes/admin.conf /root/.kube/config",
        "mkdir -p ~centos/.kube",
        "cp /etc/kubernetes/admin.conf ~centos/.kube/config",
        "chown -R $(id -u centos):$(id -g centos) ~centos/.kube",

        "sudo -u centos kubectl create -f https://docs.projectcalico.org/manifests/tigera-operator.yaml",
        "sudo -u centos kubectl create -f https://docs.projectcalico.org/manifests/custom-resources.yaml",

        "sudo -u centos kubectl taint nodes --all node-role.kubernetes.io/master-",
    ]


def k8s_join():
    return [
        {"Fn::Sub": "kubeadm join ${ControlPlaneENI.PrimaryPrivateIpAddress}:6443 --token ${KubernetesToken} --discovery-token-unsafe-skip-ca-verification"},
    ]


def cortx_prepare(cvgs, data):
    return [
        {"Fn::Sub": "git clone -b ${VersionDeploymentRepo} https://github.com/Seagate/cortx-k8s.git"},
        "mv ./cortx-k8s/k8_cortx_cloud/solution.yaml ./cortx-k8s/k8_cortx_cloud/solution.yaml.orig",
        {"Fn::Sub": "./cortx-k8s/k8_cortx_cloud/generate-cvg-yaml.sh --nodes nodes.txt --devices devices.txt --cvgs {} --data {} --solution ./cortx-k8s/k8_cortx_cloud/solution.yaml.orig  --datasize ${{DiskSizeMotr}}Gi --metadatasize ${{DiskSizeMotr}}Gi > ./cortx-k8s/k8_cortx_cloud/solution.yaml".format(cvgs, data)},
        #TODO after bump to version with https://github.com/Seagate/cortx-k8s/pull/144
        # update prereq script args. Should be:
        #     ./prereq-deploy-cortx-cloud.sh -d /dev/sdb
        "(cd cortx-k8s/k8_cortx_cloud/ && ./prereq-deploy-cortx-cloud.sh /dev/sdb)",
        "yq -i '",
        {"Fn::Sub": '  .solution.common.setup_size = "${SetupSize}"'},
        {"Fn::Sub": '| .solution.common.storage_sets.durability.sns = "${DurabilitySNS}"'},
        {"Fn::Sub": '| .solution.common.storage_sets.durability.dix = "${DurabilityDIX}"'},
        {"Fn::Sub": '| .solution.images.cortxcontrol = "${ImageCORTXControl}"'},
        {"Fn::Sub": '| .solution.images.cortxdata = "${ImageCORTXData}"'},
        {"Fn::Sub": '| .solution.images.cortxserver = "${ImageCORTXServer}"'},
        {"Fn::Sub": '| .solution.images.cortxha = "${ImageCORTXHA}"'},
        {"Fn::Sub": '| .solution.images.cortxclient = "${ImageCORTXClient}"'},
        {"Fn::Sub": '| .solution.images.openldap = "${ImageOpenLDAP}"'},
        {"Fn::Sub": '| .solution.images.consul = "${ImageConsul}"'},
        {"Fn::Sub": '| .solution.images.kafka = "${ImageKafka}"'},
        {"Fn::Sub": '| .solution.images.zookeeper = "${ImageZookeeper}"'},
        {"Fn::Sub": '| .solution.images.rancher = "${ImageRancher}"'},
        {"Fn::Sub": '| .solution.images.busybox = "${ImageBusybox}"'},
        "' cortx-k8s/k8_cortx_cloud/solution.yaml",
        "cat cortx-k8s/k8_cortx_cloud/solution.yaml",
    ]


def cortx_deploy():
    return [
        "for n in $(cat nodes.txt); do while ! kubectl wait --for=condition=Ready \"node/$n\"; do sleep 5; done; done",
        "(cd cortx-k8s/k8_cortx_cloud/ && ./deploy-cortx-cloud.sh)",
    ]


def disk_count(cvgs, data):
    # always use 1 metadata disk for now
    return cvgs * (data + 1)


def devices(disk_count):
    disk_offset = 3
    return ['/dev/sd' + x for x in string.ascii_lowercase[disk_offset:disk_offset + disk_count]]


def device_list(disk_count):
    out = ["cat <<EOF | tee devices.txt"]
    for d in devices(disk_count):
        out.append(d)
    out.append('EOF')
    return out


def node_list(worker_count):
    out = ["NODE_DOMAIN=$(cat /etc/resolv.conf | grep search | awk '{print $2}')"]
    nodes = ['Worker{}ENI'.format(i) for i in range(worker_count)]
    nodes.append('ControlPlaneENI')
    for e in nodes:
        out.append({"Fn::Sub": "NODE_IP=${{{}.PrimaryPrivateIpAddress}}".format(e)})
        out.append("SHORT_NAME=ip-$(echo \"$NODE_IP\" | sed 's/\./-/g')")
        out.append("NODE_NAME=$SHORT_NAME.$NODE_DOMAIN")
        out.append('echo "$NODE_NAME" >> nodes.txt')
        out.append('echo "$NODE_IP" "$NODE_NAME" "$SHORT_NAME" >> /etc/hosts')
    return out


def motr_disk(device):
    return {
        "DeviceName": device,
        "Ebs": {
            "VolumeSize": {"Ref": "DiskSizeMotr"},
            "DeleteOnTermination": True
        }
    }


def control_plane(resources, worker_count, cvgs, data):
    name = 'ControlPlane'
    eni_name = name + 'ENI'

    resources[eni_name] = eni()
    resources[name] = node(eni_name,
        prepare(name) +
        node_list(worker_count) +
        device_list(disk_count(cvgs, data)) +
        k8s_init() +
        cortx_prepare(cvgs, data) +
        cortx_deploy(),
    )


def worker(resources, worker_count, cvgs, data, i):
    name = 'Worker{}'.format(i)
    eni_name = name + 'ENI'

    resources[eni_name] = eni()
    resources[name] = node(eni_name,
        prepare(name) +
        node_list(worker_count) +
        device_list(disk_count(cvgs, data)) +
        k8s_join() +
        cortx_prepare(cvgs, data)
    )


if __name__ == '__main__':
    parser = argparse.ArgumentParser('Generate a CORTX Kubernetes CloudFormation template')
    parser.add_argument('--nodes', default=3, type=int, help='Number of nodes')
    parser.add_argument('--cvgs', default=2, type=int, help='Number of CVGs')
    parser.add_argument('--data', default=2, type=int, help='Number of data disks per CVG')
    args = parser.parse_args()

    worker_count = args.nodes - 1
    assert(worker_count >= 0)
    assert(args.data > 1)
    assert(args.cvgs > 0)
    out = template()

    for d in devices(disk_count(args.cvgs, args.data)):
        out['Resources']['NodeTemplate']['Properties']['LaunchTemplateData']['BlockDeviceMappings'].append(motr_disk(d))

    control_plane(out['Resources'], worker_count, args.cvgs, args.data)
    for i in range(worker_count):
        worker(out['Resources'], worker_count, args.cvgs, args.data, i)

    json.dump(out, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write('\n')
