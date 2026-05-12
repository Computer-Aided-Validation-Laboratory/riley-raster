#!/usr/bin/env python3
from __future__ import annotations

import csv
import pathlib
import statistics

from paper_bench_common import combined_case_dir_name
from paper_bench_common import legacy_hull_case_dir_name
from paper_bench_common import legacy_simd_case_dir_name
from paper_bench_common import load_stable_row_map
from paper_verif_const import repo_root


SAVE_STRATEGY = "memory"

ANALYSE_RASTER = True
ANALYSE_GEOM = True
ANALYSE_SPHERE2000 = True
ANALYSE_SPHERE2000ZOOM = True

SIMD_BASE_SIMD = "scalar"
SIMD_BASE_HULL = "off"
SIMD_VARIANT_SIMD = "simd"
SIMD_VARIANT_HULL = "off"
HULL_BASE_SIMD = "scalar"
HULL_BASE_HULL = "off"
HULL_VARIANT_SIMD = "scalar"
HULL_VARIANT_HULL = "on_no_fallback"


BENCH_SPECS = {
    "bench_fullraster": {
        "prefix": "raster",
        "metrics": ["E2E_ms", "Geom_ms", "Raster_ms", "MPx/s"],
        "speed_metrics": ["MPx/s"],
    },
    "bench_geom": {
        "prefix": "geom",
        "metrics": ["E2E_ms", "Geom_ms", "MElems/s"],
        "speed_metrics": ["MElems/s"],
    },
    "bench_sphere2000": {
        "prefix": "sphere2000",
        "metrics": ["E2E_ms", "Geom_ms", "Raster_ms", "MElems/s", "MPx/s"],
        "speed_metrics": ["MElems/s", "MPx/s"],
    },
    "bench_sphere2000zoom": {
        "prefix": "sphere2000zoom",
        "metrics": ["E2E_ms", "Geom_ms", "Raster_ms", "MElems/s", "MPx/s"],
        "speed_metrics": ["MElems/s", "MPx/s"],
    },
}

BENCH_ENABLED = {
    "bench_fullraster": ANALYSE_RASTER,
    "bench_geom": ANALYSE_GEOM,
    "bench_sphere2000": ANALYSE_SPHERE2000,
    "bench_sphere2000zoom": ANALYSE_SPHERE2000ZOOM,
}


def legacy_simd_test_case_dir(
    bench_name: str,
    simd_label: str,
) -> str:
    return legacy_simd_case_dir_name(
        bench_name,
        simd_label,
        SAVE_STRATEGY,
    )


def legacy_hull_test_case_dir(
    bench_name: str,
    simd_label: str,
    hull_mode: str,
) -> str:
    return legacy_hull_case_dir_name(
        bench_name,
        simd_label,
        hull_mode,
        SAVE_STRATEGY,
    )


def combined_test_case_dir(
    bench_name: str,
    simd_label: str,
    hull_mode: str,
) -> str:
    return combined_case_dir_name(
        bench_name,
        simd_label,
        hull_mode,
        SAVE_STRATEGY,
    )


def required_paths_for_case_pair(
    experiment_dir: str,
    base_case_dir: str,
    variant_case_dir: str,
) -> list[str]:
    required_rel_paths: list[str] = []
    for case_dir in (base_case_dir, variant_case_dir):
        for stat_name in ("median", "mad", "min", "max"):
            required_rel_paths.append(
                f"{experiment_dir}/{case_dir}/bench_stats_{stat_name}.csv"
            )
    return required_rel_paths


