#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import shutil
import subprocess
import tempfile

from perf_common import (
    repo_root,
    update_buildconfig_resolve_scratch_simd,
    update_buildconfig_simd,
)


BENCH_NAMES = [
    "bench_cam",
    "bench_dicuq",
    "bench_fullraster",
    "bench_geom",
    "bench_sphere2000",
    "bench_sphere2000zoom",
]


def compile_mode_parallel(suffix: str) -> None:
    root = repo_root()
    processes: list[tuple[str, subprocess.Popen[str]]] = []

    for bench_name in BENCH_NAMES:
        print(f"Compiling {bench_name}_{suffix}...")
        process = subprocess.Popen(
            [
                "zig",
                "build-exe",
                "-O",
                "ReleaseFast",
                str(root / "src" / f"{bench_name}.zig"),
                f"-femit-bin={root / 'bin' / f'{bench_name}_{suffix}'}",
            ],
            cwd=root,
            text=True,
        )
        processes.append((bench_name, process))

    failures: list[str] = []
    for bench_name, process in processes:
        if process.wait() != 0:
            failures.append(bench_name)

    if failures:
        joined = ", ".join(failures)
        raise SystemExit(
            f"One or more {suffix} benchmark compilations failed: {joined}.",
        )


def compile_cam_resolve_variants() -> None:
    root = repo_root()
    for resolve_mode, suffix in (
        ("off", "mainsimd_on_resolvesimd_off"),
        ("on", "mainsimd_on_resolvesimd_on"),
    ):
        print(f"Compiling bench_cam_{suffix}...")
        update_buildconfig_resolve_scratch_simd(resolve_mode)
        subprocess.run(
            [
                "zig",
                "build-exe",
                "-O",
                "ReleaseFast",
                str(root / "src" / "bench_cam.zig"),
                f"-femit-bin={root / 'bin' / f'bench_cam_{suffix}'}",
            ],
            cwd=root,
            check=True,
        )


def main() -> int:
    root = repo_root()
    buildconfig_path = root / "src" / "riley" / "zig" / "buildconfig.zig"
    backup_dir = pathlib.Path(tempfile.mkdtemp(prefix="riley-buildconfig-"))
    backup_path = backup_dir / "buildconfig.zig"
    shutil.copy2(buildconfig_path, backup_path)
    (root / "bin").mkdir(parents=True, exist_ok=True)

    try:
        update_buildconfig_simd("off")
        compile_mode_parallel("scalar")
        update_buildconfig_simd("on")
        update_buildconfig_resolve_scratch_simd("on")
        compile_mode_parallel("simd")
        compile_cam_resolve_variants()
    finally:
        shutil.copy2(backup_path, buildconfig_path)
        shutil.rmtree(backup_dir)

    print(f"Benchmark executables written to {root / 'bin'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
