# Glossary for CORTX on Kubernetes

This page will serve as a clearinghouse for all terms, definitions, and acronyms critical to both the understanding of and having success with [CORTX](https://github.com/Seagate/cortx). Please feel free to add terms as needed but place them in proper alphabetical order.

## Glossary

### CORVAULT

CORVAULT is the brand name for a specific Seagate hardware product: https://www.seagate.com/products/storage/data-storage-systems/corvault/. CORVAULT generally belongs to a category of storage referred to as RBOD (reliable bunch of disks). Physically, CORVAULT is a large 4U rack enclosure which holds up to 106 devices. By virtue of firmware running inside the enclosure, CORVAULT appears to the upper-layer host (CORTX in our case) as two very large individual disks. Internally, CORVAULT does declustered erasure such that the frequency of "disk" failures seen by the host is very low (albeit when they happen, they are a large failure).

### CORTX Control Pods

CORTX Control Pods contain the APIs which are exposed to the end-user in order to maintain the CORTX control plane and are most often used to interact with IAM settings.

### CORTX Data Pods

CORTX Data Pods contain the internal APIs which are used to manage the storage and protection of data at the lowest possible level inside of a CORTX cluster.

### CORTX HA (High Availability)

CORTX HA Pods are responsible for monitoring the overall health of the CORTX cluster and notifying components of changes in system status.

### CORTX Server Pods

CORTX Server Pods contain the APIs which are exposed to the end-user in order to provide general S3 functionality - create buckets, copy objects, delete objects, delete buckets. This API layer is implemented using the Rados Gateway (RGW) interface.

### CVG (Cylinder Volume Group)

A Cylinder Volume Group, or CVG, is a collection of drives or block devices which CORTX utilizes as a unit of storage, all managed by a single Motr IO process.

### Data Devices / Drives

Block devices, HDDs, SDDs, or other types of storage devices addressable by `/dev/{device-name}` which CORTX uses to store user data.

### JBOD

JBOD stands for "Just a Bunch of Disks" and refers to a rack enclosure containing many disks which are each individually exposed to the host (CORTX in our case).

### Metadata Devices / Drives

Block devices, HDDs, SDDs, or other types of storage devices addressable by `/dev/{device-name}` which CORTX uses to store metadata about user data.

### Motr

Motr is the central storage capability inside of a CORTX cluster. It functions as a distributed object and key-value storage system targeting mass-capacity storage configurations.

### Node

This term is unfortunately overloaded in the context of CORTX on Kubernetes. It can either mean an underlying Kubernetes worker node (in general) or it can mean any single component working inside of the CORTX cluster (Data Pod, Server Pod, Control Pod, etc.). 

Context is important and required to discern when which is which. Through the https://github.com/Seagate/cortx-k8s repository, care is used to refer to Kubernetes worker nodes as "Nodes" and CORTX nodes running on Kubernetes as "Pods".

### POD
TODO: Do we need a definition of POD? Or is that K8s 101? If the latter, then can we add, or link to, a basic K8s glossary?

### Rados Gateway (RGW)

This is the component which provides all necessary S3 functionality in a CORTX cluster through a central gateway interface.

### RBOD

RBOD means "Reliable Bunch of Drives". Physically it is similar to JBOD but interally it uses erasure or RAID to add better data protection by distributing data across multiple disks and protecting it with parity. Logically, an RBOD will therefore export itself to the host (CORTX in our case) as a smaller number of drives which are much larger in capacity. For example, imagine an RBOD of 100 drives. For high availability reasons, most RBODs will use dual ported drives and will split themselves into two groups of disks. A pair of controllers in the RBOD will provide active-passive access to each pair such that the drives served by the active controller can be instead served by the passive controller in the case of a failure of the active controller. Further imagine, that the RBOD is configured for 8+2 parity within each group of drives. Therefore, to the upper level host, this RBOD will logically appear as just two large drives, each of which being the aggregate size of 40 drives (i.e. 8+2 on 50 drives will use 20% of capacity for parity thereby leaving 80% of capacity for host data).

### Storage Set

A Storage Set is the common unit of deployment and scalability for CORTX and its mapping to the underlying infrastructure. A given Kubernetes worker node can only belong to a single Solution Set for the lifetime of a CORTX cluster. A Storage Set is defined as a collection of Kubernetes worker nodes and CVGs.
