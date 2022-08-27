# cortx

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 2.0.0-920](https://img.shields.io/badge/AppVersion-2.0.0--920-informational?style=flat-square)

CORTX is a distributed object storage system designed for great efficiency, massive capacity, and high HDD-utilization.

**Homepage:** <https://github.com/Seagate/cortx-k8s/tree/integration/charts/cortx>

## Source Code

* <https://github.com/Seagate/cortx>
* <https://github.com/Seagate/cortx-k8s>

## Requirements

Kubernetes: `>=1.22.0-0`

| Repository | Name | Version |
|------------|------|---------|
| https://charts.bitnami.com/bitnami | kafka | 16.2.7 |
| https://helm.releases.hashicorp.com | consul | 0.42.0 |

## Installation

### Downloading the Chart

Locally download the Chart files:

```bash
git clone https://github.com/Seagate/cortx-k8s.git
```

Install Chart dependencies:

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo add bitnami https://charts.bitnami.com/bitnami
helm dependency build cortx-k8s/charts/cortx
```

### Installing the Chart

To install the chart with the release name `cortx` and a configuration specified by the `myvalues.yaml` file:

```bash
helm install cortx cortx-k8s/charts/cortx -f myvalues.yaml
```

See the [Parameters](#parameters) section for details about all of the options available for configuration.

### Uninstalling the Chart

To uninstall the `cortx` release:

```bash
helm uninstall cortx
```

## Parameters

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| client.enabled | bool | `false` | Enable installation of Client instances |
| client.image.pullPolicy | string | `"IfNotPresent"` | Client image pull policy |
| client.image.registry | string | `"ghcr.io"` | Client image registry |
| client.image.repository | string | `"seagate/cortx-data"` | Client image name |
| client.image.tag | string | Chart.AppVersion | Client image tag |
| client.instanceCount | int | `1` | Number of Client instances (containers) per replica |
| client.replicaCount | int | `1` | Number of Client replicas |
| client.setupLoggingDetail | string | `""` | Configure cortx-setup Init Container logging detail levels. "default" for default (no extra details), "component" for extra component logs, and "all" for all logs. An empty value means use the global value. If all values are empty, behaves as-if "default". |
| clusterDomain | string | `"cluster.local"` | Kubernetes Cluster Domain |
| clusterId | string | A random UUID (v4) | The unique ID of the CORTX cluster. |
| clusterName | string | Chart Release fullname | The name of the CORTX cluster. |
| consul.client.containerSecurityContext.client.allowPrivilegeEscalation | bool | `false` | Allow extra privileges in Consul client agent containers |
| consul.client.resources.limits | object | `{"cpu":"500m","memory":"500Mi"}` | Client resource limits. Default values are based on a typical VM deployment and should be tuned as needed. |
| consul.client.resources.requests | object | `{"cpu":"200m","memory":"200Mi"}` | Client resource requests. Default values are based on a typical VM deployment and should be tuned as needed. |
| consul.enabled | bool | `true` | Enable installation of the Consul chart |
| consul.server.containerSecurityContext.server.allowPrivilegeEscalation | bool | `false` | Allow extra privileges in Consul server agent containers |
| consul.server.resources.limits | object | `{"cpu":"500m","memory":"500Mi"}` | Server resource limits. Default values are based on a typical VM deployment and should be tuned as needed. |
| consul.server.resources.requests | object | `{"cpu":"200m","memory":"200Mi"}` | Server resource requests. Default values are based on a typical VM deployment and should be tuned as needed. |
| consul.ui.enabled | bool | `false` | Enable the Consul UI |
| control.agent.resources.limits | object | `{"cpu":"500m","memory":"256Mi"}` | The resource limits for the Control Agent containers and processes |
| control.agent.resources.requests | object | `{"cpu":"250m","memory":"128Mi"}` | The resource requests for the Control Agent containers and processes |
| control.certificateSecret | string | `""` | Name of Secret that contains the certificate |
| control.certificateSecretKey | string | `""` | Name of Secret key that contains the certificate |
| control.enabled | bool | `true` | Enable installation of Control instances |
| control.image.pullPolicy | string | `"IfNotPresent"` | Control image pull policy |
| control.image.registry | string | `"ghcr.io"` | Control image registry |
| control.image.repository | string | `"seagate/cortx-control"` | Control image name |
| control.image.tag | string | Chart.AppVersion | Control image tag |
| control.replicaCount | int | `1` | Number of Control replicas |
| control.service.nodePorts.https | string | `""` | Node port for HTTPS for LoadBalancer and NodePort service types |
| control.service.ports.https | int | `8081` | Control API service HTTPS port |
| control.service.type | string | `"ClusterIP"` | Kubernetes service type |
| control.setupLoggingDetail | string | `""` | Configure cortx-setup Init Container logging detail levels. "default" for default (no extra details), "component" for extra component logs, and "all" for all logs. An empty value means use the global value. If all values are empty, behaves as-if "default". |
| data.blockDevicePersistence.accessModes | list | `["ReadWriteOnce"]` | Persistent volume access modes |
| data.blockDevicePersistence.storageClass | string | `""` | Persistent Volume storage class |
| data.blockDevicePersistence.volumeMode | string | `"Block"` | Persistent volume mode |
| data.confd.resources.limits | object | `{"cpu":"500m","memory":"512Mi"}` | The resource limits for the Motr confd containers and processes |
| data.confd.resources.requests | object | `{"cpu":"250m","memory":"128Mi"}` | The resource requests for the Motr confd containers and processes |
| data.extraConfiguration | string | `""` | Extra configuration, as a multiline string, to be appended to the Motr configuration. Template expressions are allowed. The result is appended to the end of the computed configuration. |
| data.image.pullPolicy | string | `"IfNotPresent"` | Data image pull policy |
| data.image.registry | string | `"ghcr.io"` | Data image registry |
| data.image.repository | string | `"seagate/cortx-data"` | Data image name |
| data.image.tag | string | Chart.AppVersion | Data image tag |
| data.ios.resources.limits | object | `{"cpu":"1000m","memory":"2Gi"}` | The resource limits for the Motr IOS containers and processes |
| data.ios.resources.requests | object | `{"cpu":"250m","memory":"1Gi"}` | The resource requests for the Motr IOS containers and processes |
| data.persistence.accessModes | list | `["ReadWriteOnce"]` | Persistent volume access modes |
| data.persistence.size | string | `"1Gi"` | Persistent volume size |
| data.replicaCount | int | `1` | Number of Data replicas |
| data.setupLoggingDetail | string | `""` | Configure cortx-setup Init Container logging detail levels. "default" for default (no extra details), "component" for extra component logs, and "all" for all logs. An empty value means use the global value. If all values are empty, behaves as-if "default". |
| existingSecret | string | `""` | The name of an existing Secret that contains CORTX configuration secrets. Required or the Chart installation will fail. |
| externalConsul.adminSecretName | string | `"consul_admin_secret"` |  |
| externalConsul.adminUser | string | `"admin"` |  |
| externalConsul.endpoints | list | `[]` |  |
| externalKafka.adminSecretName | string | `"kafka_admin_secret"` |  |
| externalKafka.adminUser | string | `"admin"` |  |
| externalKafka.endpoints | list | `[]` |  |
| fullnameOverride | string | `""` | A name that will fully override cortx.fullname |
| global.cortx.image.pullPolicy | string | `""` | CORTX image pull policy. Overrides CORTX component `image.pullPolicy`. |
| global.cortx.image.registry | string | `""` | CORTX container image registry. Overrides CORTX component `image.registry`. |
| global.cortx.image.tag | string | `""` | CORTX image tag. Overrides CORTX component `image.tag`. |
| global.cortx.setupLoggingDetail | string | `""` | Configure cortx-setup Init Container logging detail levels. Overridden by component settings. "default" for default (no extra details), "component" for extra component logs, and "all" for all logs. An empty value means use the component-specific value. If all values are empty, behaves as-if "default". |
| global.imageRegistry | string | `""` | Global container image registry. Overrides CORTX component `image.registry` and sub-charts (except Consul). |
| ha.enabled | bool | `true` | Enable installation of HA instances |
| ha.faultTolerance.resources.limits | object | `{"cpu":"500m","memory":"1Gi"}` | The resource limits for the HA Fault Tolerance containers and processes |
| ha.faultTolerance.resources.requests | object | `{"cpu":"250m","memory":"128Mi"}` | The resource requests for the HA Fault Tolerance containers and processes |
| ha.healthMonitor.resources.limits | object | `{"cpu":"500m","memory":"1Gi"}` | The resource limits for the HA Health Monitor containers and processes |
| ha.healthMonitor.resources.requests | object | `{"cpu":"250m","memory":"128Mi"}` | The resource requests for the HA Health Monitor containers and processes |
| ha.image.pullPolicy | string | `"IfNotPresent"` | HA image pull policy |
| ha.image.registry | string | `"ghcr.io"` | HA image registry |
| ha.image.repository | string | `"seagate/cortx-control"` | HA image name |
| ha.image.tag | string | Chart.AppVersion | HA image tag |
| ha.k8sMonitor.resources.limits | object | `{"cpu":"500m","memory":"1Gi"}` | The resource limits for the HA Kubernetes Monitor containers and processes |
| ha.k8sMonitor.resources.requests | object | `{"cpu":"250m","memory":"128Mi"}` | The resource requests for the HA Kubernetes Monitor containers and processes |
| ha.persistence.size | string | `"1Gi"` | Persistent volume size |
| ha.setupLoggingDetail | string | `""` | Configure cortx-setup Init Container logging detail levels. "default" for default (no extra details), "component" for extra component logs, and "all" for all logs. An empty value means use the global value. If all values are empty, behaves as-if "default". |
| hare.hax.ports.http.port | int | `22003` | The port number of the Hax HTTP endpoint. |
| hare.hax.ports.http.protocol | string | `"https"` | The protocol to configure the Hax HTTP endpoint as. Valid values are `http` or `https`. |
| hare.hax.resources.limits | object | `{"cpu":"1000m","memory":"2Gi"}` | Configure the resource limits for Hax containers. This applies to all Pods that run Hax containers. |
| hare.hax.resources.requests | object | `{"cpu":"250m","memory":"128Mi"}` | Configure the requested resources for all Hax containers. This applies to all Pods that run Hax containers. |
| kafka.containerSecurityContext.allowPrivilegeEscalation | bool | `false` | Allow extra privileges in Kafka containers |
| kafka.deleteTopicEnable | bool | `true` | Enable topic deletion |
| kafka.enabled | bool | `true` | Enable installation of the Kafka chart |
| kafka.serviceAccount.automountServiceAccountToken | bool | `false` | Allow auto mounting of the service account token |
| kafka.serviceAccount.create | bool | `true` | Enable the creation of a ServiceAccount for Kafka pods |
| kafka.startupProbe.enabled | bool | `true` | Enable startup probe to allow for slow Zookeeper startup |
| kafka.startupProbe.initialDelaySeconds | int | `10` | Initial delay for startup probe |
| kafka.transactionStateLogMinIsr | int | `2` | Overridden min.insync.replicas config for the transaction topic |
| kafka.zookeeper.containerSecurityContext.allowPrivilegeEscalation | bool | `false` | Allow extra privileges in Zookeeper containers |
| kafka.zookeeper.enabled | bool | `true` | Enable installation of the Zookeeper chart |
| kafka.zookeeper.serviceAccount.automountServiceAccountToken | bool | `false` | Allow auto mounting of the service account token |
| kafka.zookeeper.serviceAccount.create | bool | `true` | Enable the creation of a ServiceAccount for Zookeeper pods |
| kafka.zookeeperConnectionTimeoutMs | int | `60000` | Extend timeout for successful Zookeeper connection |
| nameOverride | string | `""` | A name that will partially override cortx.fullname |
| rbac.create | bool | `true` | Enable the creation of RBAC resources, Role and RoleBinding, for the CORTX ServiceAccount. |
| server.auth.adminAccessKey | string | `"cortx-admin"` | The admin user's Access Key |
| server.auth.adminUser | string | `"cortx-user"` | Name of the admin user that is created when initializing the cluster |
| server.certificateSecret | string | `""` | Name of Secret that contains the certificate |
| server.certificateSecretKey | string | `""` | Name of Secret key that contains the certificate |
| server.enabled | bool | `true` | Enable installation of Server instances |
| server.extraConfiguration | string | `""` | An optional multi-line string that contains extra RGW configuration settings. The string may contain template expressions, and is appended to the end of the computed configuration. |
| server.image.pullPolicy | string | `"IfNotPresent"` | Server image pull policy |
| server.image.registry | string | `"ghcr.io"` | Server image registry |
| server.image.repository | string | `"seagate/cortx-rgw"` | Server image name |
| server.image.tag | string | Chart.AppVersion | Server image tag |
| server.maxStartTimeout | int | `240` |  |
| server.persistence.accessModes | list | `["ReadWriteOnce"]` | Persistent volume access modes |
| server.persistence.size | string | `"1Gi"` | Persistent volume size |
| server.replicaCount | int | `1` | Number of Server replicas |
| server.rgw.resources.limits | object | `{"cpu":"2000m","memory":"2Gi"}` | The resource limits for the Server RGW containers and processes |
| server.rgw.resources.requests | object | `{"cpu":"250m","memory":"128Mi"}` | The resource requests for the Server RGW containers and processes |
| server.service.instanceCount | int | `1` | Number of service instances for LoadBalancer service types |
| server.service.nodePorts.http | string | `""` | Node port for S3 HTTP for LoadBalancer and NodePort service types |
| server.service.nodePorts.https | string | `""` | Node port for S3 HTTPS for LoadBalancer and NodePort service types |
| server.service.ports.http | int | `80` | RGW S3 service HTTP port |
| server.service.ports.https | int | `443` | RGW S3 service HTTPS port |
| server.service.type | string | `"ClusterIP"` | Kubernetes service type |
| server.setupLoggingDetail | string | `""` | Configure cortx-setup Init Container logging detail levels. "default" for default (no extra details), "component" for extra component logs, and "all" for all logs. An empty value means use the global value. If all values are empty, behaves as-if "default". |
| serviceAccount.annotations | object | `{}` | Custom annotations for the CORTX ServiceAccount |
| serviceAccount.automountServiceAccountToken | bool | `false` | Allow auto mounting of the service account token |
| serviceAccount.create | bool | `true` | Enable the creation of a ServiceAccount for CORTX pods |
| serviceAccount.name | string | `""` | The name of the service account to use. If not set and `create` is true, a name is generated using the fullname template |
| storageSets | list | `[]` |  |
