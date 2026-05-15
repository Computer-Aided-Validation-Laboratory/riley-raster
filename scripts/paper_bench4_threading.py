#!/usr/bin/env python3
from __future__ import annotations

import csv
import math
import pathlib
import re
from dataclasses import dataclass

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

from paper_bench_common import latest_run_dir_with_paths
from paper_const import (
    PLOT_LINE_FIG_SIZE_IN,
    PLOT_LINE_AXIS_FONT_SIZE,
    PLOT_LINE_LEGEND_FONT_SIZE,
    PLOT_LINE_TICK_FONT_SIZE,
    PLOT_LINE_TITLE_FONT_SIZE,
    PLOT_RESOLUTION_DPI,
    repo_root,
)


BENCH_NAME = "bench_dicuq"
EXPERIMENT_DIR = "experiment_5_complete_matrix"

OUT_DIR = repo_root() / "verif"

CASE_DIR_RE = re.compile(
    r"^bench_dicuq_threads-(?P<threads>\d+)"
    r"_geom-(?P<geom>\d+)"
    r"_raster-(?P<raster>\d+)"
    r"_frames-(?P<frames>\d+)"
    r"_render-(?P<render>offline|in_order)"
    r"_save-(?P<save>[a-z_]+)$",
)


@dataclass(slots=True)
class CaseStats:
    case_dir: pathlib.Path
    threads: int
    frames_in_flight: int
    render_mode: str
    case_name: str
    e2e_median_ms: float
    e2e_min_ms: float
    e2e_max_ms: float
    raster_median_ms: float
    raster_min_ms: float
    raster_max_ms: float
    run_count: int


@dataclass(slots=True)
class LastFrameRasterStats:
    threads: int
    render_mode: str
    frames_in_flight: int
    frame_idx: int
    median_ms: float
    min_ms: float
    max_ms: float
    sample_count: int


@dataclass(slots=True)
class CameraFrameRasterStats:
    threads: int
    render_mode: str
    frames_in_flight: int
    camera_idx: int
    frame_idx: int
    median_ms: float
    min_ms: float
    max_ms: float
    run_count: int


@dataclass(slots=True)
class CameraRunMedianRasterStats:
    threads: int
    render_mode: str
    frames_in_flight: int
    camera_idx: int
    median_ms: float
    min_ms: float
    max_ms: float
    run_count: int


def load_csv_rows(csv_path: pathlib.Path) -> list[dict[str, str]]:
    with csv_path.open(newline="") as csv_file:
        return list(csv.DictReader(csv_file))


def find_camera_all_row(csv_path: pathlib.Path) -> dict[str, str]:
    rows = load_csv_rows(csv_path)
    camera_all = [row for row in rows if row["Camera"] == "all"]
    if not camera_all:
        raise ValueError(f"no Camera=all row in {csv_path}")
    if len(camera_all) > 1:
        case_names = {row["Case"] for row in camera_all}
        if len(case_names) != 1:
            raise ValueError(f"multiple Camera=all cases in {csv_path}: {sorted(case_names)}")
    return camera_all[0]


def parse_case_stats(case_dir: pathlib.Path) -> CaseStats | None:
    match = CASE_DIR_RE.match(case_dir.name)
    if match is None:
        return None

    median_row = find_camera_all_row(case_dir / "bench_e2e_overruns_median.csv")
    min_row = find_camera_all_row(case_dir / "bench_e2e_overruns_min.csv")
    max_row = find_camera_all_row(case_dir / "bench_e2e_overruns_max.csv")

    return CaseStats(
        case_dir=case_dir,
        threads=int(match.group("threads")),
        frames_in_flight=int(match.group("frames")),
        render_mode=match.group("render"),
        case_name=median_row["Case"],
        e2e_median_ms=float(median_row["E2E_ms"]),
        e2e_min_ms=float(min_row["E2E_ms"]),
        e2e_max_ms=float(max_row["E2E_ms"]),
        raster_median_ms=float(median_row["Raster_ms"]),
        raster_min_ms=float(min_row["Raster_ms"]),
        raster_max_ms=float(max_row["Raster_ms"]),
        run_count=len(list(case_dir.glob("bench_run*_e2e.csv"))),
    )


