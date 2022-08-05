# Advanced Deployment Scenarios

This repository's root README file contains the most common user scenarios for deploying CORTX on Kubernetes. This page will document the more advanced deployment scenarios covering more complex use cases and capabilities of CORTX on Kubernetes. As much of these scenarios require manual configuration of otherwise-automated or templated artifacts, additional understanding and experience of both Kubernetes and CORTX is expected.

## Using manually-created PersistentVolumes

TODO CORTX-32209 - Need to update and enable switches in cortx-deploy-cloud.sh

> ⚠️ **WARNING:** This use case assumes advanced knowledge of PersistentVolumes, StorageClasses, PersistentVolumeClaims, and how they all interact in Kubernetes workloads. Reference https://kubernetes.io/docs/concepts/storage/persistent-volumes/ for specifics.

### Using manually-created PersistentVolumes with map heterogeneous local paths

One of the main pre-requisites of CORTX on Kubernetes is that all storage provided to CORTX from the underlying infrastructure must be homogenuous -- that is to say, the same across all Kubernetes worker nodes. However, sometimes that is not possible. This use case will document how you can provide manually created PersistentVolumes to CORTX on Kubernetes in order to achieve finer-grained control over your storage layout. 

As a warning, this does come at the cost of advanced and manually-required management of the underlying PersistentVolumes which will no longer be managed by `deploy-cortx-cloud.sh` and `destroy-cortx-cloud.sh`.

#### 1. Create a StorageClass _(if you do not already have one available for use)_

An example storage class for use by CORTX when manually creating PersistentVolumes, with the following points of configuration:
- You can select whatever unique value you desire for a name
- It is imperative that you set `volumeBindingMode` to `WaitForFirstConsumer` in order to allow Kubernetes to schedule and attach Pods correctly to the underlying physical volumes.
- The value of the `provisioner` field will vary depending upon your Kubernetes cluster setup, but the majority of the time it can be left at `kubernetes.io/no-provisioner` unless you have explicitly installed a controller to manage and provision local path PersistentVolumes.

**Example StorageClass definition**:
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: manual-block-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
```

#### 2. Create all your PersistentVolumes for use by CORTX

CORTX maps the dynamic PersistentVolumeClaims of the CORTX Data Pods to underlying PersistentVolumes based upon the `cortx.io/device-path` label. This label's value does not need to match the underlying `.spec.local.path` that the PersistentVolume actually points to. As such, you can manually map your own heterogeneous PersistentVolume paths into CORTX's requirement for homogeneous CVG device paths by applying the desired labels to each distinct PersistentVolume.

CORTX Data Pods will create PVCs based upon the `cortx.io/device-path` label and automatically do the mapping conversion between `cortx.io/device-path` to `.spec.local.path`. In other words, the CORTX Data Pods will write to the `cortx.io/device-path` inside the running container and the underlying Kubernetes worker nodes will have that data storead at `.spec.local.path`.

Keep in mind that you will need to manage your own ReclaimPolicy when manually managing PersistentVolumes in this way. This will be most important after you destroy a CORTX Cluster and before you deploy a new CORTX Cluster in its place on the same Kubernetes cluster.

**Example solution.yaml excerpt for CVG definitions**:
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

**Manual PersistentVolume template**:
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: manual-pv-{unique-id} 1️⃣
  labels:
    cortx.io/device-path: "dev-sdc" 2️⃣
spec:
  capacity:
    storage: 25Gi
  accessModes:
    - ReadWriteOnce
  volumeMode: Block
  storageClassName: manual-block-storage
  persistentVolumeReclaimPolicy: Retain
  local:
    path: /dev/mapper/xyz1 3️⃣
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - {node-name} 4️⃣
```

The only requirements in the above PersistentVolume template are:
- 1️⃣: Each PersistentVolume still requires a unique name to be defined. This is not required to map to anything referencing either the `cortx.io/device-path` or `.spec.local.path` values, but depending upon your environment it may be helpful.
- 2️⃣: A Kubernetes label on each PV with the key `cortx.io/device-path` and the value of the hostPath device path (with path-separating slashes replaced with hypens, e.g."dev-sdc") 
- 3️⃣: The underlying path which will be used by the PersistentVolume on the Kubernetes worker node. This value does not have to match the value of the `cortx.io/device-path` label reference.
- 4️⃣: A NodeAffinity selector is required for each PV to map a given PV to a specific Node. _(Note that you can create multiple sets of PVs on the same worker node, as long as you map the `cortx.io/device-path` and `.spec.local.path` values to unique values. This is detailed in the next use case below)_

