#!/usr/bin/env python3
from __future__ import annotations

import csv
import math
import pathlib
import re
import subprocess

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from PIL import Image

from paper_const import PAPER_DIR, repo_root


OUT_FIGS_TEX_PATH = pathlib.Path("verif/verif_c_figs.tex")
LOWRES_TAG = "lowres"
HIGHRES_TAG = "highres"
LOWRES_MESH = "tri6"
FIG_TILE_WIDTH = "0.27\\textwidth"
LINE_PLOT_WIDTH = "0.48\\textwidth"
PLOT_SIZE = (3.35, 2.55)
PLOT_DPI = 300.0
FONT_LABEL = 10.0
FONT_TICK = 9.0
FONT_LEGEND = 8.5
FONT_TITLE = 12.0
DIFF_FIG_SIZE = (3.2, 2.0)
DIFF_CBAR_TICK_SIZE = 18.0


def verif_root() -> pathlib.Path:
    return repo_root() / "verif"


def run_verif_c_if_needed() -> None:
    if list(verif_root().glob("c_*_*res")):
        return
    print("Missing verif_c tagged outputs, running ./bin/verif_c_aa_convergence...")
    subprocess.run(
        ["./bin/verif_c_aa_convergence"],
        cwd=repo_root(),
        check=True,
    )


def constant_shader_dir(mesh_name: str, res_tag: str) -> pathlib.Path:
    dir_candidates = [
        verif_root() / f"c_{mesh_name}_funcconst_{res_tag}",
        verif_root() / f"c_{mesh_name}_funcsin_{res_tag}",
    ]
    for dir_path in dir_candidates:
        if dir_path.exists():
            return dir_path
    raise FileNotFoundError(
        f"missing constant shader verif_c directory for {mesh_name} {res_tag}",
    )


def parse_ssaa_from_name(file_name: str) -> int | None:
    match = re.search(r"ssaa(\d+)", file_name)
    if match is None:
        return None
    return int(match.group(1))


def collect_ssaa_levels(dir_path: pathlib.Path) -> list[int]:
    levels: set[int] = set()
    for csv_path in dir_path.glob("ssaa*.csv"):
        level = parse_ssaa_from_name(csv_path.name)
        if level is not None:
            levels.add(level)
    return sorted(levels, reverse=True)


def save_png_from_bmp(src_path: pathlib.Path, dst_name: str) -> pathlib.Path:
    PAPER_DIR.mkdir(parents=True, exist_ok=True)
    dst_path = PAPER_DIR / dst_name
    with Image.open(src_path) as image:
        image.save(
            dst_path,
            format="PNG",
            optimize=True,
            dpi=(300, 300),
        )
    return dst_path


def save_diff_png_from_csv(src_path: pathlib.Path, dst_name: str) -> pathlib.Path:
    diff_mat = load_csv_matrix(src_path)
    finite_vals = diff_mat[np.isfinite(diff_mat)]
    vmax = float(np.max(np.abs(finite_vals))) if finite_vals.size > 0 else 1.0
    if vmax == 0.0:
        vmax = 1.0

    PAPER_DIR.mkdir(parents=True, exist_ok=True)
    dst_path = PAPER_DIR / dst_name

    fig, ax = plt.subplots(figsize=DIFF_FIG_SIZE, constrained_layout=False)
    im = ax.imshow(
        diff_mat,
        origin="upper",
        cmap="RdBu_r",
        vmin=-vmax,
        vmax=vmax,
        interpolation="none",
        aspect="equal",
    )
    ax.set_axis_off()
    cbar = fig.colorbar(im, ax=ax, fraction=0.05, pad=0.02)
    cbar.ax.tick_params(labelsize=DIFF_CBAR_TICK_SIZE)
    fig.subplots_adjust(left=0.01, right=0.92, bottom=0.01, top=0.99)
    fig.savefig(
        dst_path,
        dpi=PLOT_DPI,
        bbox_inches="tight",
        pad_inches=0.01,
    )
    plt.close(fig)
    return dst_path


def save_lowres_figures() -> list[int]:
    print("Preparing lowres verif_c figures from tri6 constant shader...")
    dir_path = constant_shader_dir(LOWRES_MESH, LOWRES_TAG)
    ssaa_levels = collect_ssaa_levels(dir_path)
    if not ssaa_levels:
        raise RuntimeError(f"no SSAA levels found in {dir_path}")

    highest_ssaa = ssaa_levels[0]
    lowest_ssaa = ssaa_levels[-1]

    save_png_from_bmp(
        dir_path / f"ssaa{highest_ssaa}.bmp",
        "fig_verifc_ssaa_high.png",
    )
    save_png_from_bmp(
        dir_path / f"ssaa{lowest_ssaa}.bmp",
        "fig_verifc_ssaa_low.png",
    )

    for ssaa in ssaa_levels[1:]:
        save_diff_png_from_csv(
            dir_path / f"diff_ssaa{ssaa}.csv",
            f"fig_verifc_ssaa{ssaa}_diff.png",
        )

    return ssaa_levels


