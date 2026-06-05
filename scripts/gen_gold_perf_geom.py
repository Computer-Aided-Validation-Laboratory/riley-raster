#!/usr/bin/env python3
from __future__ import annotations

import argparse

from perf_common import DEFAULT_GOLD_RUNS, generate_gold


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs", type=int, default=DEFAULT_GOLD_RUNS)
    args = parser.parse_args()
    return generate_gold("geom", args.runs)


if __name__ == "__main__":
    raise SystemExit(main())
