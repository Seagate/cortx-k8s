# Prerequisite use cases for deploying CORTX on Kubernetes

## Introduction

Kubernetes is a container orchestration platform that sits on top of underlying infrastructure that is mostly outside the control of Kubernetes. If incomplete or incorrect configuration is applied to the infrastructure, there's not much Kubernetes can do to correct that in most cases. As CORTX provides storage capabilities on top of Kubernetes, CORTX can only leverage Kubernetes which can only leverage the underlying infrastructure. As such, it is imperative to configure Kubernetes prior to installing CORTX in accordance with how you expect your CORTX workloads to behave.

This document is a collection of prerequisite use cases that are beneficial to consider and potentially implementing when planning your Kubernetes cluster and your CORTX deployment on that cluster.

## Persistent disk naming and node reboot support

### Background

CORTX's goal is to deliver object storage capabilities which are optimized for mass capacity local storage devices. As such, CORTX expects to write to those local storage devices and requires them to be repeatedly accessible upon Kubernetes node reboot, failure, addition, etc. CORTX leverages the built-in storage concepts of [PersistentVolumes](#tbd) to work with the underlying local storage, but in addressing the local storage devices, concerns are introduced for satisfying the expectations of node reboot support and beyond. 

The official Kubernetes [Local Persistence Volume Static Provisioner](https://github.com/kubernetes-sigs/sig-storage-local-static-provisioner) captures these concerns explicitly in their [Operations](https://github.com/kubernetes-sigs/sig-storage-local-static-provisioner/blob/master/docs/operations.md#operations) guide:

> This document provides guides on how to manage local volumes in your Kubernetes cluster. Before managing local volumes on your cluster nodes, here are some configuration requirements you must know:
>
>  The local-volume plugin expects paths to be stable, including across reboots and when disks are added or removed.

Kubernetes PersistentVolumes will work with the paths that are defined in them and Kubernetes does not have any additional context to control or dictate when that path should be updated, when it is expected to change, or if the underlying filesystem or device paths have been modified by the operating system.

As there are many solutions to this problem, the reference implementation below is only one way to handle it. Other solutions to this problem can include implementations that utilize Linux [device_mapper](https://en.wikipedia.org/wiki/Device_mapper) capabilities, however those specific implementations are outside the scope of the CORTX deployment documentation.

### Reference implementation

To that end, we have provided a `prereq-deploy-cortx-cloud.sh` script to provide a number of reference implementations for satisfying the Kubernetes prerequisites that CORTX expects. But as with most things in technology and infrastructure, there are many ways to solve this problem - so a completely different solution is perfectly viable as long as your solution adheres to the directives above.

The implementation contained in the `prereq-deploy-cortx-cloud.sh` script solves this in two ways:

1. If run with the `-p` flag on a Kubernetes worker node, the script will attempt to automatically update the `/etc/fstab` file for the device path that is passed in the required `-d` flag, which provides the script with the path of the disk or device to mount for secondary storage.
   - This is visible in the `prepCortxDeployment()` function of [prereq-deploy-cortx-cloud.sh](/k8_cortx_cloud/prereq-deploy-cortx-cloud.sh).
   - If the user has already mounted the device to the underlying nodes filesystem and confirmed that the filesystem the prereq script formats will be mounted automatically upon reboot, this step is not needed.

2. If run with the `-b` flag on a Kubernetes control plane node, the script will create Kubernetes Jobs that will create stable device paths _(across reboots and disk addition or removal)_ by creating symbolic links on each of the Kubernetes Nodes with the underlying device ids, available via `/dev/disk/by-id` and `blkid` lookups. The script only needs to be run once for initial setup and will create a secondary `solution.yaml` file for users to deploy CORTX on Kubernetes using these updated stable device paths in the appropriate places.
   - This is visible in the `symlinkBlockDevices()` function of [prereq-deploy-cortx-cloud.sh](/k8_cortx_cloud/prereq-deploy-cortx-cloud.sh).

### Examples

**Control Plane node**

The following example will create symbolic links on all the worker nodes in the cluster, in the form of `/dev/cortx/{previous-device-path}` and output an updated `solution-1234-symlink.yaml` file which can be used for input to `deploy-cortx-cloud.sh` for a reboot-supported CORTX deployment.

```bash
sudo ./prereq-deploy-cortx-cloud.sh -s solution-1234.yaml -b -c cortx
```

**Worker node**

The following example will mount the device located at `/dev/sdb`, create a filesystem on that device, and update `/etc/fstab` with the appropriate UUID mapping _(available via `/dev/disk/by-uuid`)_ which will allow the underlying operating system to provide the same device and filesystem the same path upon reboot or disk addition or removal.

```bash
sudo ./prereq-deploy-cortx-cloud.sh -d /dev/sdb -s solution-1234.yaml -p
```
