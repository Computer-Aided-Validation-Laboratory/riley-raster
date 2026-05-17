#!/usr/bin/env python3
from __future__ import annotations

import csv
import pathlib
import re
import statistics
from dataclasses import dataclass

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from paper_bench_common import PAPER_DIR, latest_run_dir_with_paths, repo_root
from paper_const import (
    PLOT_LINE_AXIS_FONT_SIZE,
    PLOT_LINE_FIG_SIZE_IN,
    PLOT_LINE_LEGEND_FONT_SIZE,
    PLOT_LINE_SECONDARY_AXIS_FONT_SIZE,
    PLOT_LINE_TICK_FONT_SIZE,
    PLOT_LINE_TITLE_FONT_SIZE,
    PLOT_RESOLUTION_DPI,
)


BENCH_NAME = "bench_dicuq"
EXPERIMENT_DIR = "experiment_2_geom_threads_1"
OUT_DIR = repo_root() / "verif"

RASTER_FIG_STEM = "fig_bench4_a_raster"
E2E_FIG_STEM = "fig_bench4_b_e2e"
FIGS_TEX_NAME = "bench4_figs.tex"
AMDAHL_TABLE_NAME = "bench4_amdahl_table.csv"

THREADING_FIG_CAPTION = (
    "Thread-scaling behaviour for the DIC UQ benchmark with offline rendering, "
    "one frame in flight, and one geometry thread. Panel (a) shows raster-loop "
    "throughput and speedup for the in-memory benchmark configuration. Panel (b) "
    "shows end-to-end throughput and speedup for the in-memory and disk-saving "
    "benchmark configurations. The right-hand axis reports speedup relative to "
    "the one-thread baseline for each series, and the dashed black line denotes "
    "ideal linear scaling."
)

CASE_DIR_RE = re.compile(
    r"^bench_dicuq_io-(?P<io>[a-z0-9_]+)"
    r"_threads-(?P<threads>\d+)"
    r"_geom-(?P<geom>\d+)"
    r"_raster-(?P<raster>\d+)"
    r"_frames-(?P<frames>\d+)"
    r"_render-(?P<render>offline|in_order)"
    r"_save-(?P<save>[a-z_]+)$",
)

SUBFIGURE_WIDTH = "0.48\\textwidth"


@dataclass(slots=True)
class CaseStats:
    case_dir: pathlib.Path
    io_label: str
    io_family: str
    threads: int
    geom_threads: int
    raster_threads: int
    frames_in_flight: int
    render_mode: str
    save_strategy: str
    case_name: str
    e2e_median_ms: float
    e2e_min_ms: float
    e2e_max_ms: float
    raster_median_ms: float
    raster_min_ms: float
    raster_max_ms: float
    raster_throughput_median_mpx_s: float
    raster_throughput_min_mpx_s: float
    raster_throughput_max_mpx_s: float


@dataclass(slots=True)
class ThroughputSeriesPoint:
    threads: int
    time_median_ms: float
    time_min_ms: float
    time_max_ms: float
    throughput_median: float
    throughput_min: float
    throughput_max: float


def load_csv_rows(csv_path: pathlib.Path) -> list[dict[str, str]]:
    with csv_path.open(newline="") as csv_file:
        return list(csv.DictReader(csv_file))


def find_camera_all_row(csv_path: pathlib.Path) -> dict[str, str]:
    rows = load_csv_rows(csv_path)
    camera_all = [row for row in rows if row["Camera"] == "all"]
    if len(camera_all) != 1:
        raise ValueError(f"expected exactly one Camera=all row in {csv_path}, got {len(camera_all)}")
    return camera_all[0]


