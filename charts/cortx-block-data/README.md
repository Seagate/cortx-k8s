# cortx-block-data

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

CORTX block device provider for object storage

**Homepage:** <https://github.com/Seagate/cortx-k8s/tree/integration/charts/cortx-block-data>

## Source Code

* <https://github.com/Seagate/cortx>
* <https://github.com/Seagate/cortx-k8s>

## Installation

### Downloading the Chart

Locally download the Chart files:

```bash
git clone https://github.com/Seagate/cortx-k8s.git
```

### Installing the Chart

To install the chart with the release name `cortx-block-data` and a configuration specified by the `myvalues.yaml` file:

```bash
helm install cortx-block-data cortx-k8s/charts/cortx-block-data -f myvalues.yaml
```

See the [Parameters](#parameters) section for details about all of the options available for configuration.

### Uninstalling the Chart

To uninstall the `cortx-block-data` release:

```bash
helm uninstall cortx-block-data
```

## Parameters

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| cortxblkdata.blockDevicePaths | list | `[]` |  |
| cortxblkdata.nodes | list | `[]` |  |
| cortxblkdata.storage.volumeMode | string | `"Block"` |  |
| cortxblkdata.storageClassName | string | `"local-block-storage"` |  |
