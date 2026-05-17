#!/usr/bin/env python3
from __future__ import annotations

import csv
import pathlib
import re
from dataclasses import dataclass

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

from paper_bench_common import latest_run_dir_with_paths
from paper_const import (
    PLOT_LINE_AXIS_FONT_SIZE,
    PLOT_LINE_FIG_SIZE_IN,
    PLOT_LINE_LEGEND_FONT_SIZE,
    PLOT_LINE_TICK_FONT_SIZE,
    PLOT_LINE_TITLE_FONT_SIZE,
    PLOT_RESOLUTION_DPI,
    repo_root,
)


BENCH_NAME = "bench_dicuq"
EXPERIMENT_DIR = "experiment_7_geom_sweep"
OUT_DIR = repo_root() / "verif"

CASE_DIR_RE = re.compile(
    r"^bench_dicuq_io-(?P<io>[a-z0-9_]+)"
    r"_threads-(?P<threads>\d+)"
    r"_geom-(?P<geom>\d+)"
    r"_raster-(?P<raster>\d+)"
    r"_frames-(?P<frames>\d+)"
    r"_render-(?P<render>offline|in_order)"
    r"_save-(?P<save>[a-z_]+)$",
)


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
    case_name: str
    e2e_median_ms: float
    e2e_min_ms: float
    e2e_max_ms: float
    geom_median_ms: float
    geom_min_ms: float
    geom_max_ms: float
    raster_median_ms: float
    raster_min_ms: float
    raster_max_ms: float


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
        case_name=median_row["Case"],
        e2e_median_ms=float(median_row["E2E_ms"]),
        e2e_min_ms=float(min_row["E2E_ms"]),
        e2e_max_ms=float(max_row["E2E_ms"]),
        geom_median_ms=float(median_row["Geom_ms"]),
        geom_min_ms=float(min_row["Geom_ms"]),
        geom_max_ms=float(max_row["Geom_ms"]),
        raster_median_ms=float(median_row["Raster_ms"]),
        raster_min_ms=float(min_row["Raster_ms"]),
        raster_max_ms=float(max_row["Raster_ms"]),
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
        raise FileNotFoundError(f"no experiment-7 case directories found in {experiment_root}")

    case_names = sorted({case.case_name for case in stats})
    if len(case_names) != 1:
        raise ValueError(f"expected one benchmark case in experiment 7, found {case_names}")

    return stats


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


def _style_axes(ax: plt.Axes, title: str, x_label: str) -> None:
    ax.set_title(title, fontsize=PLOT_LINE_TITLE_FONT_SIZE)
    ax.set_xlabel(x_label, fontsize=PLOT_LINE_AXIS_FONT_SIZE)
    ax.set_ylabel("Speedup vs. 1 thread", fontsize=PLOT_LINE_AXIS_FONT_SIZE)
    ax.tick_params(labelsize=PLOT_LINE_TICK_FONT_SIZE)
    ax.grid(True, linestyle=":", linewidth=0.8, alpha=0.7)


def _save_plot(fig: plt.Figure, stem: str) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    png_path = OUT_DIR / f"{stem}.png"
    svg_path = OUT_DIR / f"{stem}.svg"
    fig.tight_layout()
    fig.savefig(png_path, dpi=PLOT_RESOLUTION_DPI)
    fig.savefig(svg_path)
    plt.close(fig)
    print(f"Wrote {png_path}")
    print(f"Wrote {svg_path}")


def _add_ideal_line(ax: plt.Axes, x_values: list[int]) -> None:
    x_sorted = sorted(set(x_values))
    if not x_sorted:
        return
    ax.plot(
        x_sorted,
        [float(x) for x in x_sorted],
        "k--",
        linewidth=1.2,
        label="Ideal",
    )