def parse_last_frame_raster_stats(case_dir: pathlib.Path) -> LastFrameRasterStats | None:
    match = CASE_DIR_RE.match(case_dir.name)
    if match is None:
        return None

    run_paths = sorted(case_dir.glob("bench_run*_byframe.csv"))
    if not run_paths:
        return None

    run0_rows = load_csv_rows(run_paths[0])
    frame_vals = [
        int(row["Frame"])
        for row in run0_rows
        if row["Camera"] in {"0", "1"}
    ]
    if not frame_vals:
        raise ValueError(f"no camera 0/1 frame rows in {run_paths[0]}")
    last_frame_idx = max(frame_vals)

    raster_samples_ms: list[float] = []
    for run_path in run_paths:
        run_rows = load_csv_rows(run_path)
        for camera_idx in ("0", "1"):
            matches = [
                float(row["Raster_ms"])
                for row in run_rows
                if row["Camera"] == camera_idx and int(row["Frame"]) == last_frame_idx
            ]
            if len(matches) != 1:
                raise ValueError(
                    f"expected 1 last-frame raster row in {run_path} for "
                    f"camera {camera_idx}, frame {last_frame_idx}; got {len(matches)}"
                )
            raster_samples_ms.append(matches[0])

    raster_samples_ms.sort()
    return LastFrameRasterStats(
        threads=int(match.group("threads")),
        render_mode=match.group("render"),
        frames_in_flight=int(match.group("frames")),
        frame_idx=last_frame_idx,
        median_ms=float(_median(raster_samples_ms)),
        min_ms=min(raster_samples_ms),
        max_ms=max(raster_samples_ms),
        sample_count=len(raster_samples_ms),
    )


def _median(values: list[float]) -> float:
    values_sorted = sorted(values)
    n = len(values_sorted)
    if n == 0:
        raise ValueError("cannot take median of empty list")
    mid = n // 2
    if n % 2 == 1:
        return values_sorted[mid]
    return 0.5 * (values_sorted[mid - 1] + values_sorted[mid])


def collect_case_stats() -> list[CaseStats]:
    latest_run = latest_run_dir_with_paths(
        BENCH_NAME,
        [EXPERIMENT_DIR],
    )
    experiment_root = latest_run / EXPERIMENT_DIR
    print(f"Using benchmark run: {experiment_root}")

    stats: list[CaseStats] = []
    for case_dir in sorted(path for path in experiment_root.iterdir() if path.is_dir()):
        case_stats = parse_case_stats(case_dir)
        if case_stats is not None:
            stats.append(case_stats)

    if not stats:
        raise FileNotFoundError(f"no experiment-5 case directories found in {experiment_root}")

    case_names = sorted({case.case_name for case in stats})
    if len(case_names) != 1:
        raise ValueError(f"expected one benchmark case in experiment 5, found {case_names}")

    return stats


def collect_last_frame_raster_stats() -> list[LastFrameRasterStats]:
    latest_run = latest_run_dir_with_paths(
        BENCH_NAME,
        [EXPERIMENT_DIR],
    )
    experiment_root = latest_run / EXPERIMENT_DIR

    stats: list[LastFrameRasterStats] = []
    for case_dir in sorted(path for path in experiment_root.iterdir() if path.is_dir()):
        case_stats = parse_last_frame_raster_stats(case_dir)
        if case_stats is not None:
            stats.append(case_stats)

    if not stats:
        raise FileNotFoundError(f"no last-frame raster stats found in {experiment_root}")
    return stats


