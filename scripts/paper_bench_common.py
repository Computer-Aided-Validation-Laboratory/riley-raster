#!/usr/bin/env python3
from __future__ import annotations

import csv
import pathlib
import statistics
from collections import Counter

from paper_const import PAPER_DIR, repo_root
from paper_const import TABLE_MAD_DECIMAL_PLACES
from paper_const import TABLE_MEDIAN_DECIMAL_PLACES


def bench_tag(bench_name: str) -> str:
    return bench_name.removeprefix("bench_")


def benchmark_root_dir(bench_name: str) -> pathlib.Path:
    repo = repo_root()
    preferred = repo / "out" / f"bench_stats_{bench_tag(bench_name)}"
    if preferred.exists():
        return preferred
    legacy = repo / "out" / "benchmark_runs" / bench_name
    return legacy


def latest_run_dir(bench_name: str) -> pathlib.Path:
    root_dir = benchmark_root_dir(bench_name)
    run_dirs = sorted(
        path for path in root_dir.iterdir() if path.is_dir()
    )
    if not run_dirs:
        raise FileNotFoundError(f"no benchmark runs found in {root_dir}")
    return run_dirs[-1]


def latest_run_dir_with_paths(
    bench_name: str,
    required_rel_paths: list[str],
) -> pathlib.Path:
    root_dir = benchmark_root_dir(bench_name)
    run_dirs = sorted(
        path for path in root_dir.iterdir() if path.is_dir()
    )
    for run_dir in reversed(run_dirs):
        if all((run_dir / rel_path).exists() for rel_path in required_rel_paths):
            return run_dir
    raise FileNotFoundError(
        f"no benchmark run in {root_dir} contains required paths: "
        f"{required_rel_paths}"
    )


def combined_case_dir_name(
    bench_name: str,
    simd_label: str,
    hull_mode: str,
    save_strategy: str,
) -> str:
    return (
        f"{bench_name}_simd-{simd_label}"
        f"_hull-{hull_mode}"
        f"_save-{save_strategy}"
    )


def legacy_simd_case_dir_name(
    bench_name: str,
    simd_label: str,
    save_strategy: str,
) -> str:
    return f"{bench_name}_simd-{simd_label}_save-{save_strategy}"


def legacy_hull_case_dir_name(
    bench_name: str,
    simd_label: str,
    hull_mode: str,
    save_strategy: str,
) -> str:
    return (
        f"{bench_name}_simd-{simd_label}"
        f"_hull-{hull_mode}"
        f"_save-{save_strategy}"
    )


def latest_stats_dir_with_candidates(
    bench_name: str,
    candidates: list[tuple[str, str]],
    required_file_names: list[str] | None = None,
) -> pathlib.Path:
    required_file_names = required_file_names or ["bench_stats_median.csv"]
    root_dir = benchmark_root_dir(bench_name)
    run_dirs = sorted(path for path in root_dir.iterdir() if path.is_dir())
    for run_dir in reversed(run_dirs):
        for experiment_dir, test_case_dir in candidates:
            required_rel_paths = [
                f"{experiment_dir}/{test_case_dir}/{file_name}"
                for file_name in required_file_names
            ]
            if all((run_dir / rel_path).exists() for rel_path in required_rel_paths):
                return run_dir / experiment_dir / test_case_dir
    raise FileNotFoundError(
        f"no benchmark stats found in {root_dir} for candidates: {candidates}"
    )


def load_case_map_from_dir(
    stats_path: pathlib.Path,
    file_name: str,
) -> dict[str, dict[str, str]]:
    csv_path = stats_path / file_name
    with csv_path.open(newline="") as csv_file:
        rows = list(csv.DictReader(csv_file))
    return {row["Case"]: row for row in rows}


def load_run_case_rows_from_dir(
    stats_path: pathlib.Path,
) -> list[dict[str, dict[str, str]]]:
    run_paths = sorted(stats_path.glob("bench_run*.csv"))
    case_maps: list[dict[str, dict[str, str]]] = []
    for run_path in run_paths:
        with run_path.open(newline="") as csv_file:
            rows = list(csv.DictReader(csv_file))
        case_maps.append({row["Case"]: row for row in rows})
    return case_maps


