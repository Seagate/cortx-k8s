#!/usr/bin/env python3

#########################################
# testrunner.py
########################################

import yaml
import sys
import re
import os
import shlex
import subprocess  # nosec
import argparse
import time

from utils import Logger


def get_duration_str(start, stop):
    test_duration = stop-start
    if test_duration < 300:
        duration = f'{round(test_duration)} seconds'
    elif test_duration < 3600:
        duration = f'{round(test_duration/60)} minutes'
    else:
        hours = test_duration // 3600
        minutes = round(test_duration / 60)
        duration = f'{hours}h {minutes}m'
    return duration


class TestList:
    def __init__(self, source, vars_):
        """Represents a test list."""
        filename = None
        if isinstance(source, str):
            filename = source
            f = open(source)
            source = yaml.safe_load(f)
            f.close()

        if not isinstance(source, dict):
            raise TypeError('Invalid source specified.  Must be dict '
                            'or filename.')

        class Replacer:
            def __init__(self, vars_):
                self.vars = vars_

            def __call__(self, m):
                var = m.group(1)
                if var not in self.vars:
                    raise ValueError(f'{var} is not a valid replacement '
                                     'variable')
                return self.vars[var]

        self.vars = vars_
        if 'vars' in source:
            self.vars.update(source['vars'])
        self.repl = Replacer(self.vars)

        if 'file' in source['tests']:
            if filename.startswith('/'):
                fname = filename
            else:
                sourcedir = os.path.dirname(filename)
                fname = os.path.join(sourcedir, source['tests']['file'])
            f = open(fname)
            data = yaml.safe_load(f)
            f.close()
            self.tests = {}
            for name, v in data.items():
                self.tests[name] = v
        else:
            self.tests = source['tests']

        # Var replace the test commands
        for test in self.tests:
            self.tests[test]['cmd'] = self._replacevar(self.tests[test]['cmd'])

        self.testlist = []
        for test in source['testlist']:
            self.testlist.append(Test(test, self.tests[test]['id'],
                                      self.tests[test]['cmd']))

    def _replacevar(self, s):
        r = re.sub(r'{{\s*(\w+)\s*}}', self.repl, s)
        return r

    def run(self, logger=None):
        if not logger:
            logger = Logger()
        logger.log('Starting testlist.  %d tests.' % (len(self.testlist)))
        for i, test in enumerate(self.testlist):
            logger.log("%3d.  %s: %s" % (i+1, test.id, test.name))
        logger.log()

        tests_run = 0
        tests_failed = 0

        liststart = time.time()

        for i, test in enumerate(self.testlist):
            logger.logheader()
            logger.logheader('-'*50)
            logger.logheader(f'Running {i+1}/{len(self.testlist)}  '
                             f'{test.id}: {test.name}')
            logger.logheader(test.cmd)
            logger.logheader('-'*50)
            logger.logheader()

            teststart = time.time()

            result = test.run()

            teststop = time.time()
            duration = get_duration_str(teststart, teststop)

            tests_run += 1
            if result == 0:
                logger.logpass(f"Test {test.id}: {test.name} passed "
                               f"in {duration}")
            else:
                logger.logfail(f"Test {test.id}: {test.name} failed "
                               f"in {duration}")
                tests_failed += 1
            logger.log()
            logger.log()

        liststop = time.time()
        duration = get_duration_str(liststart, liststop)

        logger.log(f'\n\n  Test List Completed in {duration}\n\n')
        if tests_failed == 0:
            logger.logpass('-'*50)
            logger.logpass()
            logger.logpass(f'    {tests_run} tests passed')
            logger.logpass()
            logger.logpass('-'*50)
            return True

        else:
            logger.logfail('-'*50)
            logger.logfail()
            logger.logfail(f'    {tests_failed} of {tests_run} tests failed')
            logger.logfail()
            logger.logfail('-'*50)
            return False


class Test:
    def __init__(self, name, id_, cmd):
        """Represents a single regression test."""
        #Parameters:
        #  * name of the test
        #  * test id (e.g. TEST-DEPLOY-0001)
        #  * cmd to run -- any executable
        self.name = name
        self.id = id_
        self.cmd = cmd

    def run(self):
        proc = subprocess.Popen(shlex.split(self.cmd), stdout=subprocess.PIPE, # nosec B603
                                stderr=subprocess.STDOUT)
        while True:
            out = proc.stdout.readline()
            sys.stdout.write(out.decode('utf-8'))
            sys.stdout.flush()
            if not out:
                break

        result = proc.wait()
        return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('-s', '--solution-segment', required=True)
    parser.add_argument('--local-fs', default='/dev/sdb')
    parser.add_argument('-t', dest='testlist', required=True)
    args = parser.parse_args()

    vars_ = {
                  'solution': args.solution_segment,
                  'localfs': args.local_fs,
                  'test_dir': os.path.relpath(os.path.dirname(__file__)),
                  'k8_cloud_dir': os.path.relpath(os.path.join(
                                                  os.path.dirname(__file__),
                                                  '../../k8_cortx_cloud')),
           }
    testlist = TestList(args.testlist, vars_)
    tests_passed = testlist.run()
    sys.exit(0 if tests_passed else 1)
