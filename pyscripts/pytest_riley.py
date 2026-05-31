from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image


ZIG_OUT_DIR = Path("out/demo-sphere200")
PY_OUT_DIR = Path("pyout/demo-sphere200")
PYTHON_EXE = Path(".venv/bin/python")
ZIG_CMD = [
    "zig",
    "run",
    "-lc",
    "-O",
    "ReleaseFast",
    "./src/demo_sphere200.zig",
]
PY_CMD = [
    str(PYTHON_EXE),
    "./pyscripts/demo_sphere200.py",
    "--save-strategy",
    "disk",
]


def compare_file_bytes(path_a: Path, path_b: Path) -> None:
    bytes_a = path_a.read_bytes()
    bytes_b = path_b.read_bytes()
    if bytes_a == bytes_b:
        return

    mismatch_idx = next(
        (
            nn
            for nn, (aa, bb) in enumerate(zip(bytes_a, bytes_b))
            if aa != bb
        ),
        min(len(bytes_a), len(bytes_b)),
    )
    image_a = np.asarray(Image.open(path_a), dtype=np.int16)
    image_b = np.asarray(Image.open(path_b), dtype=np.int16)
    max_abs_diff = int(np.max(np.abs(image_a - image_b)))
    raise AssertionError(
        "render mismatch for "
        f"{path_a.name}: first byte diff at {mismatch_idx}, "
        f"max_abs_diff={max_abs_diff}"
    )


def compare_render_dirs(dir_a: Path, dir_b: Path) -> None:
    files_a = sorted(path_a.name for path_a in dir_a.glob("*.bmp"))
    files_b = sorted(path_b.name for path_b in dir_b.glob("*.bmp"))
    if files_a != files_b:
        raise AssertionError(
            f"output file mismatch: zig={files_a}, python={files_b}"
        )

    for file_name in files_a:
        compare_file_bytes(dir_a / file_name, dir_b / file_name)


def main() -> None:
    shutil.rmtree(ZIG_OUT_DIR, ignore_errors=True)
    shutil.rmtree(PY_OUT_DIR, ignore_errors=True)

    subprocess.run(ZIG_CMD, check=True)
    subprocess.run(PY_CMD, check=True)

    compare_render_dirs(ZIG_OUT_DIR, PY_OUT_DIR)
    print("python wrapper render matches zig demo exactly")


if __name__ == "__main__":
    try:
        main()
    except Exception as err:
        print(str(err))
        sys.exit(1)