def get_frame_triplet() -> tuple[int, int, int]:
    latest_run = latest_run_dir_with_paths(
        BENCH_NAME,
        [EXPERIMENT_DIR],
    )
    experiment_root = latest_run / EXPERIMENT_DIR
    first_case_dir = next(path for path in sorted(experiment_root.iterdir()) if path.is_dir())
    first_run = next(iter(sorted(first_case_dir.glob("bench_run*_byframe.csv"))))
    rows = load_csv_rows(first_run)
    frame_values = sorted(
        {
            int(row["Frame"])
            for row in rows
            if row["Camera"] in {"0", "1"}
        }
    )
    if not frame_values:
        raise ValueError(f"no frame rows found in {first_run}")
    return frame_values[0], frame_values[len(frame_values) // 2], frame_values[-1]


def parse_camera_frame_raster_stats(
    case_dir: pathlib.Path,
    camera_idx: int,
    frame_idx: int,
) -> CameraFrameRasterStats | None:
    match = CASE_DIR_RE.match(case_dir.name)
    if match is None:
        return None

    run_paths = sorted(case_dir.glob("bench_run*_byframe.csv"))
    if not run_paths:
        return None

    raster_samples_ms: list[float] = []
    for run_path in run_paths:
        run_rows = load_csv_rows(run_path)
        matches = [
            float(row["Raster_ms"])
            for row in run_rows
            if row["Camera"] == str(camera_idx) and int(row["Frame"]) == frame_idx
        ]
        if len(matches) != 1:
            raise ValueError(
                f"expected 1 raster row in {run_path} for "
                f"camera {camera_idx}, frame {frame_idx}; got {len(matches)}"
            )
        raster_samples_ms.append(matches[0])

    raster_samples_ms.sort()
    return CameraFrameRasterStats(
        threads=int(match.group("threads")),
        render_mode=match.group("render"),
        frames_in_flight=int(match.group("frames")),
        camera_idx=camera_idx,
        frame_idx=frame_idx,
        median_ms=float(_median(raster_samples_ms)),
        min_ms=min(raster_samples_ms),
        max_ms=max(raster_samples_ms),
        run_count=len(raster_samples_ms),
    )


def collect_camera_frame_raster_stats(
    camera_idx: int,
    frame_idx: int,
) -> list[CameraFrameRasterStats]:
    latest_run = latest_run_dir_with_paths(
        BENCH_NAME,
        [EXPERIMENT_DIR],
    )
    experiment_root = latest_run / EXPERIMENT_DIR

    stats: list[CameraFrameRasterStats] = []
    for case_dir in sorted(path for path in experiment_root.iterdir() if path.is_dir()):
        case_stats = parse_camera_frame_raster_stats(case_dir, camera_idx, frame_idx)
        if case_stats is not None:
            stats.append(case_stats)

    if not stats:
        raise FileNotFoundError(f"no camera/frame raster stats found in {experiment_root}")
    return stats


def parse_camera_runmedian_raster_stats(
    case_dir: pathlib.Path,
    camera_idx: int,
) -> CameraRunMedianRasterStats | None:
    match = CASE_DIR_RE.match(case_dir.name)
    if match is None:
        return None

    run_paths = sorted(case_dir.glob("bench_run*_byframe.csv"))
    if not run_paths:
        return None

    run_medians_ms: list[float] = []
    for run_path in run_paths:
        run_rows = load_csv_rows(run_path)
        camera_vals = sorted(
            float(row["Raster_ms"])
            for row in run_rows
            if row["Camera"] == str(camera_idx)
        )
        if not camera_vals:
            raise ValueError(f"no raster rows for camera {camera_idx} in {run_path}")
        run_medians_ms.append(float(_median(camera_vals)))

    run_medians_ms.sort()
    return CameraRunMedianRasterStats(
        threads=int(match.group("threads")),
        render_mode=match.group("render"),
        frames_in_flight=int(match.group("frames")),
        camera_idx=camera_idx,
        median_ms=float(_median(run_medians_ms)),
        min_ms=min(run_medians_ms),
        max_ms=max(run_medians_ms),
        run_count=len(run_medians_ms),
    )


def collect_camera_runmedian_raster_stats(
    camera_idx: int,
) -> list[CameraRunMedianRasterStats]:
    latest_run = latest_run_dir_with_paths(
        BENCH_NAME,
        [EXPERIMENT_DIR],
    )
    experiment_root = latest_run / EXPERIMENT_DIR

    stats: list[CameraRunMedianRasterStats] = []
    for case_dir in sorted(path for path in experiment_root.iterdir() if path.is_dir()):
        case_stats = parse_camera_runmedian_raster_stats(case_dir, camera_idx)
        if case_stats is not None:
            stats.append(case_stats)

    if not stats:
        raise FileNotFoundError(f"no camera run-median raster stats found in {experiment_root}")
    return stats


def build_lookup(stats: list[CaseStats]) -> dict[tuple[str, int, int], CaseStats]:
    return {
        (case.render_mode, case.frames_in_flight, case.threads): case
        for case in stats
    }


def calc_speedup_bounds(
    baseline_median_ms: float,
    current_median_ms: float,
    current_min_ms: float,
    current_max_ms: float,
) -> tuple[float, float, float]:
    speedup_median = baseline_median_ms / current_median_ms
    speedup_low = baseline_median_ms / current_max_ms
    speedup_high = baseline_median_ms / current_min_ms
    return speedup_median, speedup_low, speedup_high


def amdahl_serial_fraction(
    thread_values: list[int],
    speedup_values: list[float],
) -> float:
    num = 0.0
    den = 0.0
    for threads, speedup in zip(thread_values, speedup_values, strict=True):
        if threads <= 1 or speedup <= 0.0:
            continue
        x = 1.0 / float(threads)
        y = 1.0 / speedup
        w = 1.0 - x
        z = y - x
        num += w * z
        den += w * w
    if den == 0.0:
        return 0.0
    return min(1.0, max(0.0, num / den))


def amdahl_speedup(serial_fraction: float, threads: int) -> float:
    return 1.0 / (serial_fraction + (1.0 - serial_fraction) / float(threads))


def amdahl_point_serial_fraction(threads: int, speedup: float) -> float | None:
    if threads <= 1 or speedup <= 0.0:
        return None
    inv_threads = 1.0 / float(threads)
    numerator = (1.0 / speedup) - inv_threads
    denominator = 1.0 - inv_threads
    if denominator == 0.0:
        return None
    return numerator / denominator


def write_amdahl_csv(
    out_path: pathlib.Path,
    rows: list[dict[str, object]],
) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "Metric",
        "Series",
        "RenderMode",
        "FramesInFlight",
        "Threads",
        "FrameIdx",
        "SampleCount",
        "BaselineMedian_ms",
        "ObservedMedian_ms",
        "ObservedMin_ms",
        "ObservedMax_ms",
        "ObservedSpeedup_x",
        "ObservedSpeedupLow_x",
        "ObservedSpeedupHigh_x",
        "PointSerialFraction",
        "FitSerialFraction",
        "FitSerialPercent",
        "FitParallelFraction",
        "FitParallelPercent",
        "FitAsymptoticSpeedup_x",
        "PredictedSpeedup_x",
        "PredictedMedian_ms",
        "SpeedupAbsError_x",
        "SpeedupRelError_pct",
        "RunCount",
        "SampleBasis",
        "Case",
    ]
    with out_path.open("w", newline="") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {out_path}")


