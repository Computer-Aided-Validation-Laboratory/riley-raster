#!/usr/bin/env python3
from __future__ import annotations

import argparse

from perf_common import (
    ALL_PROFILE_CHOICES,
    DEFAULT_PROFILE,
    DEFAULT_TEST_RUNS,
    expand_profile_names,
    run_case_script,
)


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
        choices=ALL_PROFILE_CHOICES,
        default=DEFAULT_PROFILE,
    )
    args = parser.parse_args()

    exit_code = 0
    for profile_name in expand_profile_names(args.profile):
        for script_name in SCRIPT_NAMES:
            print(f"Running {script_name} [{profile_name}]...")
            case_exit = run_case_script(script_name, profile_name, args.runs)
            if case_exit != 0:
                exit_code = 1

    if exit_code == 0:
        print("Completed perf regression checks for all configured cases.")
    else:
        print("Completed perf regression checks with one or more red cases.")
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
