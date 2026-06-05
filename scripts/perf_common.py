#!/usr/bin/env python3
from __future__ import annotations

import csv
import datetime as dt
import json
import pathlib
import re
import shutil
import subprocess
import sys
from dataclasses import asdict, dataclass
from typing import Final


DEFAULT_GOLD_RUNS: Final[int] = 25
DEFAULT_TEST_RUNS: Final[int] = 10
DEFAULT_PROFILE: Final[str] = "1thread"
ALL_PROFILES: Final[tuple[str, ...]] = ("1thread", "4thread")
E2E_KEY: Final[str] = "E2E Time [ms]"
RASTER_KEY: Final[str] = "Raster Time [ms]"
GEOM_KEY: Final[str] = "Geom Time [ms]"
TOP_N: Final[int] = 10
STATUS_GREEN: Final[str] = "green"
STATUS_AMBER: Final[str] = "amber"
STATUS_RED: Final[str] = "red"
MEDIAN_GREEN_PCT: Final[float] = 5.0
MEDIAN_RED_PCT: Final[float] = 12.0
MEDIAN_COMBINED_RED_PCT: Final[float] = 8.0
MEDIAN_ABS_DELTA_FLOOR_MS: Final[float] = 0.2
COV_GREEN_RATIO: Final[float] = 1.75
COV_RED_RATIO: Final[float] = 3.0
COV_COMBINED_RED_RATIO: Final[float] = 2.0
MAD_ABS_DELTA_FLOOR_MS: Final[float] = 0.05
RANGE_GREEN_RATIO: Final[float] = 1.75
RANGE_RED_RATIO: Final[float] = 2.5
RANGE_COMBINED_RED_RATIO: Final[float] = 2.0
RANGE_ABS_DELTA_FLOOR_MS: Final[float] = 0.1


@dataclass(frozen=True)
class PerfCase:
    name: str
    benchmark_name: str
    binary_name: str


@dataclass(frozen=True)
class PerfProfile:
    name: str
    total_threads: int
    max_geom_threads_per_frame: int
    max_raster_threads_per_frame: int
    max_geom_workers_per_job: int
    max_raster_workers_per_job: int
    render_group_count: int = 1
    max_frames_in_flight: int = 1
    frame_batch_size_per_group: int = 1
    max_geom_jobs_in_flight_per_group: int = 1
    save_strategy: str = "memory"


@dataclass(frozen=True)
class PerfDelta:
    case_name: str
    gold_median_ms: float
    gold_mad_ms: float
    current_median_ms: float
    current_mad_ms: float
    gold_min_ms: float
    gold_max_ms: float
    current_min_ms: float
    current_max_ms: float
    gold_raster_ms: float
    current_raster_ms: float
    gold_geom_ms: float
    current_geom_ms: float
    delta_ms: float
    delta_pct: float
    mad_abs_delta_ms: float
    mad_units: float
    gold_cov_mad_pct: float
    current_cov_mad_pct: float
    cov_mad_ratio: float
    gold_range_ms: float
    current_range_ms: float
    range_abs_delta_ms: float
    range_ratio: float
    status: str
    reasons: list[str]


PERF_CASES: Final[dict[str, PerfCase]] = {
    "fullraster": PerfCase(
        name="fullraster",
        benchmark_name="bench_fullraster",
        binary_name="bench_fullraster_simd",
    ),
    "geom": PerfCase(
        name="geom",
        benchmark_name="bench_geom",
        binary_name="bench_geom_simd",
    ),
    "sphere2000": PerfCase(
        name="sphere2000",
        benchmark_name="bench_sphere2000",
        binary_name="bench_sphere2000_simd",
    ),
    "sphere2000zoom": PerfCase(
        name="sphere2000zoom",
        benchmark_name="bench_sphere2000zoom",
        binary_name="bench_sphere2000zoom_simd",
    ),
}