def build_raster_amdahl_rows(
    raw_raster_stats: list[LastFrameRasterStats],
    case_name: str,
) -> list[dict[str, object]]:
    rows_out: list[dict[str, object]] = []
    fif_stats = [case for case in raw_raster_stats if case.frames_in_flight == 1]
    for render_mode in ["offline", "in_order"]:
        mode_stats = sorted(
            [case for case in fif_stats if case.render_mode == render_mode],
            key=lambda case: case.threads,
        )
        baseline = next((case for case in mode_stats if case.threads == 1), None)
        if baseline is None:
            continue
        thread_values = [case.threads for case in mode_stats]
        speedup_values = [baseline.median_ms / case.median_ms for case in mode_stats]
        serial_fraction = amdahl_serial_fraction(thread_values, speedup_values)
        asymptotic_speedup = math.inf if serial_fraction == 0.0 else 1.0 / serial_fraction

        for case in mode_stats:
            observed_speedup, observed_low, observed_high = calc_speedup_bounds(
                baseline.median_ms,
                case.median_ms,
                case.min_ms,
                case.max_ms,
            )
            predicted_speedup = amdahl_speedup(serial_fraction, case.threads)
            predicted_ms = baseline.median_ms / predicted_speedup
            point_serial = amdahl_point_serial_fraction(case.threads, observed_speedup)
            rel_err_pct = (
                0.0
                if observed_speedup == 0.0
                else abs(predicted_speedup - observed_speedup) / observed_speedup * 100.0
            )
            rows_out.append(
                {
                    "Metric": "Raster",
                    "Series": f"{render_mode}_fif1_lastframe_cam01",
                    "RenderMode": render_mode,
                    "FramesInFlight": 1,
                    "Threads": case.threads,
                    "FrameIdx": case.frame_idx,
                    "SampleCount": case.sample_count,
                    "BaselineMedian_ms": f"{baseline.median_ms:.6f}",
                    "ObservedMedian_ms": f"{case.median_ms:.6f}",
                    "ObservedMin_ms": f"{case.min_ms:.6f}",
                    "ObservedMax_ms": f"{case.max_ms:.6f}",
                    "ObservedSpeedup_x": f"{observed_speedup:.6f}",
                    "ObservedSpeedupLow_x": f"{observed_low:.6f}",
                    "ObservedSpeedupHigh_x": f"{observed_high:.6f}",
                    "PointSerialFraction": ""
                    if point_serial is None
                    else f"{point_serial:.6f}",
                    "FitSerialFraction": f"{serial_fraction:.6f}",
                    "FitSerialPercent": f"{serial_fraction * 100.0:.6f}",
                    "FitParallelFraction": f"{1.0 - serial_fraction:.6f}",
                    "FitParallelPercent": f"{(1.0 - serial_fraction) * 100.0:.6f}",
                    "FitAsymptoticSpeedup_x": ""
                    if math.isinf(asymptotic_speedup)
                    else f"{asymptotic_speedup:.6f}",
                    "PredictedSpeedup_x": f"{predicted_speedup:.6f}",
                    "PredictedMedian_ms": f"{predicted_ms:.6f}",
                    "SpeedupAbsError_x": f"{abs(predicted_speedup - observed_speedup):.6f}",
                    "SpeedupRelError_pct": f"{rel_err_pct:.6f}",
                    "RunCount": case.sample_count // 2,
                    "SampleBasis": "last frame pooled over cameras 0 and 1 across all runs",
                    "Case": case_name,
                }
            )
    return rows_out


