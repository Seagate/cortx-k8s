#!/usr/bin/python3

import argparse
import sys

from checker import Checker
from cluster import Cluster
from utils import Logger, StopWatch


def run_deploy_test(cluster, logger, checker, shutdown=False):

    sw = StopWatch()

    logger.logheader('Generated Solution File for Test')
    logger.logfile(cluster.solution_file)

    logger.log('\n\n')
    logger.logheader('-'*80)
    logger.logheader('\n\n')
    logger.logheader('\nRunning prereq-cortx-cloud.sh on each node\n')
    logger.logheader('\n\n')
    logger.logheader('-'*80)
    logger.log('\n\n')
    sw.start()
    result = cluster.run_prereq()
    sw.stop()
    checker.test_equal(0, result, 'Run prereq-cortx-cloud.sh')
    logger.log(f'TIMING: Prereq: {sw.elapsed():.0f}s', color=Logger.OKBLUE)

    logger.log('\n\n')
    logger.logheader('-'*80)
    logger.logheader('\n\n')
    logger.logheader('\nRunning deploy-cortx-cloud.sh\n')
    logger.logheader('\n\n')
    logger.logheader('-'*80)
    logger.log('\n\n')
    sw.start()
    result = cluster.deploy()
    sw.stop()
    checker.test_equal(0, result, 'Run deploy-cortx-cloud.sh')
    logger.log(f'TIMING: Deploy: {sw.elapsed():.0f}s', color=Logger.OKBLUE)

    logger.log('\n\n')
    logger.logheader('-'*80)
    logger.logheader('\n\n')
    logger.logheader('\nRunning status-cortx-cloud.sh\n')
    logger.logheader('\n\n')
    logger.logheader('-'*80)
    logger.log('\n\n')
    sw.start()
    result = cluster.status()
    sw.stop()
    checker.test_equal(0, result, 'Run status-cortx-cloud.sh')
    logger.log(f'TIMING: Status: {sw.elapsed():.0f}s', color=Logger.OKBLUE)

    if shutdown:
        logger.log('\n\n')
        logger.logheader('-'*80)
        logger.logheader('\n\n')
        logger.logheader('\nRunning shutdown-cortx-cloud.sh\n')
        logger.logheader('\n\n')
        logger.logheader('-'*80)
        logger.log('\n\n')
        sw.start()
        result = cluster.shutdown()
        sw.stop()
        checker.test_equal(0, result, 'Run shutdown-cortx-cloud.sh')
        logger.log(f'TIMING: Status: {sw.elapsed():.0f}s', color=Logger.OKBLUE)

        logger.log('\n\n')
        logger.logheader('-'*80)
        logger.logheader('\n\n')
        logger.logheader('\nRunning start-cortx-cloud.sh\n')
        logger.logheader('\n\n')
        logger.logheader('-'*80)
        logger.log('\n\n')
        sw.start()
        result = cluster.start()
        sw.stop()
        checker.test_equal(0, result, 'Run start-cortx-cloud.sh')
        logger.log(f'TIMING: Status: {sw.elapsed():.0f}s', color=Logger.OKBLUE)

    logger.log('\n\n')
    logger.logheader('-'*80)
    logger.logheader('\n\n')
    logger.logheader('\nRunning destroy-cortx-cloud.sh\n')
    logger.logheader('\n\n')
    logger.logheader('-'*80)
    logger.log('\n\n')
    sw.start()
    result = cluster.destroy()
    sw.stop()
    checker.test_equal(0, result, 'Run destroy-cortx-cloud.sh')
    logger.log(f'TIMING: Destroy: {sw.elapsed():.0f}s', color=Logger.OKBLUE)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('-c', dest='cluster')
    parser.add_argument('-s', dest='solution')
    parser.add_argument('--shutdown', action='store_true')
    parser.add_argument('--logdir', dest='logdir', default='.')
    args = parser.parse_args()

    logger = Logger()
    checker = Checker(logger)
    cluster = Cluster(args.solution, args.cluster)
    run_deploy_test(cluster, logger, checker, args.shutdown)

    sys.exit(checker.result())
