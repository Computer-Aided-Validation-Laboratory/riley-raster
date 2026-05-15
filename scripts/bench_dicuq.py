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
SAVE_STRATEGIES = ["memory"]
GEOM_THREAD_COUNTS = [1, 2, 4, 8]
BASELINE_IO_MODES = ["direct", "async_single"]
SAMPLE = "cubic_catmull_rom"
SAMPLE_MODE = "lut_lerp"

RUN_EXPERIMENT_1 = False
RUN_EXPERIMENT_2 = False
RUN_EXPERIMENT_3 = False
RUN_EXPERIMENT_4 = False
RUN_EXPERIMENT_5 = True
RUN_EXPERIMENT_6 = False
RUN_EXPERIMENT_7 = False

EXPERIMENT_1_THREAD_COUNTS = THREAD_COUNTS
EXPERIMENT_1_SAVE_STRATEGIES = SAVE_STRATEGIES

EXPERIMENT_2_THREAD_COUNTS = THREAD_COUNTS
EXPERIMENT_2_SAVE_STRATEGIES = SAVE_STRATEGIES

EXPERIMENT_3_TOTAL_THREADS = 4
EXPERIMENT_3_GEOM_THREADS = 1
EXPERIMENT_3_RASTER_THREADS = 4
EXPERIMENT_3_FRAMES_IN_FLIGHT = FRAMES_IN_FLIGHT
EXPERIMENT_3_SAVE_STRATEGIES = SAVE_STRATEGIES

EXPERIMENT_4_TOTAL_THREADS = 4
EXPERIMENT_4_GEOM_THREADS = 1
EXPERIMENT_4_RASTER_THREADS = 4
EXPERIMENT_4_RENDER_MODES = RENDER_MODES
EXPERIMENT_4_FRAMES_IN_FLIGHT = [1, 2]
EXPERIMENT_4_SAVE_STRATEGIES = SAVE_STRATEGIES

EXPERIMENT_5_THREAD_COUNTS = THREAD_COUNTS
EXPERIMENT_5_FRAMES_IN_FLIGHT = FRAMES_IN_FLIGHT
EXPERIMENT_5_RENDER_MODES = RENDER_MODES
EXPERIMENT_5_SAVE_STRATEGIES = SAVE_STRATEGIES

EXPERIMENT_6_THREAD_COUNTS = THREAD_COUNTS
EXPERIMENT_6_FRAMES_IN_FLIGHT = FRAMES_IN_FLIGHT
EXPERIMENT_6_RENDER_MODES = RENDER_MODES
EXPERIMENT_6_SAVE_STRATEGIES = SAVE_STRATEGIES
EXPERIMENT_6_BASELINE_IO_MODES = BASELINE_IO_MODES

EXPERIMENT_7_THREAD_COUNTS = THREAD_COUNTS
EXPERIMENT_7_GEOM_THREAD_COUNTS = GEOM_THREAD_COUNTS
EXPERIMENT_7_FRAMES_IN_FLIGHT = FRAMES_IN_FLIGHT
EXPERIMENT_7_RENDER_MODES = RENDER_MODES
EXPERIMENT_7_SAVE_STRATEGIES = SAVE_STRATEGIES
EXPERIMENT_7_BASELINE_IO_MODES = BASELINE_IO_MODES


def make_case(
    *,
    experiment: str,
    io_mode: str,
    total_threads: int,
    geom_threads: int,
    raster_threads: int,
    max_frames_in_flight: int,
    render_mode: str,
    save_strategy: str,
) -> dict[str, object]:
    case_name = (
        "bench_dicuq"
        f"_io-{io_mode}"
        f"_threads-{total_threads}"
        f"_geom-{geom_threads}"
        f"_raster-{raster_threads}"
        f"_frames-{max_frames_in_flight}"
        f"_render-{render_mode}"
        f"_save-{save_strategy}"
    )
    return {
        "experiment": experiment,
        "case_name": case_name,
        "args": [
            "--io-mode",
            io_mode,
            "--render-mode",
            render_mode,
            "--max-frames-in-flight",
            str(max_frames_in_flight),
            "--save-strategy",
            save_strategy,
            "--total-threads",
            str(total_threads),
            "--max-geom-threads-per-frame",
            str(geom_threads),
            "--max-raster-threads-per-frame",
            str(raster_threads),
            "--sample",
            SAMPLE,
            "--sample-mode",
            SAMPLE_MODE,
        ],
    }


