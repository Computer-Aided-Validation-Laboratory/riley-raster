#!/usr/bin/env python3
from __future__ import annotations

import csv
import math
import pathlib
import subprocess

from PIL import Image


SHEAR_REGULAR = 10
SHEAR_SHEAR = 0

BULGE_OUT = 4
BULGE_REGULAR = 6
BULGE_IN = 8

SUMMARY_PATH = pathlib.Path("verif/verif_b_summary.csv")
OUT_PATH = pathlib.Path("verif/verif_b_tables.tex")
FIGS_TEX_PATH = pathlib.Path("verif/verif_b_figs.tex")
PAPER_DIR = pathlib.Path("~/paper-zraster").expanduser()
SCI_THRESHOLD = 1.0e-12


def repo_root() -> pathlib.Path:
    return pathlib.Path(__file__).resolve().parent.parent


def load_summary(summary_path: pathlib.Path) -> list[dict[str, str]]:
    with summary_path.open(newline="") as summary_file:
        reader = csv.DictReader(summary_file)
        return list(reader)


def find_bmp_path(row: dict[str, str]) -> pathlib.Path:
    image_path = repo_root() / row["image_path"]
    return image_path.with_suffix(".bmp")


def ensure_summary_rows() -> list[dict[str, str]]:
    summary_path = repo_root() / SUMMARY_PATH
    if not summary_path.exists():
        print("Missing verif_b summary, generating it with scripts/verif_b.py...")
        subprocess.run(
            [".venv/bin/python", "scripts/verif_b.py"],
            cwd=repo_root(),
            check=True,
        )

    rows = load_summary(summary_path)
    needed_pairs = {
        ("tri3", "shear"),
        ("quad4", "shear"),
        ("tri6", "shear"),
        ("quad8", "shear"),
        ("quad9", "shear"),
        ("tri6", "bulge"),
        ("quad8", "bulge"),
        ("quad9", "bulge"),
    }
    present_pairs = {
        (row["mesh_name"], row["distort_name"])
        for row in rows
    }
    missing_pairs = sorted(needed_pairs - present_pairs)
    if missing_pairs:
        print(
            "verif_b summary is missing required rows; regenerating with "
            "scripts/verif_b.py...",
        )
        subprocess.run(
            [".venv/bin/python", "scripts/verif_b.py", "--subset", "all"],
            cwd=repo_root(),
            check=True,
        )
        rows = load_summary(summary_path)
        present_pairs = {
            (row["mesh_name"], row["distort_name"])
            for row in rows
        }
        missing_pairs = sorted(needed_pairs - present_pairs)
        if missing_pairs:
            raise RuntimeError(
                "verif_b summary is still missing required rows after "
                "regeneration",
            )
    return rows


def find_row(
    rows: list[dict[str, str]],
    mesh_name: str,
    distort_name: str,
    frame_idx: int,
) -> dict[str, str]:
    for row in rows:
        if (
            row["mesh_name"] == mesh_name and
            row["distort_name"] == distort_name and
            int(row["frame_idx"]) == frame_idx
        ):
            return row
    raise KeyError(
        f"missing row for mesh={mesh_name} distort={distort_name} "
        f"frame={frame_idx}",
    )


def get_row_metric_vals(row: dict[str, str]) -> tuple[float, float, float, float, float]:
    centroid_x = float(row["centroid_diff_x_px"])
    centroid_y = float(row["centroid_diff_y_px"])
    centroid_r = float(row["centroid_dist_px"])
    area_err_pct = abs(float(row["area_err_pct"]))
    mask_diff_pct = float(row["mask_diff_pct"])
    return centroid_x, centroid_y, centroid_r, area_err_pct, mask_diff_pct


def fmt_sci(value: float) -> str:
    if value == 0.0:
        return "$0$"
    if abs(value) < SCI_THRESHOLD:
        return "$< 1.00 \\times 10^{-12}$"
    exponent = int(math.floor(math.log10(abs(value))))
    scale = 10.0 ** exponent
    mantissa = value / scale
    return f"${mantissa:.2f} \\times 10^{{{exponent}}}$"


def fmt_percent(value: float) -> str:
    if value == 0.0:
        return "0.000"
    return f"{value:.3f}"


def make_table_row(
    element_name: str,
    case_name: str,
    row: dict[str, str],
) -> str:
    raw_vals = get_row_metric_vals(row)
    metric_vals = (
        fmt_sci(raw_vals[0]),
        fmt_sci(raw_vals[1]),
        fmt_sci(raw_vals[2]),
        fmt_percent(raw_vals[3]),
        fmt_percent(raw_vals[4]),
    )
    return (
        f"\\texttt{{{element_name}}} & {case_name} & "
        f"{metric_vals[0]} & {metric_vals[1]} & {metric_vals[2]} & "
        f"{metric_vals[3]} & {metric_vals[4]} \\\\"
    )