def plot_raster_scaling(
    stats: list[CaseStats],
    render_mode: str,
    stem: str,
) -> None:
    points = sorted(
        [
            case
            for case in stats
            if case.io_family == "async_multi"
            and case.render_mode == render_mode
            and case.geom_threads == 1
            and case.frames_in_flight == 1
        ],
        key=lambda case: case.threads,
    )
    if not points:
        raise ValueError(f"no raster points found for render={render_mode}")

    baseline = next((case for case in points if case.threads == 1), None)
    if baseline is None:
        raise ValueError(f"no thread-1 raster baseline for render={render_mode}")

    x_vals: list[int] = []
    y_vals: list[float] = []
    yerr_low: list[float] = []
    yerr_high: list[float] = []
    for case in points:
        med, low, high = calc_speedup_bounds(
            baseline.raster_median_ms,
            case.raster_median_ms,
            case.raster_min_ms,
            case.raster_max_ms,
        )
        x_vals.append(case.threads)
        y_vals.append(med)
        yerr_low.append(med - low)
        yerr_high.append(high - med)

    fig, ax = plt.subplots(figsize=PLOT_LINE_FIG_SIZE_IN)
    _add_ideal_line(ax, x_vals)
    ax.errorbar(
        x_vals,
        y_vals,
        yerr=[yerr_low, yerr_high],
        fmt="o-",
        linewidth=1.8,
        markersize=5,
        capsize=3,
        label="FiF 1",
    )
    _style_axes(
        ax,
        f"Raster Scaling\ngeom threads = 1, FiF = 1\n{render_mode}",
        "Total Threads",
    )
    ax.legend(fontsize=PLOT_LINE_LEGEND_FONT_SIZE)
    _save_plot(fig, stem)


def plot_e2e_scaling(
    stats: list[CaseStats],
    render_mode: str,
    stem: str,
) -> None:
    async_cases = [
        case
        for case in stats
        if case.io_family == "async_multi"
        and case.render_mode == render_mode
        and case.geom_threads == 1
    ]
    fif_values = sorted({case.frames_in_flight for case in async_cases})
    if not fif_values:
        raise ValueError(f"no e2e points found for render={render_mode}")

    fig, ax = plt.subplots(figsize=PLOT_LINE_FIG_SIZE_IN)
    all_threads: list[int] = []

    for fif in fif_values:
        line_cases = sorted(
            [case for case in async_cases if case.frames_in_flight == fif],
            key=lambda case: case.threads,
        )
        baseline = next((case for case in line_cases if case.threads == 1), None)
        if baseline is None:
            print(f"Skipping e2e render={render_mode} FiF={fif}: no thread-1 baseline")
            continue

        x_vals: list[int] = []
        y_vals: list[float] = []
        yerr_low: list[float] = []
        yerr_high: list[float] = []
        for case in line_cases:
            med, low, high = calc_speedup_bounds(
                baseline.e2e_median_ms,
                case.e2e_median_ms,
                case.e2e_min_ms,
                case.e2e_max_ms,
            )
            x_vals.append(case.threads)
            y_vals.append(med)
            yerr_low.append(med - low)
            yerr_high.append(high - med)
        if not x_vals:
            continue
        all_threads.extend(x_vals)
        ax.errorbar(
            x_vals,
            y_vals,
            yerr=[yerr_low, yerr_high],
            fmt="o-",
            linewidth=1.8,
            markersize=5,
            capsize=3,
            label=f"FiF {fif}",
        )

    _add_ideal_line(ax, all_threads)
    _style_axes(
        ax,
        f"End-to-End Scaling\ngeom threads = 1\n{render_mode}",
        "Total Threads",
    )
    ax.legend(fontsize=PLOT_LINE_LEGEND_FONT_SIZE)
    _save_plot(fig, stem)


def plot_e2e_scaling_fif1_combined(
    stats: list[CaseStats],
    stem: str,
) -> None:
    async_cases = [
        case
        for case in stats
        if case.io_family == "async_multi"
        and case.geom_threads == 1
        and case.frames_in_flight == 1
    ]
    if not async_cases:
        raise ValueError("no FiF=1, geom=1 async_multi cases found for combined e2e plot")

    fig, ax = plt.subplots(figsize=PLOT_LINE_FIG_SIZE_IN)
    all_threads: list[int] = []

    for render_mode in ("offline", "in_order"):
        line_cases = sorted(
            [case for case in async_cases if case.render_mode == render_mode],
            key=lambda case: case.threads,
        )
        baseline = next((case for case in line_cases if case.threads == 1), None)
        if baseline is None:
            print(f"Skipping combined e2e render={render_mode}: no thread-1 baseline")
            continue

        x_vals: list[int] = []
        y_vals: list[float] = []
        yerr_low: list[float] = []
        yerr_high: list[float] = []
        for case in line_cases:
            med, low, high = calc_speedup_bounds(
                baseline.e2e_median_ms,
                case.e2e_median_ms,
                case.e2e_min_ms,
                case.e2e_max_ms,
            )
            x_vals.append(case.threads)
            y_vals.append(med)
            yerr_low.append(med - low)
            yerr_high.append(high - med)
        if not x_vals:
            continue
        all_threads.extend(x_vals)
        ax.errorbar(
            x_vals,
            y_vals,
            yerr=[yerr_low, yerr_high],
            fmt="o-",
            linewidth=1.8,
            markersize=5,
            capsize=3,
            label=render_mode,
        )

    _add_ideal_line(ax, all_threads)
    _style_axes(
        ax,
        "End-to-End Scaling\ngeom threads = 1, FiF = 1\noffline vs. in_order",
        "Total Threads",
    )
    ax.legend(fontsize=PLOT_LINE_LEGEND_FONT_SIZE)
    _save_plot(fig, stem)


