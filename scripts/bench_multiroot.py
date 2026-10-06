#!/usr/bin/env python3
"""Compare multi-root policies (.fast and .robust) with flat baseline.

Defaults: 96 elements, 512x512 pixels, 1x1 subsampling. --typical selects
1000 elements, 1024x1024 pixels, and 2x2 subsampling. Summary CSV includes
timings, throughput, solver metrics, and end-to-end ratios to the one-root
baseline.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import math
import pathlib
import shlex
import statistics
import subprocess


ROOT = pathlib.Path(__file__).resolve().parent.parent
FIELDS = (
    "geometry_ms",
    "prepare_ms",
    "raster_ms",
    "active_ms",
    "e2e_ms",
    "solver_calls",
    "solver_iters",
    "solver_diverged",
    "visible",
    "shaded",
    "melems_s",
    "mpx_s",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument(
        "--out-root",
        type=pathlib.Path,
        default=pathlib.Path("out/bench_stats_multiroot"),
    )
    parser.add_argument("--elements-per-type", type=int, default=24)
    parser.add_argument("--width", type=int, default=512)
    parser.add_argument("--height", type=int, default=512)
    parser.add_argument("--sub-sample", type=int, default=1)
    parser.add_argument(
        "--typical",
        action="store_true",
        help="Use 1000 elements, 1024x1024, 2x2 subsampling",
    )
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("--warmup", type=int, default=1)
    parser.add_argument("--threads", type=int, default=1)
    parser.add_argument("--optimize", default="ReleaseSafe")
    parser.add_argument(
        "--quick",
        action="store_true",
        help="One short run of each mode",
    )
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()
    if args.typical:
        args.elements_per_type = 250
        args.width = 1024
        args.height = 1024
        args.sub_sample = 2
    if args.quick:
        args.runs = 1
        args.warmup = 0
    return args


def run_case(
    args: argparse.Namespace,
    backend: str,
    name: str,
    mode: str,
    scene: str = "multi_root",
    flat_scale: float = 1.0,
    runs: int | None = None,
    warmup: int | None = None,
) -> list[dict[str, str]]:
    exe = ROOT / "zig-out" / "bin" / f"bench_multiroot_f64_{backend}"
    case_dir = args.out_dir / name
    cmd = [
        str(exe),
        "--out-dir",
        str(case_dir),
        "--elements-per-type",
        str(args.elements_per_type),
        "--width",
        str(args.width),
        "--height",
        str(args.height),
        "--sub-sample",
        str(args.sub_sample),
        "--runs",
        str(args.runs if runs is None else runs),
        "--warmup",
        str(args.warmup if warmup is None else warmup),
        "--threads",
        str(args.threads),
        "--mode",
        mode,
        "--scene",
        scene,
        "--flat-scale",
        str(flat_scale),
    ]
    print(name, flush=True)
    case_dir.mkdir(parents=True, exist_ok=True)
    (case_dir / "command.txt").write_text(
        " ".join(shlex.quote(part) for part in cmd) + "\n"
    )
    with (args.out_dir / f"{name}.log").open("w") as log:
        subprocess.run(
            cmd,
            cwd=ROOT,
            stdout=log,
            stderr=subprocess.STDOUT,
            check=True,
        )
    with (case_dir / "raw_stats_multiroot.csv").open(newline="") as file:
        return [
            {"backend": backend, **row} for row in csv.DictReader(file)
        ]


def match_flat_shading(args: argparse.Namespace, target: int) -> float:
    """Match aggregate shaded subpixels outside timed baseline runs."""
    scale = 1.0
    best_scale = scale
    best_error = float("inf")
    tolerance = max(0.005, 16 / target)
    for attempt in range(10):
        rows = run_case(
            args,
            "scalar",
            f"calibrate_flat_{attempt}",
            mode="fast",
            scene="one_root",
            flat_scale=scale,
            runs=1,
            warmup=0,
        )
        shaded = int(rows[0]["shaded"])
        if shaded == 0:
            raise RuntimeError("Flat baseline shaded no samples")
        error = abs(shaded - target) / target
        if error < best_error:
            best_scale = scale
            best_error = error
        if error <= tolerance:
            return scale
        scale *= math.sqrt(target / shaded)
    if best_error <= tolerance:
        return best_scale
    raise RuntimeError(
        f"Flat baseline shading mismatch: best error {best_error:.2%}, "
        f"allowed {tolerance:.2%}"
    )


def main() -> None:
    args = parse_args()
    timestamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    args.out_dir = args.out_root / timestamp
    args.out_dir.mkdir(parents=True, exist_ok=True)
    backends = ("scalar", "simd")
    if not args.skip_build:
        for backend in backends:
            subprocess.run(
                [
                    "zig",
                    "build",
                    "install-bench-multiroot",
                    f"-Doptimize={args.optimize}",
                    f"-Dsimd={'off' if backend == 'scalar' else 'on'}",
                ],
                cwd=ROOT,
                check=True,
            )

    modes = ("fast", "robust")
    raw_rows: list[dict[str, str]] = []
    for backend in backends:
        for mode in modes:
            name = f"{backend}_{mode}"
            raw_rows.extend(
                run_case(args, backend, name, mode=mode, scene="multi_root")
            )

    reference = next(
        row for row in raw_rows
        if row["backend"] == "scalar" and row["mode"] == "fast"
    )
    target_shaded = int(reference["shaded"])
    if target_shaded == 0:
        raise RuntimeError("Multi-root reference shaded no samples")

    flat_scale = match_flat_shading(args, target_shaded)
    for backend in backends:
        raw_rows.extend(
            run_case(
                args,
                backend,
                f"{backend}_one_root_baseline",
                mode="fast",
                scene="one_root",
                flat_scale=flat_scale,
            )
        )

    with (args.out_dir / "raw_stats_multiroot.csv").open(
        "w", newline=""
    ) as file:
        writer = csv.DictWriter(file, fieldnames=raw_rows[0].keys())
        writer.writeheader()
        writer.writerows(raw_rows)

    scalar_rows = {}
    for row in raw_rows:
        key = (row["scene"], row["mode"], row["run"])
        if row["backend"] == "scalar":
            scalar_rows[key] = row
            continue
        reference = scalar_rows[key]
        for field in ("visible", "shaded", "solver_calls"):
            if row[field] != reference[field]:
                raise RuntimeError(
                    f"Scalar/SIMD {field} mismatch for {key}: "
                    f"{reference[field]} vs {row[field]}"
                )

    summary_rows = []
    for backend in backends:
        cases = [
            ("multi_root", "fast"),
            ("multi_root", "robust"),
            ("one_root", "fast"),
        ]
        for scene, mode in cases:
            group = [
                row for row in raw_rows
                if row["backend"] == backend and
                row["scene"] == scene and
                row["mode"] == mode
            ]
            row_summary = {
                "backend": backend,
                "scene": scene,
                "mode": mode if scene == "multi_root" else "flat_baseline",
                "runs": len(group),
            }
            for field in FIELDS:
                values = [float(item[field]) for item in group]
                row_summary[f"{field}_median"] = statistics.median(values)
                row_summary[f"{field}_mean"] = statistics.mean(values)
                row_summary[f"{field}_std"] = (
                    statistics.stdev(values) if len(values) > 1 else 0.0
                )
                row_summary[f"{field}_min"] = min(values)
                row_summary[f"{field}_max"] = max(values)
            summary_rows.append(row_summary)

    for row in summary_rows:
        baseline = next(
            item for item in summary_rows
            if item["backend"] == row["backend"] and
            item["scene"] == "one_root"
        )
        row["e2e_vs_one_root"] = (
            row["e2e_ms_median"] / baseline["e2e_ms_median"]
        )
        row["shaded_delta_pct"] = 100 * (
            row["shaded_median"] / baseline["shaded_median"] - 1
        )

    summary_path = args.out_dir / "summary_stats_multiroot.csv"
    with summary_path.open("w", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=summary_rows[0].keys())
        writer.writeheader()
        writer.writerows(summary_rows)

    top_summary = ROOT / "out" / (
        f"summary_bench_multiroot_median_{timestamp}.csv"
    )
    top_summary.parent.mkdir(parents=True, exist_ok=True)
    with top_summary.open("w", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=summary_rows[0].keys())
        writer.writeheader()
        writer.writerows(summary_rows)

    print(f"Raw and summary CSV: {args.out_dir}")


if __name__ == "__main__":
    main()