def build_e2e_amdahl_rows(
    all_stats: list[CaseStats],
    case_name: str,
) -> list[dict[str, object]]:
    rows_out: list[dict[str, object]] = []
    for render_mode in ["offline", "in_order"]:
        for fif in sorted({case.frames_in_flight for case in all_stats if case.render_mode == render_mode}):
            series_stats = sorted(
                [
                    case
                    for case in all_stats
                    if case.render_mode == render_mode and case.frames_in_flight == fif
                ],
                key=lambda case: case.threads,
            )
            baseline = next((case for case in series_stats if case.threads == 1), None)
            if baseline is None:
                continue
            thread_values = [case.threads for case in series_stats]
            speedup_values = [baseline.e2e_median_ms / case.e2e_median_ms for case in series_stats]
            serial_fraction = amdahl_serial_fraction(thread_values, speedup_values)
            asymptotic_speedup = math.inf if serial_fraction == 0.0 else 1.0 / serial_fraction

            for case in series_stats:
                observed_speedup, observed_low, observed_high = calc_speedup_bounds(
                    baseline.e2e_median_ms,
                    case.e2e_median_ms,
                    case.e2e_min_ms,
                    case.e2e_max_ms,
                )
                predicted_speedup = amdahl_speedup(serial_fraction, case.threads)
                predicted_ms = baseline.e2e_median_ms / predicted_speedup
                point_serial = amdahl_point_serial_fraction(case.threads, observed_speedup)
                rel_err_pct = (
                    0.0
                    if observed_speedup == 0.0
                    else abs(predicted_speedup - observed_speedup) / observed_speedup * 100.0
                )
                rows_out.append(
                    {
                        "Metric": "EndToEnd",
                        "Series": f"{render_mode}_fif{fif}",
                        "RenderMode": render_mode,
                        "FramesInFlight": fif,
                        "Threads": case.threads,
                        "FrameIdx": "",
                        "SampleCount": case.run_count,
                        "BaselineMedian_ms": f"{baseline.e2e_median_ms:.6f}",
                        "ObservedMedian_ms": f"{case.e2e_median_ms:.6f}",
                        "ObservedMin_ms": f"{case.e2e_min_ms:.6f}",
                        "ObservedMax_ms": f"{case.e2e_max_ms:.6f}",
                        "ObservedSpeedup_x": f"{observed_speedup:.6f}",
                        "ObservedSpeedupLow_x": f"{observed_low:.6f}",
                        "ObservedSpeedupHigh_x": f"{observed_high:.6f}",
                        "PointSerialFraction": ""
                        if point_serial is None
                        else f"{point_serial:.6f}",
                        "FitSerialFraction": f"{serial_fraction:.6f}",
                        "FitSerialPercent": f"{serial_fraction * 100.0:.6f}",
                        "FitParallelFraction": f"{1.0 - serial_fraction:.6f}",
                        "FitParallelPercent": f"{(1.0 - serial_fraction) * 100.0:.6f}",
                        "FitAsymptoticSpeedup_x": ""
                        if math.isinf(asymptotic_speedup)
                        else f"{asymptotic_speedup:.6f}",
                        "PredictedSpeedup_x": f"{predicted_speedup:.6f}",
                        "PredictedMedian_ms": f"{predicted_ms:.6f}",
                        "SpeedupAbsError_x": f"{abs(predicted_speedup - observed_speedup):.6f}",
                        "SpeedupRelError_pct": f"{rel_err_pct:.6f}",
                        "RunCount": case.run_count,
                        "SampleBasis": "camera=all end-to-end summary over runs",
                        "Case": case_name,
                    }
                )
    return rows_out


def save_raster_fif1_plot(
    out_base: pathlib.Path,
    stats: list[LastFrameRasterStats],
) -> None:
    fif_stats = [case for case in stats if case.frames_in_flight == 1]
    if not fif_stats:
        raise FileNotFoundError("no FiF=1 raster stats found for bench_dicuq experiment 5")

    thread_values = sorted({case.threads for case in fif_stats})
    render_modes = ["offline", "in_order"]

    fig, ax = plt.subplots(figsize=PLOT_LINE_FIG_SIZE_IN, constrained_layout=False)

    for render_mode in render_modes:
        mode_stats = sorted(
            [case for case in fif_stats if case.render_mode == render_mode],
            key=lambda case: case.threads,
        )
        baseline = next((case for case in mode_stats if case.threads == 1), None)
        if baseline is None:
            print(f"Skipping {render_mode}: missing 1-thread FiF=1 baseline")
            continue

        xs: list[int] = []
        ys: list[float] = []
        yerr_low: list[float] = []
        yerr_high: list[float] = []

        for case in mode_stats:
            speedup_median, speedup_low, speedup_high = calc_speedup_bounds(
                baseline.median_ms,
                case.median_ms,
                case.min_ms,
                case.max_ms,
            )
            xs.append(case.threads)
            ys.append(speedup_median)
            yerr_low.append(speedup_median - speedup_low)
            yerr_high.append(speedup_high - speedup_median)

        label = "Offline" if render_mode == "offline" else "In-order"
        ax.errorbar(
            xs,
            ys,
            yerr=[yerr_low, yerr_high],
            marker="o",
            linewidth=2.0,
            markersize=5.0,
            capsize=3.0,
            label=label,
        )

    ideal_y = [float(val) for val in thread_values]
    ax.plot(
        thread_values,
        ideal_y,
        linestyle="--",
        color="black",
        linewidth=1.5,
        label="Ideal",
    )

    ax.set_xlabel("Threads", fontsize=PLOT_LINE_AXIS_FONT_SIZE)
    ax.set_ylabel("Speedup [x]", fontsize=PLOT_LINE_AXIS_FONT_SIZE)
    ax.set_title("Raster, FiF=1", fontsize=PLOT_LINE_TITLE_FONT_SIZE, pad=10.0)
    ax.tick_params(labelsize=PLOT_LINE_TICK_FONT_SIZE)
    ax.grid(True, alpha=0.25, linewidth=0.8)
    ax.set_xticks(thread_values, [str(val) for val in thread_values])
    ax.set_xlim(min(thread_values) - 0.2, max(thread_values) + 0.2)
    ax.set_ylim(bottom=0.0)
    ax.legend(fontsize=PLOT_LINE_LEGEND_FONT_SIZE, frameon=True)

    fig.subplots_adjust(
        left=0.19,
        right=0.98,
        bottom=0.18,
        top=0.87,
    )

    png_path = out_base.with_suffix(".png")
    svg_path = out_base.with_suffix(".svg")
    fig.savefig(
        png_path,
        dpi=PLOT_RESOLUTION_DPI,
        bbox_inches="tight",
        pad_inches=0.02,
    )
    fig.savefig(
        svg_path,
        bbox_inches="tight",
        pad_inches=0.02,
    )
    plt.close(fig)
    print(f"Wrote Raster FiF=1: {png_path}")
    print(f"Wrote Raster FiF=1: {svg_path}")