def make_baseline_cases(
    *,
    experiment: str,
    io_modes: list[str],
    render_modes: list[str],
    frames_in_flight: list[int],
    save_strategies: list[str],
) -> list[dict[str, object]]:
    cases: list[dict[str, object]] = []
    for io_mode in io_modes:
        for render_mode in render_modes:
            for max_frames_in_flight in frames_in_flight:
                for save_strategy in save_strategies:
                    cases.append(
                        make_case(
                            experiment=experiment,
                            io_mode=io_mode,
                            total_threads=1,
                            geom_threads=1,
                            raster_threads=1,
                            max_frames_in_flight=max_frames_in_flight,
                            render_mode=render_mode,
                            save_strategy=save_strategy,
                        )
                    )
    return cases


def experiment_1_cases() -> list[dict[str, object]]:
    cases: list[dict[str, object]] = []
    for total_threads in EXPERIMENT_1_THREAD_COUNTS:
        for save_strategy in EXPERIMENT_1_SAVE_STRATEGIES:
            cases.append(
                make_case(
                    experiment="experiment_1_all_threads",
                    io_mode="threaded",
                    total_threads=total_threads,
                    geom_threads=total_threads,
                    raster_threads=total_threads,
                    max_frames_in_flight=1,
                    render_mode="offline",
                    save_strategy=save_strategy,
                )
            )
    return cases


def experiment_2_cases() -> list[dict[str, object]]:
    cases: list[dict[str, object]] = []
    for total_threads in EXPERIMENT_2_THREAD_COUNTS:
        for save_strategy in EXPERIMENT_2_SAVE_STRATEGIES:
            cases.append(
                make_case(
                    experiment="experiment_2_geom_threads_1",
                    io_mode="threaded",
                    total_threads=total_threads,
                    geom_threads=1,
                    raster_threads=total_threads,
                    max_frames_in_flight=1,
                    render_mode="offline",
                    save_strategy=save_strategy,
                )
            )
    return cases


def experiment_3_cases() -> list[dict[str, object]]:
    cases: list[dict[str, object]] = []
    for max_frames_in_flight in EXPERIMENT_3_FRAMES_IN_FLIGHT:
        for save_strategy in EXPERIMENT_3_SAVE_STRATEGIES:
            cases.append(
                make_case(
                    experiment="experiment_3_frames_in_flight",
                    io_mode="threaded",
                    total_threads=EXPERIMENT_3_TOTAL_THREADS,
                    geom_threads=EXPERIMENT_3_GEOM_THREADS,
                    raster_threads=EXPERIMENT_3_RASTER_THREADS,
                    max_frames_in_flight=max_frames_in_flight,
                    render_mode="offline",
                    save_strategy=save_strategy,
                )
            )
    return cases


def experiment_4_cases() -> list[dict[str, object]]:
    cases: list[dict[str, object]] = []
    for render_mode in EXPERIMENT_4_RENDER_MODES:
        for max_frames_in_flight in EXPERIMENT_4_FRAMES_IN_FLIGHT:
            for save_strategy in EXPERIMENT_4_SAVE_STRATEGIES:
                cases.append(
                    make_case(
                        experiment="experiment_4_render_mode",
                        io_mode="threaded",
                        total_threads=EXPERIMENT_4_TOTAL_THREADS,
                        geom_threads=EXPERIMENT_4_GEOM_THREADS,
                        raster_threads=EXPERIMENT_4_RASTER_THREADS,
                        max_frames_in_flight=max_frames_in_flight,
                        render_mode=render_mode,
                        save_strategy=save_strategy,
                    )
                )
    return cases


def experiment_5_cases() -> list[dict[str, object]]:
    cases: list[dict[str, object]] = []
    for total_threads in EXPERIMENT_5_THREAD_COUNTS:
        for max_frames_in_flight in EXPERIMENT_5_FRAMES_IN_FLIGHT:
            for render_mode in EXPERIMENT_5_RENDER_MODES:
                for save_strategy in EXPERIMENT_5_SAVE_STRATEGIES:
                    cases.append(
                        make_case(
                            experiment="experiment_5_complete_matrix",
                            io_mode="threaded",
                            total_threads=total_threads,
                            geom_threads=total_threads,
                            raster_threads=total_threads,
                            max_frames_in_flight=max_frames_in_flight,
                            render_mode=render_mode,
                            save_strategy=save_strategy,
                        )
                    )
    return cases


