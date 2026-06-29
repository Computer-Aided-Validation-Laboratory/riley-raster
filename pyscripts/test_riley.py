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
import os
import shutil
import subprocess
import sys
from pathlib import Path
from time import perf_counter

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
    [str(PYTHON_EXE), "./pyscripts/demo_dic_from_exodus.py"],
    [str(PYTHON_EXE), "./pyscripts/demo_stereocal.py"],
]
COMPARE_DIRS = [
    ("out/demo-sphere200", "pyout/demo-sphere200"),
    ("out/demo-rabbits", "pyout/demo-rabbits"),
    ("out/demo-dicuq", "pyout/demo-dicuq"),
    ("out/demo-dicuq", "pyout/demo-dicuq-from-exodus"),
    ("out/demo-stereocal", "pyout/demo-stereocal"),
]
FORCE_ZIG_RENDER: bool = False
EXACT_8BIT_COMPARE: bool = True
FLOAT_FALLBACK_ABS_TOL: float = 0.5


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--force-zig-render",
        action="store_true",
        help="Re-run the Zig demo renders even if cached BMPs exist.",
    )
    return parser.parse_args()


def has_bmp_renders(dir_path: Path) -> bool:
    if not dir_path.is_dir():
        return False

    return any(dir_path.rglob("*.bmp"))


def compare_renders(path_a: Path, path_b: Path) -> None:
    arr_a_raw = np.asarray(Image.open(path_a))
    arr_b_raw = np.asarray(Image.open(path_b))
    if arr_a_raw.shape != arr_b_raw.shape:
        raise AssertionError(
            f"shape mismatch for {path_a.name}: "
            f"zig={arr_a_raw.shape} python={arr_b_raw.shape}"
        )

    if (
        EXACT_8BIT_COMPARE
        and arr_a_raw.dtype == np.uint8
        and arr_b_raw.dtype == np.uint8
    ):
        if not np.array_equal(arr_a_raw, arr_b_raw):
            diff = np.abs(
                arr_a_raw.astype(np.int16) - arr_b_raw.astype(np.int16),
            )
            max_diff = int(np.max(diff))
            diff_count = int(np.count_nonzero(diff))
            raise AssertionError(
                f"render mismatch for {path_a.name}: "
                f"exact 8-bit compare failed, "
                f"max_abs_diff={max_diff}, diff_px={diff_count}"
            )
        return

    arr_a = arr_a_raw.astype(np.float32, copy=False)
    arr_b = arr_b_raw.astype(np.float32, copy=False)
    max_diff = float(np.max(np.abs(arr_a - arr_b)))
    if max_diff > FLOAT_FALLBACK_ABS_TOL:
        raise AssertionError(
            f"render mismatch for {path_a.name}: "
            f"max_abs_diff={max_diff:.4f} > "
            f"tol={FLOAT_FALLBACK_ABS_TOL:.4f}"
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

    print(f"Comparing renders in {dir_a} against {dir_b}...")
    compare_start = perf_counter()
    for rel_path in files_a:
        compare_renders(dir_a / rel_path, dir_b / rel_path)
    compare_elapsed = perf_counter() - compare_start
    print(f"Compare completed in {compare_elapsed:.3f}s.")


def run_command(
    label: str,
    cmd: list[str],
    env: dict[str, str],
) -> float:
    print(f"Running {label}: {' '.join(cmd)}")
    start = perf_counter()
    subprocess.run(
        cmd,
        check=True,
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.STDOUT,
    )
    elapsed = perf_counter() - start
    print(f"{label} completed in {elapsed:.3f}s.")
    return elapsed


def main() -> None:
    total_start = perf_counter()
    args = parse_args()
    silent_env = dict(os.environ)
    silent_env["RILEY_DEMO_SILENT"] = "1"

    force_zig_render = FORCE_ZIG_RENDER or args.force_zig_render

    if force_zig_render:
        for zig_dir, _ in COMPARE_DIRS:
            shutil.rmtree(zig_dir, ignore_errors=True)

    for _, py_dir in COMPARE_DIRS:
        shutil.rmtree(py_dir, ignore_errors=True)

    needs_zig_render = force_zig_render or any(
        not has_bmp_renders(Path(zig_dir))
        for zig_dir, _ in COMPARE_DIRS
    )

    if needs_zig_render:
        run_command("zig demo render", ZIG_CMD, silent_env)
    else:
        print("Reusing cached Zig demo renders.")

    for cmd in PY_CMDS:
        run_command(f"python render {cmd[1]}", cmd, silent_env)

    for zig_dir, py_dir in COMPARE_DIRS:
        compare_render_dirs(Path(zig_dir), Path(py_dir))

    total_elapsed = perf_counter() - total_start
    print(f"test_riley completed in {total_elapsed:.3f}s.")


if __name__ == "__main__":
    try:
        main()
    except Exception as err:
        print(str(err))
        sys.exit(1)