def resolve_ablation_layout(
    bench_name: str,
    ablation_name: str,
) -> tuple[pathlib.Path, str, str, str]:
    if ablation_name == "simd":
        candidates = [
            (
                "experiment_1",
                combined_test_case_dir(
                    bench_name,
                    SIMD_BASE_SIMD,
                    SIMD_BASE_HULL,
                ),
                combined_test_case_dir(
                    bench_name,
                    SIMD_VARIANT_SIMD,
                    SIMD_VARIANT_HULL,
                ),
                "combined",
            ),
            (
                "experiment_1",
                legacy_simd_test_case_dir(
                    bench_name,
                    SIMD_BASE_SIMD,
                ),
                legacy_simd_test_case_dir(
                    bench_name,
                    SIMD_VARIANT_SIMD,
                ),
                "legacy",
            ),
        ]
    elif ablation_name == "hull":
        candidates = [
            (
                "experiment_1",
                combined_test_case_dir(
                    bench_name,
                    HULL_BASE_SIMD,
                    HULL_BASE_HULL,
                ),
                combined_test_case_dir(
                    bench_name,
                    HULL_VARIANT_SIMD,
                    HULL_VARIANT_HULL,
                ),
                "combined",
            ),
            (
                "experiment_2",
                legacy_hull_test_case_dir(
                    bench_name,
                    "simd",
                    "off",
                ),
                legacy_hull_test_case_dir(
                    bench_name,
                    "simd",
                    "on_no_fallback",
                ),
                "legacy",
            ),
        ]
    else:
        raise ValueError(f"unsupported ablation name: {ablation_name}")

    root_dir = repo_root() / "out" / "benchmark_runs" / bench_name
    run_dirs = sorted(path for path in root_dir.iterdir() if path.is_dir())
    for run_dir in reversed(run_dirs):
        for experiment_dir, base_case_dir, variant_case_dir, _layout_name in candidates:
            required_rel_paths = required_paths_for_case_pair(
                experiment_dir,
                base_case_dir,
                variant_case_dir,
            )
            if all((run_dir / rel_path).exists() for rel_path in required_rel_paths):
                return run_dir, experiment_dir, base_case_dir, variant_case_dir
    raise FileNotFoundError(
        f"no benchmark run in {root_dir} contains a complete {ablation_name} "
        "ablation layout"
    )


def load_stats_bundle(
    run_dir: pathlib.Path,
    experiment_dir: str,
    test_case_dir: str,
) -> dict[str, dict[str, dict[str, str]]]:
    case_dir = run_dir / experiment_dir / test_case_dir
    return {
        stat_name: load_stable_row_map(case_dir / f"bench_stats_{stat_name}.csv")
        for stat_name in ("median", "mad", "min", "max")
    }


def fmt_float(value: float) -> str:
    return f"{value:.6f}"


def calc_speedup(
    base_row: dict[str, str],
    variant_row: dict[str, str],
    metric_name: str,
) -> float:
    base_val = float(base_row[metric_name])
    variant_val = float(variant_row[metric_name])
    if base_val == 0.0:
        return 0.0
    return variant_val / base_val


def build_ablation_rows(
    run_dir: pathlib.Path,
    experiment_dir: str,
    base_case_dir: str,
    variant_case_dir: str,
    metrics: list[str],
    speed_metrics: list[str],
) -> list[dict[str, str]]:
    base_stats = load_stats_bundle(run_dir, experiment_dir, base_case_dir)
    variant_stats = load_stats_bundle(run_dir, experiment_dir, variant_case_dir)

    stable_keys = [
        key
        for key in base_stats["median"].keys()
        if key in variant_stats["median"]
    ]

    rows: list[dict[str, str]] = []
    for stable_key in stable_keys:
        base_meta = base_stats["median"][stable_key]
        variant_meta = variant_stats["median"][stable_key]
        out_row = {
            "CaseStableKey": stable_key,
            "Case": base_meta["Case"],
            "CaseOccurrence": base_meta["CaseOccurrence"],
            "Element": base_meta["Element"],
            "Shader": base_meta["Shader"],
            "Interpolator": base_meta["Interpolator"],
            "BaseConfig": base_case_dir,
            "VariantConfig": variant_case_dir,
        }

        for metric_name in metrics:
            for stat_name in ("median", "mad", "min", "max"):
                out_row[f"{metric_name}_{stat_name}_base"] = (
                    base_stats[stat_name][stable_key][metric_name]
                )
                out_row[f"{metric_name}_{stat_name}_variant"] = (
                    variant_stats[stat_name][stable_key][metric_name]
                )

        for metric_name in speed_metrics:
            speedup = calc_speedup(
                base_stats["median"][stable_key],
                variant_stats["median"][stable_key],
                metric_name,
            )
            out_row[f"{metric_name}_speedup_x"] = fmt_float(speedup)

        out_row["CaseStableKeyTail"] = stable_key
        rows.append(out_row)

    return rows


