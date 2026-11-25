# --------------------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
# --------------------------------------------------------------------------------------
from __future__ import annotations

import argparse
import importlib
import sys

from riley.pydemos import __all__ as DEMO_NAMES

_DEMOS_WITH_OPTIONS = {
    "demo0b_procedural_quickstart",
    "demo1b_procedural_sphere",
    "demo2d_rabbit_procedural",
}


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="python -m riley",
        epilog=f"Available demos: {', '.join(DEMO_NAMES)}.",
    )
    parser.add_argument(
        "command",
        choices=[*DEMO_NAMES, "test"],
        metavar="command",
        help="Demo name to run, or 'test' to run the packaged pytest suite.",
    )
    parser.add_argument("options", nargs=argparse.REMAINDER, help=argparse.SUPPRESS)
    args = parser.parse_args()

    if args.command == "test":
        import pytest

        pytest_args = ["-s", "--pyargs", "riley.pytests", *args.options]
        raise SystemExit(pytest.main(pytest_args))

    if args.command not in _DEMOS_WITH_OPTIONS:
        # Argparse may consume a trailing `--` before filling the remainder.
        options = sys.argv[sys.argv.index(args.command, 1) + 1:]
        if options in (["-h"], ["--help"]):
            argparse.ArgumentParser(
                prog=f"{parser.prog} {args.command}",
                description="This demo takes no arguments.",
            ).print_help()
            parser.exit()
        if options:
            parser.error(f"{args.command} does not accept arguments: {' '.join(options)}")

    demo_module = importlib.import_module(f"riley.pydemos.{args.command}")
    if args.command in _DEMOS_WITH_OPTIONS:
        demo_module.main(args.options)
    else:
        demo_module.main()


if __name__ == "__main__":
    main()
