#!/usr/bin/env python3
from __future__ import annotations

import argparse

from perf_common import (
    ALL_PROFILE_CHOICES,
    DEFAULT_GOLD_RUNS,
    DEFAULT_PROFILE,
    expand_profile_names,
    run_case_script,
)


SCRIPT_NAMES = [
    "gen_gold_perf_fullraster.py",
    "gen_gold_perf_geom.py",
    "gen_gold_perf_sphere2000.py",
    "gen_gold_perf_sphere2000zoom.py",
]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs", type=int, default=DEFAULT_GOLD_RUNS)
    parser.add_argument(
        "--profile",
        choices=ALL_PROFILE_CHOICES,
        default=DEFAULT_PROFILE,
    )
    args = parser.parse_args()

    for profile_name in expand_profile_names(args.profile):
        for script_name in SCRIPT_NAMES:
            print(f"Running {script_name} [{profile_name}]...")
            exit_code = run_case_script(script_name, profile_name, args.runs)
            if exit_code != 0:
                return exit_code

    print("Completed perf gold generation for all configured cases.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
