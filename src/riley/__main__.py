# --------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher)
# --------------------------------------------------------------------------
from __future__ import annotations

import argparse
import importlib

_DEMO_FUNCS = {
    "demo00_quickstart": "riley.pydemos.demo00_quickstart",
    "demo01_sphere": "riley.pydemos.demo01_sphere",
    "demo02a_rabbits_mono": "riley.pydemos.demo02a_rabbits_mono",
    "demo02b_rabbits_rgb": "riley.pydemos.demo02b_rabbits_rgb",
    "demo02c_rabbits_fields": "riley.pydemos.demo02c_rabbits_fields",
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


def main() -> None:
    parser = argparse.ArgumentParser(prog="python -m riley")
    parser.add_argument(
        "command",
        nargs="?",
        help="Demo name to run, or 'test' to run the packaged pytest suite.",
    )
    args, extra_args = parser.parse_known_args()

    if args.command is None:
        parser.error(
            "expected a command such as 'demo00_quickstart' or 'test'. "
            f"Available demos: {', '.join(sorted(_DEMO_FUNCS))}.",
        )

    if args.command == "test":
        import pytest

        pytest_args = ["-s", "--pyargs", "riley.pytests", *extra_args]
        raise SystemExit(pytest.main(pytest_args))

    if args.command not in _DEMO_FUNCS:
        parser.error(
            f"unknown command '{args.command}'. Available demos: "
            f"{', '.join(sorted(_DEMO_FUNCS))}, test.",
        )

    demo_module = importlib.import_module(_DEMO_FUNCS[args.command])
    demo_module.main()


if __name__ == "__main__":
    main()