PROFILE_MAP: Final[dict[str, dict[str, PerfProfile]]] = {
    "fullraster": {
        "1thread": PerfProfile(
            name="1thread",
            total_threads=1,
            max_geom_threads_per_frame=1,
            max_raster_threads_per_frame=1,
            max_geom_workers_per_job=1,
            max_raster_workers_per_job=1,
        ),
        "4thread": PerfProfile(
            name="4thread",
            total_threads=4,
            max_geom_threads_per_frame=4,
            max_raster_threads_per_frame=4,
            max_geom_workers_per_job=1,
            max_raster_workers_per_job=4,
        ),
    },
    "geom": {
        "1thread": PerfProfile(
            name="1thread",
            total_threads=1,
            max_geom_threads_per_frame=1,
            max_raster_threads_per_frame=1,
            max_geom_workers_per_job=1,
            max_raster_workers_per_job=1,
        ),
        "4thread": PerfProfile(
            name="4thread",
            total_threads=4,
            max_geom_threads_per_frame=4,
            max_raster_threads_per_frame=4,
            max_geom_workers_per_job=4,
            max_raster_workers_per_job=4,
        ),
    },
    "sphere2000": {
        "1thread": PerfProfile(
            name="1thread",
            total_threads=1,
            max_geom_threads_per_frame=1,
            max_raster_threads_per_frame=1,
            max_geom_workers_per_job=1,
            max_raster_workers_per_job=1,
        ),
        "4thread": PerfProfile(
            name="4thread",
            total_threads=4,
            max_geom_threads_per_frame=4,
            max_raster_threads_per_frame=4,
            max_geom_workers_per_job=1,
            max_raster_workers_per_job=4,
        ),
    },
    "sphere2000zoom": {
        "1thread": PerfProfile(
            name="1thread",
            total_threads=1,
            max_geom_threads_per_frame=1,
            max_raster_threads_per_frame=1,
            max_geom_workers_per_job=1,
            max_raster_workers_per_job=1,
        ),
        "4thread": PerfProfile(
            name="4thread",
            total_threads=4,
            max_geom_threads_per_frame=4,
            max_raster_threads_per_frame=4,
            max_geom_workers_per_job=1,
            max_raster_workers_per_job=4,
        ),
    },
}


REFERENCE_ROOTS: Final[dict[str, pathlib.Path]] = {
    "1thread": pathlib.Path("perf/dev_single_threaded"),
    "4thread": pathlib.Path("perf/dev_4_threaded"),
}


def repo_root() -> pathlib.Path:
    return pathlib.Path(__file__).resolve().parent.parent


def command_path(path: pathlib.Path) -> str:
    path_abs = path.resolve()
    root_abs = repo_root().resolve()
    try:
        return str(path_abs.relative_to(root_abs))
    except ValueError:
        return str(path_abs)


def python_path() -> pathlib.Path:
    venv_python = repo_root() / ".venv" / "bin" / "python"
    if venv_python.exists():
        return venv_python
    return pathlib.Path(sys.executable)


def timestamp_string() -> str:
    return dt.datetime.now().strftime("%Y%m%d_%H%M%S")


def case_or_die(case_name: str) -> PerfCase:
    try:
        return PERF_CASES[case_name]
    except KeyError as exc:
        names = ", ".join(PERF_CASES.keys())
        raise SystemExit(
            f"Unknown perf case '{case_name}'. Expected one of: {names}.",
        ) from exc


def profile_or_die(case_name: str, profile_name: str) -> PerfProfile:
    try:
        return PROFILE_MAP[case_name][profile_name]
    except KeyError as exc:
        raise SystemExit(
            f"Unsupported perf profile '{profile_name}' for case '{case_name}'.",
        ) from exc


def binary_path(case: PerfCase) -> pathlib.Path:
    path = repo_root() / "bin" / case.binary_name
    if not path.exists():
        raise SystemExit(
            "Missing benchmark binary "
            f"{path}. Run scripts/compile_para_simd_benchmarks.py first.",
        )
    return path


def gold_dir(case: PerfCase, profile: PerfProfile) -> pathlib.Path:
    return repo_root() / "gold" / f"perf_{case.name}_{profile.name}"


def test_run_dir(case: PerfCase, profile: PerfProfile) -> pathlib.Path:
    return (
        repo_root()
        / "out"
        / "perf_test_stats"
        / f"{case.name}_{profile.name}"
        / timestamp_string()
    )


def gold_stage_dir(case: PerfCase, profile: PerfProfile) -> pathlib.Path:
    return (
        repo_root()
        / "out"
        / "perf_gold_stage"
        / f"{case.name}_{profile.name}"
        / timestamp_string()
    )


def image_out_dir(case: PerfCase, profile: PerfProfile) -> pathlib.Path:
    return (
        repo_root()
        / "out"
        / "perf_test_images"
        / f"{case.name}_{profile.name}"
    )


