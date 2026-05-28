#!/usr/bin/env python3
from __future__ import annotations

import argparse
import pathlib
import shlex
import subprocess
import time
from typing import Iterable

from bench_common import build_run_root
from bench_common import command_path
from bench_common import default_image_out_dir
from bench_common import format_duration
from bench_common import repo_root
from bench_common import timestamp_string
from bench_common import write_command_file
from bench_common import write_timing_csv


# Laptop target: 8 cores / 8 active work-capable threads.
TOTAL_ACTIVE_THREADS = [1, 2, 4, 8]
RENDER_GROUP_COUNT_CHOICES = [1, 2, 4, 8]
RENDER_MODES = ["offline", "in_order"]
GEOM_SCHEDULING_MODES = ["spread", "pack"]
SAVE_STRATEGIES = [
    "disk",
    "memory",
]

SAMPLE = "cubic_catmull_rom"
SAMPLE_MODE = "lut_lerp"

# Experiment 1: idealized offline design with one render group and spread
# geometry, intended to approximate the scheduler behavior we want.
RUN_EXPERIMENT_1 = False
# Experiment 2: geometry isolation with raster constrained to one worker so we
# can study geometry scheduling behavior directly.
RUN_EXPERIMENT_2 = False
# Experiment 3: showdown between one large render group and many smaller render
# groups at the same total active-thread budget.
RUN_EXPERIMENT_3 = False
# Experiment 4: full factorial sweep over render mode, render-group partition,
# geometry scheduling mode, and grouped scheduler knobs.
RUN_EXPERIMENT_4 = False
# Experiment 5: offline sweet-spot sweep. Geometry stays single-threaded per
# job while we sweep render-group partitioning and geometry lookahead over the
# cases that should plausibly scale well.
RUN_EXPERIMENT_5 = False
# Experiment 6: max-thread partition check. Compare only one large render group
# against one-thread-per-group at the maximum thread count.
RUN_EXPERIMENT_6 = True
# Experiment 7: same sweep as experiment 5, but only `.disk` with overlapping
# frame saves enabled.
RUN_EXPERIMENT_7 = False

# Experiment 1: idealized offline design.
# Single render group, geometry spread, one worker per geometry job, one raster
# job at a time using all group workers.
EXPERIMENT_1_TOTAL_ACTIVE_THREADS = TOTAL_ACTIVE_THREADS
EXPERIMENT_1_SAVE_STRATEGIES = SAVE_STRATEGIES

# Experiment 2: geometry isolation.
# Single render group, offline, raster constrained to one worker so geometry
# behavior dominates.
EXPERIMENT_2_TOTAL_ACTIVE_THREADS = TOTAL_ACTIVE_THREADS
EXPERIMENT_2_GEOM_SCHEDULING_MODES = GEOM_SCHEDULING_MODES
EXPERIMENT_2_FRAME_BATCH_SIZE_VALUES = ["1", "max"]
EXPERIMENT_2_GEOM_JOBS_IN_FLIGHT_VALUES = ["1", "max"]
EXPERIMENT_2_GEOM_WORKERS_PER_JOB_VALUES = ["1", "max"]
EXPERIMENT_2_SAVE_STRATEGIES = SAVE_STRATEGIES

# Experiment 3: showdown.
# Compare one group with N workers vs many groups with one worker each, and the
# equal-sized intermediate partitions where N is divisible.
EXPERIMENT_3_TOTAL_ACTIVE_THREADS = TOTAL_ACTIVE_THREADS
EXPERIMENT_3_RENDER_GROUP_COUNTS = RENDER_GROUP_COUNT_CHOICES
EXPERIMENT_3_SAVE_STRATEGIES = SAVE_STRATEGIES

# Experiment 4: full factorial.
EXPERIMENT_4_TOTAL_ACTIVE_THREADS = TOTAL_ACTIVE_THREADS
EXPERIMENT_4_RENDER_GROUP_COUNTS = RENDER_GROUP_COUNT_CHOICES
EXPERIMENT_4_RENDER_MODES = RENDER_MODES
EXPERIMENT_4_GEOM_SCHEDULING_MODES = GEOM_SCHEDULING_MODES
EXPERIMENT_4_FRAME_BATCH_SIZE_VALUES = ["1", "max"]
EXPERIMENT_4_GEOM_JOBS_IN_FLIGHT_VALUES = ["1", "max"]
EXPERIMENT_4_GEOM_WORKERS_PER_JOB_VALUES = ["1", "max"]
EXPERIMENT_4_SAVE_STRATEGIES = SAVE_STRATEGIES

