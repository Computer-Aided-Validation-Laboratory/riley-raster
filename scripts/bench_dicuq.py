#!/usr/bin/env python3
from __future__ import annotations

import argparse
import pathlib
import shlex
import subprocess

from bench_common import build_run_root
from bench_common import command_path
from bench_common import repo_root
from bench_common import write_command_file


THREAD_COUNTS = [1, 2, 4, 8]
FRAMES_IN_FLIGHT = [1, 2, 4, 8]
RENDER_MODES = ["offline", "in_order"]
#SAVE_STRATEGIES = ["disk", "memory"]
SAVE_STRATEGIES = ["memory"]
SAMPLE = "cubic_catmull_rom"
SAMPLE_MODE = "lut_lerp"


def experiment_1_cases() -> list[dict[str, object]]:
    cases: list[dict[str, object]] = []
    for total_threads in THREAD_COUNTS:
        for save_strategy in SAVE_STRATEGIES:
            case_name = (
                "bench_dicuq"
                f"_threads-{total_threads}"
                f"_geom-{total_threads}"
                f"_raster-{total_threads}"
                "_frames-1"
                "_render-offline"
                f"_save-{save_strategy}"
            )
            cases.append(
                {
                    "experiment": "experiment_1_all_threads",
                    "case_name": case_name,
                    "args": [
                        "--render-mode",
                        "offline",
                        "--max-frames-in-flight",
                        "1",
                        "--save-strategy",
                        save_strategy,
                        "--total-threads",
                        str(total_threads),
                        "--max-geom-threads-per-frame",
                        str(total_threads),
                        "--max-raster-threads-per-frame",
                        str(total_threads),
                        "--sample",
                        SAMPLE,
                        "--sample-mode",
                        SAMPLE_MODE,
                    ],
                }
            )
    return cases


def experiment_2_cases() -> list[dict[str, object]]:
    cases: list[dict[str, object]] = []
    for total_threads in THREAD_COUNTS:
        for save_strategy in SAVE_STRATEGIES:
            case_name = (
                "bench_dicuq"
                f"_threads-{total_threads}"
                "_geom-1"
                f"_raster-{total_threads}"
                "_frames-1"
                "_render-offline"
                f"_save-{save_strategy}"
            )
            cases.append(
                {
                    "experiment": "experiment_2_geom_threads_1",
                    "case_name": case_name,
                    "args": [
                        "--render-mode",
                        "offline",
                        "--max-frames-in-flight",
                        "1",
                        "--save-strategy",
                        save_strategy,
                        "--total-threads",
                        str(total_threads),
                        "--max-geom-threads-per-frame",
                        "1",
                        "--max-raster-threads-per-frame",
                        str(total_threads),
                        "--sample",
                        SAMPLE,
                        "--sample-mode",
                        SAMPLE_MODE,
                    ],
                }
            )
    return cases


def experiment_3_cases() -> list[dict[str, object]]:
    cases: list[dict[str, object]] = []
    for max_frames_in_flight in FRAMES_IN_FLIGHT:
        for save_strategy in SAVE_STRATEGIES:
            case_name = (
                "bench_dicuq"
                "_threads-4"
                "_geom-1"
                "_raster-4"
                f"_frames-{max_frames_in_flight}"
                "_render-offline"
                f"_save-{save_strategy}"
            )
            cases.append(
                {
                    "experiment": "experiment_3_frames_in_flight",
                    "case_name": case_name,
                    "args": [
                        "--render-mode",
                        "offline",
                        "--max-frames-in-flight",
                        str(max_frames_in_flight),
                        "--save-strategy",
                        save_strategy,
                        "--total-threads",
                        "4",
                        "--max-geom-threads-per-frame",
                        "1",
                        "--max-raster-threads-per-frame",
                        "4",
                        "--sample",
                        SAMPLE,
                        "--sample-mode",
                        SAMPLE_MODE,
                    ],
                }
            )
    return cases