def save_raster_camera_frame_plot(
    out_base: pathlib.Path,
    stats: list[CameraFrameRasterStats],
    camera_idx: int,
    frame_idx: int,
    frame_label: str,
) -> None:
    fif_stats = [case for case in stats if case.frames_in_flight == 1]
    if not fif_stats:
        raise FileNotFoundError("no FiF=1 raster stats found for bench_dicuq experiment 5")

    thread_values = sorted({case.threads for case in fif_stats})
    render_modes = ["offline", "in_order"]

    fig, ax = plt.subplots(figsize=PLOT_LINE_FIG_SIZE_IN, constrained_layout=False)

    for render_mode in render_modes:
        mode_stats = sorted(
            [case for case in fif_stats if case.render_mode == render_mode],
            key=lambda case: case.threads,
        )
        baseline = next((case for case in mode_stats if case.threads == 1), None)
        if baseline is None:
            print(f"Skipping {render_mode}: missing 1-thread FiF=1 baseline")
            continue

        xs: list[int] = []
        ys: list[float] = []
        yerr_low: list[float] = []
        yerr_high: list[float] = []

        for case in mode_stats:
            speedup_median, speedup_low, speedup_high = calc_speedup_bounds(
                baseline.median_ms,
                case.median_ms,
                case.min_ms,
                case.max_ms,
            )
            xs.append(case.threads)
            ys.append(speedup_median)
            yerr_low.append(speedup_median - speedup_low)
            yerr_high.append(speedup_high - speedup_median)

        label = "Offline" if render_mode == "offline" else "In-order"
        ax.errorbar(
            xs,
            ys,
            yerr=[yerr_low, yerr_high],
            marker="o",
            linewidth=2.0,
            markersize=5.0,
            capsize=3.0,
            label=label,
        )

    ideal_y = [float(val) for val in thread_values]
    ax.plot(
        thread_values,
        ideal_y,
        linestyle="--",
        color="black",
        linewidth=1.5,
        label="Ideal",
    )

    ax.set_xlabel("Threads", fontsize=PLOT_LINE_AXIS_FONT_SIZE)
    ax.set_ylabel("Speedup [x]", fontsize=PLOT_LINE_AXIS_FONT_SIZE)
    ax.set_title(
        f"Raster, FiF=1, cam {camera_idx}, {frame_label} frame",
        fontsize=PLOT_LINE_TITLE_FONT_SIZE,
        pad=10.0,
    )
    ax.tick_params(labelsize=PLOT_LINE_TICK_FONT_SIZE)
    ax.grid(True, alpha=0.25, linewidth=0.8)
    ax.set_xticks(thread_values, [str(val) for val in thread_values])
    ax.set_xlim(min(thread_values) - 0.2, max(thread_values) + 0.2)
    ax.set_ylim(bottom=0.0)
    ax.legend(fontsize=PLOT_LINE_LEGEND_FONT_SIZE, frameon=True)

    fig.subplots_adjust(
        left=0.19,
        right=0.98,
        bottom=0.18,
        top=0.87,
    )

    png_path = out_base.with_suffix(".png")
    svg_path = out_base.with_suffix(".svg")
    fig.savefig(
        png_path,
        dpi=PLOT_RESOLUTION_DPI,
        bbox_inches="tight",
        pad_inches=0.02,
    )
    fig.savefig(
        svg_path,
        bbox_inches="tight",
        pad_inches=0.02,
    )
    plt.close(fig)
    print(f"Wrote Raster cam {camera_idx} {frame_label}: {png_path}")
    print(f"Wrote Raster cam {camera_idx} {frame_label}: {svg_path}")


