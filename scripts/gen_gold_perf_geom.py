#!/usr/bin/env python3
from __future__ import annotations

import argparse

from perf_common import ALL_PROFILES, DEFAULT_GOLD_RUNS, DEFAULT_PROFILE, generate_gold


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs", type=int, default=DEFAULT_GOLD_RUNS)
    parser.add_argument(
        "--profile",
        choices=ALL_PROFILES,
        default=DEFAULT_PROFILE,
    )
    args = parser.parse_args()
    return generate_gold("geom", args.profile, args.runs)


if __name__ == "__main__":
    raise SystemExit(main())
