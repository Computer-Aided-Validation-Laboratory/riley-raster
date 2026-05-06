#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import pathlib
import shlex
import subprocess
import sys


DEFAULT_PIXELS_X = 1600
DEFAULT_PIXELS_Y = 1000
DEFAULT_SUB_SAMPLE = 1
DEFAULT_TOTAL_THREADS = 1


def repo_root() -> pathlib.Path:
    return pathlib.Path(__file__).resolve().parent.parent


def build_run_root(
    benchmark_name: str,
    out_root: pathlib.Path | None,
) -> pathlib.Path:
    root_dir = out_root or (
        repo_root() / "out" / "benchmark_runs" / benchmark_name
    )
    timestamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    return root_dir / timestamp


def experiment_1_cases(benchmark_name: str) -> list[dict[str, object]]:
    cases: list[dict[str, object]] = []
    for simd_label in ("scalar", "simd"):
        for save_strategy in ("disk", "memory"):
            case_name = (
                f"{benchmark_name}_simd-{simd_label}"
                f"_save-{save_strategy}"
            )
            cases.append(
                {
                    "experiment": "experiment_1",
                    "case_name": case_name,
                    "executable": f"{benchmark_name}_{simd_label}",
                    "args": [
                        "--save-strategy",
                        save_strategy,
                    ],
                }
            )
    return cases


def experiment_2_cases(benchmark_name: str) -> list[dict[str, object]]:
    cases: list[dict[str, object]] = []
    for hull_mode in ("on_no_fallback", "off"):
        for save_strategy in ("disk", "memory"):
            case_name = (
                f"{benchmark_name}_simd-simd"
                f"_hull-{hull_mode}"
                f"_save-{save_strategy}"
            )
            cases.append(
                {
                    "experiment": "experiment_2",
                    "case_name": case_name,
                    "executable": f"{benchmark_name}_simd",
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
        str(output_dir),
        "--pixels-x",
        str(DEFAULT_PIXELS_X),
        "--pixels-y",
        str(DEFAULT_PIXELS_Y),
        "--sub-sample",
        str(DEFAULT_SUB_SAMPLE),
        "--total-threads",
        str(DEFAULT_TOTAL_THREADS),
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
        choices=("all", "1", "2"),
        default="all",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
    )
    args = parser.parse_args()

    run_root = build_run_root(benchmark_name, args.out_root)
    cases: list[dict[str, object]] = []
    if args.experiment in ("all", "1"):
        cases.extend(experiment_1_cases(benchmark_name))
    if args.experiment in ("all", "2"):
        cases.extend(experiment_2_cases(benchmark_name))

    if not args.dry_run:
        run_root.mkdir(parents=True, exist_ok=True)

    for case in cases:
        run_case(
            benchmark_name,
            case,
            run_root,
            args.runs,
            args.dry_run,
        )

    if not args.dry_run:
        print(f"Results written under {run_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(
        "Import this module from a bench_X.py script.",
    )