def stats_dir(
    bench_name: str,
    experiment_dir: str,
    test_case_dir: str,
) -> pathlib.Path:
    return latest_run_dir(bench_name) / experiment_dir / test_case_dir


def load_case_map(
    bench_name: str,
    experiment_dir: str,
    test_case_dir: str,
    file_name: str,
) -> dict[str, dict[str, str]]:
    csv_path = stats_dir(
        bench_name,
        experiment_dir,
        test_case_dir,
    ) / file_name
    with csv_path.open(newline="") as csv_file:
        rows = list(csv.DictReader(csv_file))
    return {row["Case"]: row for row in rows}


def fmt_triplet(
    median_row: dict[str, str],
    mad_row: dict[str, str],
    col_name: str,
) -> str:
    median_val = float(median_row[col_name])
    mad_val = float(mad_row[col_name])
    return (
        f"${median_val:.{TABLE_MEDIAN_DECIMAL_PLACES}f} "
        f"\\pm {mad_val:.{TABLE_MAD_DECIMAL_PLACES}f}$"
    )


def row_value(
    row: dict[str, str],
    *col_names: str,
) -> str:
    for col_name in col_names:
        if col_name in row and row[col_name] != "":
            return row[col_name]
    raise KeyError(f"missing columns {col_names} in row")


def row_float(
    row: dict[str, str],
    *col_names: str,
) -> float:
    return float(row_value(row, *col_names))


def fmt_triplet_any(
    median_row: dict[str, str],
    mad_row: dict[str, str],
    *col_names: str,
) -> str:
    median_val = row_float(median_row, *col_names)
    mad_val = row_float(mad_row, *col_names)
    return (
        f"${median_val:.{TABLE_MEDIAN_DECIMAL_PLACES}f} "
        f"\\pm {mad_val:.{TABLE_MAD_DECIMAL_PLACES}f}$"
    )


def load_run_case_rows(
    bench_name: str,
    experiment_dir: str,
    test_case_dir: str,
) -> list[dict[str, dict[str, str]]]:
    run_dir = stats_dir(bench_name, experiment_dir, test_case_dir)
    run_paths = sorted(run_dir.glob("bench_run*.csv"))
    case_maps: list[dict[str, dict[str, str]]] = []
    for run_path in run_paths:
        with run_path.open(newline="") as csv_file:
            rows = list(csv.DictReader(csv_file))
        case_maps.append({row["Case"]: row for row in rows})
    return case_maps


def add_stable_case_keys(
    rows: list[dict[str, str]],
) -> list[dict[str, str]]:
    case_counts = Counter(row["Case"] for row in rows)
    seen_counts: dict[str, int] = {}
    keyed_rows: list[dict[str, str]] = []

    for row in rows:
        case_name = row["Case"]
        seen_counts[case_name] = seen_counts.get(case_name, 0) + 1
        case_occ = seen_counts[case_name]
        stable_key = case_name
        if case_counts[case_name] > 1:
            stable_key = f"{case_name}__{case_occ}"

        keyed_row = dict(row)
        keyed_row["CaseStableKey"] = stable_key
        keyed_row["CaseOccurrence"] = str(case_occ)
        keyed_rows.append(keyed_row)

    return keyed_rows


def load_stable_row_map(csv_path: pathlib.Path) -> dict[str, dict[str, str]]:
    with csv_path.open(newline="") as csv_file:
        rows = list(csv.DictReader(csv_file))
    keyed_rows = add_stable_case_keys(rows)
    return {row["CaseStableKey"]: row for row in keyed_rows}


def calc_median_mad(values: list[float]) -> tuple[float, float]:
    if not values:
        return 0.0, 0.0
    median_val = statistics.median(values)
    abs_devs = [abs(val - median_val) for val in values]
    mad_val = statistics.median(abs_devs)
    return median_val, mad_val


def write_tabs_tex(
    file_name: str,
    tabs_tex: str,
) -> None:
    verif_path = repo_root() / "verif" / file_name
    paper_path = PAPER_DIR / file_name
    verif_path.parent.mkdir(parents=True, exist_ok=True)
    PAPER_DIR.mkdir(parents=True, exist_ok=True)
    verif_path.write_text(tabs_tex)
    paper_path.write_text(tabs_tex)
    print(f"Wrote {verif_path}")
    print(f"Wrote {paper_path}")