def save_raster_camera_runmedian_plot(
    out_base: pathlib.Path,
    stats: list[CameraRunMedianRasterStats],
    camera_idx: int,
) -> None:
    fif_stats = [case for case in stats if case.frames_in_flight == 1]
    if not fif_stats:
        raise FileNotFoundError("no FiF=1 raster run-median stats found for bench_dicuq experiment 5")

    thread_values = sorted({case.threads for case in fif_stats})
    render_modes = ["offline", "in_order"]

    fig, ax = plt.subplots(figsize=PLOT_LINE_FIG_SIZE_IN, constrained_layout=False)

    for render_mode in render_modes:
        mode_stats = sorted(
            [case for case in fif_stats if case.render_mode == render_mode],
            key=lambda case: case.threads,
        )
        baseline = next((case for case in mode_stats if case.threads == 1), None)
        if baseline is None:
            print(f"Skipping {render_mode}: missing 1-thread FiF=1 baseline")
            continue

        xs: list[int] = []
        ys: list[float] = []
        yerr_low: list[float] = []
        yerr_high: list[float] = []

        for case in mode_stats:
            speedup_median, speedup_low, speedup_high = calc_speedup_bounds(
                baseline.median_ms,
                case.median_ms,
                case.min_ms,
                case.max_ms,
            )
            xs.append(case.threads)
            ys.append(speedup_median)
            yerr_low.append(speedup_median - speedup_low)
            yerr_high.append(speedup_high - speedup_median)

        label = "Offline" if render_mode == "offline" else "In-order"
        ax.errorbar(
            xs,
            ys,
            yerr=[yerr_low, yerr_high],
            marker="o",
            linewidth=2.0,
            markersize=5.0,
            capsize=3.0,
            label=label,
        )

    ideal_y = [float(val) for val in thread_values]
    ax.plot(
        thread_values,
        ideal_y,
        linestyle="--",
        color="black",
        linewidth=1.5,
        label="Ideal",
    )

    ax.set_xlabel("Threads", fontsize=PLOT_LINE_AXIS_FONT_SIZE)
    ax.set_ylabel("Speedup [x]", fontsize=PLOT_LINE_AXIS_FONT_SIZE)
    ax.set_title(
        f"Raster, FiF=1, cam {camera_idx}, run median over frames",
        fontsize=PLOT_LINE_TITLE_FONT_SIZE,
        pad=10.0,
    )
    ax.tick_params(labelsize=PLOT_LINE_TICK_FONT_SIZE)
    ax.grid(True, alpha=0.25, linewidth=0.8)
    ax.set_xticks(thread_values, [str(val) for val in thread_values])
    ax.set_xlim(min(thread_values) - 0.2, max(thread_values) + 0.2)
    ax.set_ylim(bottom=0.0)
    ax.legend(fontsize=PLOT_LINE_LEGEND_FONT_SIZE, frameon=True)

    fig.subplots_adjust(
        left=0.19,
        right=0.98,
        bottom=0.18,
        top=0.87,
    )

    png_path = out_base.with_suffix(".png")
    svg_path = out_base.with_suffix(".svg")
    fig.savefig(
        png_path,
        dpi=PLOT_RESOLUTION_DPI,
        bbox_inches="tight",
        pad_inches=0.02,
    )
    fig.savefig(
        svg_path,
        bbox_inches="tight",
        pad_inches=0.02,
    )
    plt.close(fig)
    print(f"Wrote Raster cam {camera_idx} run-median: {png_path}")
    print(f"Wrote Raster cam {camera_idx} run-median: {svg_path}")


