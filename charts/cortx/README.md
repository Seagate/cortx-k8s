# cortx

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 2.0.0-859](https://img.shields.io/badge/AppVersion-2.0.0--859-informational?style=flat-square)

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
| client.image.pullPolicy | string | `"IfNotPresent"` | Client image pull policy ref: https://kubernetes.io/docs/user-guide/images/#pre-pulling-images |
| client.image.registry | string | `"ghcr.io"` | Client image registry |
| client.image.repository | string | `"seagate/cortx-data"` | Client image name |
| client.image.tag | string | Chart.AppVersion | Client image tag |
| client.instanceCount | int | `1` | Number of Client instances (containers) per replica |
| client.replicaCount | int | `1` | Number of Client replicas |
| clusterDomain | string | `"cluster.local"` | Kubernetes Cluster Domain |
| clusterId | string | Chart Release fullname | The unique ID of the CORTX cluster. |
| clusterName | string | Chart Release fullname | The name of the CORTX cluster. |
| consul.client.containerSecurityContext.client.allowPrivilegeEscalation | bool | `false` | Allow extra privileges in Consul client agent containers |
| consul.enabled | bool | `true` | Enable installation of the Consul chart |
| consul.server.containerSecurityContext.server.allowPrivilegeEscalation | bool | `false` | Allow extra privileges in Consul server agent containers |
| consul.ui.enabled | bool | `false` | Enable the Consul UI |
| cortxcontrol.agent.resources.limits.cpu | string | `"500m"` |  |
| cortxcontrol.agent.resources.limits.memory | string | `"256Mi"` |  |
| cortxcontrol.agent.resources.requests.cpu | string | `"250m"` |  |
| cortxcontrol.agent.resources.requests.memory | string | `"128Mi"` |  |
| cortxcontrol.enabled | bool | `true` |  |
| cortxcontrol.image | string | `"ghcr.io/seagate/centos:7"` |  |
| cortxcontrol.localpathpvc.requeststoragesize | string | `"1Gi"` |  |
| cortxcontrol.service.loadbal.enabled | bool | `true` |  |
| cortxcontrol.service.loadbal.nodePorts.https | string | `""` |  |
| cortxcontrol.service.loadbal.ports.https | int | `8081` |  |
| cortxcontrol.service.loadbal.type | string | `"NodePort"` |  |
| cortxdata.confd.resources.limits.cpu | string | `"500m"` |  |
| cortxdata.confd.resources.limits.memory | string | `"512Mi"` |  |
| cortxdata.confd.resources.requests.cpu | string | `"250m"` |  |
| cortxdata.confd.resources.requests.memory | string | `"128Mi"` |  |
| cortxdata.cvgs | list | `[]` |  |
| cortxdata.image | string | `"ghcr.io/seagate/centos:7"` |  |
| cortxdata.localpathpvc.accessmodes[0] | string | `"ReadWriteOnce"` |  |
| cortxdata.localpathpvc.requeststoragesize | string | `"1Gi"` |  |
| cortxdata.motr.containerGroupSize | int | `1` | The number of Motr IO containers per CORTX Data Pod. As the number of CVGs increase, this value can be increased to reduce the number of total CORTX Data Pods per Kubernetes Worker Node. |
| cortxdata.motr.extraConfiguration | string | `""` |  |
| cortxdata.motr.resources.limits.cpu | string | `"1000m"` |  |
| cortxdata.motr.resources.limits.memory | string | `"2Gi"` |  |
| cortxdata.motr.resources.requests.cpu | string | `"250m"` |  |
| cortxdata.motr.resources.requests.memory | string | `"1Gi"` |  |
| cortxdata.nodes | list | `[]` |  |
| cortxdata.persistentStorage.accessModes[0] | string | `"ReadWriteMany"` |  |
| cortxdata.persistentStorage.volumeMode | string | `"Block"` |  |
| cortxdata.replicas | int | `3` |  |
| cortxdata.storageClassName | string | `"local-block-storage"` |  |
| cortxha.enabled | bool | `true` |  |
| cortxha.fault_tolerance.resources.limits.cpu | string | `"500m"` |  |
| cortxha.fault_tolerance.resources.limits.memory | string | `"1Gi"` |  |
| cortxha.fault_tolerance.resources.requests.cpu | string | `"250m"` |  |
| cortxha.fault_tolerance.resources.requests.memory | string | `"128Mi"` |  |
| cortxha.health_monitor.resources.limits.cpu | string | `"500m"` |  |
| cortxha.health_monitor.resources.limits.memory | string | `"1Gi"` |  |
| cortxha.health_monitor.resources.requests.cpu | string | `"250m"` |  |
| cortxha.health_monitor.resources.requests.memory | string | `"128Mi"` |  |
| cortxha.image | string | `"ghcr.io/seagate/centos:7"` |  |
| cortxha.k8s_monitor.resources.limits.cpu | string | `"500m"` |  |
| cortxha.k8s_monitor.resources.limits.memory | string | `"1Gi"` |  |
| cortxha.k8s_monitor.resources.requests.cpu | string | `"250m"` |  |
| cortxha.k8s_monitor.resources.requests.memory | string | `"128Mi"` |  |
| cortxha.localpathpvc.requeststoragesize | string | `"1Gi"` |  |
| cortxserver.authAdmin | string | `"cortx-admin"` |  |
| cortxserver.authUser | string | `"cortx-user"` |  |
| cortxserver.enabled | bool | `true` |  |
| cortxserver.extraConfiguration | string | `""` |  |
| cortxserver.image | string | `"ghcr.io/seagate/centos:7"` |  |
| cortxserver.localpathpvc.accessmodes[0] | string | `"ReadWriteOnce"` |  |
| cortxserver.localpathpvc.requeststoragesize | string | `"1Gi"` |  |
| cortxserver.maxStartTimeout | int | `240` |  |
| cortxserver.replicas | int | `3` |  |
| cortxserver.rgw.resources.limits.cpu | string | `"2000m"` |  |
| cortxserver.rgw.resources.limits.memory | string | `"2Gi"` |  |
| cortxserver.rgw.resources.requests.cpu | string | `"250m"` |  |
| cortxserver.rgw.resources.requests.memory | string | `"128Mi"` |  |
| cortxserver.service.count | int | `1` |  |
| cortxserver.service.nodePorts.http | string | `""` |  |
| cortxserver.service.nodePorts.https | string | `""` |  |
| cortxserver.service.ports.http | int | `80` |  |
| cortxserver.service.ports.https | int | `443` |  |
| cortxserver.service.type | string | `"ClusterIP"` |  |
| existingSecret | string | `""` | The name of an existing Secret that contains CORTX configuration secrets. Required or the Chart installation will fail. |
| externalConsul.adminSecretName | string | `"consul_admin_secret"` |  |
| externalConsul.adminUser | string | `"admin"` |  |
| externalConsul.endpoints | list | `[]` |  |
| externalKafka.adminSecretName | string | `"kafka_admin_secret"` |  |
| externalKafka.adminUser | string | `"admin"` |  |
| externalKafka.endpoints | list | `[]` |  |
| fullnameOverride | string | `""` | A name that will fully override cortx.fullname |
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
| serviceAccount.annotations | object | `{}` | Custom annotations for the CORTX ServiceAccount |
| serviceAccount.automountServiceAccountToken | bool | `false` | Allow auto mounting of the service account token |
| serviceAccount.create | bool | `true` | Enable the creation of a ServiceAccount for CORTX pods |
| serviceAccount.name | string | `""` | The name of the service account to use. If not set and `create` is true, a name is generated using the fullname template |
| storageSets | object | `{}` |  |