def reference_dir(case: PerfCase, profile: PerfProfile) -> pathlib.Path | None:
    profile_root = REFERENCE_ROOTS.get(profile.name)
    if profile_root is None:
        return None

    ref_dir = repo_root() / profile_root / case.name
    if not ref_dir.exists():
        return None
    return ref_dir


def summary_file_map(root: pathlib.Path) -> dict[str, pathlib.Path]:
    return {
        "median": root / "bench_stats_median.csv",
        "mad": root / "bench_stats_mad.csv",
        "min": root / "bench_stats_min.csv",
        "max": root / "bench_stats_max.csv",
        "cov": root / "bench_stats_cov.csv",
    }


def profile_args(profile: PerfProfile) -> list[str]:
    return [
        "--render-group-count",
        str(profile.render_group_count),
        "--total-threads",
        str(profile.total_threads),
        "--max-geom-threads-per-frame",
        str(profile.max_geom_threads_per_frame),
        "--max-raster-threads-per-frame",
        str(profile.max_raster_threads_per_frame),
        "--max-frames-in-flight",
        str(profile.max_frames_in_flight),
        "--frame-batch-size-per-group",
        str(profile.frame_batch_size_per_group),
        "--max-geom-jobs-in-flight-per-group",
        str(profile.max_geom_jobs_in_flight_per_group),
        "--max-geom-workers-per-job",
        str(profile.max_geom_workers_per_job),
        "--max-raster-workers-per-job",
        str(profile.max_raster_workers_per_job),
        "--save-strategy",
        profile.save_strategy,
    ]


def run_benchmark_binary(
    case: PerfCase,
    profile: PerfProfile,
    runs: int,
    out_dir: pathlib.Path,
) -> list[str]:
    out_dir.parent.mkdir(parents=True, exist_ok=True)
    image_out_dir(case, profile).mkdir(parents=True, exist_ok=True)
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)

    cmd = [
        str(binary_path(case)),
        "--out-dir",
        command_path(out_dir),
        "--image-out-dir",
        command_path(image_out_dir(case, profile)),
        "--runs",
        str(runs),
        *profile_args(profile),
    ]

    (out_dir / "command.txt").write_text(" ".join(cmd) + "\n")

    with (out_dir / "stdout.txt").open("w") as stdout_file, (
        out_dir / "stderr.txt"
    ).open("w") as stderr_file:
        subprocess.run(
            cmd,
            cwd=repo_root(),
            check=True,
            stdout=stdout_file,
            stderr=stderr_file,
        )

    return cmd


def load_csv_rows(path: pathlib.Path) -> list[dict[str, str]]:
    with path.open(newline="") as csv_file:
        return list(csv.DictReader(csv_file))


def load_summary_map(root: pathlib.Path, kind: str) -> dict[str, dict[str, str]]:
    rows = load_csv_rows(summary_file_map(root)[kind])
    return {row["Case"]: row for row in rows}


def parse_float(row: dict[str, str], key: str) -> float:
    return float(row[key])


def safe_ratio(numerator: float, denominator: float, eps: float = 1e-9) -> float:
    return numerator / max(denominator, eps)


