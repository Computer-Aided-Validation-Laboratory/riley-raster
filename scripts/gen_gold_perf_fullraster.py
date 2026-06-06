#!/usr/bin/env python3
from __future__ import annotations

import argparse

from perf_common import (
    ALL_PROFILE_CHOICES,
    DEFAULT_CLI_PROFILE,
    DEFAULT_GOLD_RUNS,
    expand_profile_names,
    generate_gold,
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs", type=int, default=DEFAULT_GOLD_RUNS)
    parser.add_argument(
        "--profile",
        choices=ALL_PROFILE_CHOICES,
        default=DEFAULT_CLI_PROFILE,
    )
    args = parser.parse_args()
    for profile_name in expand_profile_names(args.profile):
        exit_code = generate_gold("fullraster", profile_name, args.runs)
        if exit_code != 0:
            return exit_code
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
