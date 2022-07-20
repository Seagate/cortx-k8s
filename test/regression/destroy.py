#!/usr/bin/env python3

import argparse
import sys

from cluster import Cluster

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('-s', '--solution', action='append')
    args = parser.parse_args()

    cluster = Cluster(args.solution)
    result = cluster.destroy()
    sys.exit(result)
