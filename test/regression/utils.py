import datetime
import os
import subprocess  # nosec
import sys
import time


#################################################################
#
# Logger
#
################################################################

class Logger:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    CYAN = '\033[36m'
    BROWN = '\033[33m'
    PASSING = '\033[92m'
    WARNING = '\033[93m'
    FAILING = '\033[91m'
    ENDC = '\033[0m'

    def __init__(self, logfile=None):
        """Class for facilitationg test output."""
        #Key elements:
        #  * Prepend a timestamp
        #  * Support terminal colord output

        # Default is to log only things that are logged all the time
        # By raising this level you can get more verbose logging
        self.loglevel = 0
        self.shortdate = False
        self.f = None
        if logfile:
            self.f = open(logfile, 'a')

    def timestamp(self):
        if self.shortdate:
            datestr = datetime.datetime.now().strftime('%H:%M:%S')
        else:
            datestr = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        return datestr + ' '

    def log(self, s='', prefix=None, level=0, color=None, log_timestamp=True):
        if level > self.loglevel:
            return

        if not s:
            # empty string should at least print a newline
            s = ' '
        for line in s.splitlines():
            if prefix is not None:
                line = prefix + ' ' + line
            if log_timestamp:
                line = self.timestamp() + line
            if color:
                pline = color + line + Logger.ENDC
            else:
                pline = line
            print(pline)
            if self.f:
                print(line, file=self.f)

    def logpass(self, s=''):
        self.log(s, color=Logger.PASSING)

    def logfail(self, s=''):
        self.log(s, color=Logger.FAILING)

    def logwarning(self, s=''):
        self.log(s, color=Logger.WARNING)

    def logheader(self, s=''):
        self.log(s, color=Logger.HEADER)

    def logfile(self, filename, separator_width=75):
        hstr = f'Contents of {filename}'
        if len(hstr)+2 >= separator_width:
            dashstr = ''
        else:
            dashstr = '-' * (separator_width - len(hstr))
        self.log(hstr + ' ' + dashstr)
        self.log(open(filename).read())
        self.log('-'*separator_width)


class StopWatch:
    def __init__(self):
        """Simple stopwatch utility."""
        self.starttime = 0
        self.stoptime = 0

    def start(self):
        self.starttime = time.time()

    def stop(self):
        self.stoptime = time.time()

    def elapsed(self):
        return self.stoptime - self.starttime


def run(cmd, cwd=None, return_stdout=False):
    print(f"Running: {cmd}, cwd={cwd}")
    stdout = []
    proc = subprocess.Popen(cmd, cwd=cwd, stdout=subprocess.PIPE, # nosec B603
                            stderr=subprocess.STDOUT)
    while True:
        out = proc.stdout.readline().decode('utf-8')
        if not out:
            break
        sys.stdout.write(out)
        sys.stdout.flush()
        stdout.append(out)

    result = proc.wait()
    if return_stdout:
        return result, '\n'.join(stdout)
    return result


class RemoteRun:
    def __init__(self, host, user):
        """Class for facilitating running remote commands."""
        self.host = host
        self.user = user

    def test(self):
        cmd = 'date &> /dev/null'
        sys.stdout.flush()
        sys.stderr.flush()
        result = os.system(f'ssh {self.user}@{self.host} "{cmd}"')
        sys.stdout.flush()
        sys.stderr.flush()
        if result != 0:
            raise AssertionError('Cannot remote exec on '
                                 f'{self.user}@{self.host}')

    def run(self, cmd):
        cmd = f'ssh {self.user}@{self.host} "{cmd}"'
        print(f"Running: {cmd}")
        sys.stdout.flush()
        sys.stderr.flush()
        result = os.system(cmd)
        sys.stdout.flush()
        sys.stderr.flush()
        return result

    def scp(self, sourcefiles, dest):
        if isinstance(sourcefiles, list):
            sourcefiles = ' '.join(sourcefiles)
        self.run(f'mkdir -p {dest}')
        cmd = f'rsync {sourcefiles} {self.user}@{self.host}:{dest}'
        print(f"Running: {cmd}")
        sys.stdout.flush()
        sys.stderr.flush()
        result = os.system(cmd)
        sys.stdout.flush()
        sys.stderr.flush()
        return result