def experiment_6_cases() -> list[dict[str, object]]:
    cases = make_baseline_cases(
        experiment="experiment_6_io_matrix",
        io_modes=EXPERIMENT_6_BASELINE_IO_MODES,
        render_modes=EXPERIMENT_6_RENDER_MODES,
        frames_in_flight=EXPERIMENT_6_FRAMES_IN_FLIGHT,
        save_strategies=EXPERIMENT_6_SAVE_STRATEGIES,
    )
    for total_threads in EXPERIMENT_6_THREAD_COUNTS:
        for max_frames_in_flight in EXPERIMENT_6_FRAMES_IN_FLIGHT:
            for render_mode in EXPERIMENT_6_RENDER_MODES:
                for save_strategy in EXPERIMENT_6_SAVE_STRATEGIES:
                    cases.append(
                        make_case(
                            experiment="experiment_6_io_matrix",
                            io_mode="threaded",
                            total_threads=total_threads,
                            geom_threads=total_threads,
                            raster_threads=total_threads,
                            max_frames_in_flight=max_frames_in_flight,
                            render_mode=render_mode,
                            save_strategy=save_strategy,
                        )
                    )
    return cases


def experiment_7_cases() -> list[dict[str, object]]:
    cases = make_baseline_cases(
        experiment="experiment_7_geom_sweep",
        io_modes=EXPERIMENT_7_BASELINE_IO_MODES,
        render_modes=EXPERIMENT_7_RENDER_MODES,
        frames_in_flight=EXPERIMENT_7_FRAMES_IN_FLIGHT,
        save_strategies=EXPERIMENT_7_SAVE_STRATEGIES,
    )
    for total_threads in EXPERIMENT_7_THREAD_COUNTS:
        raster_threads = total_threads
        for geom_threads in EXPERIMENT_7_GEOM_THREAD_COUNTS:
            if geom_threads > raster_threads:
                continue
            for max_frames_in_flight in EXPERIMENT_7_FRAMES_IN_FLIGHT:
                for render_mode in EXPERIMENT_7_RENDER_MODES:
                    for save_strategy in EXPERIMENT_7_SAVE_STRATEGIES:
                        cases.append(
                            make_case(
                                experiment="experiment_7_geom_sweep",
                                io_mode="threaded",
                                total_threads=total_threads,
                                geom_threads=geom_threads,
                                raster_threads=raster_threads,
                                max_frames_in_flight=max_frames_in_flight,
                                render_mode=render_mode,
                                save_strategy=save_strategy,
                            )
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


def experiment_enabled(experiment_id: str) -> bool:
    return {
        "1": RUN_EXPERIMENT_1,
        "2": RUN_EXPERIMENT_2,
        "3": RUN_EXPERIMENT_3,
        "4": RUN_EXPERIMENT_4,
        "5": RUN_EXPERIMENT_5,
        "6": RUN_EXPERIMENT_6,
        "7": RUN_EXPERIMENT_7,
    }[experiment_id]


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
        choices=("all", "1", "2", "3", "4", "5", "6", "7"),
        default="all",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
    )
    args = parser.parse_args()

    run_root = build_run_root("bench_dicuq", args.out_root)
    cases: list[dict[str, object]] = []
    if args.experiment in ("all", "1") and experiment_enabled("1"):
        cases.extend(experiment_1_cases())
    if args.experiment in ("all", "2") and experiment_enabled("2"):
        cases.extend(experiment_2_cases())
    if args.experiment in ("all", "3") and experiment_enabled("3"):
        cases.extend(experiment_3_cases())
    if args.experiment in ("all", "4") and experiment_enabled("4"):
        cases.extend(experiment_4_cases())
    if args.experiment in ("all", "5") and experiment_enabled("5"):
        cases.extend(experiment_5_cases())
    if args.experiment in ("all", "6") and experiment_enabled("6"):
        cases.extend(experiment_6_cases())
    if args.experiment in ("all", "7") and experiment_enabled("7"):
        cases.extend(experiment_7_cases())

    if args.experiment != "all" and not experiment_enabled(args.experiment):
        print(
            f"Experiment {args.experiment} is disabled by top-of-file constants."
        )
        return 0

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