def save_plot(
    out_base: pathlib.Path,
    render_mode: str,
    metric_name: str,
    stats: list[CaseStats],
) -> None:
    lookup = build_lookup(stats)
    fif_values = sorted({case.frames_in_flight for case in stats if case.render_mode == render_mode})
    thread_values = sorted({case.threads for case in stats if case.render_mode == render_mode})

    fig, ax = plt.subplots(figsize=PLOT_LINE_FIG_SIZE_IN, constrained_layout=False)

    for fif in fif_values:
        baseline = lookup.get((render_mode, fif, 1))
        if baseline is None:
            print(f"Skipping FiF={fif} for {render_mode}: missing 1-thread baseline")
            continue

        xs: list[int] = []
        ys: list[float] = []
        yerr_low: list[float] = []
        yerr_high: list[float] = []

        for threads in thread_values:
            case = lookup.get((render_mode, fif, threads))
            if case is None:
                continue

            if metric_name == "raster":
                median_ms = case.raster_median_ms
                min_ms = case.raster_min_ms
                max_ms = case.raster_max_ms
                baseline_median_ms = baseline.raster_median_ms
            elif metric_name == "e2e":
                median_ms = case.e2e_median_ms
                min_ms = case.e2e_min_ms
                max_ms = case.e2e_max_ms
                baseline_median_ms = baseline.e2e_median_ms
            else:
                raise ValueError(f"unsupported metric {metric_name}")

            speedup_median, speedup_low, speedup_high = calc_speedup_bounds(
                baseline_median_ms,
                median_ms,
                min_ms,
                max_ms,
            )

            xs.append(threads)
            ys.append(speedup_median)
            yerr_low.append(speedup_median - speedup_low)
            yerr_high.append(speedup_high - speedup_median)

        if not xs:
            continue

        ax.errorbar(
            xs,
            ys,
            yerr=[yerr_low, yerr_high],
            marker="o",
            linewidth=2.0,
            markersize=5.0,
            capsize=3.0,
            label=f"FiF={fif}",
        )

    if thread_values:
        ideal_x = thread_values
        ideal_y = [float(val) for val in thread_values]
        ax.plot(
            ideal_x,
            ideal_y,
            linestyle="--",
            color="black",
            linewidth=1.5,
            label="Ideal",
        )

    mode_label = "Offline" if render_mode == "offline" else "In-order"
    metric_label = "Raster" if metric_name == "raster" else "End-to-end"

    ax.set_xlabel("Threads", fontsize=PLOT_LINE_AXIS_FONT_SIZE)
    ax.set_ylabel("Speedup [x]", fontsize=PLOT_LINE_AXIS_FONT_SIZE)
    ax.set_title(f"{mode_label}", fontsize=PLOT_LINE_TITLE_FONT_SIZE, pad=10.0)
    ax.tick_params(labelsize=PLOT_LINE_TICK_FONT_SIZE)
    ax.grid(True, alpha=0.25, linewidth=0.8)
    if thread_values:
        ax.set_xticks(thread_values, [str(val) for val in thread_values])
        ax.set_xlim(min(thread_values) - 0.2, max(thread_values) + 0.2)
    ax.set_ylim(bottom=0.0)
    ax.legend(fontsize=PLOT_LINE_LEGEND_FONT_SIZE, frameon=True)

    fig.subplots_adjust(
        left=0.19,
        right=0.98,
        bottom=0.18,
        top=0.87,
    )

    png_path = out_base.with_suffix(".png")
    svg_path = out_base.with_suffix(".svg")
    fig.savefig(
        png_path,
        dpi=PLOT_RESOLUTION_DPI,
        bbox_inches="tight",
        pad_inches=0.02,
    )
    fig.savefig(
        svg_path,
        bbox_inches="tight",
        pad_inches=0.02,
    )
    plt.close(fig)
    print(f"Wrote {metric_label} {mode_label}: {png_path}")
    print(f"Wrote {metric_label} {mode_label}: {svg_path}")


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    all_stats = collect_case_stats()
    raw_raster_stats = collect_last_frame_raster_stats()
    first_frame, middle_frame, last_frame = get_frame_triplet()

    case_name = all_stats[0].case_name
    max_threads = max(case.threads for case in all_stats)
    print(f"Using case: {case_name}")
    print(f"Detected max threads: {max_threads}")
    print(
        f"Raster frame selections: first={first_frame}, middle={middle_frame}, last={last_frame}",
    )

    raster_specs = [
        ("a", 0, first_frame, "first"),
        ("b", 0, middle_frame, "middle"),
        ("c", 0, last_frame, "last"),
        ("d", 1, first_frame, "first"),
        ("e", 1, middle_frame, "middle"),
        ("f", 1, last_frame, "last"),
    ]
    for suffix, camera_idx, frame_idx, frame_label in raster_specs:
        camera_frame_stats = collect_camera_frame_raster_stats(camera_idx, frame_idx)
        save_raster_camera_frame_plot(
            OUT_DIR / f"fig_bench4_raster_{suffix}",
            camera_frame_stats,
            camera_idx,
            frame_idx,
            frame_label,
        )

    runmedian_specs = [
        ("g", 0),
        ("h", 1),
    ]
    for suffix, camera_idx in runmedian_specs:
        camera_runmedian_stats = collect_camera_runmedian_raster_stats(camera_idx)
        save_raster_camera_runmedian_plot(
            OUT_DIR / f"fig_bench4_raster_{suffix}",
            camera_runmedian_stats,
            camera_idx,
        )

    write_amdahl_csv(
        OUT_DIR / "bench4_raster_amdahl.csv",
        build_raster_amdahl_rows(raw_raster_stats, case_name),
    )
    write_amdahl_csv(
        OUT_DIR / "bench4_e2e_amdahl.csv",
        build_e2e_amdahl_rows(all_stats, case_name),
    )

    render_pairs = [("offline", "a"), ("in_order", "b")]
    for render_mode, suffix in render_pairs:
        save_plot(
            OUT_DIR / f"fig_bench4_e2e_{suffix}",
            render_mode,
            "e2e",
            all_stats,
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