# Experiment 5: offline sweet-spot sweep.
# Partition total threads across render groups, keep geometry single-threaded
# per job, and sweep only the batch/lookahead knobs that should matter.
EXPERIMENT_5_TOTAL_ACTIVE_THREADS = TOTAL_ACTIVE_THREADS
EXPERIMENT_5_RENDER_GROUP_COUNTS = RENDER_GROUP_COUNT_CHOICES
EXPERIMENT_5_FRAME_BATCH_SIZE_VALUES = ["1", "max", "double"]
EXPERIMENT_5_GEOM_JOBS_IN_FLIGHT_VALUES = ["1", "max"]
EXPERIMENT_5_SAVE_STRATEGIES = SAVE_STRATEGIES

# Experiment 6: max-thread partition check.
EXPERIMENT_6_TOTAL_THREADS = max(TOTAL_ACTIVE_THREADS)
EXPERIMENT_6_RENDER_GROUP_COUNTS = [1, EXPERIMENT_6_TOTAL_THREADS]
EXPERIMENT_6_SAVE_STRATEGIES = SAVE_STRATEGIES

# Experiment 7: offline sweet-spot sweep with overlapping disk saves.
EXPERIMENT_7_TOTAL_ACTIVE_THREADS = EXPERIMENT_5_TOTAL_ACTIVE_THREADS
EXPERIMENT_7_RENDER_GROUP_COUNTS = EXPERIMENT_5_RENDER_GROUP_COUNTS
EXPERIMENT_7_FRAME_BATCH_SIZE_VALUES = EXPERIMENT_5_FRAME_BATCH_SIZE_VALUES
EXPERIMENT_7_GEOM_JOBS_IN_FLIGHT_VALUES = EXPERIMENT_5_GEOM_JOBS_IN_FLIGHT_VALUES



def divisors_from_choices(total_threads: int, choices: Iterable[int]) -> list[int]:
    return [
        groups
        for groups in sorted(set(choices))
        if groups > 0 and groups <= total_threads and total_threads % groups == 0
    ]


def resolve_group_value(value: str, workers_per_group: int) -> int:
    if value == "1":
        return 1
    if value == "max":
        return workers_per_group
    if value == "double":
        return max(1, 2 * workers_per_group)
    raise ValueError(f"Unsupported grouped value token: {value}")


def workers_per_group(total_threads: int, render_group_count: int) -> int:
    if total_threads <= 0:
        raise ValueError("total_threads must be positive")
    if render_group_count <= 0:
        raise ValueError("render_group_count must be positive")
    if total_threads % render_group_count != 0:
        raise ValueError(
            "total_threads must be evenly divisible by render_group_count"
        )
    return total_threads // render_group_count


def max_active_geom_workers(
    *,
    workers_per_group: int,
    frame_batch_size_per_group: int,
    max_geom_jobs_in_flight_per_group: int,
    max_geom_workers_per_job: int,
    geom_scheduling_mode: str,
) -> int:
    jobs_available = min(
        frame_batch_size_per_group,
        max_geom_jobs_in_flight_per_group,
    )
    if geom_scheduling_mode == "spread":
        return min(
            workers_per_group,
            jobs_available * max_geom_workers_per_job,
        )
    if geom_scheduling_mode == "pack":
        return min(workers_per_group, max_geom_workers_per_job)
    raise ValueError(f"Unsupported geometry scheduling mode: {geom_scheduling_mode}")


def is_dominated_case(
    *,
    workers_per_group: int,
    frame_batch_size_per_group: int,
    max_geom_jobs_in_flight_per_group: int,
    max_geom_workers_per_job: int,
    geom_scheduling_mode: str,
    max_raster_workers_per_job: int,
) -> bool:
    if workers_per_group <= 1:
        return False
    geom_workers_max = max_active_geom_workers(
        workers_per_group=workers_per_group,
        frame_batch_size_per_group=frame_batch_size_per_group,
        max_geom_jobs_in_flight_per_group=max_geom_jobs_in_flight_per_group,
        max_geom_workers_per_job=max_geom_workers_per_job,
        geom_scheduling_mode=geom_scheduling_mode,
    )
    raster_workers_max = min(workers_per_group, max_raster_workers_per_job)
    return max(geom_workers_max, raster_workers_max) < workers_per_group


