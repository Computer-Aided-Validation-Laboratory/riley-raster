#!/usr/bin/env python3
"""Benchmark Riley buffer modes against PSFs and scene densities.

Compares tile_local, global_subpx_full, and global_subpx_stripe over
multiple PSFs (none, gaussian_1_0, gaussian_1_5) and SSAA subsampling
ratios (2x2, 4x4, 8x8) across dense and sparse scenes.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import itertools
import pathlib
import shlex
import statistics
import subprocess


ROOT = pathlib.Path(__file__).resolve().parent.parent
FIELDS = (
    "geometry_ms",
    "tile_overlap_ms",
    "buffer_setup_ms",
    "tile_raster_ms",
    "resolve_ms",
    "raster_loop_ms",
    "raster_stage_ms",
    "active_ms",
    "e2e_ms",
    "stripe_count",
    "active_tile_count",
    "overlap_refs_total",
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
        default=pathlib.Path("out/bench_stats_buffer_psf"),
    )
    parser.add_argument("--elements-per-type", type=int, default=24)
    parser.add_argument("--width", type=int, default=512)
    parser.add_argument("--height", type=int, default=512)
    parser.add_argument(
        "--typical",
        action="store_true",
        help="Use 250 elements/type (1000 total) and 1024x1024 resolution",
    )
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("--warmup", type=int, default=1)
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--optimize", default="ReleaseFast")
    parser.add_argument(
        "--quick",
        action="store_true",
        help="Single run with no warmup for quick verification",
    )
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()
    if args.typical:
        args.elements_per_type = 250
        args.width = 1024
        args.height = 1024
    if args.quick:
        args.runs = 1
        args.warmup = 0
    return args


def build_binary(optimize: str) -> None:
    cmd = [
        "zig",
        "build",
        "install-bench-buffer-psf",
        f"-Doptimize={optimize}",
        "-Dsimd=on",
    ]
    print(f"Building: {shlex.join(cmd)}")
    subprocess.run(cmd, cwd=ROOT, check=True)


def run_case(
    args: argparse.Namespace,
    name: str,
    scene_density: str,
    buffer_mode: str,
    psf: str,
    sub_sample: int,
) -> list[dict[str, str]]:
    exe = ROOT / "zig-out" / "bin" / "bench_buffer_psf_f64_simd"
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
        "--runs",
        str(args.runs),
        "--warmup",
        str(args.warmup),
        "--threads",
        str(args.threads),
        "--sub-sample",
        str(sub_sample),
        "--scene-density",
        scene_density,
        "--psf",
        psf,
        "--buffer-mode",
        buffer_mode,
    ]
    subprocess.run(cmd, cwd=ROOT, check=True)
    csv_path = case_dir / "raw_stats_buffer_psf.csv"
    with csv_path.open() as f:
        reader = csv.DictReader(f)
        return list(reader)


def aggregate_rows(rows: list[dict[str, str]]) -> dict[str, float | str | int]:
    first = rows[0]
    agg: dict[str, float | str | int] = {
        "scene_density": first["scene_density"],
        "buffer_mode": first["buffer_mode"],
        "psf": first["psf"],
        "sub_sample": int(first["sub_sample"]),
        "threads": int(first["threads"]),
        "elements": int(first["elements"]),
        "width": int(first["width"]),
        "height": int(first["height"]),
        "runs": len(rows),
    }
    for field in FIELDS:
        vals = [float(r[field]) for r in rows]
        agg[f"{field}_median"] = statistics.median(vals)
        agg[f"{field}_min"] = min(vals)
        agg[f"{field}_max"] = max(vals)
    return agg


def main() -> None:
    args = parse_args()
    if not args.skip_build:
        build_binary(args.optimize)

    stamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    args.out_dir = args.out_root / stamp
    args.out_dir.mkdir(parents=True, exist_ok=True)

    buffer_modes = ("tile_local", "global_subpx_full", "global_subpx_stripe")
    psfs = ("none", "gaussian_1_0", "gaussian_1_5")
    densities = ("dense", "sparse")
    sub_samples = (2, 4, 8) if not args.quick else (2, 4)

    all_raw: list[dict[str, str]] = []
    summaries: list[dict[str, float | str | int]] = []

    for density, sub_sample, psf, buffer_mode in itertools.product(
        densities,
        sub_samples,
        psfs,
        buffer_modes,
    ):
        case_name = f"{density}_ssaa{sub_sample}_{psf}_{buffer_mode}"
        print(f"Running case: {case_name}")
        rows = run_case(
            args,
            name=case_name,
            scene_density=density,
            buffer_mode=buffer_mode,
            psf=psf,
            sub_sample=sub_sample,
        )
        for r in rows:
            r["case_name"] = case_name
        all_raw.extend(rows)
        summaries.append(aggregate_rows(rows))

    # Calculate ratios relative to tile_local baseline
    baseline_lookup = {
        (s["scene_density"], s["sub_sample"], s["psf"]): s
        for s in summaries
        if s["buffer_mode"] == "tile_local"
    }

    for s in summaries:
        key = (s["scene_density"], s["sub_sample"], s["psf"])
        base = baseline_lookup.get(key)
        if base:
            s["raster_ms_vs_tile_local"] = (
                float(s["raster_stage_ms_median"]) /
                float(base["raster_stage_ms_median"])
            )
            s["e2e_ms_vs_tile_local"] = (
                float(s["e2e_ms_median"]) / float(base["e2e_ms_median"])
            )
        else:
            s["raster_ms_vs_tile_local"] = 1.0
            s["e2e_ms_vs_tile_local"] = 1.0

    raw_csv = args.out_dir / "raw_stats.csv"
    if all_raw:
        with raw_csv.open("w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=list(all_raw[0].keys()))
            writer.writeheader()
            writer.writerows(all_raw)

    summary_csv = args.out_dir / "summary.csv"
    if summaries:
        with summary_csv.open("w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=list(summaries[0].keys()))
            writer.writeheader()
            writer.writerows(summaries)

    print(f"\nBenchmark completed successfully.")
    print(f"Results saved to: {args.out_dir}")
    print(f"  Raw:     {raw_csv}")
    print(f"  Summary: {summary_csv}")


if __name__ == "__main__":
    main()
