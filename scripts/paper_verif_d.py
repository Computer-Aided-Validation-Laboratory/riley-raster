#!/usr/bin/env python3
from __future__ import annotations

import csv
import pathlib

from PIL import Image

from paper_const import PAPER_DIR, repo_root


OUT_STATS_PATH = pathlib.Path("verif/verif_d_stats.csv")
OUT_FIGS_TEX_PATH = pathlib.Path("verif/verif_d_figs.tex")
RABBIT_MESH_NAMES = ["tri3", "quad4", "tri6", "quad8", "quad9"]
COUNT_TOL = 1.0e-6

FIG_CAPTION = (
    "Visibility test images for the \\texttt{tri6} rabbit meshes in "
    "verification case 4: (a) both meshes, (b) front mesh only, and (c) the "
    "difference image."
)


def verif_case_dir(mesh_name: str) -> pathlib.Path:
    return repo_root() / "verif" / f"d_{mesh_name}_rabbit"


def load_csv_matrix(csv_path: pathlib.Path) -> list[list[float]]:
    rows: list[list[float]] = []
    with csv_path.open(newline="") as csv_file:
        reader = csv.reader(csv_file)
        for row in reader:
            vals = [float(val) for val in row if val != ""]
            if vals:
                rows.append(vals)
    return rows


def count_ones(rows: list[list[float]], target: float = 1.0) -> int:
    count = 0
    for row in rows:
        for val in row:
            if abs(val - target) <= COUNT_TOL:
                count += 1
    return count


def write_stats_csv() -> None:
    out_path = repo_root() / OUT_STATS_PATH
    out_path.parent.mkdir(parents=True, exist_ok=True)

    with out_path.open("w", newline="") as csv_file:
        writer = csv.writer(csv_file)
        writer.writerow(["element", "count front", "count both", "diff"])

        for mesh_name in RABBIT_MESH_NAMES:
            case_dir = verif_case_dir(mesh_name)
            front_rows = load_csv_matrix(case_dir / "frontonly.csv")
            both_rows = load_csv_matrix(case_dir / "both.csv")
            count_front = count_ones(front_rows)
            count_both = count_ones(both_rows)
            writer.writerow([
                mesh_name,
                count_front,
                count_both,
                count_both - count_front,
            ])


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


def export_tri6_figures() -> None:
    case_dir = verif_case_dir("tri6")
    save_png_from_bmp(case_dir / "both.bmp", "fig_verifd_both.png")
    save_png_from_bmp(case_dir / "frontonly.bmp", "fig_verifd_frontonly.png")
    save_png_from_bmp(case_dir / "diff.bmp", "fig_verifd_diff.png")


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
            "fig_verifd_both.png",
            "0.32\\textwidth",
            "fig:verifd_both",
        )
        + "\n\\hfill\n"
        + subfigure_block(
            "fig_verifd_frontonly.png",
            "0.32\\textwidth",
            "fig:verifd_frontonly",
        )
        + "\n\\hfill\n"
        + subfigure_block(
            "fig_verifd_diff.png",
            "0.32\\textwidth",
            "fig:verifd_diff",
        )
        + "\n"
        + f"\\caption{{{FIG_CAPTION}}}\n"
        + "\\label{fig:verification_case_d_tri6}\n"
        + "\\end{figure}\n"
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
    print("Writing verif_d stats CSV...")
    write_stats_csv()
    print("Exporting tri6 rabbit BMPs to PNG...")
    export_tri6_figures()
    print("Writing verif_d figure TeX...")
    figs_tex = build_figs_tex()
    write_figs_tex(figs_tex)
    print(f"Wrote {repo_root() / OUT_STATS_PATH}")
    print(f"Saved figure assets to {PAPER_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