def classify_perf_delta(
    delta_pct: float,
    delta_ms: float,
    mad_abs_delta_ms: float,
    cov_mad_ratio: float,
    range_abs_delta_ms: float,
    range_ratio: float,
) -> tuple[str, list[str]]:
    reasons: list[str] = []
    median_active = (
        delta_pct > 0.0 and delta_ms > MEDIAN_ABS_DELTA_FLOOR_MS
    )
    cov_active = (
        cov_mad_ratio > 1.0 and mad_abs_delta_ms > MAD_ABS_DELTA_FLOOR_MS
    )
    range_active = (
        range_ratio > 1.0 and range_abs_delta_ms > RANGE_ABS_DELTA_FLOOR_MS
    )

    if median_active and delta_pct > MEDIAN_RED_PCT:
        reasons.append(f"median +{delta_pct:.2f}%")
    if cov_active and cov_mad_ratio > COV_RED_RATIO:
        reasons.append(f"cov_mad x{cov_mad_ratio:.2f}")
    if range_active and range_ratio > RANGE_RED_RATIO:
        reasons.append(f"range x{range_ratio:.2f}")
    if (
        median_active
        and delta_pct > MEDIAN_COMBINED_RED_PCT
        and cov_active
        and cov_mad_ratio > COV_COMBINED_RED_RATIO
    ):
        reasons.append(
            f"median+cov combined (+{delta_pct:.2f}%, x{cov_mad_ratio:.2f})",
        )
    if (
        median_active
        and delta_pct > MEDIAN_COMBINED_RED_PCT
        and range_active
        and range_ratio > RANGE_COMBINED_RED_RATIO
    ):
        reasons.append(
            f"median+range combined (+{delta_pct:.2f}%, x{range_ratio:.2f})",
        )
    if reasons:
        return STATUS_RED, reasons

    if median_active and delta_pct > MEDIAN_GREEN_PCT:
        reasons.append(f"median +{delta_pct:.2f}%")
    if cov_active and cov_mad_ratio > COV_GREEN_RATIO:
        reasons.append(f"cov_mad x{cov_mad_ratio:.2f}")
    if range_active and range_ratio > RANGE_GREEN_RATIO:
        reasons.append(f"range x{range_ratio:.2f}")
    if reasons:
        return STATUS_AMBER, reasons

    return STATUS_GREEN, ["within thresholds"]


def compare_case_maps(
    gold_root: pathlib.Path,
    current_root: pathlib.Path,
) -> list[PerfDelta]:
    gold_median = load_summary_map(gold_root, "median")
    gold_mad = load_summary_map(gold_root, "mad")
    gold_min = load_summary_map(gold_root, "min")
    gold_max = load_summary_map(gold_root, "max")
    current_median = load_summary_map(current_root, "median")
    current_mad = load_summary_map(current_root, "mad")
    current_min = load_summary_map(current_root, "min")
    current_max = load_summary_map(current_root, "max")

    gold_cases = set(gold_median.keys())
    current_cases = set(current_median.keys())
    if gold_cases != current_cases:
        missing = sorted(gold_cases - current_cases)
        extra = sorted(current_cases - gold_cases)
        raise SystemExit(
            "Mismatch in compared perf cases. "
            f"Missing in current: {missing}. Extra in current: {extra}.",
        )

    deltas: list[PerfDelta] = []
    for case_name in sorted(gold_cases):
        gold_med_row = gold_median[case_name]
        gold_mad_row = gold_mad[case_name]
        gold_min_row = gold_min[case_name]
        gold_max_row = gold_max[case_name]
        cur_med_row = current_median[case_name]
        cur_mad_row = current_mad[case_name]
        cur_min_row = current_min[case_name]
        cur_max_row = current_max[case_name]

        gold_median_ms = parse_float(gold_med_row, E2E_KEY)
        current_median_ms = parse_float(cur_med_row, E2E_KEY)
        gold_mad_ms = parse_float(gold_mad_row, E2E_KEY)
        current_mad_ms = parse_float(cur_mad_row, E2E_KEY)
        gold_min_ms = parse_float(gold_min_row, E2E_KEY)
        gold_max_ms = parse_float(gold_max_row, E2E_KEY)
        current_min_ms = parse_float(cur_min_row, E2E_KEY)
        current_max_ms = parse_float(cur_max_row, E2E_KEY)
        delta_ms = current_median_ms - gold_median_ms
        delta_pct = (
            0.0
            if gold_median_ms == 0.0
            else delta_ms / gold_median_ms * 100.0
        )
        mad_abs_delta_ms = current_mad_ms - gold_mad_ms
        mad_units = delta_ms / max(gold_mad_ms, current_mad_ms, 1e-9)
        gold_cov_mad_pct = 100.0 * safe_ratio(gold_mad_ms, gold_median_ms)
        current_cov_mad_pct = 100.0 * safe_ratio(
            current_mad_ms,
            current_median_ms,
        )
        cov_mad_ratio = safe_ratio(current_cov_mad_pct, gold_cov_mad_pct)
        gold_range_ms = gold_max_ms - gold_min_ms
        current_range_ms = current_max_ms - current_min_ms
        range_abs_delta_ms = current_range_ms - gold_range_ms
        range_ratio = safe_ratio(current_range_ms, gold_range_ms)
        status, reasons = classify_perf_delta(
            delta_pct,
            delta_ms,
            mad_abs_delta_ms,
            cov_mad_ratio,
            range_abs_delta_ms,
            range_ratio,
        )

        deltas.append(
            PerfDelta(
                case_name=case_name,
                gold_median_ms=gold_median_ms,
                gold_mad_ms=gold_mad_ms,
                current_median_ms=current_median_ms,
                current_mad_ms=current_mad_ms,
                gold_min_ms=gold_min_ms,
                gold_max_ms=gold_max_ms,
                current_min_ms=current_min_ms,
                current_max_ms=current_max_ms,
                gold_raster_ms=parse_float(gold_med_row, RASTER_KEY),
                current_raster_ms=parse_float(cur_med_row, RASTER_KEY),
                gold_geom_ms=parse_float(gold_med_row, GEOM_KEY),
                current_geom_ms=parse_float(cur_med_row, GEOM_KEY),
                delta_ms=delta_ms,
                delta_pct=delta_pct,
                mad_abs_delta_ms=mad_abs_delta_ms,
                mad_units=mad_units,
                gold_cov_mad_pct=gold_cov_mad_pct,
                current_cov_mad_pct=current_cov_mad_pct,
                cov_mad_ratio=cov_mad_ratio,
                gold_range_ms=gold_range_ms,
                current_range_ms=current_range_ms,
                range_abs_delta_ms=range_abs_delta_ms,
                range_ratio=range_ratio,
                status=status,
                reasons=reasons,
            ),
        )

    return deltas