def load_csv_matrix(csv_path: pathlib.Path) -> np.ndarray:
    with csv_path.open(newline="") as csv_file:
        reader = csv.reader(csv_file)
        rows = [
            [float(val) for val in row if val != ""]
            for row in reader
        ]
    return np.asarray(rows, dtype=float)


def calc_rmse(mat: np.ndarray) -> float:
    return float(np.sqrt(np.mean(mat * mat)))


def build_rmse_data(res_tag: str) -> dict[str, list[tuple[int, float]]]:
    print(f"Calculating {res_tag} RMSE curves from diff CSVs...")
    mesh_names = ["tri3", "tri6", "quad4", "quad8", "quad9"]
    rmse_data: dict[str, list[tuple[int, float]]] = {}
    for mesh_name in mesh_names:
        dir_path = constant_shader_dir(mesh_name, res_tag)
        entries: list[tuple[int, float]] = []
        for csv_path in sorted(dir_path.glob("diff_ssaa*.csv")):
            ssaa = parse_ssaa_from_name(csv_path.name)
            if ssaa is None:
                continue
            diff_mat = load_csv_matrix(csv_path)
            entries.append((ssaa, calc_rmse(diff_mat)))
        if not entries:
            raise RuntimeError(f"no diff CSVs found in {dir_path}")
        rmse_data[mesh_name] = sorted(entries, key=lambda entry: entry[0])
    return rmse_data


def save_rmse_plot(
    rmse_data: dict[str, list[tuple[int, float]]],
    out_name: str,
) -> None:
    print(f"Saving verif_c RMSE line plot: {out_name}...")
    PAPER_DIR.mkdir(parents=True, exist_ok=True)
    fig, ax = plt.subplots(figsize=PLOT_SIZE, constrained_layout=False)

    x_ticks = sorted(
        {ssaa for entries in rmse_data.values() for ssaa, _ in entries},
    )
    x_pos_map = {ssaa: ii for ii, ssaa in enumerate(x_ticks)}

    for mesh_name in ["tri3", "tri6", "quad4", "quad8", "quad9"]:
        entries = rmse_data[mesh_name]
        x_vals = [x_pos_map[ssaa] for ssaa, _ in entries]
        y_vals = [rmse for _, rmse in entries]
        ax.plot(
            x_vals,
            y_vals,
            marker="o",
            linewidth=1.8,
            markersize=4.5,
            label=mesh_name,
        )

    x_tick_pos = list(range(len(x_ticks)))
    ax.set_xticks(x_tick_pos, [str(ssaa) for ssaa in x_ticks])
    ax.set_xlabel("Sub-sample [px]", fontsize=FONT_LABEL)
    ax.set_ylabel("RMSE [GL]", fontsize=FONT_LABEL)
    ax.tick_params(labelsize=FONT_TICK)
    ax.grid(True, which="both", alpha=0.3)
    ax.legend(fontsize=FONT_LEGEND, frameon=True)
    fig.subplots_adjust(
        left=0.18,
        right=0.98,
        bottom=0.18,
        top=0.90,
    )

    fig.savefig(
        PAPER_DIR / f"{out_name}.png",
        dpi=PLOT_DPI,
        bbox_inches="tight",
        pad_inches=0.02,
    )
    fig.savefig(
        PAPER_DIR / f"{out_name}.svg",
        bbox_inches="tight",
        pad_inches=0.02,
    )
    plt.close(fig)


def subfigure_block(file_name: str, width_str: str, label: str) -> str:
    return (
        f"\\begin{{subfigure}}[c]{{{width_str}}}\n"
        "\\centering\n"
        f"\\includegraphics[width=\\linewidth]{{{file_name}}}\n"
        "\\caption{}\n"
        f"\\label{{{label}}}\n"
        "\\end{subfigure}"
    )


def render_subfigure_block(file_name: str, width_str: str, label: str) -> str:
    return (
        f"\\begin{{subfigure}}[c]{{{width_str}}}\n"
        "\\centering\n"
        f"\\includegraphics[width=0.8\\linewidth]{{{file_name}}}\n"
        "\\caption{}\n"
        f"\\label{{{label}}}\n"
        "\\end{subfigure}"
    )


