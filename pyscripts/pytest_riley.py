# --------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher)
# --------------------------------------------------------------------------
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image


PYTHON_EXE = Path(sys.executable)
ZIG_CMD = [
    "zig",
    "run",
    "-lc",
    "-O",
    "ReleaseFast",
    "./src/run_all_demos.zig",
]
PY_CMDS = [
    [str(PYTHON_EXE), "./pyscripts/demo_sphere200.py"],
    [str(PYTHON_EXE), "./pyscripts/demo_rabbits.py"],
    [str(PYTHON_EXE), "./pyscripts/demo_dicuq.py"],
    [str(PYTHON_EXE), "./pyscripts/demo_stereocal.py"],
]
COMPARE_DIRS = [
    ("out/demo-sphere200", "pyout/demo-sphere200"),
    ("out/demo-rabbits", "pyout/demo-rabbits"),
    ("out/demo-dicuq", "pyout/demo-dicuq"),
    ("out/demo-stereocal", "pyout/demo-stereocal"),
]


# Tolerance: 1.0 allows a single 8-bit quantisation step of
# difference between zig and python renders, guarding against
# platform-level floating point rounding noise.
MAX_ABS_DIFF_TOL: float = 1.0


def compare_renders_float(
    path_a: Path,
    path_b: Path,
    tol: float = MAX_ABS_DIFF_TOL,
) -> None:
    arr_a = np.asarray(Image.open(path_a), dtype=np.float32)
    arr_b = np.asarray(Image.open(path_b), dtype=np.float32)
    if arr_a.shape != arr_b.shape:
        raise AssertionError(
            f"shape mismatch for {path_a.name}: "
            f"zig={arr_a.shape} python={arr_b.shape}"
        )
    max_diff = float(np.max(np.abs(arr_a - arr_b)))
    if max_diff > tol:
        raise AssertionError(
            f"render mismatch for {path_a.name}: "
            f"max_abs_diff={max_diff:.4f} > tol={tol:.4f}"
        )


def compare_render_dirs(dir_a: Path, dir_b: Path) -> None:
    files_a = sorted(
        path_a.relative_to(dir_a)
        for path_a in dir_a.rglob("*.bmp")
    )
    files_b = sorted(
        path_b.relative_to(dir_b)
        for path_b in dir_b.rglob("*.bmp")
    )
    if files_a != files_b:
        raise AssertionError(
            f"output file mismatch: zig={files_a}, python={files_b}"
        )

    for rel_path in files_a:
        compare_renders_float(dir_a / rel_path, dir_b / rel_path)


def main() -> None:
    silent_env = dict(os.environ)
    silent_env["RILEY_DEMO_SILENT"] = "1"
    for zig_dir, py_dir in COMPARE_DIRS:
        shutil.rmtree(zig_dir, ignore_errors=True)
        shutil.rmtree(py_dir, ignore_errors=True)

    subprocess.run(
        ZIG_CMD,
        check=True,
        env=silent_env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.STDOUT,
    )
    for cmd in PY_CMDS:
        subprocess.run(
            cmd,
            check=True,
            env=silent_env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.STDOUT,
        )

    for zig_dir, py_dir in COMPARE_DIRS:
        compare_render_dirs(Path(zig_dir), Path(py_dir))

    print(
        "python wrapper renders match zig demos "
        f"within tol={MAX_ABS_DIFF_TOL:.1f}"
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as err:
        print(str(err))
        sys.exit(1)