def make_case(
    *,
    experiment: str,
    total_threads: int,
    render_group_count: int,
    render_mode: str,
    frame_batch_size_per_group: int,
    max_geom_jobs_in_flight_per_group: int,
    max_geom_workers_per_job: int,
    geom_scheduling_mode: str,
    max_raster_workers_per_job: int,
    save_strategy: str,
    disk_save_overlap: bool = False,
) -> dict[str, object]:
    workers_group = workers_per_group(total_threads, render_group_count)
    case_name = (
        "bench_dicuq"
        f"_threads-{total_threads}"
        f"_groups-{render_group_count}"
        f"_workerspg-{workers_group}"
        f"_batch-{frame_batch_size_per_group}"
        f"_geomjobs-{max_geom_jobs_in_flight_per_group}"
        f"_geomw-{max_geom_workers_per_job}"
        f"_geommode-{geom_scheduling_mode}"
        f"_rasterw-{max_raster_workers_per_job}"
        f"_render-{render_mode}"
        f"_save-{save_strategy}"
        f"_overlap-{str(disk_save_overlap).lower()}"
    )
    args = [
        "--render-group-count",
        str(render_group_count),
        "--total-threads",
        str(total_threads),
        "--render-mode",
        render_mode,
        "--frame-batch-size-per-group",
        str(frame_batch_size_per_group),
        "--max-geom-jobs-in-flight-per-group",
        str(max_geom_jobs_in_flight_per_group),
        "--max-geom-workers-per-job",
        str(max_geom_workers_per_job),
        "--geom-scheduling-mode",
        geom_scheduling_mode,
        "--max-raster-workers-per-job",
        str(max_raster_workers_per_job),
        "--save-strategy",
        save_strategy,
        "--disk-save-overlap",
        str(disk_save_overlap).lower(),
        "--sample",
        SAMPLE,
        "--sample-mode",
        SAMPLE_MODE,
    ]
    return {
        "experiment": experiment,
        "case_name": case_name,
        "args": args,
    }


def unique_cases(cases: list[dict[str, object]]) -> list[dict[str, object]]:
    unique: list[dict[str, object]] = []
    seen: set[str] = set()
    for case in cases:
        case_name = str(case["case_name"])
        if case_name in seen:
            continue
        seen.add(case_name)
        unique.append(case)
    return unique


def experiment_1_cases() -> list[dict[str, object]]:
    cases: list[dict[str, object]] = []
    for total_threads in EXPERIMENT_1_TOTAL_ACTIVE_THREADS:
        render_group_count = 1
        group_workers = workers_per_group(total_threads, render_group_count)
        for save_strategy in EXPERIMENT_1_SAVE_STRATEGIES:
            cases.append(
                make_case(
                    experiment="experiment_1_idealized_offline",
                    total_threads=total_threads,
                    render_group_count=render_group_count,
                    render_mode="offline",
                    frame_batch_size_per_group=group_workers,
                    max_geom_jobs_in_flight_per_group=group_workers,
                    max_geom_workers_per_job=1,
                    geom_scheduling_mode="spread",
                    max_raster_workers_per_job=group_workers,
                    save_strategy=save_strategy,
                )
            )
    return unique_cases(cases)


