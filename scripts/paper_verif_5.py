#!/usr/bin/env python3
from __future__ import annotations

import csv
import math
import pathlib
import re

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from paper_const import (
    SHEAR_REGULAR,
    SHEAR_SHEAR,
    bulge_in_frame,
    bulge_out_frame,
    repo_root,
)


VERIF_DIR = pathlib.Path("verif/verif_5")
OUT_TABS_TEX_PATH = VERIF_DIR / "tabs_verif_5.tex"
OUT_FIGS_TEX_PATH = VERIF_DIR / "figs_verif_5.tex"
OUT_DIR = repo_root() / VERIF_DIR
CASE_RE = re.compile(
    r"^verif_5_(?P<mesh_name>[^_]+)_(?P<geom_name>[^_]+)_(?P<camera_case>.+)$",
)
CAMERA_CASE_ORDER = [
    "none",
    "mild_barrel",
    "mild_pincushion",
    "strong_barrel",
    "mixed_asymmetric",
]
CAMERA_CASE_LABELS = {
    "none": "none",
    "mild_barrel": "mild barrel",
    "mild_pincushion": "mild pincushion",
    "strong_barrel": "strong barrel",
    "mixed_asymmetric": "mixed asymmetric",
}


def parse_case_dir_name(
    dir_name: str,
) -> tuple[str, str, str]:
    match = CASE_RE.match(dir_name)
    if match is None:
        raise ValueError(f"could not parse case directory {dir_name}")
    return (
        match.group("mesh_name"),
        match.group("geom_name"),
        match.group("camera_case"),
    )


def load_rows(csv_path: pathlib.Path) -> list[dict[str, str]]:
    with csv_path.open(newline="") as csv_file:
        return list(csv.DictReader(csv_file))


def load_case_rows() -> dict[tuple[str, str, str], list[dict[str, str]]]:
    case_rows: dict[tuple[str, str, str], list[dict[str, str]]] = {}
    for case_dir in sorted(OUT_DIR.glob("verif_5_*")):
        if not case_dir.is_dir():
            continue
        stats_path = case_dir / "roundtrip_stats.csv"
        if not stats_path.exists():
            continue
        case_key = parse_case_dir_name(case_dir.name)
        case_rows[case_key] = load_rows(stats_path)
    if not case_rows:
        raise FileNotFoundError("no verif_5 case directories found")
    return case_rows


def accepted_err_vals(rows: list[dict[str, str]]) -> np.ndarray:
    err_vals: list[float] = []
    for row in rows:
        converged = row["converged"] == "1"
        in_bounds = row["in_bounds"] == "1"
        err_dist = float(row["err_dist"])
        if converged and in_bounds and math.isfinite(err_dist):
            err_vals.append(err_dist)
    return np.asarray(err_vals, dtype=float)


def err_map_from_rows(rows: list[dict[str, str]]) -> np.ndarray:
    row_idx = np.asarray([int(row["row_idx"]) for row in rows], dtype=int)
    col_idx = np.asarray([int(row["col_idx"]) for row in rows], dtype=int)
    rows_num = int(np.max(row_idx)) + 1
    cols_num = int(np.max(col_idx)) + 1
    err_map = np.full((rows_num, cols_num), np.nan, dtype=float)
    for row in rows:
        rr = int(row["row_idx"])
        cc = int(row["col_idx"])
        err_dist = float(row["err_dist"])
        converged = row["converged"] == "1"
        if converged and math.isfinite(err_dist):
            err_map[rr, cc] = err_dist
    return err_map


def fmt_case_name(geom_name: str) -> str:
    if geom_name == "shear":
        return "shear"
    if geom_name == "bulge":
        return "bulge"
    return geom_name


def make_table_row(
    mesh_name: str,
    geom_name: str,
    camera_case: str,
    rows: list[dict[str, str]],
) -> str:
    err_vals = accepted_err_vals(rows)
    if err_vals.size == 0:
        rms_err = math.nan
        max_err = math.nan
        mean_iters = math.nan
    else:
        rms_err = float(np.sqrt(np.mean(err_vals * err_vals)))
        max_err = float(np.max(err_vals))
        mean_iters = float(
            np.mean(
                [
                    int(row["iters"])
                    for row in rows
                    if row["converged"] == "1" and row["in_bounds"] == "1"
                ]
            )
        )
    return (
        f"\\texttt{{{mesh_name}}} & {fmt_case_name(geom_name)} & "
        f"{CAMERA_CASE_LABELS[camera_case]} & {rms_err:.3e} & "
        f"{max_err:.3e} & {mean_iters:.2f} \\\\"
    )