def copy_perf_outputs(src_root: pathlib.Path, dst_root: pathlib.Path) -> None:
    if dst_root.exists():
        shutil.rmtree(dst_root)
    dst_root.mkdir(parents=True)

    for name in (
        "bench_stats_median.csv",
        "bench_stats_mad.csv",
        "bench_stats_min.csv",
        "bench_stats_max.csv",
        "bench_stats_cov.csv",
        "config.txt",
        "command.txt",
        "stdout.txt",
        "stderr.txt",
    ):
        path = src_root / name
        if path.exists():
            shutil.copy2(path, dst_root / name)

    for run_csv in src_root.glob("bench_run*.csv"):
        shutil.copy2(run_csv, dst_root / run_csv.name)


def write_metadata(
    out_dir: pathlib.Path,
    case: PerfCase,
    profile: PerfProfile,
    runs: int,
    command: list[str],
) -> None:
    payload = {
        "case": case.name,
        "profile": profile.name,
        "benchmark_name": case.benchmark_name,
        "binary_name": case.binary_name,
        "runs": runs,
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "command": command,
        "profile_config": asdict(profile),
        "reference_dir": (
            command_path(reference_dir(case, profile))
            if reference_dir(case, profile) is not None
            else None
        ),
    }
    (out_dir / "metadata.json").write_text(json.dumps(payload, indent=2) + "\n")


def write_comparison_json(
    out_dir: pathlib.Path,
    deltas: list[PerfDelta],
    reference_root: pathlib.Path,
) -> None:
    payload = {
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "reference_root": command_path(reference_root),
        "deltas": [asdict(delta) for delta in deltas],
    }
    (out_dir / "comparison.json").write_text(json.dumps(payload, indent=2) + "\n")


def report_file_prefix(case: PerfCase) -> str:
    return case.name


