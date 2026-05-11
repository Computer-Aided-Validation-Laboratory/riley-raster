#!/usr/bin/env python3
from __future__ import annotations

import pathlib


SHEAR_REGULAR = 10
SHEAR_SHEAR = 0

BULGE_OUT = 4
BULGE_REGULAR = 6
BULGE_IN = 8
BULGE_OUT_LIMIT = 0

PAPER_DIR = pathlib.Path("~/paper-zraster").expanduser()


def repo_root() -> pathlib.Path:
    return pathlib.Path(__file__).resolve().parent.parent


def bulge_in_limit_frame(mesh_name: str) -> int:
    if mesh_name in {"quad8", "quad9"}:
        return BULGE_IN + 2
    return BULGE_IN + 1