def experiment_2_cases() -> list[dict[str, object]]:
    cases: list[dict[str, object]] = []
    for total_threads in EXPERIMENT_2_TOTAL_ACTIVE_THREADS:
        render_group_count = 1
        group_workers = workers_per_group(total_threads, render_group_count)
        for geom_mode in EXPERIMENT_2_GEOM_SCHEDULING_MODES:
            for batch_value in EXPERIMENT_2_FRAME_BATCH_SIZE_VALUES:
                for geom_jobs_value in EXPERIMENT_2_GEOM_JOBS_IN_FLIGHT_VALUES:
                    for geom_workers_value in (
                        EXPERIMENT_2_GEOM_WORKERS_PER_JOB_VALUES
                    ):
                        for save_strategy in EXPERIMENT_2_SAVE_STRATEGIES:
                            frame_batch_size = resolve_group_value(
                                batch_value,
                                group_workers,
                            )
                            max_geom_jobs = resolve_group_value(
                                geom_jobs_value,
                                group_workers,
                            )
                            max_geom_workers = resolve_group_value(
                                geom_workers_value,
                                group_workers,
                            )
                            if is_dominated_case(
                                workers_per_group=group_workers,
                                frame_batch_size_per_group=frame_batch_size,
                                max_geom_jobs_in_flight_per_group=max_geom_jobs,
                                max_geom_workers_per_job=max_geom_workers,
                                geom_scheduling_mode=geom_mode,
                                max_raster_workers_per_job=1,
                            ):
                                continue
                            cases.append(
                                make_case(
                                    experiment="experiment_2_geometry_isolation",
                                    total_threads=total_threads,
                                    render_group_count=render_group_count,
                                    render_mode="offline",
                                    frame_batch_size_per_group=frame_batch_size,
                                    max_geom_jobs_in_flight_per_group=max_geom_jobs,
                                    max_geom_workers_per_job=max_geom_workers,
                                    geom_scheduling_mode=geom_mode,
                                    max_raster_workers_per_job=1,
                                    save_strategy=save_strategy,
                                )
                            )
    return unique_cases(cases)


def experiment_3_cases() -> list[dict[str, object]]:
    cases: list[dict[str, object]] = []
    for total_threads in EXPERIMENT_3_TOTAL_ACTIVE_THREADS:
        for render_group_count in divisors_from_choices(
            total_threads, EXPERIMENT_3_RENDER_GROUP_COUNTS
        ):
            group_workers = workers_per_group(total_threads, render_group_count)
            for save_strategy in EXPERIMENT_3_SAVE_STRATEGIES:
                cases.append(
                    make_case(
                        experiment="experiment_3_showdown",
                        total_threads=total_threads,
                        render_group_count=render_group_count,
                        render_mode="offline",
                        frame_batch_size_per_group=group_workers,
                        max_geom_jobs_in_flight_per_group=group_workers,
                        max_geom_workers_per_job=1,
                        geom_scheduling_mode="spread",
                        max_raster_workers_per_job=group_workers,
                        save_strategy=save_strategy,
                    )
                )
    return unique_cases(cases)


def experiment_4_cases() -> list[dict[str, object]]:
    cases: list[dict[str, object]] = []
    for total_threads in EXPERIMENT_4_TOTAL_ACTIVE_THREADS:
        for render_group_count in divisors_from_choices(
            total_threads, EXPERIMENT_4_RENDER_GROUP_COUNTS
        ):
            group_workers = workers_per_group(total_threads, render_group_count)
            for render_mode in EXPERIMENT_4_RENDER_MODES:
                for geom_mode in EXPERIMENT_4_GEOM_SCHEDULING_MODES:
                    for batch_value in EXPERIMENT_4_FRAME_BATCH_SIZE_VALUES:
                        for geom_jobs_value in (
                            EXPERIMENT_4_GEOM_JOBS_IN_FLIGHT_VALUES
                        ):
                            for geom_workers_value in (
                                EXPERIMENT_4_GEOM_WORKERS_PER_JOB_VALUES
                            ):
                                for save_strategy in EXPERIMENT_4_SAVE_STRATEGIES:
                                    frame_batch_size = resolve_group_value(
                                        batch_value,
                                        group_workers,
                                    )
                                    max_geom_jobs = resolve_group_value(
                                        geom_jobs_value,
                                        group_workers,
                                    )
                                    max_geom_workers = resolve_group_value(
                                        geom_workers_value,
                                        group_workers,
                                    )
                                    if is_dominated_case(
                                        workers_per_group=group_workers,
                                        frame_batch_size_per_group=frame_batch_size,
                                        max_geom_jobs_in_flight_per_group=max_geom_jobs,
                                        max_geom_workers_per_job=max_geom_workers,
                                        geom_scheduling_mode=geom_mode,
                                        max_raster_workers_per_job=group_workers,
                                    ):
                                        continue
                                    cases.append(
                                        make_case(
                                            experiment="experiment_4_full_factorial",
                                            total_threads=total_threads,
                                            render_group_count=render_group_count,
                                            render_mode=render_mode,
                                            frame_batch_size_per_group=frame_batch_size,
                                            max_geom_jobs_in_flight_per_group=max_geom_jobs,
                                            max_geom_workers_per_job=max_geom_workers,
                                            geom_scheduling_mode=geom_mode,
                                            max_raster_workers_per_job=group_workers,
                                            save_strategy=save_strategy,
                                        )
                                    )
    return unique_cases(cases)


