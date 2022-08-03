# Advanced Deployment Scenarios

This repository's root README file contains the most common user scenarios for deploying CORTX on Kubernetes. This page will document the more advanced deployment scenarios covering more complex use cases and capabilities of CORTX on Kubernetes. As much of these scenarios require manual configuration of otherwise-automated or templated artifacts, additional understanding and experience of both Kubernetes and CORTX is expected.

## Using manually-created PersistentVolumes

TODO CORTX-32209 - Need to update and enable switches in cortx-deploy-cloud.sh

Include references to https://kubernetes.io/docs/concepts/storage/persistent-volumes/ for specifics.

### Using manually-created PersistentVolumes with map heterogeneous local paths

1. Create a StorageClass

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: manual-block-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
```

2. Create all your PVs that reference that StorageClass
  - The only requirements are:
    - A Kubernetes label on each PV with the key `cortx.io/device-path` and the value of the hostPath device path (with slashes replaced with hypens, e.g."dev-sdc")
    - A NodeAffinity selector for each PV to map a given PV to a specific Node. However, you can create multiple sets of PVs on the same worker node, as long as you map the `cortx.io/device-path` and `.spec.local.path` values as detailed below.
  - The underlying path in the PVs `.spec.local.path` does not have to match the value of the `cortx.io/device-path` label reference.
  - CORTX Data Pods will create PVCs based upon the `cortx.io/device-path` label and automatically do the mapping conversion between `cortx.io/device-path` to `.spec.local.path`. In other words, the CORTX Data Pods will write to the `cortx.io/device-path` and the underlying Kubernetes worker nodes will have that data storead at `.spec.local.path`. 
  - Keep in mind you will need to manage your own ReclaimPolicy when manually managing PVs.

**solution.yaml excerpt for CVG definitions**:
```yaml
  storage_sets:
  - name: storage-set-1
    durability:
      sns: 1+0+0
      dix: 1+0+0
    container_group_size: 1
    nodes:
    - {node-names}
    storage:
    - name: cvg-01
      type: ios
      devices:
        metadata:
        - path: /dev/sdc
          size: 25Gi
        data:
        - path: /dev/sdd
          size: 25Gi
    - name: cvg-02
      type: ios
      devices:
        metadata:
        - path: /dev/sde
          size: 25Gi
        data:
        - path: /dev/sdf
          size: 25Gi
```

**Manual PersistentVolume creation**:
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: manual-pv-{unique-id}
  labels:
    cortx.io/device-path: "dev-sdc"
spec:
  capacity:
    storage: 25Gi
  accessModes:
    - ReadWriteOnce
  volumeMode: Block
  storageClassName: manual-block-storage
  persistentVolumeReclaimPolicy: Retain
  local:
    path: /dev/mapper/xyz1
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - {node-name}
```

3. Modify deploy-cortx-cloud.sh to skip cortx-block-data deployment and use manually created StorageClass

4. Run deploy-cortx-cloud.sh




### Using manually-created PersistentVolumes to stack multiple Data Pods per Worker Node

TODO CORTX-32209 Works as expected; Just need to create manual PVs with unique names, correct labels, and local.path pointing to unique devices on each node
