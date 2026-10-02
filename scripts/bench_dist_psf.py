#!/usr/bin/env python3
"""Orchestrator for distortion and PSF rasterisation benchmarks.

Runs Experiment 1 (Distortion Models vs Element Size) and Experiment 2
(Distortion and Point Spread Functions) across plate mesh densities and element types.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
from pathlib import Path
import shlex
import subprocess
import time

import numpy as np

from perf_common import command_path, repo_root


# -----------------------------------------------------------------------------
# Configuration Constants
# -----------------------------------------------------------------------------

PARAMETER_FIELDNAMES: list[str] = [
    "study_group",
    "case_name",
    "mesh_type",
    "mesh_density",
    "distort",
    "psf",
    "subpixel_center_map",
]

CSV_METRIC_MAP: list[tuple[str, str]] = [
    ("Total Elems", "total_elems"),
    ("Vis Elems", "vis_elems"),
    ("Total Px", "total_px"),
    ("Shaded Px", "shaded_px"),
    ("Setup F Buff [ms]", "setup_f_buff_ms"),
    ("Prep Frame [ms]", "prep_frame_ms"),
    ("Geom Time [ms]", "geom_time_ms"),
    ("Coord Ops [ms]", "coord_ops_ms"),
    ("Cull Ops [ms]", "cull_ops_ms"),
    ("Prep Hulls Shaders [ms]", "prep_hulls_shaders_ms"),
    ("Remap Inds [ms]", "remap_inds_ms"),
    ("Cam Inv Time [ms]", "cam_inv_time_ms"),
    ("Elem Loop Time [ms]", "elem_loop_time_ms"),
    ("Resolve Time [ms]", "resolve_time_ms"),
    ("Raster Time [ms]", "raster_time_ms"),
    ("Save Time [ms]", "save_time_ms"),
    ("Frame Time [ms]", "frame_time_ms"),
    ("E2E Time [ms]", "e2e_time_ms"),
    ("Geom TP [MElem/s]", "geom_tp_melem_s"),
    ("Raster TP [MPx/s]", "raster_tp_mpx_s"),
    ("Frame TP [MPx/s]", "frame_tp_mpx_s"),
    ("E2E TP [MPx/s]", "e2e_tp_mpx_s"),
]

DEFAULT_OUT_ROOT: Path = Path("out") / "bench_stats_dist_psf"
DEFAULT_IMAGE_OUT_DIR: Path = Path("out") / "bench_images_dist_psf"
DEFAULT_RUNS: int = 25
DEFAULT_FRAMES: int = 2
DEFAULT_TOTAL_THREADS: int = 1
DEFAULT_MAX_RASTER_WORKERS_PER_JOB: int = 1

DEFAULT_EXPERIMENT1: bool = True
DEFAULT_EXPERIMENT2: bool = True
DEFAULT_EXPERIMENT3: bool = True

ELEMENT_TYPES: list[str] = [
    "tri3",
    "tri6",
    "quad4",
    "quad8",
    "quad9",
]

MESH_DENSITIES: list[str] = [
    "fullraster",
    "1e2",
    "1e3",
    "1e4",
    "1e5",
]

# Experiment 1: Distortion models vs element density (subpixel_center_map = per_tile)
EXP1_DISTORTION_CASES: list[str] = [
    "none",
    "brown_zero",
    "brown_ext_zero",
    "brown_pincushion",
    "brown_ext_pincushion",
    "poly_zero",
    "poly_deg3_pincushion",
    "poly_deg7_pincushion",
]
EXP1_PSF_CASE: str = "pixel_box"

# Experiment 2: Cartesian product of distortion and PSF families
EXP2_DISTORTION_CASES: list[str] = [
    "none",
    "brown_pincushion",
    "poly_deg5_pincushion",
]

EXP2_PSF_CASES: list[str] = [
    "pixel_box",
    "gaussian_0p5",
    "gaussian_1p5",
    "aniso_gaussian_0p5_0p25",
    "aniso_gaussian_1p5_0p5",
]

# Experiment 3: Same as Exp 1 with subpixel_center_map = in_mem
EXP3_DISTORTION_CASES: list[str] = EXP1_DISTORTION_CASES
EXP3_PSF_CASE: str = EXP1_PSF_CASE
EXP3_SUBPIXEL_CENTER_MAP: str = "in_mem"


def build_experiment1_cases() -> list[dict[str, object]]:
    """Build test matrix for Experiment 1 (Distortion vs Element Density)."""
    cases: list[dict[str, object]] = []
    for etype in ELEMENT_TYPES:
        for density in MESH_DENSITIES:
            for dist in EXP1_DISTORTION_CASES:
                case_name = f"exp1_{etype}_{density}_{dist}_{EXP1_PSF_CASE}"
                cases.append(
                    {
                        "study_group": "experiment1",
                        "case_name": case_name,
                        "mesh_type": etype,
                        "mesh_density": density,
                        "distort": dist,
                        "psf": EXP1_PSF_CASE,
                        "subpixel_center_map": "per_tile",
                    }
                )
    return cases


def build_experiment2_cases() -> list[dict[str, object]]:
    """Build test matrix for Experiment 2 (Distortion x PSF Interaction)."""
    cases: list[dict[str, object]] = []
    for etype in ELEMENT_TYPES:
        for density in MESH_DENSITIES:
            for dist in EXP2_DISTORTION_CASES:
                for psf in EXP2_PSF_CASES:
                    case_name = f"exp2_{etype}_{density}_{dist}_{psf}"
                    cases.append(
                        {
                            "study_group": "experiment2",
                            "case_name": case_name,
                            "mesh_type": etype,
                            "mesh_density": density,
                            "distort": dist,
                            "psf": psf,
                            "subpixel_center_map": "per_tile",
                        }
                    )
    return cases


def build_experiment3_cases() -> list[dict[str, object]]:
    """Build test matrix for Experiment 3 (Exp 1 with subpixel_center_map = in_mem)."""
    cases: list[dict[str, object]] = []
    for etype in ELEMENT_TYPES:
        for density in MESH_DENSITIES:
            for dist in EXP3_DISTORTION_CASES:
                case_name = f"exp3_{etype}_{density}_{dist}_{EXP3_PSF_CASE}_in_mem"
                cases.append(
                    {
                        "study_group": "experiment3",
                        "case_name": case_name,
                        "mesh_type": etype,
                        "mesh_density": density,
                        "distort": dist,
                        "psf": EXP3_PSF_CASE,
                        "subpixel_center_map": EXP3_SUBPIXEL_CENTER_MAP,
                    }
                )
    return cases


EXPERIMENT1_CASES = build_experiment1_cases()
EXPERIMENT2_CASES = build_experiment2_cases()
EXPERIMENT3_CASES = build_experiment3_cases()


def binary_path() -> Path:
    """Resolve the benchmark binary executable path."""
    path = repo_root() / "bin" / "bench_dist_psf_f64_simd"
    if not path.exists():
        # Fallback to plain binary name if present
        alt_path = repo_root() / "bin" / "bench_dist_psf"
        if alt_path.exists():
            return alt_path
        raise SystemExit(
            f"Missing benchmark binary at {path}. Run "
            "'zig build install-bench-dist-psf -Doptimize=ReleaseFast --prefix .' first."
        )
    return path


def write_timing_csv(
    rows: list[dict[str, object]],
    timestamp: str,
) -> Path:
    """Write overall timing benchmark summary CSV."""
    out_dir = repo_root() / "out"
    out_dir.mkdir(parents=True, exist_ok=True)
    csv_path = out_dir / f"time_bench_dist_psf_{timestamp}.csv"
    with csv_path.open("w", newline="") as csv_file:
        fieldnames = [
            "study_group",
            "case_name",
            "mesh_type",
            "mesh_density",
            "distort",
            "psf",
            "seconds",
        ]
        writer = csv.DictWriter(csv_file, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)
    return csv_path


def load_case_run_metrics(
    case_dir: Path,
    runs: int,
) -> dict[str, np.ndarray]:
    """Load metric samples across all runs from a case directory."""
    raw_metric_lists: dict[str, list[float]] = {
        out_name: [] for _, out_name in CSV_METRIC_MAP
    }
    for rr in range(runs):
        run_file = case_dir / f"bench_run{rr}.csv"
        if not run_file.exists():
            continue
        with run_file.open("r", newline="") as f:
            reader = csv.DictReader(f)
            for row in reader:
                for csv_header, out_name in CSV_METRIC_MAP:
                    val_str = row.get(csv_header, "0")
                    try:
                        raw_metric_lists[out_name].append(float(val_str))
                    except ValueError:
                        raw_metric_lists[out_name].append(0.0)
                break

    return {
        key: np.array(vals, dtype=np.float64)
        for key, vals in raw_metric_lists.items()
    }


def compute_case_stat_rows(
    case: dict[str, object],
    run_root: Path,
    runs: int,
) -> dict[str, dict[str, object]]:
    """Compute summary statistic rows (median, mad, mean, std, min, max) for a case."""
    case_name = str(case["case_name"])
    case_dir = run_root / case_name
    metrics_map = load_case_run_metrics(case_dir, runs)

    stat_kinds = ["median", "mad", "mean", "std", "min", "max"]
    stat_rows: dict[str, dict[str, object]] = {}

    for kind in stat_kinds:
        row: dict[str, object] = {
            "study_group": case["study_group"],
            "case_name": case["case_name"],
            "mesh_type": case["mesh_type"],
            "mesh_density": case["mesh_density"],
            "distort": case["distort"],
            "psf": case["psf"],
            "subpixel_center_map": case.get("subpixel_center_map", "per_tile"),
        }
        for _, out_name in CSV_METRIC_MAP:
            vals = metrics_map.get(out_name, np.array([], dtype=np.float64))
            if len(vals) == 0:
                row[out_name] = "0.000000"
                continue
            if kind == "median":
                stat_val = float(np.median(vals))
            elif kind == "mad":
                med = float(np.median(vals))
                stat_val = float(np.median(np.abs(vals - med)))
            elif kind == "mean":
                stat_val = float(np.mean(vals))
            elif kind == "std":
                stat_val = float(np.std(vals))
            elif kind == "min":
                stat_val = float(np.min(vals))
            elif kind == "max":
                stat_val = float(np.max(vals))
            else:
                stat_val = 0.0
            row[out_name] = f"{stat_val:.6f}"
        stat_rows[kind] = row

    return stat_rows


def write_consolidated_summary_csvs(
    all_case_stat_rows: list[dict[str, dict[str, object]]],
    run_root: Path,
    timestamp: str,
) -> dict[str, Path]:
    """Write consolidated summary CSVs per statistic and per experiment."""
    out_dir = repo_root() / "out"
    out_dir.mkdir(parents=True, exist_ok=True)
    fieldnames = PARAMETER_FIELDNAMES + [out_name for _, out_name in CSV_METRIC_MAP]

    written_paths: dict[str, Path] = {}
    stat_kinds = ["median", "mad", "mean", "std", "min", "max"]

    # 1. Overall summary files across all active cases
    for kind in stat_kinds:
        rows = [c_stats[kind] for c_stats in all_case_stat_rows if kind in c_stats]
        csv_path = run_root / f"summary_stats_{kind}.csv"
        with csv_path.open("w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            for r in rows:
                writer.writerow(r)
        written_paths[f"all_{kind}"] = csv_path

    # Also write a timestamped median summary file directly into out/ for easy lookup
    median_rows = [
        c_stats["median"] for c_stats in all_case_stat_rows if "median" in c_stats
    ]
    out_median_csv = out_dir / f"summary_bench_dist_psf_median_{timestamp}.csv"
    with out_median_csv.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for r in median_rows:
            writer.writerow(r)
    written_paths["out_median"] = out_median_csv

    # 2. Per-experiment grouped summary files (e.g. experiment1, experiment2, experiment3)
    study_groups = sorted(
        {
            str(c_stats["median"]["study_group"])
            for c_stats in all_case_stat_rows
            if "median" in c_stats
        }
    )
    for group in study_groups:
        for kind in ("median", "mad"):
            group_rows = [
                c_stats[kind]
                for c_stats in all_case_stat_rows
                if kind in c_stats and str(c_stats[kind]["study_group"]) == group
            ]
            group_csv = run_root / f"summary_stats_{group}_{kind}.csv"
            with group_csv.open("w", newline="") as f:
                writer = csv.DictWriter(f, fieldnames=fieldnames)
                writer.writeheader()
                for r in group_rows:
                    writer.writerow(r)
            written_paths[f"{group}_{kind}"] = group_csv

    return written_paths


def run_case(
    case: dict[str, object],
    run_root: Path,
    image_out_dir: Path | None,
    runs: int,
    frames: int,
    total_threads: int,
    max_raster_workers: int,
    dry_run: bool,
) -> float:
    """Run a single benchmark case across repeat iterations."""
    case_name = str(case["case_name"])
    output_dir = run_root / case_name
    bin_path = binary_path()

    cmd: list[str] = [
        command_path(bin_path),
        "--mesh-subset",
        str(case["mesh_type"]),
        "--mesh-density",
        str(case["mesh_density"]),
        "--distort",
        str(case["distort"]),
        "--psf",
        str(case["psf"]),
        "--runs",
        str(runs),
        "--frames",
        str(frames),
        "--total-threads",
        str(total_threads),
        "--max-raster-workers-per-job",
        str(max_raster_workers),
        "--out-dir",
        str(output_dir),
    ]
    if "subpixel_center_map" in case:
        cmd.extend(["--subpixel-center-map", str(case["subpixel_center_map"])])
    if image_out_dir is not None:
        cmd.extend(["--image-out-dir", str(image_out_dir / case_name)])

    if dry_run:
        print("DRY-RUN:", " ".join(shlex.quote(p) for p in cmd))
        return 0.0

    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "command.txt").write_text(
        " ".join(shlex.quote(p) for p in cmd) + "\n"
    )

    print(f"Running {case_name} ({runs} runs, {frames} frames)...")
    start_time = time.perf_counter()
    res = subprocess.run(cmd, cwd=repo_root(), check=False)
    elapsed = time.perf_counter() - start_time

    if res.returncode != 0:
        print(f"Error running {case_name} (exit code {res.returncode})")
    return elapsed


def main() -> None:
    """CLI Entrypoint for distortion and PSF benchmark orchestration."""
    parser = argparse.ArgumentParser(
        description="Benchmark distortion models and point spread functions in Riley."
    )
    parser.add_argument(
        "--runs",
        type=int,
        default=DEFAULT_RUNS,
        help=f"Repeat count per benchmark case (default: {DEFAULT_RUNS})",
    )
    parser.add_argument(
        "--frames",
        type=int,
        default=DEFAULT_FRAMES,
        help=f"Number of frames per render run (default: {DEFAULT_FRAMES})",
    )
    parser.add_argument(
        "--out-root",
        type=Path,
        default=DEFAULT_OUT_ROOT,
        help="Root directory for stats output",
    )
    parser.add_argument(
        "--image-out-dir",
        type=Path,
        default=None,
        help="Optional directory to save rendered comparison images",
    )
    parser.add_argument(
        "--total-threads",
        type=int,
        default=DEFAULT_TOTAL_THREADS,
        help=f"Total threads budget (default: {DEFAULT_TOTAL_THREADS})",
    )
    parser.add_argument(
        "--max-raster-workers",
        type=int,
        default=DEFAULT_MAX_RASTER_WORKERS_PER_JOB,
        help="Max raster worker threads per job",
    )
    parser.add_argument(
        "--no-exp1",
        action="store_true",
        help="Disable Experiment 1",
    )
    parser.add_argument(
        "--no-exp2",
        action="store_true",
        help="Disable Experiment 2",
    )
    parser.add_argument(
        "--no-exp3",
        action="store_true",
        help="Disable Experiment 3",
    )
    parser.add_argument(
        "--mesh-type",
        type=str,
        default=None,
        help="Filter to a specific element type (e.g. tri3, quad4)",
    )
    parser.add_argument(
        "--mesh-density",
        type=str,
        default=None,
        help="Filter to a specific mesh density (e.g. fullraster, 1e3)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print commands without executing them",
    )

    args = parser.parse_args()
    timestamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    run_root: Path = args.out_root / timestamp

    active_cases: list[dict[str, object]] = []
    if DEFAULT_EXPERIMENT1 and not args.no_exp1:
        active_cases.extend(EXPERIMENT1_CASES)
    if DEFAULT_EXPERIMENT2 and not args.no_exp2:
        active_cases.extend(EXPERIMENT2_CASES)
    if DEFAULT_EXPERIMENT3 and not args.no_exp3:
        active_cases.extend(EXPERIMENT3_CASES)

    if args.mesh_type is not None:
        active_cases = [
            c for c in active_cases if str(c["mesh_type"]) == args.mesh_type
        ]
    if args.mesh_density is not None:
        active_cases = [
            c
            for c in active_cases
            if str(c["mesh_density"]) == args.mesh_density
        ]

    print(f"Benchmark Suite: {len(active_cases)} cases to execute.")
    timing_rows: list[dict[str, object]] = []

    total_start = time.perf_counter()
    for case in active_cases:
        elapsed = run_case(
            case,
            run_root=run_root,
            image_out_dir=args.image_out_dir,
            runs=args.runs,
            frames=args.frames,
            total_threads=args.total_threads,
            max_raster_workers=args.max_raster_workers,
            dry_run=args.dry_run,
        )
        timing_rows.append(
            {
                "study_group": case["study_group"],
                "case_name": case["case_name"],
                "mesh_type": case["mesh_type"],
                "mesh_density": case["mesh_density"],
                "distort": case["distort"],
                "psf": case["psf"],
                "seconds": f"{elapsed:.4f}",
            }
        )

    total_elapsed = time.perf_counter() - total_start
    if not args.dry_run:
        csv_file = write_timing_csv(timing_rows, timestamp)
        all_case_stat_rows = [
            compute_case_stat_rows(case, run_root=run_root, runs=args.runs)
            for case in active_cases
        ]
        summary_paths = write_consolidated_summary_csvs(
            all_case_stat_rows, run_root=run_root, timestamp=timestamp
        )
        print(f"\nBenchmark completed in {total_elapsed:.2f} s.")
        print(f"Stats written to: {run_root}")
        print(f"Summary timing CSV: {csv_file}")
        print(f"Consolidated median summary CSV: {summary_paths['out_median']}")


if __name__ == "__main__":
    main()