def build_table_tex(case_rows: dict[tuple[str, str, str], list[dict[str, str]]]) -> str:
    body_rows: list[str] = []
    for mesh_name in ["quad4", "tri6", "quad8", "quad9"]:
        geom_names = ["shear"] if mesh_name == "quad4" else ["shear", "bulge"]
        for geom_name in geom_names:
            for camera_case in CAMERA_CASE_ORDER:
                key = (mesh_name, geom_name, camera_case)
                rows = case_rows.get(key)
                if rows is None:
                    continue
                body_rows.append(
                    make_table_row(mesh_name, geom_name, camera_case, rows)
                )
    body = "\n".join(body_rows)
    return (
        "\\begin{table}[htbp]\n"
        "\\centering\n"
        "\\caption{Camera distortion round-trip recovery errors for "
        "verification case 5.}\n"
        "\\label{tab:verification_case_5_roundtrip}\n"
        "\\begin{tabular}{lllrrr}\n"
        "\\hline\n"
        "Element & Geometry & Distortion & RMS [px] & Max [px] & "
        "Mean iters. \\\\\n"
        "\\hline\n"
        f"{body}\n"
        "\\hline\n"
        "\\end{tabular}\n"
        "\\end{table}\n"
    )


def save_err_map_png(
    err_map: np.ndarray,
    out_name: str,
) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out_path = OUT_DIR / out_name
    fig, ax = plt.subplots(figsize=(3.6, 3.2), constrained_layout=False)
    masked_map = np.ma.masked_invalid(err_map)
    im = ax.imshow(
        masked_map,
        origin="lower",
        cmap="viridis",
        interpolation="none",
        aspect="auto",
    )
    ax.set_xlabel("sample col")
    ax.set_ylabel("sample row")
    ax.set_title("round-trip error [px]")
    cbar = fig.colorbar(im, ax=ax, fraction=0.05, pad=0.03)
    cbar.ax.tick_params(labelsize=9.0)
    fig.subplots_adjust(left=0.16, right=0.92, bottom=0.15, top=0.88)
    fig.savefig(out_path, dpi=300.0, bbox_inches="tight", pad_inches=0.02)
    fig.savefig(
        out_path.with_suffix(".svg"),
        bbox_inches="tight",
        pad_inches=0.02,
    )
    plt.close(fig)


def export_selected_figures(
    case_rows: dict[tuple[str, str, str], list[dict[str, str]]],
) -> list[str]:
    selected_specs = [
        ("quad4", "shear"),
        ("tri6", "bulge"),
        ("quad8", "bulge"),
        ("quad9", "bulge"),
    ]
    figure_names: list[str] = []
    for mesh_name, geom_name in selected_specs:
        for camera_case in CAMERA_CASE_ORDER:
            key = (mesh_name, geom_name, camera_case)
            rows = case_rows.get(key)
            if rows is None:
                continue
            out_name = (
                f"fig_verif_5_{mesh_name}_{geom_name}_{camera_case}.png"
            )
            save_err_map_png(err_map_from_rows(rows), out_name)
            figure_names.append(out_name)
    return figure_names


def subfigure_block(file_name: str) -> str:
    return (
        "\\begin{subfigure}[c]{0.19\\textwidth}\n"
        "\\centering\n"
        f"\\includegraphics[width=\\linewidth]{{{file_name}}}\n"
        "\\caption{}\n"
        "\\end{subfigure}"
    )


def build_figs_tex(figure_names: list[str]) -> str:
    blocks = "\n".join(subfigure_block(file_name) for file_name in figure_names)
    return (
        "\\begin{figure}[htbp]\n"
        "\\centering\n"
        f"{blocks}\n"
        "\\caption{Selected round-trip error maps for verification case 5.}\n"
        "\\label{fig:verification_case_5_roundtrip}\n"
        "\\end{figure}\n"
    )


def write_outputs(tabs_tex: str, figs_tex: str) -> None:
    out_tabs_path = repo_root() / OUT_TABS_TEX_PATH
    out_figs_path = repo_root() / OUT_FIGS_TEX_PATH
    out_tabs_path.parent.mkdir(parents=True, exist_ok=True)
    out_tabs_path.write_text(tabs_tex)
    out_figs_path.write_text(figs_tex)
    print(f"Wrote {out_tabs_path}")
    print(f"Wrote {out_figs_path}")


def main() -> int:
    case_rows = load_case_rows()
    print("Building verif_5 table...")
    tabs_tex = build_table_tex(case_rows)
    print("Exporting verif_5 figures...")
    figure_names = export_selected_figures(case_rows)
    print("Building verif_5 figure TeX...")
    figs_tex = build_figs_tex(figure_names)
    write_outputs(tabs_tex, figs_tex)
    print(f"Saved figure assets to {OUT_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