def build_shear_table(rows: list[dict[str, str]]) -> str:
    mesh_names = ["tri3", "quad4", "tri6", "quad8", "quad9"]
    body_rows: list[str] = []
    for mesh_name in mesh_names:
        row_regular = find_row(rows, mesh_name, "shear", SHEAR_REGULAR)
        row_shear = find_row(rows, mesh_name, "shear", SHEAR_SHEAR)
        body_rows.append(make_table_row(mesh_name, "regular", row_regular))
        body_rows.append(make_table_row(mesh_name, "shear", row_shear))

    body = "\n".join(body_rows)
    return (
        "\\begin{table}[htbp]\n"
        "\\centering\n"
        "\\caption{Silhouette verification for the affine deformation case "
        "using one sensor point per pixel. TODO}\n"
        "\\label{tab:verification_silhouette_affine}\n"
        "\\begin{tabular}{llrrrrrr}\n"
        "\\hline\n"
        "Element & Case & \\makecell{Centroid\\\\Err. $x$ [px]} & "
        "\\makecell{Centroid\\\\Err. $y$ [px]} & "
        "\\makecell{Centroid\\\\Err. $r$ [px]} & "
        "\\makecell{Area\\\\Err. [\\%]} & "
        "\\makecell{Ref. Mask\\\\Err. [\\%]}\\\\\n"
        "\\hline\n"
        f"{body}\n"
        "\\hline\n"
        "\\end{tabular}\n"
        "\\end{table}\n"
    )


def build_bulge_table(rows: list[dict[str, str]]) -> str:
    mesh_names = ["tri6", "quad8", "quad9"]
    body_rows: list[str] = []
    for mesh_name in mesh_names:
        row_inward = find_row(rows, mesh_name, "bulge", BULGE_IN)
        row_regular = find_row(rows, mesh_name, "bulge", BULGE_REGULAR)
        row_outward = find_row(rows, mesh_name, "bulge", BULGE_OUT)
        body_rows.append(make_table_row(mesh_name, "inward bulge", row_inward))
        body_rows.append(make_table_row(mesh_name, "regular", row_regular))
        body_rows.append(make_table_row(mesh_name, "outward bulge", row_outward))

    body = "\n".join(body_rows)
    return (
        "\\begin{table}[htbp]\n"
        "\\centering\n"
        "\\caption{Silhouette verification for the nonlinear edge-bulge "
        "cases using one sensor point per pixel. These cases are only "
        "applied to the higher-order elements because the linear "
        "\\texttt{tri3} and \\texttt{quad4} elements do not have midside "
        "nodes that can define a curved boundary.}\n"
        "\\label{tab:verification_silhouette_bulge}\n"
        "\\begin{tabular}{llrrrrrr}\n"
        "\\hline\n"
        "Element & Case & \\makecell{Centroid\\\\Err. $x$ [px]} & "
        "\\makecell{Centroid\\\\Err. $y$ [px]} & "
        "\\makecell{Centroid\\\\Err. $r$ [px]} & "
        "\\makecell{Area\\\\Err. [\\%]} & "
        "\\makecell{Ref. Mask\\\\Err. [\\%]}\\\\\n"
        "\\hline\n"
        f"{body}\n"
        "\\hline\n"
        "\\end{tabular}\n"
        "\\end{table}\n"
    )


def save_frame_png(
    row: dict[str, str],
    dst_name: str,
) -> pathlib.Path:
    src_path = find_bmp_path(row)
    if not src_path.exists():
        raise FileNotFoundError(f"missing source bmp {src_path}")

    PAPER_DIR.mkdir(parents=True, exist_ok=True)
    dst_path = PAPER_DIR / dst_name
    with Image.open(src_path) as img:
        img.save(
            dst_path,
            format="PNG",
            optimize=True,
            dpi=(300, 300),
        )
    return dst_path


def subfigure_block(
    file_name: str,
    width_str: str,
    label: str,
) -> str:
    return (
        f"\\begin{{subfigure}}[t]{{{width_str}}}\n"
        "\\centering\n"
        f"\\includegraphics[width=\\linewidth]{{{file_name}}}\n"
        "\\caption{}\n"
        f"\\label{{{label}}}\n"
        "\\end{subfigure}"
    )


