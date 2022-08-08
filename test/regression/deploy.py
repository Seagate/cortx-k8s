#!/usr/bin/env python3

import argparse
import sys

from cluster import Cluster

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('-s', '--solution', action='append', required=True)
    parser.add_argument('--local-fs')
    args = parser.parse_args()

    print(f"args = {args}")

    cluster = Cluster(args.solution, localfs=args.local_fs)
    if args.local_fs:
        result = cluster.run_prereq()
        if result != 0:
            sys.exit(1)

    result = cluster.deploy()
    sys.exit(result)
