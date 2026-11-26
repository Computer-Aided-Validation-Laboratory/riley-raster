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

_DEMO_FUNCS = {
    "demo00_quickstart": "riley.pydemos.demo00_quickstart",
    "demo00b_procedural_quickstart": "riley.pydemos.demo00b_procedural_quickstart",
    "demo01_sphere": "riley.pydemos.demo01_sphere",
    "demo01b_procedural_sphere": "riley.pydemos.demo01b_procedural_sphere",
    "demo02a_rabbits_mono": "riley.pydemos.demo02a_rabbits_mono",
    "demo02b_rabbits_rgb": "riley.pydemos.demo02b_rabbits_rgb",
    "demo02c_rabbits_fields": "riley.pydemos.demo02c_rabbits_fields",
    "demo02d_rabbit_procedural": "riley.pydemos.demo02d_rabbit_procedural",
    "demo03_dicuq": "riley.pydemos.demo03_dicuq",
    "demo03_dicuq_from_exodus": "riley.pydemos.demo03_dicuq_from_exodus",
    "demo04_stereocal": "riley.pydemos.demo04_stereocal",
    "demo05_cameramodels": "riley.pydemos.demo05_cameramodels",
    "demo06_featurezoo": "riley.pydemos.demo06_featurezoo",
    "demo07_shaderpipe_quickstart": "riley.pydemos.demo07_shaderpipe_quickstart",
    "demo08_shaderpipe_gallery": "riley.pydemos.demo08_shaderpipe_gallery",
    "demo09_diciruq": "riley.pydemos.demo09_diciruq",
    "demo10_sphere_lit": "riley.pydemos.demo10_sphere_lit",
}
_PROCEDURAL_DEMOS = {
    "demo00b_procedural_quickstart",
    "demo01b_procedural_sphere",
    "demo02d_rabbit_procedural",
}


def main() -> None:
    parser = argparse.ArgumentParser(prog="python -m riley")
    parser.add_argument(
        "command",
        nargs="?",
        help="Demo name to run, or 'test' to run the packaged pytest suite.",
    )
    parser.add_argument("command_args", nargs=argparse.REMAINDER, help=argparse.SUPPRESS)
    args = parser.parse_args()

    if args.command is None:
        parser.error(
            "expected a command such as 'demo00_quickstart' or 'test'. "
            f"Available demos: {', '.join(sorted(_DEMO_FUNCS))}.",
        )

    if args.command == "test":
        import pytest

        pytest_args = ["-s", "--pyargs", "riley.pytests", *args.command_args]
        raise SystemExit(pytest.main(pytest_args))

    if args.command not in _DEMO_FUNCS:
        parser.error(
            f"unknown command '{args.command}'. Available demos: "
            f"{', '.join(sorted(_DEMO_FUNCS))}, test.",
        )

    if args.command not in _PROCEDURAL_DEMOS:
        demo_parser = argparse.ArgumentParser(
            prog=f"{parser.prog} {args.command}", allow_abbrev=False,
        )
        demo_parser.parse_args(args.command_args)
        importlib.import_module(_DEMO_FUNCS[args.command]).main()
    else:
        importlib.import_module(_DEMO_FUNCS[args.command]).main(args.command_args)


if __name__ == "__main__":
    main()
