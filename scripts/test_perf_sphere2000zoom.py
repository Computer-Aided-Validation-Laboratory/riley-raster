#!/usr/bin/env python3
from __future__ import annotations

import argparse

from perf_common import (
    ALL_PROFILE_CHOICES,
    DEFAULT_CLI_PROFILE,
    DEFAULT_TEST_RUNS,
    expand_profile_names,
    test_perf,
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs", type=int, default=DEFAULT_TEST_RUNS)
    parser.add_argument(
        "--profile",
        choices=ALL_PROFILE_CHOICES,
        default=DEFAULT_CLI_PROFILE,
    )
    args = parser.parse_args()
    exit_code = 0
    for profile_name in expand_profile_names(args.profile):
        case_exit = test_perf("sphere2000zoom", profile_name, args.runs)
        if case_exit != 0:
            exit_code = 1
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