def parse_case_stats(case_dir: pathlib.Path) -> CaseStats | None:
    match = CASE_DIR_RE.match(case_dir.name)
    if match is None:
        return None

    median_row = find_camera_all_row(case_dir / "bench_e2e_overruns_median.csv")
    min_row = find_camera_all_row(case_dir / "bench_e2e_overruns_min.csv")
    max_row = find_camera_all_row(case_dir / "bench_e2e_overruns_max.csv")

    io_label = match.group("io")
    io_family = "async_multi" if io_label.startswith("async_multi") else io_label

    return CaseStats(
        case_dir=case_dir,
        io_label=io_label,
        io_family=io_family,
        threads=int(match.group("threads")),
        geom_threads=int(match.group("geom")),
        raster_threads=int(match.group("raster")),
        frames_in_flight=int(match.group("frames")),
        render_mode=match.group("render"),
        save_strategy=match.group("save"),
        case_name=median_row["Case"],
        e2e_median_ms=float(median_row["E2E_ms"]),
        e2e_min_ms=float(min_row["E2E_ms"]),
        e2e_max_ms=float(max_row["E2E_ms"]),
        raster_median_ms=float(median_row["Raster_ms"]),
        raster_min_ms=float(min_row["Raster_ms"]),
        raster_max_ms=float(max_row["Raster_ms"]),
        raster_throughput_median_mpx_s=float(median_row["Throughput_MPx/s"]),
        raster_throughput_min_mpx_s=float(min_row["Throughput_MPx/s"]),
        raster_throughput_max_mpx_s=float(max_row["Throughput_MPx/s"]),
    )


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
        raise FileNotFoundError(f"no experiment-2 case directories found in {experiment_root}")

    return stats


def estimate_total_mpx(stats: list[CaseStats]) -> float:
    estimates = [
        case.raster_throughput_median_mpx_s * case.raster_median_ms / 1000.0
        for case in stats
        if case.io_family == "async_multi"
        and case.render_mode == "offline"
        and case.frames_in_flight == 1
        and case.geom_threads == 1
    ]
    if not estimates:
        raise ValueError("unable to estimate total MPx for bench4 experiment 2")
    return statistics.median(estimates)


def build_raster_memory_series(stats: list[CaseStats]) -> list[ThroughputSeriesPoint]:
    points = sorted(
        [
            case
            for case in stats
            if case.io_family == "async_multi"
            and case.render_mode == "offline"
            and case.frames_in_flight == 1
            and case.geom_threads == 1
            and case.save_strategy == "memory"
        ],
        key=lambda case: case.threads,
    )
    if not points:
        raise ValueError("no raster memory points found for experiment 2")

    return [
        ThroughputSeriesPoint(
            threads=case.threads,
            time_median_ms=case.raster_median_ms,
            time_min_ms=case.raster_min_ms,
            time_max_ms=case.raster_max_ms,
            throughput_median=case.raster_throughput_median_mpx_s,
            throughput_min=case.raster_throughput_min_mpx_s,
            throughput_max=case.raster_throughput_max_mpx_s,
        )
        for case in points
    ]


def build_e2e_series(
    stats: list[CaseStats],
    save_strategy: str,
    total_mpx: float,
) -> list[ThroughputSeriesPoint]:
    points = sorted(
        [
            case
            for case in stats
            if case.io_family == "async_multi"
            and case.render_mode == "offline"
            and case.frames_in_flight == 1
            and case.geom_threads == 1
            and case.save_strategy == save_strategy
        ],
        key=lambda case: case.threads,
    )
    if not points:
        raise ValueError(f"no e2e {save_strategy} points found for experiment 2")

    series: list[ThroughputSeriesPoint] = []
    for case in points:
        throughput_median = total_mpx * 1000.0 / case.e2e_median_ms
        throughput_min = total_mpx * 1000.0 / case.e2e_max_ms
        throughput_max = total_mpx * 1000.0 / case.e2e_min_ms
        series.append(
            ThroughputSeriesPoint(
                threads=case.threads,
                time_median_ms=case.e2e_median_ms,
                time_min_ms=case.e2e_min_ms,
                time_max_ms=case.e2e_max_ms,
                throughput_median=throughput_median,
                throughput_min=throughput_min,
                throughput_max=throughput_max,
            )
        )
    return series