def write_case_report_csv(
    out_dir: pathlib.Path,
    case: PerfCase,
    deltas: list[PerfDelta],
) -> None:
    timestamp = timestamp_string()
    fieldnames = [
        "case_name",
        "status",
        "reasons",
        "gold_geom_ms",
        "current_geom_ms",
        "geom_delta_ms",
        "geom_delta_pct",
        "gold_raster_ms",
        "current_raster_ms",
        "raster_delta_ms",
        "raster_delta_pct",
        "gold_median_ms",
        "current_median_ms",
        "delta_ms",
        "delta_pct",
        "gold_mad_ms",
        "current_mad_ms",
        "mad_abs_delta_ms",
        "mad_units",
        "gold_cov_mad_pct",
        "current_cov_mad_pct",
        "cov_mad_ratio",
        "gold_min_ms",
        "gold_max_ms",
        "current_min_ms",
        "current_max_ms",
        "gold_range_ms",
        "current_range_ms",
        "range_abs_delta_ms",
        "range_ratio",
        "case_name_end",
        "status_end",
        "reasons_end",
    ]
    rows: list[dict[str, str]] = []
    for delta in deltas:
        geom_delta_ms = delta.current_geom_ms - delta.gold_geom_ms
        geom_delta_pct = (
            0.0
            if delta.gold_geom_ms == 0.0
            else geom_delta_ms / delta.gold_geom_ms * 100.0
        )
        raster_delta_ms = delta.current_raster_ms - delta.gold_raster_ms
        raster_delta_pct = (
            0.0
            if delta.gold_raster_ms == 0.0
            else raster_delta_ms / delta.gold_raster_ms * 100.0
        )
        reasons = "; ".join(delta.reasons)
        rows.append(
            {
                "case_name": delta.case_name,
                "status": delta.status,
                "reasons": reasons,
                "gold_geom_ms": f"{delta.gold_geom_ms:.6f}",
                "current_geom_ms": f"{delta.current_geom_ms:.6f}",
                "geom_delta_ms": f"{geom_delta_ms:.6f}",
                "geom_delta_pct": f"{geom_delta_pct:.6f}",
                "gold_raster_ms": f"{delta.gold_raster_ms:.6f}",
                "current_raster_ms": f"{delta.current_raster_ms:.6f}",
                "raster_delta_ms": f"{raster_delta_ms:.6f}",
                "raster_delta_pct": f"{raster_delta_pct:.6f}",
                "gold_median_ms": f"{delta.gold_median_ms:.6f}",
                "current_median_ms": f"{delta.current_median_ms:.6f}",
                "delta_ms": f"{delta.delta_ms:.6f}",
                "delta_pct": f"{delta.delta_pct:.6f}",
                "gold_mad_ms": f"{delta.gold_mad_ms:.6f}",
                "current_mad_ms": f"{delta.current_mad_ms:.6f}",
                "mad_abs_delta_ms": f"{delta.mad_abs_delta_ms:.6f}",
                "mad_units": f"{delta.mad_units:.6f}",
                "gold_cov_mad_pct": f"{delta.gold_cov_mad_pct:.6f}",
                "current_cov_mad_pct": f"{delta.current_cov_mad_pct:.6f}",
                "cov_mad_ratio": f"{delta.cov_mad_ratio:.6f}",
                "gold_min_ms": f"{delta.gold_min_ms:.6f}",
                "gold_max_ms": f"{delta.gold_max_ms:.6f}",
                "current_min_ms": f"{delta.current_min_ms:.6f}",
                "current_max_ms": f"{delta.current_max_ms:.6f}",
                "gold_range_ms": f"{delta.gold_range_ms:.6f}",
                "current_range_ms": f"{delta.current_range_ms:.6f}",
                "range_abs_delta_ms": f"{delta.range_abs_delta_ms:.6f}",
                "range_ratio": f"{delta.range_ratio:.6f}",
                "case_name_end": delta.case_name,
                "status_end": delta.status,
                "reasons_end": reasons,
            },
        )

    report_sets = {
        "overall": rows,
        "amber": [row for row in rows if row["status"] == STATUS_AMBER],
        "red": [row for row in rows if row["status"] == STATUS_RED],
    }
    prefix = report_file_prefix(case)
    for label, report_rows in report_sets.items():
        report_path = out_dir / f"{prefix}_{label}_{timestamp}.csv"
        with report_path.open("w", newline="") as csv_file:
            writer = csv.DictWriter(csv_file, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(report_rows)


def write_summary_report(
    out_dir: pathlib.Path,
    case: PerfCase,
    profile: PerfProfile,
    label: str,
    deltas: list[PerfDelta],
) -> None:
    status_counts = {
        STATUS_GREEN: sum(1 for delta in deltas if delta.status == STATUS_GREEN),
        STATUS_AMBER: sum(1 for delta in deltas if delta.status == STATUS_AMBER),
        STATUS_RED: sum(1 for delta in deltas if delta.status == STATUS_RED),
    }
    overall_status = STATUS_RED
    if status_counts[STATUS_RED] == 0:
        overall_status = STATUS_AMBER
    if (
        status_counts[STATUS_RED] == 0
        and status_counts[STATUS_AMBER] == 0
    ):
        overall_status = STATUS_GREEN

    worst_by_median = sorted(
        deltas,
        key=lambda item: item.delta_pct,
        reverse=True,
    )[:TOP_N]
    worst_by_cov = sorted(
        deltas,
        key=lambda item: item.cov_mad_ratio,
        reverse=True,
    )[:TOP_N]
    worst_by_range = sorted(
        deltas,
        key=lambda item: item.range_ratio,
        reverse=True,
    )[:TOP_N]

    lines = [
        f"perf report: {case.name}/{profile.name}",
        f"generated_at_utc={dt.datetime.now(dt.timezone.utc).isoformat()}",
        f"comparison_label={label}",
        f"overall_status={overall_status}",
        (
            "counts="
            f"green:{status_counts[STATUS_GREEN]},"
            f"amber:{status_counts[STATUS_AMBER]},"
            f"red:{status_counts[STATUS_RED]}"
        ),
        "",
        "thresholds:",
        (
            f"  median green<= {MEDIAN_GREEN_PCT:.2f}%"
            f", red> {MEDIAN_RED_PCT:.2f}%"
            f", abs_floor> {MEDIAN_ABS_DELTA_FLOOR_MS:.2f} ms"
        ),
        (
            f"  cov_mad green<= x{COV_GREEN_RATIO:.2f}"
            f", red> x{COV_RED_RATIO:.2f}"
            f", abs_floor> {MAD_ABS_DELTA_FLOOR_MS:.2f} ms"
        ),
        (
            f"  range green<= x{RANGE_GREEN_RATIO:.2f}"
            f", red> x{RANGE_RED_RATIO:.2f}"
            f", abs_floor> {RANGE_ABS_DELTA_FLOOR_MS:.2f} ms"
        ),
        "",
        "worst_median_regressions:",
    ]

    for delta in worst_by_median:
        lines.append(
            "  "
            f"{delta.case_name}: {delta.status} "
            f"median {delta.current_median_ms:.3f} vs {delta.gold_median_ms:.3f} ms "
            f"({delta.delta_ms:+.3f} ms, {delta.delta_pct:+.2f}%) "
            f"geom {delta.current_geom_ms:.3f}/{delta.gold_geom_ms:.3f} "
            f"raster {delta.current_raster_ms:.3f}/{delta.gold_raster_ms:.3f} "
            f"reasons: {', '.join(delta.reasons)}"
        )

    lines.extend(["", "worst_cov_mad_regressions:"])
    for delta in worst_by_cov:
        lines.append(
            "  "
            f"{delta.case_name}: {delta.status} "
            f"COV(MAD) {delta.current_cov_mad_pct:.3f}% vs "
            f"{delta.gold_cov_mad_pct:.3f}% (x{delta.cov_mad_ratio:.2f}) "
            f"reasons: {', '.join(delta.reasons)}"
        )

    lines.extend(["", "worst_range_regressions:"])
    for delta in worst_by_range:
        lines.append(
            "  "
            f"{delta.case_name}: {delta.status} "
            f"range {delta.current_range_ms:.3f} vs {delta.gold_range_ms:.3f} ms "
            f"(x{delta.range_ratio:.2f}) "
            f"reasons: {', '.join(delta.reasons)}"
        )

    (out_dir / "comparison_report.txt").write_text("\n".join(lines) + "\n")


def report_deltas(
    case: PerfCase,
    profile: PerfProfile,
    deltas: list[PerfDelta],
    label: str,
) -> int:
    regressions = sorted(
        [delta for delta in deltas if delta.delta_ms > 0.0],
        key=lambda item: (
            item.status == STATUS_RED,
            item.status == STATUS_AMBER,
            item.delta_ms,
            item.delta_pct,
        ),
        reverse=True,
    )
    improvements = sorted(
        [delta for delta in deltas if delta.delta_ms < 0.0],
        key=lambda item: (
            item.status == STATUS_RED,
            item.status == STATUS_AMBER,
            item.delta_ms,
        ),
    )

    red_regressions = [
        delta for delta in regressions if delta.status == STATUS_RED
    ]
    amber_regressions = [
        delta for delta in regressions if delta.status == STATUS_AMBER
    ]
    amber_or_red_improvements = [
        delta for delta in improvements if delta.status != STATUS_GREEN
    ]

    prefix = f"[perf:{case.name}:{profile.name}]"
    print(f"{prefix} Top regressions vs {label} (E2E median):")
    for delta in regressions[:TOP_N]:
        sig = delta.status
        print(
            "  "
            f"{delta.case_name}: "
            f"{delta.current_median_ms:.6f} ms vs {delta.gold_median_ms:.6f} ms "
            f"({delta.delta_ms:+.6f} ms, {delta.delta_pct:+.2f}%, "
            f"cov x{delta.cov_mad_ratio:.2f}, "
            f"range x{delta.range_ratio:.2f}, {sig})",
        )

    print(f"{prefix} Top improvements vs {label} (E2E median):")
    for delta in improvements[:TOP_N]:
        sig = delta.status
        print(
            "  "
            f"{delta.case_name}: "
            f"{delta.current_median_ms:.6f} ms vs {delta.gold_median_ms:.6f} ms "
            f"({delta.delta_ms:+.6f} ms, {delta.delta_pct:+.2f}%, "
            f"cov x{delta.cov_mad_ratio:.2f}, "
            f"range x{delta.range_ratio:.2f}, {sig})",
        )

    if not red_regressions and not amber_regressions and not amber_or_red_improvements:
        print(f"{prefix} No significant performance difference detected.")
        return 0

    if red_regressions:
        print(
            f"{prefix} RED regressions detected: "
            f"{len(red_regressions)} case(s).",
        )
        return 1

    if amber_regressions:
        print(
            f"{prefix} AMBER regressions detected: "
            f"{len(amber_regressions)} case(s).",
        )
        return 0

    print(
        f"{prefix} Non-green improvements detected: "
        f"{len(amber_or_red_improvements)} case(s).",
    )
    return 0


def generate_gold(
    case_name: str,
    profile_name: str = DEFAULT_PROFILE,
    runs: int = DEFAULT_GOLD_RUNS,
) -> int:
    case = case_or_die(case_name)
    profile = profile_or_die(case_name, profile_name)
    print(
        f"[perf:{case.name}:{profile.name}] Generating gold with "
        f"{runs} run(s)...",
    )
    staging_dir = gold_stage_dir(case, profile)
    command = run_benchmark_binary(case, profile, runs, staging_dir)
    final_gold_dir = gold_dir(case, profile)
    copy_perf_outputs(staging_dir, final_gold_dir)
    write_metadata(final_gold_dir, case, profile, runs, command)
    print(f"[perf:{case.name}:{profile.name}] Gold written to {final_gold_dir}")
    return 0


def test_perf(
    case_name: str,
    profile_name: str = DEFAULT_PROFILE,
    runs: int = DEFAULT_TEST_RUNS,
) -> int:
    case = case_or_die(case_name)
    profile = profile_or_die(case_name, profile_name)
    baseline_dir = gold_dir(case, profile)
    if not baseline_dir.exists():
        raise SystemExit(
            f"Missing perf gold for {case.name}/{profile.name} at "
            f"{baseline_dir}. Run gen_gold_perf_{case.name}.py first.",
        )

    print(
        f"[perf:{case.name}:{profile.name}] Running comparison with "
        f"{runs} run(s)...",
    )
    out_dir = test_run_dir(case, profile)
    command = run_benchmark_binary(case, profile, runs, out_dir)
    write_metadata(out_dir, case, profile, runs, command)
    deltas = compare_case_maps(baseline_dir, out_dir)
    write_comparison_json(out_dir, deltas, baseline_dir)
    write_case_report_csv(out_dir, deltas)
    write_summary_report(out_dir, case, profile, "gold", deltas)
    return report_deltas(case, profile, deltas, "gold")


def run_case_script(
    script_name: str,
    profile_name: str,
    runs: int | None = None,
) -> None:
    command = [str(python_path()), str(repo_root() / "scripts" / script_name)]
    command.extend(["--profile", profile_name])
    if runs is not None:
        command.extend(["--runs", str(runs)])
    subprocess.run(command, cwd=repo_root(), check=True)


def update_buildconfig_simd(simd_mode: str) -> None:
    buildconfig_path = repo_root() / "src" / "riley" / "zig" / "buildconfig.zig"
    text = buildconfig_path.read_text()
    pattern = re.compile(
        r"(^\s*simd:\s*SimdMode\s*=\s*)\.(on|off)(,\s*$)",
        re.MULTILINE,
    )
    text_updated, replace_count = pattern.subn(
        r"\1." + simd_mode + r"\3",
        text,
        count=1,
    )
    if replace_count != 1:
        raise SystemExit("Failed to update buildconfig simd mode.")
    buildconfig_path.write_text(text_updated)
