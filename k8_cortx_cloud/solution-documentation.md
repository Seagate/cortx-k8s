# Solution Documentation

The CORTX solution consists of all paramaters required to deploy CORTX cloud. The pre-req, deploy,
and destroy scripts parse the solution file and extract information they need to deploy and destroy
the CORTX cloud.

## 1. Namespace (solution.namespace)
   The kubernetes namespace for CORTX Control/Data to be deployed in.

## 2. Secrets (solution.secrets)
   * Name of the CORTX secret is defined in "solution.secrets.name".
   * The CORTX secret keys are defined in "solution.secrets.content" for the following components:
      * Kafka
      * Consul
      * Common
      * S3 auth
      * CSM auth
      * CSM management

## 3. Images (solution.images)
   This section contains the CORTX and third party images which are used to deploy CORTX cloud.

## 4. Common (solution.common)
   This section contains common paramaters that applies to all the CORTX data nodes.   

   * Storage provisioner path (solution.common.storage_provisioner_path): The mount point (host path)
     on the worker nodes used by local path provisioner.

   * Container path (solution.common.container_path):
      This section contains the internal CORTX container mount paths for CORTX Provisioner, Control,      
      and Data pods. These mount paths are also being used to build CORTX cluster config file:
      * Local path (solution.common.container_path.local): Storage local to the CORTX Control/Data pods.
      * Shared path (solution.common.container_path.shared): Shared between CORTX Data pods.
      * Log path (solution.common.container_path.log): This is path is for CORTX to store logs, and
        can be either local or share.
   
   * S3:

      (Placeholder for CORTX to provide info)

      * Number of S3 instances (solution.common.s3.num_inst): The number of S3 containers in the
        CORTX data pod.
      * S3 start port number (solution.common.s3.start_port_num): The port number for the first
        S3 container in the CORTX data pod.
   
   * MOTR:

      (Placeholder for CORTX to provide info)

      * Number of MOTR client instances (solution.common.motr.num_client_inst): The number of MOTR
        containers in the CORTX data pod.
      * MOTR start port number (solution.common.motr.start_port_num): The port number of the first
        MOTR container in the CORTX data pod.

   * Storage sets:
   
      (Placeholder for CORTX to provide info)

      * Storage set name (solution.common.storage_sets.name): (Placeholder for CORTX to provide info)
      * SNS durability (solution.common.storage_sets.durability.sns): (Placeholder for CORTX to provide info)
      * DIX durability (solution.common.storage_sets.durability.dix): (Placeholder for CORTX to provide info)

## 5. Storage (solution.storage)
   The metadata and data drives are defined in this section. All the drives must be the same across all
   worker nodes. A minimum of 1 CVG of type ios with one metadata drive and one data drive is required.

   (Placeholder for CORTX to provide CVG info/details)

## 6. Nodes (solution.nodes)
   This section contains information about all the worker nodes used to deploy CORTX cloud cluster. All nodes
   must have all the metadata and data drives mentioned in the "Storage" section above.