def calc_speedup_point(
    baseline_throughput: float,
    point: ThroughputSeriesPoint,
) -> tuple[float, float, float]:
    speedup_median = point.throughput_median / baseline_throughput
    speedup_min = point.throughput_min / baseline_throughput
    speedup_max = point.throughput_max / baseline_throughput
    return speedup_median, speedup_min, speedup_max


def fit_amdahl_serial_fraction(
    threads: list[int],
    speedups: list[float],
) -> float:
    grid = np.linspace(0.0, 1.0, 200_001)
    n = np.asarray(threads, dtype=float)
    s_obs = np.asarray(speedups, dtype=float)
    preds = 1.0 / (grid[:, None] + (1.0 - grid[:, None]) / n[None, :])
    err = np.sum((preds - s_obs[None, :]) ** 2, axis=1)
    return float(grid[int(np.argmin(err))])


def point_serial_fraction(threads: int, speedup: float) -> float | None:
    if threads <= 1 or speedup <= 0.0:
        return None
    return (1.0 / speedup - 1.0 / threads) / (1.0 - 1.0 / threads)


def save_dual_axis_plot(
    stem: str,
    fig: plt.Figure,
) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    PAPER_DIR.mkdir(parents=True, exist_ok=True)
    for base_dir in (OUT_DIR, PAPER_DIR):
        fig.savefig(base_dir / f"{stem}.png", dpi=PLOT_RESOLUTION_DPI)
        fig.savefig(base_dir / f"{stem}.svg")
    plt.close(fig)
    print(f"Wrote {OUT_DIR / f'{stem}.png'}")
    print(f"Wrote {OUT_DIR / f'{stem}.svg'}")
    print(f"Wrote {PAPER_DIR / f'{stem}.png'}")
    print(f"Wrote {PAPER_DIR / f'{stem}.svg'}")


def style_axes(ax_left: plt.Axes, ax_right: plt.Axes, title: str, y_left_label: str) -> None:
    if title:
        ax_left.set_title(title, fontsize=PLOT_LINE_TITLE_FONT_SIZE)
    ax_left.set_xlabel("Total Threads", fontsize=PLOT_LINE_AXIS_FONT_SIZE)
    ax_left.set_ylabel(y_left_label, fontsize=PLOT_LINE_AXIS_FONT_SIZE)
    ax_right.set_ylabel(
        "Speedup vs. 1 thread",
        fontsize=PLOT_LINE_SECONDARY_AXIS_FONT_SIZE,
    )
    ax_left.tick_params(labelsize=PLOT_LINE_TICK_FONT_SIZE)
    ax_right.tick_params(labelsize=PLOT_LINE_TICK_FONT_SIZE)
    ax_left.grid(True, linestyle=":", linewidth=0.8, alpha=0.7)


def sync_speedup_axis(ax_left: plt.Axes, ax_right: plt.Axes, baseline_throughput: float) -> None:
    left_lo, left_hi = ax_left.get_ylim()
    ax_right.set_ylim(left_lo / baseline_throughput, left_hi / baseline_throughput)


def plot_raster_figure(series: list[ThroughputSeriesPoint]) -> None:
    baseline = next(point for point in series if point.threads == 1)
    fig, ax_left = plt.subplots(figsize=PLOT_LINE_FIG_SIZE_IN)

    x_vals = [point.threads for point in series]
    throughput = [point.throughput_median for point in series]
    throughput_err_low = [point.throughput_median - point.throughput_min for point in series]
    throughput_err_high = [point.throughput_max - point.throughput_median for point in series]

    baseline_throughput = baseline.throughput_median
    ax_right = ax_left.twinx()

    ax_left.errorbar(
        x_vals,
        throughput,
        yerr=[throughput_err_low, throughput_err_high],
        fmt="o-",
        linewidth=1.8,
        markersize=5,
        capsize=3,
        label="Throughput",
        color="tab:blue",
    )
    ax_left.plot(
        x_vals,
        [baseline_throughput * float(x) for x in x_vals],
        "k--",
        linewidth=1.2,
        label="Ideal",
    )

    style_axes(
        ax_left,
        ax_right,
        "",
        "Raster Throughput\n[MPx/s]",
    )
    ax_left.set_xticks(x_vals, [str(x) for x in x_vals])
    sync_speedup_axis(ax_left, ax_right, baseline_throughput)

    handles_left, labels_left = ax_left.get_legend_handles_labels()
    handles_right, labels_right = ax_right.get_legend_handles_labels()
    ax_left.legend(
        handles_left + handles_right,
        labels_left + labels_right,
        fontsize=PLOT_LINE_LEGEND_FONT_SIZE,
        loc="upper left",
        ncol=1,
    )

    fig.tight_layout()
    save_dual_axis_plot(RASTER_FIG_STEM, fig)


