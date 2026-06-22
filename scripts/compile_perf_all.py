#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import subprocess

from perf_common import repo_root


BUILD_VARIANTS = (
    ("f64", "inner"),
    ("f64", "over_pixels"),
    ("f32", "inner"),
    ("f32", "over_pixels"),
)


def binary_name(precision: str, simd_texture_interp: str) -> str:
    interp_tag = "overpx" if simd_texture_interp == "over_pixels" else "inner"
    return f"bench_fullraster_{precision}_simd_{interp_tag}"


def main() -> int:
    root = repo_root()
    (root / "bin").mkdir(parents=True, exist_ok=True)

    processes: list[tuple[str, subprocess.Popen[str]]] = []
    for precision, simd_texture_interp in BUILD_VARIANTS:
        name = binary_name(precision, simd_texture_interp)
        print(f"Compiling {name}...")
        process = subprocess.Popen(
            [
                "zig",
                "build",
                "install-bench-fullraster",
                "--prefix",
                ".",
                "-Doptimize=ReleaseFast",
                f"-Dprecision={precision}",
                "-Dsimd=on",
                f"-Dsimd-texture-interp={simd_texture_interp}",
            ],
            cwd=root,
            text=True,
        )
        processes.append((name, process))

    failures: list[str] = []
    for name, process in processes:
        if process.wait() != 0:
            failures.append(name)

    if failures:
        joined = ", ".join(failures)
        raise SystemExit(f"Benchmark compile failed: {joined}.")

    print("Generated benchmark binaries:")
    for precision, simd_texture_interp in BUILD_VARIANTS:
        print(f"  {root / 'bin' / binary_name(precision, simd_texture_interp)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
