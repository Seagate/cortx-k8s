# cortx

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 2.0.0-817](https://img.shields.io/badge/AppVersion-2.0.0--817-informational?style=flat-square)

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
| clusterDomain | string | `"cluster.local"` |  |
| configmap.clusterDomain | string | `"cluster.local"` |  |
| configmap.clusterId | string | `""` |  |
| configmap.clusterName | string | `"cortx-cluster"` |  |
| configmap.clusterStorageSets | object | `{}` |  |
| configmap.clusterStorageVolumes | object | `{}` |  |
| configmap.cortxControl.agent.resources.limits.cpu | string | `"500m"` |  |
| configmap.cortxControl.agent.resources.limits.memory | string | `"256Mi"` |  |
| configmap.cortxControl.agent.resources.requests.cpu | string | `"250m"` |  |
| configmap.cortxControl.agent.resources.requests.memory | string | `"128Mi"` |  |
| configmap.cortxHare.hax.resources.limits.cpu | string | `"1000m"` |  |
| configmap.cortxHare.hax.resources.limits.memory | string | `"2Gi"` |  |
| configmap.cortxHare.hax.resources.requests.cpu | string | `"250m"` |  |
| configmap.cortxHare.hax.resources.requests.memory | string | `"128Mi"` |  |
| configmap.cortxHare.haxClientEndpoints | list | `[]` |  |
| configmap.cortxHare.haxDataEndpoints | list | `[]` |  |
| configmap.cortxHare.haxServerEndpoints | list | `[]` |  |
| configmap.cortxMotr.clientEndpoints | list | `[]` |  |
| configmap.cortxMotr.clientInstanceCount | int | `0` |  |
| configmap.cortxMotr.confd.resources.limits.cpu | string | `"500m"` |  |
| configmap.cortxMotr.confd.resources.limits.memory | string | `"512Mi"` |  |
| configmap.cortxMotr.confd.resources.requests.cpu | string | `"250m"` |  |
| configmap.cortxMotr.confd.resources.requests.memory | string | `"128Mi"` |  |
| configmap.cortxMotr.confdEndpoints | list | `[]` |  |
| configmap.cortxMotr.extraConfiguration | string | `""` |  |
| configmap.cortxMotr.iosEndpoints | list | `[]` |  |
| configmap.cortxMotr.motr.resources.limits.cpu | string | `"1000m"` |  |
| configmap.cortxMotr.motr.resources.limits.memory | string | `"2Gi"` |  |
| configmap.cortxMotr.motr.resources.requests.cpu | string | `"250m"` |  |
| configmap.cortxMotr.motr.resources.requests.memory | string | `"1Gi"` |  |
| configmap.cortxMotr.rgwEndpoints | list | `[]` |  |
| configmap.cortxSecretName | string | `"cortx-secret"` |  |
| configmap.cortxSecretValues | object | `{}` |  |
| configmap.cortxStoragePaths.config | string | `"/etc/cortx"` |  |
| configmap.cortxStoragePaths.local | string | `"/etc/cortx"` |  |
| configmap.cortxStoragePaths.log | string | `"/etc/cortx/log"` |  |
| configmap.cortxVersion | string | `"unknown"` |  |
| consul.client.containerSecurityContext.client.allowPrivilegeEscalation | bool | `false` | Allow extra privileges in Consul client agent containers |
| consul.enabled | bool | `true` | Enable installation of the Consul chart |
| consul.server.containerSecurityContext.server.allowPrivilegeEscalation | bool | `false` | Allow extra privileges in Consul server agent containers |
| consul.ui.enabled | bool | `false` | Enable the Consul UI |
| cortxcontrol.agent.resources.limits.cpu | string | `"500m"` |  |
| cortxcontrol.agent.resources.limits.memory | string | `"256Mi"` |  |
| cortxcontrol.agent.resources.requests.cpu | string | `"250m"` |  |
| cortxcontrol.agent.resources.requests.memory | string | `"128Mi"` |  |
| cortxcontrol.cfgmap.mountpath | string | `"/etc/cortx/solution"` |  |
| cortxcontrol.enabled | bool | `true` |  |
| cortxcontrol.image | string | `"ghcr.io/seagate/centos:7"` |  |
| cortxcontrol.localpathpvc.mountpath | string | `"/etc/cortx"` |  |
| cortxcontrol.localpathpvc.requeststoragesize | string | `"1Gi"` |  |
| cortxcontrol.machineid.mountpath | string | `"/etc/cortx/solution/node"` |  |
| cortxcontrol.machineid.value | string | `""` |  |
| cortxcontrol.service.loadbal.enabled | bool | `true` |  |
| cortxcontrol.service.loadbal.nodePorts.https | string | `""` |  |
| cortxcontrol.service.loadbal.ports.https | int | `8081` |  |
| cortxcontrol.service.loadbal.type | string | `"NodePort"` |  |
| cortxcontrol.sslcfgmap.mountpath | string | `"/etc/cortx/solution/ssl"` |  |
| cortxha.cfgmap.mountpath | string | `"/etc/cortx/solution"` |  |
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
| cortxha.localpathpvc.mountpath | string | `"/etc/cortx"` |  |
| cortxha.localpathpvc.requeststoragesize | string | `"1Gi"` |  |
| cortxha.machineid.mountpath | string | `"/etc/cortx/solution/node"` |  |
| cortxha.machineid.value | string | `""` |  |
| cortxha.sslcfgmap.mountpath | string | `"/etc/cortx/solution/ssl"` |  |
| cortxserver.authAdmin | string | `"cortx-admin"` |  |
| cortxserver.authSecret | string | `"s3_auth_admin_secret"` |  |
| cortxserver.authUser | string | `"cortx-user"` |  |
| cortxserver.cfgmap.mountpath | string | `"/etc/cortx/solution"` |  |
| cortxserver.enabled | bool | `true` |  |
| cortxserver.extraConfiguration | string | `""` |  |
| cortxserver.hax.port | int | `22003` |  |
| cortxserver.hax.resources.limits.cpu | string | `"1000m"` |  |
| cortxserver.hax.resources.limits.memory | string | `"2Gi"` |  |
| cortxserver.hax.resources.requests.cpu | string | `"250m"` |  |
| cortxserver.hax.resources.requests.memory | string | `"128Mi"` |  |
| cortxserver.image | string | `"ghcr.io/seagate/centos:7"` |  |
| cortxserver.localpathpvc.accessmodes[0] | string | `"ReadWriteOnce"` |  |
| cortxserver.localpathpvc.mountpath | string | `"/etc/cortx"` |  |
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
| cortxserver.sslcfgmap.mountpath | string | `"/etc/cortx/solution/ssl"` |  |
| externalConsul.adminSecretName | string | `"consul_admin_secret"` |  |
| externalConsul.adminUser | string | `"admin"` |  |
| externalConsul.endpoints | list | `[]` |  |
| externalKafka.adminSecretName | string | `"kafka_admin_secret"` |  |
| externalKafka.adminUser | string | `"admin"` |  |
| externalKafka.endpoints | list | `[]` |  |
| fullnameOverride | string | `""` |  |
| kafka.containerSecurityContext.allowPrivilegeEscalation | bool | `false` | Allow extra privileges in Kafka containers |
| kafka.deleteTopicEnable | bool | `true` | Enable topic deletion |
| kafka.enabled | bool | `true` | Enable installation of the Kafka chart |
| kafka.serviceAccount.automountServiceAccountToken | bool | `false` | Allow auto mounting of the service account token |
| kafka.serviceAccount.create | bool | `true` | Enable the creation of a ServiceAccount for Kafka pods |
| kafka.transactionStateLogMinIsr | int | `2` | Overridden min.insync.replicas config for the transaction topic |
| kafka.zookeeper.containerSecurityContext.allowPrivilegeEscalation | bool | `false` | Allow extra privileges in Zookeeper containers |
| kafka.zookeeper.enabled | bool | `true` | Enable installation of the Zookeeper chart |
| kafka.zookeeper.serviceAccount.automountServiceAccountToken | bool | `false` | Allow auto mounting of the service account token |
| kafka.zookeeper.serviceAccount.create | bool | `true` | Enable the creation of a ServiceAccount for Zookeeper pods |
| nameOverride | string | `""` |  |
| platform.networkPolicy.cortxControl.podAppLabel | string | `"cortx-control-pod"` |  |
| platform.networkPolicy.cortxData.podNameLabel | string | `"cortx-data"` |  |
| platform.networkPolicy.create | bool | `false` |  |
| platform.podSecurityPolicy.create | bool | `false` |  |
| platform.rbacRole.create | bool | `true` |  |
| platform.rbacRoleBinding.create | bool | `true` |  |
| platform.services.hax.port | int | `22003` |  |
| platform.services.hax.protocol | string | `"https"` |  |
| platform.services.hax.type | string | `"ClusterIP"` |  |
| serviceAccount.annotations | object | `{}` | Custom annotations for the CORTX ServiceAccount |
| serviceAccount.automountServiceAccountToken | bool | `false` | Allow auto mounting of the service account token |
| serviceAccount.create | bool | `true` | Enable the creation of a ServiceAccount for CORTX pods |
| serviceAccount.name | string | `""` | The name of the service account to use. If not set and `create` is true, a name is generated using the fullname template |
| waitForBackends.consulLeader | bool | `true` | Wait for Consul to be ready by checking for a leader. This is configured independently of `waitForBackends.enabled`. |
| waitForBackends.enabled | bool | `true` | Wait for backend services (Consul and Kafka) to be started before creating CORTX resources |
| waitForBackends.image.registry | string | `"docker.io"` |  |
| waitForBackends.image.repository | string | `"bitnami/kubectl"` |  |
| waitForBackends.image.tag | string | `"1.24.0-debian-10-r6"` |  |
| waitForBackends.kafkaTopic | bool | `true` | Wait for Kafka to be ready by writing and deleting a per-Pod topic. This is configured independently of `waitForBackends.enabled`. |
