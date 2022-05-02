# cortx

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 2.0.0-735](https://img.shields.io/badge/AppVersion-2.0.0--735-informational?style=flat-square)

CORTX is a distributed object storage system designed for great efficiency, massive capacity, and high HDD-utilization.

**Homepage:** <https://github.com/Seagate/cortx-k8s/tree/integration/charts/cortx>

## Source Code

* <https://github.com/Seagate/cortx>
* <https://github.com/Seagate/cortx-k8s>

## Requirements

Kubernetes: `>=1.22.0-0`

## Installation

### Downloading the Chart

Locally download the Chart files:

```bash
git clone https://github.com/Seagate/cortx-k8s.git
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
| serviceAccount.annotations | object | `{}` | Custom annotations for the CORTX ServiceAccount |
| serviceAccount.automountServiceAccountToken | bool | `false` | Enable/disable auto mounting of the service account token |
| serviceAccount.create | bool | `true` | Enable the creation of a ServiceAccount for CORTX pods |
| serviceAccount.name | string | `""` | The name of the service account to use. If not set and `create` is true, a name is generated using the fullname template |
