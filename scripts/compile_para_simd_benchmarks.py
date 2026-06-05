#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import shutil
import subprocess
import tempfile

from perf_common import repo_root, update_buildconfig_simd


BENCH_NAMES = [
    "bench_dicuq",
    "bench_fullraster",
    "bench_geom",
    "bench_sphere2000",
    "bench_sphere2000zoom",
]


def main() -> int:
    root = repo_root()
    buildconfig_path = root / "src" / "riley" / "zig" / "buildconfig.zig"
    backup_dir = pathlib.Path(tempfile.mkdtemp(prefix="riley-buildconfig-"))
    backup_path = backup_dir / "buildconfig.zig"
    shutil.copy2(buildconfig_path, backup_path)
    (root / "bin").mkdir(parents=True, exist_ok=True)

    try:
        update_buildconfig_simd("on")
        for bench_name in BENCH_NAMES:
            print(f"Compiling {bench_name}_simd...")
            subprocess.run(
                [
                    "zig",
                    "build-exe",
                    "-O",
                    "ReleaseFast",
                    str(root / "src" / f"{bench_name}.zig"),
                    f"-femit-bin={root / 'bin' / f'{bench_name}_simd'}",
                ],
                cwd=root,
                check=True,
            )
    finally:
        shutil.copy2(backup_path, buildconfig_path)
        shutil.rmtree(backup_dir)

    print(f"SIMD benchmark executables written to {root / 'bin'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