def plot_e2e_figure(
    memory_series: list[ThroughputSeriesPoint],
    disk_series: list[ThroughputSeriesPoint],
) -> None:
    memory_baseline = next(point for point in memory_series if point.threads == 1)

    fig, ax_left = plt.subplots(figsize=PLOT_LINE_FIG_SIZE_IN)

    mem_x = [point.threads for point in memory_series]
    mem_thr = [point.throughput_median for point in memory_series]
    mem_err_low = [point.throughput_median - point.throughput_min for point in memory_series]
    mem_err_high = [point.throughput_max - point.throughput_median for point in memory_series]

    disk_x = [point.threads for point in disk_series]
    disk_thr = [point.throughput_median for point in disk_series]
    disk_err_low = [point.throughput_median - point.throughput_min for point in disk_series]
    disk_err_high = [point.throughput_max - point.throughput_median for point in disk_series]

    baseline_throughput = memory_baseline.throughput_median
    ax_right = ax_left.twinx()

    ax_left.errorbar(
        mem_x,
        mem_thr,
        yerr=[mem_err_low, mem_err_high],
        fmt="o-",
        linewidth=1.8,
        markersize=5,
        capsize=3,
        label="Mem.",
        color="tab:blue",
    )
    ax_left.errorbar(
        disk_x,
        disk_thr,
        yerr=[disk_err_low, disk_err_high],
        fmt="o-",
        linewidth=1.8,
        markersize=5,
        capsize=3,
        label="Disk",
        color="tab:orange",
    )
    ideal_x = sorted(set(mem_x + disk_x))
    ax_left.plot(
        ideal_x,
        [baseline_throughput * float(x) for x in ideal_x],
        "k--",
        linewidth=1.2,
        label="Ideal",
    )

    style_axes(
        ax_left,
        ax_right,
        "",
        "End-to-End Throughput\n[MPx/s]",
    )
    ax_left.set_xticks(ideal_x, [str(x) for x in ideal_x])
    sync_speedup_axis(ax_left, ax_right, baseline_throughput)

    handles_left, labels_left = ax_left.get_legend_handles_labels()
    handles_right, labels_right = ax_right.get_legend_handles_labels()
    ax_left.legend(
        handles_left + handles_right,
        labels_left + labels_right,
        fontsize=PLOT_LINE_LEGEND_FONT_SIZE,
        loc="upper left",
        ncol=1,
    )

    fig.tight_layout()
    save_dual_axis_plot(E2E_FIG_STEM, fig)


def subfigure_block(file_name: str, width_str: str, label: str) -> str:
    return (
        f"\\begin{{subfigure}}[c]{{{width_str}}}\n"
        "\\centering\n"
        f"\\includegraphics[width=\\linewidth]{{{file_name}}}\n"
        "\\caption{}\n"
        f"\\label{{{label}}}\n"
        "\\end{subfigure}"
    )


def build_figs_tex() -> str:
    return (
        "\\begin{figure}[htbp]\n"
        "\\centering\n"
        + subfigure_block(
            f"{RASTER_FIG_STEM}.png",
            SUBFIGURE_WIDTH,
            "fig:bench4_raster_scaling",
        )
        + "\n\\hfill\n"
        + subfigure_block(
            f"{E2E_FIG_STEM}.png",
            SUBFIGURE_WIDTH,
            "fig:bench4_e2e_scaling",
        )
        + "\n"
        + f"\\caption{{{THREADING_FIG_CAPTION}}}\n"
        + "\\label{fig:bench4_threading}\n"
        + "\\end{figure}\n"
    )


