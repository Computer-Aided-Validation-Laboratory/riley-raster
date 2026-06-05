#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import datetime as dt
import pathlib
import shlex
import subprocess
import sys
import time


SAVE_STRATEGIES = (
    "memory",
)
SIMD_LABELS = ("scalar", "simd")
HULL_MODES = ("off", "on_no_fallback")


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


def experiment_1_cases(benchmark_name: str) -> list[dict[str, object]]:
    cases: list[dict[str, object]] = []
    for simd_label in SIMD_LABELS:
        for hull_mode in HULL_MODES:
            for save_strategy in SAVE_STRATEGIES:
                case_name = (
                    f"{benchmark_name}_simd-{simd_label}"
                    f"_hull-{hull_mode}"
                    f"_save-{save_strategy}"
                )
                cases.append(
                    {
                        "experiment": "experiment_1",
                        "case_name": case_name,
                        "executable": f"{benchmark_name}_{simd_label}",
                        "args": [
                            "--hull-mode",
                            hull_mode,
                            "--save-strategy",
                            save_strategy,
                        ],
                    }
                )
    return cases


def write_command_file(
    output_dir: pathlib.Path,
    command: list[str],
) -> None:
    command_path = output_dir / "command.txt"
    command_path.write_text(
        " ".join(shlex.quote(part) for part in command) + "\n",
    )


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


def run_case(
    benchmark_name: str,
    case: dict[str, object],
    run_root: pathlib.Path,
    runs: int | None,
    dry_run: bool,
) -> None:
    output_dir = run_root / case["experiment"] / case["case_name"]

    executable_path = repo_root() / "bin" / str(case["executable"])
    command = [
        str(executable_path),
        "--out-dir",
        command_path(output_dir),
        "--image-out-dir",
        command_path(default_image_out_dir(benchmark_name)),
    ]
    if runs is not None:
        command.extend(["--runs", str(runs)])
    command.extend(str(arg) for arg in case["args"])

    print(f"[{benchmark_name}] {case['case_name']}")
    if dry_run:
        print("  dry-run:", " ".join(shlex.quote(part) for part in command))
        return

    output_dir.mkdir(parents=True, exist_ok=True)
    write_command_file(output_dir, command)

    stdout_path = output_dir / "stdout.txt"
    stderr_path = output_dir / "stderr.txt"
    with stdout_path.open("w") as stdout_file, stderr_path.open(
        "w"
    ) as stderr_file:
        subprocess.run(
            command,
            check=True,
            cwd=repo_root(),
            stdout=stdout_file,
            stderr=stderr_file,
        )


def run_benchmark_matrix(benchmark_name: str) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--out-root",
        type=pathlib.Path,
        default=None,
    )
    parser.add_argument(
        "--runs",
        type=int,
        default=None,
    )
    parser.add_argument(
        "--experiment",
        choices=("all", "1"),
        default="all",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
    )
    args = parser.parse_args()

    timing_timestamp = timestamp_string()
    run_root = build_run_root(benchmark_name, args.out_root)
    cases: list[dict[str, object]] = []
    if args.experiment in ("all", "1"):
        cases.extend(experiment_1_cases(benchmark_name))

    if not args.dry_run:
        run_root.mkdir(parents=True, exist_ok=True)

    script_start = time.perf_counter()
    timing_rows: list[dict[str, object]] = []

    if args.experiment in ("all", "1"):
        exp_start = time.perf_counter()
        for cc in cases:
            run_case(
                benchmark_name,
                cc,
                run_root,
                args.runs,
                args.dry_run,
            )
        exp_seconds = time.perf_counter() - exp_start
        print(
            f"[{benchmark_name}] Experiment 1 summary: {format_duration(exp_seconds)}"
        )
        timing_rows.append(
            {
                "benchmark": benchmark_name,
                "kind": "experiment",
                "name": "experiment_1",
                "seconds": f"{exp_seconds:.6f}",
            }
        )

    total_seconds = time.perf_counter() - script_start
    print(f"[{benchmark_name}] Total summary: {format_duration(total_seconds)}")
    timing_rows.append(
        {
            "benchmark": benchmark_name,
            "kind": "total",
            "name": "all",
            "seconds": f"{total_seconds:.6f}",
        }
    )
    if not args.dry_run:
        timing_csv = write_timing_csv(benchmark_name, timing_rows, timing_timestamp)
        print(f"[{benchmark_name}] Timing written to {timing_csv}")
        print(f"Results written under {run_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(
        "Import this module from a bench_X.py script.",
    )
