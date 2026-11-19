#!/usr/bin/env python3
from __future__ import annotations


import csv
import datetime as dt
import pathlib


def benchmark_tag(benchmark_name: str) -> str:
    return benchmark_name.removeprefix("bench_")


def repo_root() -> pathlib.Path:
    return pathlib.Path(__file__).resolve().parent.parent


def build_run_root(
    benchmark_name: str,
    out_root: pathlib.Path | None,
) -> pathlib.Path:
    root_dir = out_root or (
        pathlib.Path("out") / f"bench_stats_{benchmark_tag(benchmark_name)}"
    )
    timestamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    return root_dir / timestamp


def default_image_out_dir(benchmark_name: str) -> pathlib.Path:
    return pathlib.Path("out") / f"bench_images_{benchmark_tag(benchmark_name)}"


def timestamp_string() -> str:
    return dt.datetime.now().strftime("%Y%m%d_%H%M%S")


def command_path(path: pathlib.Path) -> str:
    path_abs = path.resolve()
    root_abs = repo_root().resolve()
    try:
        return str(path_abs.relative_to(root_abs))
    except ValueError:
        return str(path_abs)


def format_duration(seconds: float) -> str:
    if seconds >= 3600.0:
        return f"{seconds / 3600.0:.2f} h"
    if seconds >= 60.0:
        return f"{seconds / 60.0:.2f} min"
    return f"{seconds:.2f} s"


def write_timing_csv(
    benchmark_name: str,
    rows: list[dict[str, object]],
    timestamp: str,
) -> pathlib.Path:
    out_dir = repo_root() / "out"
    out_dir.mkdir(parents=True, exist_ok=True)
    csv_path = out_dir / f"time_{benchmark_name}_{timestamp}.csv"
    with csv_path.open("w", newline="") as csv_file:
        writer = csv.DictWriter(
            csv_file,
            fieldnames=[
                "benchmark",
                "kind",
                "name",
                "seconds",
            ],
        )
        writer.writeheader()
        for row in rows:
            writer.writerow(row)
    return csv_path


if __name__ == "__main__":
    raise SystemExit(
        "Import this module from a bench_X.py script.",
    )