As an example, I have created 16 PersistentVolumes with labels mapped to the CVG device paths above, while having the underlying disk paths be customized:
```bash 
> kubectl get pv -o custom-columns=NAME:.metadata.name,LABELS:.metadata.labels,PATH:.spec.local.path
NAME                 LABELS                              PATH
manual-pv-0703-sdc   map[cortx.io/device-path:dev-sdc]   /dev/cortx/disk0703p1
manual-pv-0703-sdd   map[cortx.io/device-path:dev-sdd]   /dev/cortx/disk0703p2
manual-pv-0703-sde   map[cortx.io/device-path:dev-sde]   /dev/cortx/disk0703p3
manual-pv-0703-sdf   map[cortx.io/device-path:dev-sdf]   /dev/cortx/disk0703p4
manual-pv-0704-sdc   map[cortx.io/device-path:dev-sdc]   /dev/cortx/disk0704p1
manual-pv-0704-sdd   map[cortx.io/device-path:dev-sdd]   /dev/cortx/disk0704p2
manual-pv-0704-sde   map[cortx.io/device-path:dev-sde]   /dev/cortx/disk0704p3
manual-pv-0704-sdf   map[cortx.io/device-path:dev-sdf]   /dev/cortx/disk0704p4
manual-pv-0705-sdc   map[cortx.io/device-path:dev-sdc]   /dev/cortx/disk0705p1
manual-pv-0705-sdd   map[cortx.io/device-path:dev-sdd]   /dev/cortx/disk0705p2
manual-pv-0705-sde   map[cortx.io/device-path:dev-sde]   /dev/cortx/disk0705p3
manual-pv-0705-sdf   map[cortx.io/device-path:dev-sdf]   /dev/cortx/disk0705p4
manual-pv-0706-sdc   map[cortx.io/device-path:dev-sdc]   /dev/cortx/disk0706p1
manual-pv-0706-sdd   map[cortx.io/device-path:dev-sdd]   /dev/cortx/disk0706p2
manual-pv-0706-sde   map[cortx.io/device-path:dev-sde]   /dev/cortx/disk0706p3
manual-pv-0706-sdf   map[cortx.io/device-path:dev-sdf]   /dev/cortx/disk0706p4
```

#### 3. Modify deploy-cortx-cloud.sh to skip cortx-block-data deployment and use manually created StorageClass

In order to direct the [`deploy-cortx-cloud.sh`](https://github.com/Seagate/cortx-k8s/blob/integration/k8_cortx_cloud/deploy-cortx-cloud.sh) script from automatically deploying its own local block data storage, you will need to provide two environment variables to the deployment script prior to running it.

1. Set `CORTX_DEPLOY_CUSTOM_BLOCK_STORAGE` to any non-empty value to instruct the deploy script to skip creation of its own PersistentVolumes.

```bash
export CORTX_DEPLOY_CUSTOM_BLOCK_STORAGE=true
```

2. Set `CORTX_DEPLOY_CUSTOM_STORAGE_CLASS` equal to the value of your StorageClass name, defined above in Step 1. 

```bash
export CORTX_DEPLOY_CUSTOM_STORAGE_CLASS=manual-block-storage
```
#### 4. Deploy CORTX on Kubernetes 

Run [`deploy-cortx-cloud.sh`](https://github.com/Seagate/cortx-k8s/blob/integration/k8_cortx_cloud/deploy-cortx-cloud.sh) from the same shell environment in which the above two environment variables were set. You should see your manually created PersistentVolumes soon become bound to running CORTX Data Pods!

### Using manually-created PersistentVolumes to stack multiple Data Pods per Worker Node

TODO CORTX-32209 Works as expected; Just need to create manual PVs with unique names, correct labels, and local.path pointing to unique devices on each node
