#!/usr/bin/env python3
from __future__ import annotations

import argparse

from perf_common import (
    ALL_PROFILE_CHOICES,
    DEFAULT_CLI_PROFILE,
    PERF_CASES,
    compare_ref_to_gold,
    expand_profile_names,
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--profile",
        choices=ALL_PROFILE_CHOICES,
        default=DEFAULT_CLI_PROFILE,
    )
    args = parser.parse_args()

    for profile_name in expand_profile_names(args.profile):
        for case_name in PERF_CASES:
            compare_ref_to_gold(case_name, profile_name)

    print("Completed local-gold vs reference perf comparisons.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
