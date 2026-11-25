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
from pathlib import Path

from riley.types import Disk2DParams, Gaussian2DParams, Perlin2DParams


def demo_speckle_params(
    pattern: str, *, size: float,
) -> Disk2DParams | Gaussian2DParams | Perlin2DParams:
    if pattern == "disk":
        return Disk2DParams(coverage=0.5, radius=size)
    if pattern == "gaussian":
        return Gaussian2DParams(coverage=0.5, radius=size)
    if pattern == "perlin":
        return Perlin2DParams(cell_size=size)
    raise ValueError(f"Unknown speckle pattern: {pattern}")


def procedural_parser(demo_name: str, description: str) -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog=f"python -m riley {demo_name}",
        description=description,
        allow_abbrev=False,
    )
    parser.add_argument(
        "--pattern", choices=("disk", "gaussian", "perlin"), default="disk",
        help="speckle pattern (default: disk)",
    )
    default_output = Path("out_riley_py") / demo_name
    parser.add_argument(
        "--output", type=_output_path, default=default_output, metavar="DIR",
        help=f"output directory (default: {default_output})",
    )
    return parser


def _output_path(value: str) -> Path:
    if not value:
        raise argparse.ArgumentTypeError("expected a non-empty directory")
    return Path(value)
