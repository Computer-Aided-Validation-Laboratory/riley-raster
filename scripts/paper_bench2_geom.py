#!/usr/bin/env python3
from __future__ import annotations

import csv
from paper_bench_common import fmt_triplet
from paper_bench_common import calc_median_mad
from paper_bench_common import load_case_map
from paper_bench_common import load_run_case_rows
from paper_bench_common import stats_dir
from paper_bench_common import write_tabs_tex
from paper_verif_const import repo_root


BENCH_NAME = "bench_geom"
EXPERIMENT_DIR = "experiment_1"
TEST_CASE_DIR = "bench_geom_simd-simd_save-memory"
GEOM_SHADER_LABEL = "nodal interp."
GEOM_SHADER_CASE_SUFFIX = "nodal_grey"
GEOM_CASES = [
    ("tri3", "tri3", "tri3"),
    ("tri6", "tri6", "tri6"),
    ("quad4", "quad4newton", "quad4newton"),
    ("quad8", "quad8", "quad8"),
    ("quad9", "quad9", "quad9"),
]
OUT_TABS_NAME = "bench2_tabs.tex"


def count_elements(mesh_dir_name: str) -> int:
    connect_path = (
        repo_root() /
        "data" /
        "bench" /
        f"{mesh_dir_name}_geom" /
        "connect.csv"
    )
    with connect_path.open(newline="") as csv_file:
        rows = [
            row for row in csv.reader(csv_file)
            if any(cell.strip() for cell in row)
        ]
    return len(rows)


def count_nodes(mesh_dir_name: str) -> int:
    coords_path = (
        repo_root() /
        "data" /
        "bench" /
        f"{mesh_dir_name}_geom" /
        "coords.csv"
    )
    with coords_path.open(newline="") as csv_file:
        rows = [
            row for row in csv.reader(csv_file)
            if any(cell.strip() for cell in row)
        ]
    return len(rows)


def fmt_float_pair(
    median_val: float,
    mad_val: float,
) -> str:
    return f"${median_val:.1f} \\pm {mad_val:.1f}$"


def build_table_tex() -> str:
    median_map = load_case_map(
        BENCH_NAME,
        EXPERIMENT_DIR,
        TEST_CASE_DIR,
        "bench_stats_median.csv",
    )
    mad_map = load_case_map(
        BENCH_NAME,
        EXPERIMENT_DIR,
        TEST_CASE_DIR,
        "bench_stats_mad.csv",
    )
    run_case_maps = load_run_case_rows(
        BENCH_NAME,
        EXPERIMENT_DIR,
        TEST_CASE_DIR,
    )

    body_rows: list[str] = []
    for element_label, mesh_dir_name, case_prefix in GEOM_CASES:
        case_name = f"{case_prefix}_{GEOM_SHADER_CASE_SUFFIX}"
        median_row = median_map[case_name]
        mad_row = mad_map[case_name]
        elems_num = count_elements(mesh_dir_name)
        nodes_num = count_nodes(mesh_dir_name)
        e2e_text = fmt_triplet(
            median_row,
            mad_row,
            "E2E_ms",
        )
        geom_text = fmt_triplet(
            median_row,
            mad_row,
            "Geom_ms",
        )
        throughput_vals: list[float] = []
        for case_map in run_case_maps:
            run_row = case_map[case_name]
            geom_ms = float(run_row["Geom_ms"])
            if geom_ms > 0.0:
                throughput_vals.append(nodes_num / geom_ms / 1.0e3)
        throughput_median, throughput_mad = calc_median_mad(
            throughput_vals,
        )
        elem_throughput_vals: list[float] = []
        for case_map in run_case_maps:
            run_row = case_map[case_name]
            geom_ms = float(run_row["Geom_ms"])
            if geom_ms > 0.0:
                elem_throughput_vals.append(elems_num / geom_ms / 1.0e3)
        elem_throughput_median, elem_throughput_mad = calc_median_mad(
            elem_throughput_vals,
        )
        elem_throughput_text = fmt_float_pair(
            elem_throughput_median,
            elem_throughput_mad,
        )
        node_throughput_text = fmt_float_pair(
            throughput_median,
            throughput_mad,
        )
        body_rows.append(
            "\\texttt{" + element_label + "} & " +
            str(elems_num) + " & " +
            str(nodes_num) + " & " +
            e2e_text + " & " +
            geom_text + " & " +
            elem_throughput_text + " & " +
            node_throughput_text + " \\\\"
        )

    body = "\n".join(body_rows)
    return (
        "\\begin{table}[htbp]\n"
        "\\centering\n"
        "\\caption{Geometry-preprocessing benchmark results for "
        "representative element types. The image size is fixed at "
        "$1600 \\times 1000$ pixels, SSAA is fixed at $1 \\times 1$, and "
        "all runs are single threaded. Timings and throughputs are reported "
        "as median $\\pm$ MAD over 10 runs. Wall-clock timings are reported "
        "in $10^{-3}$ seconds. The geometry throughput is reported in both "
        "MElem/s and MNodes/s, computed from the exact input element and node "
        "counts and the geometry preprocessing time.}\n"
        "\\label{tab:performance_geometry_benchmark}\n"
        "\\begin{tabular}{lrrllll}\n"
        "\\hline\n"
        "\\makecell[c]{Element\\\\ Type} & "
        "\\makecell[c]{Element\\\\ Count} & "
        "\\makecell[c]{Node\\\\ Count} & "
        "\\makecell[c]{End-to-end\\\\ {[$10^{-3}$ s]}} & "
        "\\makecell[c]{Geometry\\\\ {[$10^{-3}$ s]}} & "
        "\\makecell[c]{Throughput\\\\ {[MElem/s]}} & "
        "\\makecell[c]{Throughput\\\\ {[MNodes/s]}} \\\\\n"
        "\\hline\n"
        f"{body}\n"
        "\\hline\n"
        "\\end{tabular}\n"
        "\\end{table}\n"
    )
def main() -> int:
    stats_path = stats_dir(BENCH_NAME, EXPERIMENT_DIR, TEST_CASE_DIR)
    print(f"Using benchmark stats from {stats_path}...")
    print(f"Using shader selection: {GEOM_SHADER_LABEL}")
    tabs_tex = build_table_tex()
    write_tabs_tex(OUT_TABS_NAME, tabs_tex)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
