#!/usr/bin/env python3

import argparse
import sys

from cluster import Cluster

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('-s', '--solution', action='append', required=True)
    args = parser.parse_args()

    Cluster(args.solution)
