# CORTX-K8s Regression Tests

## Purpose
CORTX-K8s regression tests are designed to verify that scripts and
template files are functioning as expected.  These tests are not
comprehensive CORTX system tests.

## Test Pre-Requisites
  * Your system has kubectl access to an existing Kubernetes cluster that meets CORTX requirements.
  * There is no existing CORTX cluster running.  (The tests assume that a new CORTX cluster can be deployed.)

## Test Configuration
There is a file in this directory called `example_config.yaml`.  This defines customizations
over the standard `k8s_cortx_cloud/solution.yaml`.  Copy this file and customize it to
describe your desired CORTX cluster:

  * **nodes:** The list of hostnames CORTX should be deployed on

  * **storage:** The description of the storage to be used.

    * Note: The storage configuration must be identical for all CORTX nodes
    * local-fs: Path to the devices used for local storage.  This will be formatted as a file system on each node.
    * cvg1, cvg2, etc: Definitions of the one or more CVGs.  Each has the following two fields:

      * metadata: Device that stores metadata (there may be only one per cvg in this format)
      * data: List of devices that store data

  * See `example_config.yaml` for other configuration options

The test framework uses this file as input and generates a solution.yaml file based on the
default `k8_cortx_cloud/solution.yaml` file.

## Run the Tests
To run all deploy tests:
```
./testrunner.py -c myconf.conf -t testlists/deploy.yaml
```
Where:
  * -c specifies your [test configuration](#test-configuration)
  * -t specifies the test list to run.  (Currently only `deploy.yaml` is supported.)
