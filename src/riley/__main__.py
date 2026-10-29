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
    "demo0_quickstart": "riley.pydemos.demo0_quickstart",
    "demo1_sphere": "riley.pydemos.demo1_sphere",
    "demo2a_rabbits_mono": "riley.pydemos.demo2a_rabbits_mono",
    "demo2b_rabbits_rgb": "riley.pydemos.demo2b_rabbits_rgb",
    "demo2c_rabbits_fields": "riley.pydemos.demo2c_rabbits_fields",
    "demo3_dicuq": "riley.pydemos.demo3_dicuq",
    "demo3_dicuq_from_exodus": "riley.pydemos.demo3_dicuq_from_exodus",
    "demo4_stereocal": "riley.pydemos.demo4_stereocal",
    "demo5_cameramodels": "riley.pydemos.demo5_cameramodels",
    "demo6_featurezoo": "riley.pydemos.demo6_featurezoo",
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
            "expected a command such as 'demo0_quickstart' or 'test'. "
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
