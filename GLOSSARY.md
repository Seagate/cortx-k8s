# Glossary for CORTX on Kubernetes

This page will serve as a clearinghouse for all terms, definitions, and acronyms critical to both the understanding of and having success with [CORTX](https://github.com/Seagate/cortx).

## Glossary

### CORVAULT

TODO CORTX-specific definition required.

### CORTX Control

CORTX Control Pods contain the APIs which are exposed to the end-user in order to maintain the CORTX control plane and are most often used to interact with IAM settings.

### CORTX Data

CORTX Data Pods contain the internal APIs which are used to manage the storage and protection of data at the lowest possible level inside of a CORTX cluster.

### CORTX HA

CORTX HA Pods are responsible for monitoring the overall health of the CORTX cluster and notifying components of changes in system status.
### CORTX Server

CORTX Server Pods contain the APIs which are exposed to the end-user in order to provide general S3 functionality - create buckets, copy objects, delete objects, delete buckets. This API layer is implemented using the Rados Gateway (RGW) interface.

### CVG
### Cylinder Volume Group

A Cylinder Volume Group, or CVG, is a collection of drives or block devices which CORTX utilizes as a unit of storage, all managed by a single Motr IO process.

### Data Devices
### Data Drives

Block devices, HDDs, SDDs, or other types of storage devices addressable by `/dev/{device-name}` which CORTX uses to store user data.

### JBOD

TODO CORTX-specific definition required.

### Metadata Devices
### Metadata Drives

Block devices, HDDs, SDDs, or other types of storage devices addressable by `/dev/{device-name}` which CORTX uses to store metadata about user data.

### Motr

Motr is the central storage capability inside of a CORTX cluster. It functions as a distributed object and key-value storage system targeting mass-capacity storage configurations.

### Node

This term is unfortunately overloaded in the context of CORTX on Kubernetes. It can either mean an underlying Kubernetes worker node (in general) or it can mean any single component working inside of the CORTX cluster (Data Pod, Server Pod, Control Pod, etc.). 

Context is important and required to discern when which is which. Through the https://github.com/Seagate/cortx-k8s repository, care is used to refer to Kubernetes worker nodes as "Nodes" and CORTX nodes running on Kubernetes as "Pods".

### Rados Gateway
### RGW

This is the component which provides all necessary S3 functionality in a CORTX cluster through a central gateway interface.

### RBOD

TODO CORTX-specific definition required.

### Storage Set

A Storage Set is the common unit of deployment and scalability for CORTX and its mapping to the underlying infrastructure. A given Kubernetes worker node can only belong to a single Solution Set for the lifetime of a CORTX cluster. A Storage Set is defined as a collection of Kubernetes worker nodes and CVGs.
