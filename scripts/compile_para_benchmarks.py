#!/usr/bin/env python3
from __future__ import annotations

import argparse
import shutil
import subprocess

from bench_common import native_exe, repo_root


BENCH_NAMES = [
    "bench_dicuq",
    "bench_dist_psf",
    "bench_fullraster",
    "bench_tiltraster",
    "bench_geom",
    "bench_sphere2000",
    "bench_sphere2000zoom",
    "bench_thread_geom",
]


BATCH_SIZE = 4


def compile_mode_parallel(simd_mode: str, suffix: str) -> None:
    root = repo_root()
    failures: list[str] = []

    for ii in range(0, len(BENCH_NAMES), BATCH_SIZE):
        batch = BENCH_NAMES[ii : ii + BATCH_SIZE]
        processes: list[tuple[str, subprocess.Popen[str]]] = []
        for bench_name in batch:
            print(f"Compiling {bench_name}_{suffix}...")
            process = subprocess.Popen(
                [
                    "zig",
                    "build",
                    f"install-{bench_name.replace('_', '-')}",
                    "--prefix",
                    ".",
                    "-Doptimize=ReleaseFast",
                    "-Dprecision=f64",
                    f"-Dsimd={simd_mode}",
                ],
                cwd=root,
                text=True,
            )
            processes.append((bench_name, process))

        for bench_name, process in processes:
            if process.wait() != 0:
                failures.append(bench_name)

    if failures:
        joined = ", ".join(failures)
        raise SystemExit(
            f"One or more {suffix} benchmark compilations failed: {joined}.",
        )

    for bench_name in BENCH_NAMES:
        src = native_exe(root / "bin" / f"{bench_name}_f64_{suffix}")
        dst = native_exe(root / "bin" / f"{bench_name}_{suffix}")
        if not src.is_file():
            raise SystemExit(f"Build succeeded but did not install {src}.")
        shutil.copy2(src, dst)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Build the standard f64 benchmark binaries and aliases.",
    )
    parser.add_argument(
        "--simd-only", action="store_true",
        help="Build only SIMD binaries instead of both scalar and SIMD.",
    )
    args = parser.parse_args()

    root = repo_root()
    (root / "bin").mkdir(parents=True, exist_ok=True)

    if not args.simd_only:
        compile_mode_parallel("off", "scalar")
    compile_mode_parallel("on", "simd")

    print(f"Benchmark executables written to {root / 'bin'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