def write_figs_tex(figs_tex: str) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    PAPER_DIR.mkdir(parents=True, exist_ok=True)
    for out_path in (OUT_DIR / FIGS_TEX_NAME, PAPER_DIR / FIGS_TEX_NAME):
        out_path.write_text(figs_tex)
        print(f"Wrote {out_path}")


def write_amdahl_table(
    raster_series: list[ThroughputSeriesPoint],
    e2e_memory_series: list[ThroughputSeriesPoint],
    e2e_disk_series: list[ThroughputSeriesPoint],
) -> None:
    out_path = OUT_DIR / AMDAHL_TABLE_NAME
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    rows: list[dict[str, str]] = []
    for series_name, series in (
        ("raster_loop", raster_series),
        ("e2e_memory", e2e_memory_series),
        ("e2e_disk", e2e_disk_series),
    ):
        baseline = next(point for point in series if point.threads == 1)
        threads = [point.threads for point in series]
        speedups = [point.throughput_median / baseline.throughput_median for point in series]
        fitted_fs = fit_amdahl_serial_fraction(threads, speedups)
        fitted_fp = 1.0 - fitted_fs
        asym_speedup = (1.0 / fitted_fs) if fitted_fs > 0.0 else float("inf")

        for point in series:
            speedup_median, speedup_min, speedup_max = calc_speedup_point(
                baseline.throughput_median,
                point,
            )
            predicted_speedup = 1.0 / (
                fitted_fs + fitted_fp / float(point.threads)
            )
            predicted_throughput = baseline.throughput_median * predicted_speedup
            point_fs = point_serial_fraction(point.threads, speedup_median)

            rows.append(
                {
                    "Series": series_name,
                    "Threads": str(point.threads),
                    "TimeMedian_ms": f"{point.time_median_ms:.6f}",
                    "TimeMin_ms": f"{point.time_min_ms:.6f}",
                    "TimeMax_ms": f"{point.time_max_ms:.6f}",
                    "ThroughputMedian_MPx_s": f"{point.throughput_median:.6f}",
                    "ThroughputMin_MPx_s": f"{point.throughput_min:.6f}",
                    "ThroughputMax_MPx_s": f"{point.throughput_max:.6f}",
                    "SpeedupMedian": f"{speedup_median:.6f}",
                    "SpeedupMin": f"{speedup_min:.6f}",
                    "SpeedupMax": f"{speedup_max:.6f}",
                    "PointSerialFraction": "" if point_fs is None else f"{point_fs:.6f}",
                    "FittedSerialFraction": f"{fitted_fs:.6f}",
                    "FittedParallelFraction": f"{fitted_fp:.6f}",
                    "AsymptoticSpeedup": "inf" if not np.isfinite(asym_speedup) else f"{asym_speedup:.6f}",
                    "PredictedSpeedup": f"{predicted_speedup:.6f}",
                    "PredictedThroughput_MPx_s": f"{predicted_throughput:.6f}",
                }
            )

    with out_path.open("w", newline="") as csv_file:
        fieldnames = list(rows[0].keys())
        writer = csv.DictWriter(csv_file, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {out_path}")


def main() -> int:
    stats = collect_case_stats()
    raster_series = build_raster_memory_series(stats)
    total_mpx = estimate_total_mpx(stats)
    e2e_memory_series = build_e2e_series(stats, "memory", total_mpx)
    e2e_disk_series = build_e2e_series(stats, "disk", total_mpx)

    plot_raster_figure(raster_series)
    plot_e2e_figure(e2e_memory_series, e2e_disk_series)
    write_figs_tex(build_figs_tex())
    write_amdahl_table(raster_series, e2e_memory_series, e2e_disk_series)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