def write_csv(
    file_name: str,
    rows: list[dict[str, str]],
) -> pathlib.Path:
    out_path = repo_root() / "verif" / file_name
    out_path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        raise ValueError(f"no rows to write for {file_name}")
    field_names = list(rows[0].keys())
    with out_path.open("w", newline="") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=field_names)
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {out_path}")
    return out_path


def summarize_speedups(
    rows: list[dict[str, str]],
    metric_name: str,
) -> tuple[float, float, float]:
    speedups = [float(row[f"{metric_name}_speedup_x"]) for row in rows]
    return min(speedups), statistics.median(speedups), max(speedups)


def analyse_bench(
    bench_name: str,
    prefix: str,
    metrics: list[str],
    speed_metrics: list[str],
) -> tuple[pathlib.Path, pathlib.Path, list[dict[str, str]], list[dict[str, str]]]:
    simd_run_dir, simd_experiment_dir, simd_base_case_dir, simd_variant_case_dir = (
        resolve_ablation_layout(bench_name, "simd")
    )
    hull_run_dir, hull_experiment_dir, hull_base_case_dir, hull_variant_case_dir = (
        resolve_ablation_layout(bench_name, "hull")
    )

    print(
        f"{bench_name}: SIMD run dir = {simd_run_dir} "
        f"({simd_experiment_dir}, {simd_base_case_dir} -> "
        f"{simd_variant_case_dir})"
    )
    print(
        f"{bench_name}: Hull run dir = {hull_run_dir} "
        f"({hull_experiment_dir}, {hull_base_case_dir} -> "
        f"{hull_variant_case_dir})"
    )

    simd_rows = build_ablation_rows(
        simd_run_dir,
        simd_experiment_dir,
        simd_base_case_dir,
        simd_variant_case_dir,
        metrics,
        speed_metrics,
    )
    hull_rows = build_ablation_rows(
        hull_run_dir,
        hull_experiment_dir,
        hull_base_case_dir,
        hull_variant_case_dir,
        metrics,
        speed_metrics,
    )

    simd_csv = write_csv(f"{prefix}_simd_ablation.csv", simd_rows)
    hull_csv = write_csv(f"{prefix}_hull_ablation.csv", hull_rows)
    return simd_csv, hull_csv, simd_rows, hull_rows


def print_raster_overview(
    simd_rows: list[dict[str, str]],
    hull_rows: list[dict[str, str]],
) -> None:
    simd_min, simd_med, simd_max = summarize_speedups(simd_rows, "MPx/s")
    hull_min, hull_med, hull_max = summarize_speedups(hull_rows, "MPx/s")

    e2e_simd = [
        float(row["E2E_ms_median_base"]) / float(row["E2E_ms_median_variant"])
        for row in simd_rows
        if float(row["E2E_ms_median_variant"]) != 0.0
    ]
    e2e_hull = [
        float(row["E2E_ms_median_base"]) / float(row["E2E_ms_median_variant"])
        for row in hull_rows
        if float(row["E2E_ms_median_variant"]) != 0.0
    ]

    print("\nRaster overview")
    print(
        "SIMD ablation MPx/s speedup "
        f"min/median/max = {simd_min:.3f} / {simd_med:.3f} / {simd_max:.3f}"
    )
    print(
        "SIMD ablation E2E speedup "
        f"median = {statistics.median(e2e_simd):.3f}"
    )
    print(
        "Hull ablation MPx/s speedup "
        f"min/median/max = {hull_min:.3f} / {hull_med:.3f} / {hull_max:.3f}"
    )
    print(
        "Hull ablation E2E speedup "
        f"median = {statistics.median(e2e_hull):.3f}"
    )


def main() -> int:
    all_results: dict[str, tuple[pathlib.Path, pathlib.Path, list[dict[str, str]], list[dict[str, str]]]] = {}

    for bench_name, spec in BENCH_SPECS.items():
        if not BENCH_ENABLED[bench_name]:
            print(f"{bench_name}: skipped by top-level selection constant")
            continue
        all_results[bench_name] = analyse_bench(
            bench_name,
            spec["prefix"],
            spec["metrics"],
            spec["speed_metrics"],
        )

    if "bench_fullraster" in all_results:
        _, _, raster_simd_rows, raster_hull_rows = all_results["bench_fullraster"]
        print_raster_overview(raster_simd_rows, raster_hull_rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
