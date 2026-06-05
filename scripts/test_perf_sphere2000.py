#!/usr/bin/env python3
from __future__ import annotations

import argparse

from perf_common import DEFAULT_TEST_RUNS, test_perf


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs", type=int, default=DEFAULT_TEST_RUNS)
    args = parser.parse_args()
    return test_perf("sphere2000", args.runs)


if __name__ == "__main__":
    raise SystemExit(main())
