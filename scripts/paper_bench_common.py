#!/usr/bin/env python3
from __future__ import annotations

import csv
import pathlib
import statistics

from paper_verif_const import PAPER_DIR, repo_root


def latest_run_dir(bench_name: str) -> pathlib.Path:
    root_dir = repo_root() / "out" / "benchmark_runs" / bench_name
    run_dirs = sorted(
        path for path in root_dir.iterdir() if path.is_dir()
    )
    if not run_dirs:
        raise FileNotFoundError(f"no benchmark runs found in {root_dir}")
    return run_dirs[-1]


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
    return f"${median_val:.1f} \\pm {mad_val:.1f}$"


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
