#!/usr/bin/env python3
"""Run all native benchmarks using the same harness options."""
import sys
from benchmark_catalog import BENCHMARKS
from benchmark_harness import main

if __name__ == "__main__":
    options = sys.argv[1:]
    for name in BENCHMARKS:
        main(name, options)
