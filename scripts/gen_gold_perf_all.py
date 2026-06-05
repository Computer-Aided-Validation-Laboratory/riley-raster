#!/usr/bin/env python3
from __future__ import annotations

import argparse

from perf_common import ALL_PROFILES, DEFAULT_GOLD_RUNS, DEFAULT_PROFILE, run_case_script


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
        choices=ALL_PROFILES,
        default=DEFAULT_PROFILE,
    )
    args = parser.parse_args()

    for script_name in SCRIPT_NAMES:
        print(f"Running {script_name}...")
        run_case_script(script_name, args.profile, args.runs)

    print("Completed perf gold generation for all configured cases.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
