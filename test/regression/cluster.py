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
import sys
from yaml import safe_load

import utils
from utils import RemoteRun, Logger


class ClusterError(Exception):
    pass

class Cluster:

    def __init__(self, solution_files, solution_outfile=None,
                  localfs=None, logger=None):
        """Represents a CORTX cluster.

           Arguments:
               solution_files:
                      Solution.yaml file(s) that specify
                      the cluster configuration.

                      If a single solution_file is specified then
                      that file is used in place.

                      If multiple solution_files are specified
                      then the data from those files is combined
                      into a single file file, with the data from
                      the latter files overriding data in the
                      previous files.  Often "solution.example.yaml"
                      is specified as the first file in the list
                      and is overridden (or "customized") by latter
                      files.

                      The result is a new file generated at the
                      location specified by solution_outfile, or,
                      if that is not specified, then by a filename
                      in /tmp based on the input filenames.

                solution_outfile: Name of the generated solution file.
                      If multiple solution_files are specified then
                      this specifies the name of the generated
                      solution file.  If None, then a filename in
                      /tmp is generated.

                localfs: If specified, this indicates the path
                      to the local filesystem configured for the
                      Rancher local-path provisioner.  This is only
                      needed by the prereq function.

                logger: If specified, use this logger object for logging
        """
        if not logger:
            logger = Logger()
        self.logger = logger

        if isinstance(solution_files, str):
            solution_files = [solution_files]

        if len(solution_files) == 1:
            # If just a single solution file, then use it in
            # place.  Do not generate a new solution file.
            self.solution_file = solution_files[0]

        else:
            self.solution_file = self._generate_solution_yaml(solution_files, outfile=solution_outfile)
            logger.log(f"Generated solution file: {self.solution_file}")
            if not self.solution_file:
                # There was an error.  Exit.
                raise ClusterError('Failed to generate solution file')


        self.user = 'root'  # TODO: parameterize this
        self.localfs = localfs

        solution = safe_load(open(self.solution_file))
        self.solution = solution['solution']


    @staticmethod
    def _generate_solution_yaml(input_files, outfile=None, path='/tmp'):
        if not outfile:
            outfile_parts = []
            for file_ in reversed(input_files):
                file_ = os.path.basename(file_)
                if file_.endswith('.yaml'):
                    file_ = os.path.splitext(file_)[0]
                if file_ == 'solution.example':
                    file_ = 'solution'
                outfile_parts.append(file_)
            outfile = os.path.join(path, '.'.join(outfile_parts) + '.yaml')
        outf = open(outfile, 'w')
        args = ['yq', 'ea', '. as $item ireduce ({}; . * $item )'] + input_files
        child = subprocess.Popen(args, stdout=outf, stderr=subprocess.PIPE)
        child.wait()
        if child.returncode != 0:
            os.remove(outfile)
            print(child.stderr.read().decode().strip(), file=sys.stderr)
            return None
        return outfile


    @staticmethod
    def _get_k8_cortx_cloud_dir():
        return os.path.relpath(os.path.join(os.path.dirname(__file__),
                                            '../../k8_cortx_cloud'))

    def run_prereq(self):
        """Run prereq script on all nodes."""
        # First copy the prereq script and solution file to the
        # node.  Then run the script.
        if not self.localfs:
            print("Cannot run prereq-deploy-cortx-cloud.sh. "
                  "No localfs specified.")
            return

        blkdev = self.localfs
        result = 0

        print("\nRunning prereq-deploy-cortx-cloud.sh\n")

        nodes = []
        for storage_set in self.solution['storage_sets']:
            nodes += storage_set['nodes']
        for node in nodes:
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