def experiment_4_cases() -> list[dict[str, object]]:
    cases: list[dict[str, object]] = []
    for render_mode in RENDER_MODES:
        for max_frames_in_flight in [1, 2]:
            for save_strategy in SAVE_STRATEGIES:
                case_name = (
                    "bench_dicuq"
                    "_threads-4"
                    "_geom-1"
                    "_raster-4"
                    f"_frames-{max_frames_in_flight}"
                    f"_render-{render_mode}"
                    f"_save-{save_strategy}"
                )
                cases.append(
                    {
                        "experiment": "experiment_4_render_mode",
                        "case_name": case_name,
                        "args": [
                            "--render-mode",
                            render_mode,
                            "--max-frames-in-flight",
                            str(max_frames_in_flight),
                            "--save-strategy",
                            save_strategy,
                            "--total-threads",
                            "4",
                            "--max-geom-threads-per-frame",
                            "1",
                            "--max-raster-threads-per-frame",
                            "4",
                            "--sample",
                            SAMPLE,
                            "--sample-mode",
                            SAMPLE_MODE,
                        ],
                    }
                )
    return cases


def experiment_5_cases() -> list[dict[str, object]]:
    cases: list[dict[str, object]] = []
    for total_threads in THREAD_COUNTS:
        for max_frames_in_flight in FRAMES_IN_FLIGHT:
            for render_mode in RENDER_MODES:
                for save_strategy in SAVE_STRATEGIES:
                    case_name = (
                        "bench_dicuq"
                        f"_threads-{total_threads}"
                        f"_geom-{total_threads}"
                        f"_raster-{total_threads}"
                        f"_frames-{max_frames_in_flight}"
                        f"_render-{render_mode}"
                        f"_save-{save_strategy}"
                    )
                    cases.append(
                        {
                            "experiment": "experiment_5_complete_matrix",
                            "case_name": case_name,
                            "args": [
                                "--render-mode",
                                render_mode,
                                "--max-frames-in-flight",
                                str(max_frames_in_flight),
                                "--save-strategy",
                                save_strategy,
                                "--total-threads",
                                str(total_threads),
                                "--max-geom-threads-per-frame",
                                str(total_threads),
                                "--max-raster-threads-per-frame",
                                str(total_threads),
                                "--sample",
                                SAMPLE,
                                "--sample-mode",
                                SAMPLE_MODE,
                            ],
                        }
                    )
    return cases


def run_case(
    case: dict[str, object],
    run_root: pathlib.Path,
    runs: int | None,
    dry_run: bool,
) -> None:
    output_dir = run_root / str(case["experiment"]) / str(case["case_name"])
    executable_path = repo_root() / "bin" / "bench_dicuq_simd"
    command = [
        str(executable_path),
        "--out-dir",
        command_path(output_dir),
    ]
    if runs is not None:
        command.extend(["--runs", str(runs)])
    command.extend(str(arg) for arg in case["args"])

    print(f"[bench_dicuq] {case['case_name']}")
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


def main() -> int:
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
        choices=("all", "1", "2", "3", "4", "5"),
        default="all",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
    )
    args = parser.parse_args()

    run_root = build_run_root("bench_dicuq", args.out_root)
    cases: list[dict[str, object]] = []
    if args.experiment in ("all", "1"):
        cases.extend(experiment_1_cases())
    if args.experiment in ("all", "2"):
        cases.extend(experiment_2_cases())
    if args.experiment in ("all", "3"):
        cases.extend(experiment_3_cases())
    if args.experiment in ("all", "4"):
        cases.extend(experiment_4_cases())
    if args.experiment in ("all", "5"):
        cases.extend(experiment_5_cases())

    if not args.dry_run:
        run_root.mkdir(parents=True, exist_ok=True)

    for case in cases:
        run_case(
            case,
            run_root,
            args.runs,
            args.dry_run,
        )

    if not args.dry_run:
        print(f"Results written under {run_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
