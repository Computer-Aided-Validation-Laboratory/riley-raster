#!/usr/bin/env python3
from __future__ import annotations

import shutil
from pathlib import Path

import analysis_bench4_threading as analysis

from paper_bench_common import PAPER_DIR, write_tabs_tex
from paper_const import repo_root


OUT_DIR = repo_root() / "verif"

RASTER_FIG_STEM = "fig_bench4_best_raster_throughput"
E2E_FIG_STEM = "fig_bench4_best_e2e_throughput"
FIGS_TEX_NAME = "figs_bench4.tex"
AMDAHL_SOURCE_NAME = "bench4_amdahl.csv"
AMDAHL_TABLE_NAME = "bench4_amdahl_table.csv"

THREADING_FIG_CAPTION = (
    "Thread-scaling behaviour for the DIC UQ benchmark with offline "
    "rendering. Panel (a) shows the best raster-loop throughput by save "
    "mode, and panel (b) shows the end-to-end throughput by save mode. "
    "The right-hand axis reports speedup relative to the one thread "
    "baseline, and the dashed lines denote ideal linear scaling."
)

SUBFIGURE_WIDTH = "0.48\\textwidth"


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


def copy_file_to_outputs(src_path: Path, dst_name: str | None = None) -> None:
    dst_name = dst_name or src_path.name
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    PAPER_DIR.mkdir(parents=True, exist_ok=True)

    out_path = OUT_DIR / dst_name
    paper_path = PAPER_DIR / dst_name

    if src_path.resolve() != out_path.resolve():
        shutil.copy2(src_path, out_path)
        print(f"Wrote {out_path}")
    else:
        print(f"Using {out_path}")

    shutil.copy2(src_path, paper_path)
    print(f"Wrote {paper_path}")


def copy_required_assets() -> None:
    for stem in (RASTER_FIG_STEM, E2E_FIG_STEM):
        copy_file_to_outputs(OUT_DIR / f"{stem}.png")
        copy_file_to_outputs(OUT_DIR / f"{stem}.svg")

    copy_file_to_outputs(
        OUT_DIR / AMDAHL_SOURCE_NAME,
        AMDAHL_TABLE_NAME,
    )


def main() -> int:
    analysis.main(include_disk_overlap=False)
    copy_required_assets()
    write_tabs_tex(FIGS_TEX_NAME, build_figs_tex())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
