#!/usr/bin/python3

import argparse
import sys

from cluster import Cluster

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('-s', dest='solution')
    parser.add_argument('-c', dest='cluster')
    args = parser.parse_args()

    cluster = Cluster(args.solution, args.cluster)
    result = cluster.destroy()
    sys.exit(result)
