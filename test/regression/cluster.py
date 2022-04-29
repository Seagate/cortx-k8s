##################################################
# cluster.py - Work In Progress
#
# Represents a CORTX cluster.
#
# This is used to facilitate test programming.
#
##################################################


import os
import subprocess  # nosec
from yaml import safe_load, dump

import utils
from utils import RemoteRun, Logger


class Cluster:

    def __init__(self, solution_file, cluster_file=None,
                 logger=None, logdir=None):
        """Represents a CORTX cluster."""
        if cluster_file and cluster_file.lower() == 'none':
            # Special case -- this allows for the special name
            # of "none" for the cluster file to allow tests that
            # require a cluster_file to use this value.
            cluster_file = None

        if not logger:
            logger = Logger()
        self.logger = logger

        if not solution_file:
            solution_file = os.environ.get('SOLUTION_FILE')
            if solution_file:
                print(f"Using SOLUTION_FILE {solution_file}")
            else:
                solution_file = os.path.relpath(os.path.join(
                                           os.path.dirname(__file__),
                                           '../../k8_cortx_cloud/'
                                           'solution.example.yaml'))
                print(f"No solution file specified: using {solution_file}")

        self.solution_file = solution_file
        self.user = 'root'  # TODO: parameterize this

        self.cluster_file = cluster_file
        self.cluster_data = None
        if self.cluster_file:
            f = open(self.cluster_file)
            self.cluster_data = safe_load(f)
            f.close()

            self._verify_cluster_yaml()
            self.localfs = self.cluster_data['storage']['local-fs']

            self.generate_solution_file()

        solution = safe_load(open(self.solution_file))
        self.solution = solution['solution']
        nodes = solution['solution']['nodes']
        self.nodes = [n['name'] for n in nodes.values()]

    def _verify_cluster_yaml(self):
        if not self.cluster_data['nodes']:
            raise ValueError(f"Error in {self.cluster_file}: "
                             "'nodes' not present")
        if not isinstance(self.cluster_data['nodes'], list):
            raise ValueError(f"Error in {self.cluster_file}: "
                             "'nodes' must be a list of hostnames")
        if not self.cluster_data['storage']:
            raise ValueError(f"Error in {self.cluster_file}: "
                             "'storage' not present")

        # TODO: check the structure of 'storage'
        fail = False
        for node in self.cluster_data['nodes']:
            self.logger.log(f'Testing remote access to {self.user}@{node}')
            try:
                RemoteRun(node, self.user).test()
            except AssertionError:
                self.logger.logfail(f'Cannot remote access {self.user}@{node}')
                fail = True

        if fail:
            raise AssertionError('Cannot ssh to one or more nodes.')

    def _set_cortx_version(self, solution):
        cortx_ver = self.cluster_data.get('cortx_ver')
        if cortx_ver:
            images = solution['solution']['images']
            for image in images:
                if image == 'cortxserver':
                    if 'cortx_rgw' in cortx_ver:
                        images[image] = cortx_ver['cortx_rgw']
                elif image.startswith('cortx'):
                    images[image] = cortx_ver['cortx_all']

    def _set_secrets(self, solution):
        secrets = self.cluster_data.get('secrets')
        if secrets:
            solution['solution']['secrets'] = secrets

    def _set_namespace(self, solution):
        namespace = self.cluster_data.get('namespace')
        if namespace:
            solution['solution']['namespace'] = namespace

    def _set_nodeports(self, solution):
        nodeports = self.cluster_data.get('nodePorts')
        if nodeports:
            # Allow for unspecified entries in input file
            new_nodeports = {'control': {'https': None},
                             's3': {'http': None, 'https': None}}
            if 'control' in nodeports:
                if 'https' in nodeports['control']:
                    new_nodeports['control']['https'] = \
                        nodeports['control']['https']
            if 's3' in nodeports:
                if 'https' in nodeports['s3']:
                    new_nodeports['s3']['https'] = nodeports['s3']['https']
                if 'http' in nodeports['s3']:
                    new_nodeports['s3']['http'] = nodeports['s3']['http']

            extsvc = solution['solution']['common']['external_services']
            extsvc['control']['nodePorts']['https'] = \
                new_nodeports['control']['https']
            extsvc['s3']['nodePorts']['https'] = new_nodeports['s3']['https']
            extsvc['s3']['nodePorts']['http'] = new_nodeports['s3']['http']

    def _set_nodes(self, solution):
        i = 1
        nodes = {}
        for node in self.cluster_data['nodes']:
            nodekey = f'node{i}'
            nodes[nodekey] = {'name': node}
            i += 1
        solution['solution']['nodes'] = nodes

    def _set_storage(self, solution):

        def get_device_size(blkdev):
            # TODO: parameterize user
            user = 'root'
            node = self.cluster_data['nodes'][0]
            stdout = subprocess.Popen(['ssh', f'{user}@{node}',  # nosec B602
                                       f'lsblk {blkdev}'],
                                      stdout=subprocess.PIPE).communicate()[0]
            for line in stdout.splitlines():
                line = line.decode('utf-8')
                if line.startswith('NAME'):
                    continue
                size = line.split()[3]
                return size

        solution_storage = {}
        cluster_storage = self.cluster_data.get('storage')

        for cvg in cluster_storage:
            if cvg == 'local-fs':
                continue

            solution_storage[cvg] = {'name': cvg, 'type': 'ios', 'devices': {}}
            device = solution_storage[cvg]['devices']

            metablk = cluster_storage[cvg]['metadata']
            metasize = get_device_size(metablk)
            device['metadata'] = {'device': metablk, 'size': metasize}

            device['data'] = {}
            i = 1
            for datablk in cluster_storage[cvg]['data']:
                datasize = get_device_size(datablk)
                device['data'][f'd{i}'] = {'device': datablk, 'size': datasize}
                i += 1
        solution['solution']['storage'] = solution_storage

    def generate_solution_file(self):

        generated_solution = self.cluster_data.get('generated_solution')

        if not generated_solution:
            self.logger.log("'generated_solution' field not in cluster config "
                            "file.  No new solution will be generated'")
            return

        solution = safe_load(open(self.solution_file))

        self._set_cortx_version(solution)
        self._set_secrets(solution)
        self._set_namespace(solution)
        self._set_nodeports(solution)
        self._set_nodes(solution)
        self._set_storage(solution)

        print("Writing generated solution file: " + generated_solution)
        f = open(generated_solution, 'w')
        dump(solution, f)
        f.close()

        self.solution_file = generated_solution

    @staticmethod
    def _get_k8_cortx_cloud_dir():
        return os.path.relpath(os.path.join(os.path.dirname(__file__),
                                            '../../k8_cortx_cloud'))

    def run_prereq(self):
        """Run prereq script on all nodes."""
        # First copy the prereq script and solution file to the
        # node.  Then run the script.
        if not self.cluster_data:
            print("Cannot run prereq-deploy-cortx-cloud.sh. "
                  "No cluster config file specified.")
            return

        blkdev = self.localfs
        result = 0

        print("\nRunning prereq-deploy-cortx-cloud.sh\n")

        for node in self.nodes:
            files = [
                      self.solution_file,
                      os.path.join(self._get_k8_cortx_cloud_dir(),
                                   'prereq-deploy-cortx-cloud.sh')
                    ]
            print(f"------------- prereq {node} --------------\n")
            result += RemoteRun(node, self.user).scp(
                                files, '/tmp/cortx-k8s')  # nosec B108
            result += RemoteRun(node, self.user).run(
                                f'cd /tmp/cortx-k8s; '
                                f'./prereq-deploy-cortx-cloud.sh -d {blkdev} '
                                f'-s {os.path.basename(self.solution_file)}')
            result += RemoteRun(node, self.user).run('rm -rf /tmp/cortx-k8s')
            print("\n\n")

        return result

    def deploy(self):
        cmd = ['./deploy-cortx-cloud.sh', os.path.abspath(self.solution_file)]
        result = utils.run(cmd, cwd=self._get_k8_cortx_cloud_dir())
        if result != 0:
            print("\nDeploy FAILED!\n")
        return result

    def destroy(self):
        cmd = ['./destroy-cortx-cloud.sh', os.path.abspath(self.solution_file)]
        result = utils.run(cmd, cwd=self._get_k8_cortx_cloud_dir())
        if result != 0:
            print("\nDestroy FAILED!\n")
        return result

    def shutdown(self):
        cmd = ['./shutdown-cortx-cloud.sh',
               os.path.abspath(self.solution_file)]
        result = utils.run(cmd, cwd=self._get_k8_cortx_cloud_dir())
        if result != 0:
            print("\nShutdown FAILED!\n")
        return result

    def start(self):
        cmd = ['./start-cortx-cloud.sh', os.path.abspath(self.solution_file)]
        result = utils.run(cmd, cwd=self._get_k8_cortx_cloud_dir())
        if result != 0:
            print("\nStart FAILED!\n")
        return result

    def status(self):
        cmd = ['./status-cortx-cloud.sh', os.path.abspath(self.solution_file)]
        result, stdout = utils.run(cmd, cwd=self._get_k8_cortx_cloud_dir(),
                                   return_stdout=True)
        # Scan stdout for anything but PASS
        numfails = False
        for line in stdout.splitlines():
            if 'STATUS' not in line:
                continue
            if 'PASSED' not in line:
                numfails += 1

        if result != 0 or numfails != 0:
            print(f"\nStatus FAILED!  {numfails} failed checks.\n")

            # This is a workaround until status-cortx-cloud.sh returns
            # a valid return value.  (Currently it always returns 0.)
            if result == 0:
                result = 1

        return result
