#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import subprocess

from perf_common import repo_root

BATCH_SIZE = 4

BUILD_VARIANTS = (
    ("f64", "inner", 8),
    ("f64", "over_pixels", 8),
    ("f32", "inner", 16),
    ("f32", "over_pixels", 16),
    ("f64", "inner", 4),
    ("f32", "inner", 8),
)


def default_lanes(precision: str) -> int:
    return 16 if precision == "f32" else 8


def binary_name(
    precision: str,
    simd_texture_interp: str,
    lanes: int,
) -> str:
    interp_tag = (
        "overpx" if simd_texture_interp == "over_pixels"
        else "inner"
    )
    if lanes == default_lanes(precision):
        return f"bench_tiltraster_{precision}_simd_{interp_tag}"
    else:
        return f"bench_tiltraster_{precision}_simd_{interp_tag}_v{lanes}"


def main() -> int:
    root = repo_root()
    (root / "bin").mkdir(parents=True, exist_ok=True)

    failures: list[str] = []
    for i in range(0, len(BUILD_VARIANTS), BATCH_SIZE):
        batch = BUILD_VARIANTS[i : i + BATCH_SIZE]
        processes: list[tuple[str, subprocess.Popen[str]]] = []
        for precision, simd_texture_interp, lanes in batch:
            name = binary_name(precision, simd_texture_interp, lanes)
            print(f"Compiling {name}...")
            process = subprocess.Popen(
                [
                    "zig",
                    "build",
                    "install-bench-tiltraster",
                    "--prefix",
                    ".",
                    "-Doptimize=ReleaseFast",
                    f"-Dprecision={precision}",
                    "-Dsimd=on",
                    f"-Dsimd-texture-interp={simd_texture_interp}",
                    f"-Dsimd-vector-width={lanes}",
                ],
                cwd=root,
                text=True,
            )
            processes.append((name, process))

        for name, process in processes:
            if process.wait() != 0:
                failures.append(name)

    if failures:
        joined = ", ".join(failures)
        raise SystemExit(f"Benchmark compile failed: {joined}.")

    print("Generated benchmark binaries:")
    for precision, simd_texture_interp, lanes in BUILD_VARIANTS:
        bin_path = (
            root / "bin" /
            binary_name(precision, simd_texture_interp, lanes)
        )
        print(f"  {bin_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
