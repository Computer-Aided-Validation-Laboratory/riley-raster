#!/usr/bin/env python3
"""Compare multi-root policies with a shade-matched one-root baseline.

Defaults: 96 elements, 512x512 pixels, 1x1 subsampling. --typical selects
1000 elements, 1024x1024 pixels, and 2x2 subsampling. The flat baseline
footprint is calibrated outside timed runs against legacy_front's aggregate
shaded-subpixel count. Summary CSV includes end-to-end ratios to that baseline.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import itertools
import math
import os
import pathlib
import shlex
import statistics
import struct
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
    "candidate_children",
    "cache_eligible",
    "cache_attempts",
    "cache_successes",
    "cache_failures",
    "extrap_attempts",
    "extrap_successes",
    "center_attempts",
    "center_successes",
    "bank_fallbacks",
    "bank_fallback_successes",
    "bank_improved",
    "bank_recovered",
    "bank_numerical_ties",
    "cross_child",
    "center_failures",
    "reuse_recoveries",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--out-root", type=pathlib.Path,
                        default=pathlib.Path("out/bench_stats_multiroot"))
    parser.add_argument("--elements-per-type", type=int, default=24)
    parser.add_argument("--width", type=int, default=512)
    parser.add_argument("--height", type=int, default=512)
    parser.add_argument("--sub-sample", type=int, default=1)
    parser.add_argument("--typical", action="store_true",
                        help="Use 1000 elements, 1024x1024, 2x2 subsampling")
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("--warmup", type=int, default=1)
    parser.add_argument("--threads", type=int, default=1)
    parser.add_argument("--optimize", default="ReleaseSafe")
    parser.add_argument("--quick", action="store_true",
                        help="One short run of each main method")
    parser.add_argument("--reuse-experiment", action="store_true",
                        help="Run only the ten fixed4 reuse-plan policies")
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--skip-verif", action="store_true",
                        help="Do not run and tabulate the offline root oracle")
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


def build_cases(
    quick: bool, reuse_experiment: bool = False
) -> list[tuple[str, str, bool, bool, int, str]]:
    if reuse_experiment:
        focused = [
            ("fixed4", "center", False, False, 1, "column"),
            ("fixed4", "center", True, False, 1, "column"),
        ]
        for method in ("column", "nearest_2d", "interp_2d", "affine_2d"):
            focused.append(("fixed4_reuse", "center", False, False, 1, method))
            focused.append((
                "fixed4_centre_reuse", "center", False, False, 1, method
            ))
        return focused
    existing = [
        ("legacy_front", "center", False, False),
        ("legacy_depth", "center", False, False),
        ("fixed4", "center", False, False),
        ("fixed16", "center", False, False),
        ("adaptive", "center", False, False),
        ("fixed4", "center", True, False),
        ("fixed16", "center", True, False),
        ("adaptive", "center", True, False),
    ]
    coherent = [
        ("patch_center", "center", False, False),
        ("patch_reuse", "center", False, False),
        ("patch_reuse_seedbank", "center", False, False),
        ("patch_extrapolate", "center", False, False),
        ("patch_extrapolate_seedbank", "center", False, False),
        ("all_seeds", "center", False, False),
    ]
    main = [(*case, 1, "column") for case in existing + coherent]
    if quick:
        return main
    extra = list(itertools.product(
        ("fixed4", "fixed16", "adaptive"),
        ("front_near", "front_strong"),
        (False, True),
        (False,),
    ))
    frozen = [
        (method, "center", fallback, True)
        for method in ("fixed4", "fixed16", "adaptive")
        for fallback in (False, True)
    ]
    radius_sweep = [(*case, radius, "column") for case in coherent[1:5]
                    for radius in (2, 4)]
    return main + [(*case, 1, "column") for case in extra + frozen] + radius_sweep


def run_case(
    args: argparse.Namespace,
    backend: str,
    name: str,
    method: str,
    seed: str,
    fallback: bool,
    frozen: bool,
    radius: int = 1,
    reuse_method: str = "column",
    scene: str = "multi_root",
    flat_scale: float = 1.0,
    runs: int | None = None,
    warmup: int | None = None,
) -> list[dict[str, str]]:
    exe = ROOT / "zig-out" / "bin" / f"bench_multiroot_f64_{backend}"
    case_dir = args.out_dir / name
    cmd = [
        str(exe), "--out-dir", str(case_dir),
        "--elements-per-type", str(args.elements_per_type),
        "--width", str(args.width), "--height", str(args.height),
        "--sub-sample", str(args.sub_sample),
        "--runs", str(args.runs if runs is None else runs),
        "--warmup", str(args.warmup if warmup is None else warmup),
        "--threads", str(args.threads), "--method", method,
        "--child-seed", seed, "--scene", scene,
        "--flat-scale", str(flat_scale),
        "--legacy-fallback", "on" if fallback else "off",
        "--single-frozen-jac", "on" if frozen else "off",
        "--reuse-radius-rows", str(radius),
        "--reuse-method", reuse_method,
    ]
    print(name, flush=True)
    case_dir.mkdir(parents=True, exist_ok=True)
    (case_dir / "command.txt").write_text(
        " ".join(shlex.quote(part) for part in cmd) + "\n"
    )
    with (args.out_dir / f"{name}.log").open("w") as log:
        subprocess.run(cmd, cwd=ROOT, stdout=log,
                       stderr=subprocess.STDOUT, check=True)
    with (case_dir / "raw_stats_multiroot.csv").open(newline="") as file:
        return [{"backend": backend, **row} for row in csv.DictReader(file)]


def match_flat_shading(args: argparse.Namespace, target: int) -> float:
    """Match aggregate shaded subpixels outside the timed baseline runs."""
    scale = 1.0
    best_scale = scale
    best_error = float("inf")
    tolerance = max(0.005, 16 / target)
    for attempt in range(10):
        rows = run_case(args, "scalar", f"calibrate_flat_{attempt}",
                        "legacy_front", "center", False, False,
                        scene="one_root", flat_scale=scale,
                        runs=1, warmup=0)
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
    raise RuntimeError(f"Flat baseline shading mismatch: best error "
                       f"{best_error:.2%}, allowed {tolerance:.2%}")


def write_coherent_accuracy_summary(
    rows: list[dict[str, str]], out_dir: pathlib.Path
) -> None:
    """Aggregate per-patch oracle counts by geometry and policy."""
    count_fields = (
        "rays", "oracle_hits", "front", "nearest", "stage1_attempted",
        "stage1_miss", "stage1_wrong", "stage2_miss", "stage2_wrong",
        "bank_recovered", "bank_improved", "false_front",
        "hull_missed", "child_missed", "child_rejected_misses",
        "starts", "iters", "newton_failures",
        "center_iters", "reuse_iters", "d3_iters",
        "reuse_eligible", "reuse_attempts", "reuse_successes",
        "center_attempts", "center_successes", "center_failures",
        "reuse_recoveries", "d3_invocations", "d3_recoveries",
    )
    groups: dict[tuple[str, str, str, str], dict[str, int]] = {}
    variants: dict[tuple[str, str, str, str, str], dict[str, int]] = {}
    for row in rows:
        if row["family"] != "coherentmatrix":
            continue
        key = (row["reference"], row["kind"], row["N"], row["policy"])
        counts = groups.setdefault(key, dict.fromkeys(count_fields, 0))
        variant_key = (row["reference"], row["kind"], row["N"],
                       row["variant"], row["policy"])
        variant_counts = variants.setdefault(
            variant_key, dict.fromkeys(count_fields, 0)
        )
        for field in count_fields:
            counts[field] += int(row[field])
            variant_counts[field] += int(row[field])
    if not groups:
        raise RuntimeError("No coherent oracle rows in verification.log")
    summary = []
    for (reference, kind, nodes, policy), counts in sorted(groups.items()):
        hits = counts["oracle_hits"]
        total_hits = hits + counts["hull_missed"] + counts["child_missed"]
        rays = counts["rays"]
        summary.append({
            "reference": reference,
            "oracle_scope": (
                "candidate_only" if reference == "analytic_fe"
                else "full_sensor"
            ),
            "kind": kind, "N": nodes, "policy": policy,
            **counts,
            "front_pct": (
                100 * (counts["front"] - counts["false_front"]) / hits
                if hits else 0
            ),
            "nearest_pct": 100 * counts["nearest"] / hits if hits else 0,
            "pipeline_nearest_pct": (
                100 * counts["nearest"] / total_hits
                if total_hits and reference != "analytic_fe" else ""
            ),
            "starts_per_ray": counts["starts"] / rays if rays else 0,
            "iters_per_ray": counts["iters"] / rays if rays else 0,
            "iters_per_front": (
                counts["iters"] / counts["front"]
                if counts["front"] else 0
            ),
            "reuse_success_pct": (
                100 * counts["reuse_successes"] / counts["reuse_attempts"]
                if counts["reuse_attempts"] else 0
            ),
            "center_failure_recovery_pct": (
                100 * counts["reuse_recoveries"] / counts["center_failures"]
                if counts["center_failures"] else 0
            ),
        })
    for reference, filename in (
        ("analytic", "accuracy_summary_coherent_multiroot.csv"),
        ("full_bank", "bank_agreement_summary_coherent_multiroot.csv"),
    ):
        selected = [row for row in summary if
                    (row["reference"] in ("analytic", "analytic_fe"))
                    == (reference == "analytic")]
        if not selected:
            if reference == "full_bank":
                continue
            raise RuntimeError("No analytic coherent oracle rows")
        path = out_dir / filename
        with path.open("w", newline="") as file:
            writer = csv.DictWriter(file, fieldnames=selected[0].keys())
            writer.writeheader()
            writer.writerows(selected)
    variant_summary = []
    for key, counts in sorted(variants.items()):
        reference, kind, nodes, variant, policy = key
        if reference not in ("analytic", "analytic_fe"):
            continue
        hits = counts["oracle_hits"]
        total_hits = hits + counts["hull_missed"] + counts["child_missed"]
        variant_summary.append({
            "reference": reference,
            "oracle_scope": (
                "candidate_only" if reference == "analytic_fe"
                else "full_sensor"
            ),
            "kind": kind, "N": nodes,
            "variant": variant, "policy": policy, **counts,
            "nearest_pct": 100 * counts["nearest"] / hits if hits else 0,
            "pipeline_nearest_pct": (
                100 * counts["nearest"] / total_hits
                if total_hits and reference != "analytic_fe" else ""
            ),
            "starts_per_ray": (
                counts["starts"] / counts["rays"] if counts["rays"] else 0
            ),
            "iters_per_ray": (
                counts["iters"] / counts["rays"] if counts["rays"] else 0
            ),
        })
    path = out_dir / "accuracy_by_variant_coherent_multiroot.csv"
    with path.open("w", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=variant_summary[0].keys())
        writer.writeheader()
        writer.writerows(variant_summary)


def write_analytic_hit_list(log: str, out_dir: pathlib.Path) -> None:
    """Decode one bit per reference-hit pixel, excluding bank-only data."""
    path = out_dir / "analytic_hit_list_multiroot.csv"
    with path.open("w", newline="") as file:
        writer = csv.writer(file)
        writer.writerow(("reference", "oracle_scope", "kind", "N",
                         "variant", "pixel_x", "pixel_y", "inverse_depth"))
        for line in log.splitlines():
            start = line.find("coherenthitmask ")
            if start < 0:
                continue
            fields = dict(token.split("=", 1) for token in
                          line[start:].split()[1:])
            width = int(fields["width"])
            height = int(fields["height"])
            mask = bytes.fromhex(fields["bits"])
            if len(mask) * 8 != width * height:
                raise RuntimeError("Malformed analytic hit mask")
            depths = struct.iter_unpack("!d", bytes.fromhex(fields["depths"]))
            scope = ("candidate_only" if fields["reference"] == "analytic_fe"
                     else "full_sensor")
            for index in range(width * height):
                if mask[index // 8] & (1 << (index % 8)):
                    writer.writerow((fields["reference"], scope,
                                     fields["kind"], fields["N"],
                                     fields["variant"], index % width,
                                     index // width, next(depths)[0]))
            if next(depths, None) is not None:
                raise RuntimeError("Extra analytic hit depths")


def main() -> None:
    args = parse_args()
    timestamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    args.out_dir = args.out_root / timestamp
    args.out_dir.mkdir(parents=True, exist_ok=True)
    backends = ("scalar", "simd")
    if not args.skip_build:
        for backend in backends:
            subprocess.run(
                ["zig", "build", "install-bench-multiroot",
                 f"-Doptimize={args.optimize}",
                 f"-Dsimd={'off' if backend == 'scalar' else 'on'}"],
                cwd=ROOT,
                check=True,
            )
    raw_rows: list[dict[str, str]] = []
    for backend in backends:
        cases = build_cases(args.quick, args.reuse_experiment)
        for method, seed, fallback, frozen, radius, reuse_method in cases:
            name = (f"{backend}_{method}_{seed}_fb{int(fallback)}"
                    f"_fj{int(frozen)}_r{radius}_m{reuse_method}")
            raw_rows.extend(run_case(args, backend, name, method, seed,
                                     fallback, frozen, radius, reuse_method))
    reference = next(row for row in raw_rows if
                     row["backend"] == "scalar" and
                     ((args.reuse_experiment and row["method"] == "fixed4" and
                       row["legacy_fallback"] == "true") or
                      (not args.reuse_experiment and
                       row["method"] == "legacy_front")))
    target_shaded = int(reference["shaded"])
    if target_shaded == 0:
        raise RuntimeError("Multi-root reference shaded no samples")
    flat_scale = match_flat_shading(args, target_shaded)
    for backend in backends:
        raw_rows.extend(run_case(
            args, backend, f"{backend}_one_root_baseline",
            "legacy_front", "center", False, False,
            scene="one_root", flat_scale=flat_scale,
        ))
    with (args.out_dir / "raw_stats_multiroot.csv").open("w", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=raw_rows[0].keys())
        writer.writeheader()
        writer.writerows(raw_rows)
    scalar_rows = {}
    for row in raw_rows:
        key = (row["scene"], row["method"], row["child_seed"],
               row["legacy_fallback"],
               row["single_frozen_jac"], row["reuse_radius_rows"],
               row["reuse_method"], row["run"])
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
        cases = [("multi_root", *case) for case in
                 build_cases(args.quick, args.reuse_experiment)]
        cases.append(("one_root", "legacy_front", "center", False, False,
                      1, "column"))
        for scene, method, seed, fallback, frozen, radius, reuse_method in cases:
            group = [row for row in raw_rows if
                     row["backend"] == backend and row["scene"] == scene and
                     row["method"] == method and
                     row["child_seed"] == seed and
                     row["legacy_fallback"] == str(fallback).lower() and
                     row["single_frozen_jac"] == str(frozen).lower() and
                     row["reuse_radius_rows"] == str(radius) and
                     row["reuse_method"] == reuse_method]
            row = {"backend": backend, "scene": scene, "method": method,
                   "child_seed": seed, "legacy_fallback": fallback,
                   "single_frozen_jac": frozen,
                   "reuse_radius_rows": radius, "runs": len(group)}
            row["reuse_method"] = reuse_method
            for field in FIELDS:
                values = [float(item[field]) for item in group]
                row[f"{field}_median"] = statistics.median(values)
                row[f"{field}_mean"] = statistics.mean(values)
                row[f"{field}_std"] = (
                    statistics.stdev(values) if len(values) > 1 else 0.0
                )
                row[f"{field}_min"] = min(values)
                row[f"{field}_max"] = max(values)
            summary_rows.append(row)
    for row in summary_rows:
        baseline = next(item for item in summary_rows if
                        item["backend"] == row["backend"] and
                        item["scene"] == "one_root")
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
    if not args.skip_verif:
        verify = subprocess.run(
            ["zig", "build", "test-verif", "-Doptimize=Debug"],
            cwd=ROOT,
            env={**os.environ, "RILEY_ORACLE_HIT_LIST": "1"},
            capture_output=True,
            text=True,
        )
        log = verify.stdout + verify.stderr
        (args.out_dir / "verification.log").write_text(log)
        if verify.returncode:
            raise RuntimeError("Verification failed; see verification.log")
        accuracy_rows = []
        for line in log.splitlines():
            markers = ("hierarchymatrix ", "hierarchyseed ",
                       "facingmatrix ", "seedmatrix ",
                       "coherentmatrix ")
            start = next((line.find(marker) for marker in markers
                          if marker in line), -1)
            if start < 0:
                continue
            line = line[start:]
            family, *tokens = line.split()
            row = {"family": family}
            for token in tokens:
                if "=" in token:
                    key, value = token.split("=", 1)
                    row[key] = value
            accuracy_rows.append(row)
        if not accuracy_rows:
            raise RuntimeError("No oracle accuracy rows in verification.log")
        fieldnames = list(dict.fromkeys(
            key for row in accuracy_rows for key in row))
        with (args.out_dir / "accuracy_stats_multiroot.csv").open(
            "w", newline=""
        ) as file:
            writer = csv.DictWriter(file, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(accuracy_rows)
        write_coherent_accuracy_summary(accuracy_rows, args.out_dir)
        write_analytic_hit_list(log, args.out_dir)
    print(f"Raw and summary CSV: {args.out_dir}")


if __name__ == "__main__":
    main()