def experiment_5_cases() -> list[dict[str, object]]:
    cases: list[dict[str, object]] = []
    for total_threads in EXPERIMENT_5_TOTAL_ACTIVE_THREADS:
        for render_group_count in divisors_from_choices(
            total_threads, EXPERIMENT_5_RENDER_GROUP_COUNTS
        ):
            group_workers = workers_per_group(total_threads, render_group_count)
            for batch_value in EXPERIMENT_5_FRAME_BATCH_SIZE_VALUES:
                for geom_jobs_value in (
                    EXPERIMENT_5_GEOM_JOBS_IN_FLIGHT_VALUES
                ):
                    for save_strategy in EXPERIMENT_5_SAVE_STRATEGIES:
                        frame_batch_size = resolve_group_value(
                            batch_value,
                            group_workers,
                        )
                        max_geom_jobs = resolve_group_value(
                            geom_jobs_value,
                            group_workers,
                        )
                        cases.append(
                            make_case(
                                experiment="experiment_5_offline_sweet_spot",
                                total_threads=total_threads,
                                render_group_count=render_group_count,
                                render_mode="offline",
                                frame_batch_size_per_group=frame_batch_size,
                                max_geom_jobs_in_flight_per_group=max_geom_jobs,
                                max_geom_workers_per_job=1,
                                geom_scheduling_mode="spread",
                                max_raster_workers_per_job=group_workers,
                                save_strategy=save_strategy,
                            )
                        )
    return unique_cases(cases)


def experiment_6_cases() -> list[dict[str, object]]:
    cases: list[dict[str, object]] = []
    total_threads = EXPERIMENT_6_TOTAL_THREADS
    for render_group_count in EXPERIMENT_6_RENDER_GROUP_COUNTS:
        group_workers = workers_per_group(total_threads, render_group_count)
        for save_strategy in EXPERIMENT_6_SAVE_STRATEGIES:
            cases.append(
                make_case(
                    experiment="experiment_6_max_thread_partition_check",
                    total_threads=total_threads,
                    render_group_count=render_group_count,
                    render_mode="offline",
                    frame_batch_size_per_group=group_workers,
                    max_geom_jobs_in_flight_per_group=group_workers,
                    max_geom_workers_per_job=1,
                    geom_scheduling_mode="spread",
                    max_raster_workers_per_job=group_workers,
                    save_strategy=save_strategy,
                )
            )
    return unique_cases(cases)


def experiment_7_cases() -> list[dict[str, object]]:
    cases: list[dict[str, object]] = []
    for total_threads in EXPERIMENT_7_TOTAL_ACTIVE_THREADS:
        for render_group_count in divisors_from_choices(
            total_threads, EXPERIMENT_7_RENDER_GROUP_COUNTS
        ):
            group_workers = workers_per_group(total_threads, render_group_count)
            for batch_value in EXPERIMENT_7_FRAME_BATCH_SIZE_VALUES:
                for geom_jobs_value in EXPERIMENT_7_GEOM_JOBS_IN_FLIGHT_VALUES:
                    frame_batch_size = resolve_group_value(
                        batch_value,
                        group_workers,
                    )
                    max_geom_jobs = resolve_group_value(
                        geom_jobs_value,
                        group_workers,
                    )
                    cases.append(
                        make_case(
                            experiment="experiment_7_offline_sweet_spot_disk_overlap",
                            total_threads=total_threads,
                            render_group_count=render_group_count,
                            render_mode="offline",
                            frame_batch_size_per_group=frame_batch_size,
                            max_geom_jobs_in_flight_per_group=max_geom_jobs,
                            max_geom_workers_per_job=1,
                            geom_scheduling_mode="spread",
                            max_raster_workers_per_job=group_workers,
                            save_strategy="disk",
                            disk_save_overlap=True,
                        )
                    )
    return unique_cases(cases)


