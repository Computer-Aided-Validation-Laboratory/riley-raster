#!/usr/bin/env python3
from __future__ import annotations

import argparse

from perf_common import ALL_PROFILES, DEFAULT_PROFILE, DEFAULT_TEST_RUNS, run_case_script


SCRIPT_NAMES = [
    "test_perf_fullraster.py",
    "test_perf_geom.py",
    "test_perf_sphere2000.py",
    "test_perf_sphere2000zoom.py",
]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs", type=int, default=DEFAULT_TEST_RUNS)
    parser.add_argument(
        "--profile",
        choices=ALL_PROFILES,
        default=DEFAULT_PROFILE,
    )
    args = parser.parse_args()

    exit_code = 0
    for script_name in SCRIPT_NAMES:
        print(f"Running {script_name}...")
        try:
            run_case_script(script_name, args.profile, args.runs)
        except Exception:
            exit_code = 1
            raise

    if exit_code == 0:
        print("Completed perf regression checks for all configured cases.")
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
