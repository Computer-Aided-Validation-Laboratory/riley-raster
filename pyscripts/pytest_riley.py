from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image


PYTHON_EXE = Path(".venv/bin/python")
ZIG_CMD = [
    "zig",
    "run",
    "-lc",
    "-O",
    "ReleaseFast",
    "./src/run_all_demos.zig",
]
PY_CMDS = [
    [str(PYTHON_EXE), "./pyscripts/demo_sphere200.py", "--save-strategy", "disk"],
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
        compare_file_bytes(dir_a / rel_path, dir_b / rel_path)


def main() -> None:
    for zig_dir, py_dir in COMPARE_DIRS:
        shutil.rmtree(zig_dir, ignore_errors=True)
        shutil.rmtree(py_dir, ignore_errors=True)

    subprocess.run(ZIG_CMD, check=True)
    for cmd in PY_CMDS:
        subprocess.run(cmd, check=True)

    for zig_dir, py_dir in COMPARE_DIRS:
        compare_render_dirs(Path(zig_dir), Path(py_dir))

    print("python wrapper renders match zig demos exactly")


if __name__ == "__main__":
    try:
        main()
    except Exception as err:
        print(str(err))
        sys.exit(1)