def run_case(
    case: dict[str, object],
    run_root: pathlib.Path,
    runs: int | None,
    dry_run: bool,
    case_idx: int,
    total_cases: int,
) -> None:
    output_dir = run_root / str(case["experiment"]) / str(case["case_name"])
    executable_path = repo_root() / "bin" / "bench_dicuq_simd"
    command = [
        str(executable_path),
        "--out-dir",
        command_path(output_dir),
        "--image-out-dir",
        command_path(default_image_out_dir("bench_dicuq")),
    ]
    if runs is not None:
        command.extend(["--runs", str(runs)])
    command.extend(str(arg) for arg in case["args"])

    if dry_run:
        print(
            f"[bench_dicuq] EXP: {case['experiment']}, "
            f"CASE: {case_idx}/{total_cases} {case['case_name']}"
        )
        print("  dry-run:", " ".join(shlex.quote(part) for part in command))
        return

    output_dir.mkdir(parents=True, exist_ok=True)
    write_command_file(output_dir, command)

    stdout_path = output_dir / "stdout.txt"
    stderr_path = output_dir / "stderr.txt"
    print(
        f"[bench_dicuq] EXP: {case['experiment']}, "
        f"CASE: {case_idx}/{total_cases} {case['case_name']}"
    )
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


def experiment_header(experiment_id: str, when: str) -> str:
    return f"========== Experiment {experiment_id} {when} =========="


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
    timing_timestamp = timestamp_string()
    if args.experiment != "all" and not experiment_enabled(args.experiment):
        print(
            f"Experiment {args.experiment} is disabled by top-of-file constants."
        )
        return 0

    if not args.dry_run:
        run_root.mkdir(parents=True, exist_ok=True)

    selected_experiments: list[tuple[str, callable]] = []
    if args.experiment in ("all", "1") and experiment_enabled("1"):
        selected_experiments.append(("1", experiment_1_cases))
    if args.experiment in ("all", "2") and experiment_enabled("2"):
        selected_experiments.append(("2", experiment_2_cases))
    if args.experiment in ("all", "3") and experiment_enabled("3"):
        selected_experiments.append(("3", experiment_3_cases))
    if args.experiment in ("all", "4") and experiment_enabled("4"):
        selected_experiments.append(("4", experiment_4_cases))
    if args.experiment in ("all", "5") and experiment_enabled("5"):
        selected_experiments.append(("5", experiment_5_cases))
    if args.experiment in ("all", "6") and experiment_enabled("6"):
        selected_experiments.append(("6", experiment_6_cases))
    if args.experiment in ("all", "7") and experiment_enabled("7"):
        selected_experiments.append(("7", experiment_7_cases))

    all_cases: list[dict[str, object]] = []
    for _, case_builder in selected_experiments:
        all_cases.extend(case_builder())
    total_cases = len(all_cases)

    script_start = time.perf_counter()
    timing_rows: list[dict[str, object]] = []
    case_idx = 0
    for experiment_id, case_builder in selected_experiments:
        print(experiment_header(experiment_id, "START"))
        exp_start = time.perf_counter()
        cases = case_builder()
        for case in cases:
            case_idx += 1
            run_case(
                case,
                run_root,
                args.runs,
                args.dry_run,
                case_idx,
                total_cases,
            )
        exp_seconds = time.perf_counter() - exp_start
        experiment_name = cases[0]["experiment"] if cases else f"experiment_{experiment_id}"
        print(
            f"[bench_dicuq] Experiment {experiment_id} summary: "
            f"{format_duration(exp_seconds)}"
        )
        timing_rows.append(
            {
                "benchmark": "bench_dicuq",
                "kind": "experiment",
                "name": str(experiment_name),
                "seconds": f"{exp_seconds:.6f}",
            }
        )
        print(experiment_header(experiment_id, "END"))

    total_seconds = time.perf_counter() - script_start
    print(f"[bench_dicuq] Total summary: {format_duration(total_seconds)}")
    timing_rows.append(
        {
            "benchmark": "bench_dicuq",
            "kind": "total",
            "name": "all",
            "seconds": f"{total_seconds:.6f}",
        }
    )
    if not args.dry_run:
        timing_csv = write_timing_csv("bench_dicuq", timing_rows, timing_timestamp)
        print(f"[bench_dicuq] Timing written to {timing_csv}")
        print(f"Results written under {run_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