def build_lowres_figure_tex(ssaa_levels: list[int]) -> str:
    highest_ssaa = ssaa_levels[0]
    lowest_ssaa = ssaa_levels[-1]
    row_lines = [
        "\\makecell[c]{Ref.\\\\SS " +
        f"{highest_ssaa}" + "} & " +
        render_subfigure_block(
            "fig_verifc_ssaa_high.png",
            FIG_TILE_WIDTH,
            "fig:verifc_ssaa_high",
        ) +
        " \\\\",
    ]

    for ssaa in ssaa_levels[1:]:
        row_lines.append(
            "\\makecell[c]{Diff.\\\\SS " +
            f"{ssaa}" + "} & " +
            subfigure_block(
                f"fig_verifc_ssaa{ssaa}_diff.png",
                FIG_TILE_WIDTH,
                f"fig:verifc_ssaa{ssaa}_diff",
            ) +
            " \\\\",
        )

    row_lines.append(
        "\\makecell[c]{Render.\\\\SS " +
        f"{lowest_ssaa}" + "} & " +
        render_subfigure_block(
            "fig_verifc_ssaa_low.png",
            FIG_TILE_WIDTH,
            "fig:verifc_ssaa_low",
        ) +
        " \\\\",
    )

    rows_tex = "\n".join(row_lines)
    return (
        "\\begin{figure}[htbp]\n"
        "\\centering\n"
        "\\begin{tabular}{cc}\n"
        f"{rows_tex}\n"
        "\\end{tabular}\n"
        "\\caption{Verification case C anti-aliasing convergence for the "
        "\\texttt{tri6} rabbit with the constant shader at low resolution. "
        "SS denotes sub-sample. The reference render is shown at the top, "
        "followed by the difference images in descending SS order, and the "
        "lowest-SS render at the bottom. The difference images are plotted "
        "with a zero-centred diverging colour scale in 8-bit grey levels "
        "(GL).}\n"
        "\\label{fig:verification_case_c_lowres}\n"
        "\\end{figure}\n"
    )


def build_rmse_figure_tex() -> str:
    return (
        "\\begin{figure}[htbp]\n"
        "\\centering\n"
        "\\begin{subfigure}[c]{" + LINE_PLOT_WIDTH + "}\n"
        "\\centering\n"
        "\\includegraphics[width=\\linewidth]{fig_verifc_rmse_line_plot_lowres.png}\n"
        "\\caption{}\n"
        "\\label{fig:verifc_rmse_line_plot_lowres}\n"
        "\\end{subfigure}\n"
        "\\hfill\n"
        "\\begin{subfigure}[c]{" + LINE_PLOT_WIDTH + "}\n"
        "\\centering\n"
        "\\includegraphics[width=\\linewidth]{fig_verifc_rmse_line_plot_highres.png}\n"
        "\\caption{}\n"
        "\\label{fig:verifc_rmse_line_plot_highres}\n"
        "\\end{subfigure}\n"
        "\\caption{Verification case C RMSE convergence for the low-"
        "resolution (a) and high-resolution (b) difference images using "
        "the constant rabbit shader. SS denotes sub-sample and GL denotes "
        "8-bit grey levels. Each line shows one element type.}\n"
        "\\label{fig:verification_case_c_rmse}\n"
        "\\end{figure}\n"
    )


def write_figs_tex(figs_tex: str) -> None:
    out_figs_path = repo_root() / OUT_FIGS_TEX_PATH
    paper_figs_path = PAPER_DIR / OUT_FIGS_TEX_PATH.name

    out_figs_path.parent.mkdir(parents=True, exist_ok=True)
    PAPER_DIR.mkdir(parents=True, exist_ok=True)

    out_figs_path.write_text(figs_tex)
    paper_figs_path.write_text(figs_tex)

    print(f"Wrote {out_figs_path}")
    print(f"Wrote {paper_figs_path}")


def main() -> int:
    print("Checking verif_c outputs...")
    run_verif_c_if_needed()

    print("Exporting lowres BMP figures to PNG...")
    ssaa_levels = save_lowres_figures()

    print("Building lowres RMSE data...")
    lowres_rmse_data = build_rmse_data(LOWRES_TAG)
    save_rmse_plot(lowres_rmse_data, "fig_verifc_rmse_line_plot_lowres")

    print("Building highres RMSE data...")
    highres_rmse_data = build_rmse_data(HIGHRES_TAG)
    save_rmse_plot(highres_rmse_data, "fig_verifc_rmse_line_plot_highres")

    print("Writing verif_c figure TeX...")
    figs_tex = (
        build_lowres_figure_tex(ssaa_levels) +
        "\n" +
        build_rmse_figure_tex()
    )
    write_figs_tex(figs_tex)
    print(f"Saved figure assets to {PAPER_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