def build_shear_fig_tex(rows: list[dict[str, str]]) -> str:
    mesh_names = ["tri3", "quad4", "tri6", "quad8", "quad9"]
    row_blocks: list[str] = []
    label_idx = 0
    for mesh_name in mesh_names:
        row_regular = find_row(rows, mesh_name, "shear", SHEAR_REGULAR)
        row_shear = find_row(rows, mesh_name, "shear", SHEAR_SHEAR)
        regular_name = f"fig_verifb_{mesh_name}_shear_regular.png"
        shear_name = f"fig_verifb_{mesh_name}_shear_shear.png"
        save_frame_png(row_regular, regular_name)
        save_frame_png(row_shear, shear_name)

        regular_label = chr(ord("a") + label_idx)
        shear_label = chr(ord("a") + label_idx + 1)
        label_idx += 2
        regular_block = subfigure_block(
            regular_name,
            "0.18\\textwidth",
            f"fig:verifb_{mesh_name}_shear_regular",
        )
        shear_block = subfigure_block(
            shear_name,
            "0.18\\textwidth",
            f"fig:verifb_{mesh_name}_shear_shear",
        )
        row_blocks.append(
            "\\makecell[c]{\\texttt{" + mesh_name + "}} & " +
            regular_block + " & " + shear_block + " \\\\"
        )

    rows_tex = "\n".join(row_blocks)
    return (
        "\\begin{figure}[htbp]\n"
        "\\centering\n"
        "\\resizebox{0.48\\textwidth}{!}{%\n"
        "\\begin{tabular}{ccc}\n"
        "\\makecell[c]{Element} & \\makecell[c]{Regular} & "
        "\\makecell[c]{Shear}\\\\\n"
        f"{rows_tex}\n"
        "\\end{tabular}\n"
        "}\n"
        "\\caption{Silhouette verification images for the affine shear cases. "
        "Each row corresponds to one element type and compares the regular "
        "and sheared states.}\n"
        "\\label{fig:verification_silhouette_shear}\n"
        "\\end{figure}\n"
    )


def build_bulge_fig_tex(rows: list[dict[str, str]]) -> str:
    mesh_names = ["tri6", "quad8", "quad9"]
    row_blocks: list[str] = []
    label_idx = 0
    for mesh_name in mesh_names:
        bulge_in_limit = BULGE_IN + 1
        if mesh_name in {"quad8", "quad9"}:
            bulge_in_limit = BULGE_IN + 2
        frame_cases = [
            ("bulge_out_limit", 0, "out limit"),
            ("bulge_out", BULGE_OUT, "outward bulge"),
            ("bulge_regular", BULGE_REGULAR, "regular"),
            ("bulge_in", BULGE_IN, "inward bulge"),
            ("bulge_in_limit", bulge_in_limit, "in limit"),
        ]
        subfig_blocks: list[str] = []
        for suffix, frame_idx, caption_name in frame_cases:
            row = find_row(rows, mesh_name, "bulge", frame_idx)
            file_name = f"fig_verifb_{mesh_name}_{suffix}.png"
            save_frame_png(row, file_name)
            sub_label = chr(ord("a") + label_idx)
            label_idx += 1
            subfig_blocks.append(
                subfigure_block(
                    file_name,
                    "0.135\\textwidth",
                    f"fig:verifb_{mesh_name}_{suffix}",
                )
            )
        row_blocks.append(
            "\\makecell[c]{\\texttt{" + mesh_name + "}} & " +
            " & ".join(subfig_blocks) +
            " \\\\"
        )

    rows_tex = "\n".join(row_blocks)
    return (
        "\\begin{figure*}[htbp]\n"
        "\\centering\n"
        "\\resizebox{\\textwidth}{!}{%\n"
        "\\begin{tabular}{cccccc}\n"
        "\\makecell[c]{Element} & \\makecell[c]{Out limit} & "
        "\\makecell[c]{Outward} & \\makecell[c]{Regular} & "
        "\\makecell[c]{Inward} & \\makecell[c]{In limit}\\\\\n"
        f"{rows_tex}\n"
        "\\end{tabular}\n"
        "}\n"
        "\\caption{Silhouette verification images for the nonlinear bulge "
        "cases. Each row corresponds to one higher-order element type and "
        "shows the outward limit, outward bulge, regular, inward bulge, and "
        "inward limit states.}\n"
        "\\label{fig:verification_silhouette_bulge}\n"
        "\\end{figure*}\n"
    )


def main() -> int:
    print("Loading verif_b summary...")
    rows = ensure_summary_rows()
    print(f"Loaded {len(rows)} summary rows.")
    out_path = repo_root() / OUT_PATH
    figs_tex_path = repo_root() / FIGS_TEX_PATH
    out_path.parent.mkdir(parents=True, exist_ok=True)

    print("Building LaTeX tables...")
    tables_tex = (
        build_shear_table(rows) +
        "\n" +
        build_bulge_table(rows)
    )
    print("Building figure TeX and exporting PNG figures...")
    figs_tex = (
        build_shear_fig_tex(rows) +
        "\n" +
        build_bulge_fig_tex(rows)
    )
    print(f"Writing tables to {out_path}...")
    out_path.write_text(tables_tex)
    print(f"Writing figure TeX to {figs_tex_path}...")
    figs_tex_path.write_text(figs_tex)
    print(f"Wrote {out_path}")
    print(f"Wrote {figs_tex_path}")
    print(f"Saved png figures to {PAPER_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