def plot_geom_scaling(
    stats: list[CaseStats],
    render_mode: str,
    raster_threads: int,
    stem: str,
) -> None:
    async_cases = [
        case
        for case in stats
        if case.io_family == "async_multi"
        and case.render_mode == render_mode
        and case.raster_threads == raster_threads
    ]
    fif_values = sorted({case.frames_in_flight for case in async_cases})
    if not fif_values:
        raise ValueError(
            f"no geometry points found for render={render_mode}, raster_threads={raster_threads}"
        )

    fig, ax = plt.subplots(figsize=PLOT_LINE_FIG_SIZE_IN)
    all_geom_threads: list[int] = []
    sparse_only = True

    for fif in fif_values:
        line_cases = sorted(
            [case for case in async_cases if case.frames_in_flight == fif],
            key=lambda case: case.geom_threads,
        )
        baseline = next((case for case in line_cases if case.geom_threads == 1), None)
        if baseline is None:
            print(
                f"Skipping geom render={render_mode} raster={raster_threads} "
                f"FiF={fif}: no geom-thread-1 baseline"
            )
            continue

        x_vals: list[int] = []
        y_vals: list[float] = []
        yerr_low: list[float] = []
        yerr_high: list[float] = []
        for case in line_cases:
            med, low, high = calc_speedup_bounds(
                baseline.geom_median_ms,
                case.geom_median_ms,
                case.geom_min_ms,
                case.geom_max_ms,
            )
            x_vals.append(case.geom_threads)
            y_vals.append(med)
            yerr_low.append(med - low)
            yerr_high.append(high - med)

        if len(x_vals) > 1:
            sparse_only = False
        if not x_vals:
            continue
        all_geom_threads.extend(x_vals)
        ax.errorbar(
            x_vals,
            y_vals,
            yerr=[yerr_low, yerr_high],
            fmt="o-",
            linewidth=1.8,
            markersize=5,
            capsize=3,
            label=f"FiF {fif}",
        )

    _add_ideal_line(ax, all_geom_threads)
    title = f"Geometry Scaling\nraster threads = {raster_threads}\n{render_mode}"
    if sparse_only:
        title += "\n(only geom = 1 available)"
        print(
            f"Warning: geometry scaling for render={render_mode}, raster_threads={raster_threads} "
            "has only single-point lines in this experiment-7 run."
        )
    _style_axes(ax, title, "Geometry Threads")
    ax.legend(fontsize=PLOT_LINE_LEGEND_FONT_SIZE)
    _save_plot(fig, stem)


def main() -> int:
    stats = collect_case_stats()
    max_raster_threads = max(
        case.raster_threads
        for case in stats
        if case.io_family == "async_multi"
    )

    plot_raster_scaling(stats, "offline", "fig_bench4_raster_a")
    plot_raster_scaling(stats, "in_order", "fig_bench4_raster_b")

    plot_e2e_scaling(stats, "offline", "fig_bench4_e2e_a")
    plot_e2e_scaling(stats, "in_order", "fig_bench4_e2e_b")
    plot_e2e_scaling_fif1_combined(stats, "fig_bench4_e2e_c")

    plot_geom_scaling(stats, "offline", max_raster_threads, "fig_bench4_geommax_a")
    plot_geom_scaling(stats, "in_order", max_raster_threads, "fig_bench4_geommax_b")

    plot_geom_scaling(stats, "offline", 1, "fig_bench4_geom1_a")
    plot_geom_scaling(stats, "in_order", 1, "fig_bench4_geom1_b")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
