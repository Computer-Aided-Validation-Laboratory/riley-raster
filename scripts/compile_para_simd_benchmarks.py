#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import subprocess
import re

from perf_common import repo_root


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





def main() -> int:
    root = repo_root()
    buildconfig_path = root / "src" / "riley" / "zig" / "buildconfig.zig"
    (root / "bin").mkdir(parents=True, exist_ok=True)

    buildconfig_text = buildconfig_path.read_text()
    simd_match = re.search(
        r"^\s*simd:\s*SimdMode\s*=\s*\.(on|off)\s*,\s*$",
        buildconfig_text,
        re.MULTILINE,
    )
    if simd_match is None:
        raise SystemExit("Failed to determine buildconfig simd mode.")
    if simd_match.group(1) != "on":
        raise SystemExit(
            "compile_para_simd_benchmarks.py requires buildconfig simd to be .on.",
        )

    compile_mode_parallel("simd")

    print(f"SIMD benchmark executables written to {root / 'bin'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
