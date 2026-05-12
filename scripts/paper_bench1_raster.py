#!/usr/bin/env python3
from __future__ import annotations

from paper_bench_common import fmt_triplet
from paper_bench_common import load_case_map
from paper_bench_common import stats_dir
from paper_bench_common import write_tabs_tex


BENCH_NAME = "bench_fullraster"
EXPERIMENT_DIR = "experiment_1"
TEST_CASE_DIR = "bench_fullraster_simd-simd_save-memory"

ELEMENT_CASES = [
    (
        "tri3",
        2,
        [
            ("nodal interp.", "tri3_nodal_grey"),
            (
                "\\makecell[c]{Catmull--Rom\\\\ direct}",
                "tri3_tex8_grey_cubic_catmull_rom_direct",
            ),
            (
                "\\makecell[c]{Catmull--Rom\\\\ LUT-lerp}",
                "tri3_tex8_grey_cubic_catmull_rom_lut_lerp",
            ),
        ],
    ),
    (
        "tri6",
        2,
        [
            ("nodal interp.", "tri6_nodal_grey"),
            (
                "\\makecell[c]{Catmull--Rom\\\\ direct}",
                "tri6_tex8_grey_cubic_catmull_rom_direct",
            ),
            (
                "\\makecell[c]{Catmull--Rom\\\\ LUT-lerp}",
                "tri6_tex8_grey_cubic_catmull_rom_lut_lerp",
            ),
        ],
    ),
    (
        "quad4",
        1,
        [
            ("nodal interp.", "quad4newton_nodal_grey"),
            (
                "\\makecell[c]{Catmull--Rom\\\\ direct}",
                "quad4newton_tex8_grey_cubic_catmull_rom_direct",
            ),
            (
                "\\makecell[c]{Catmull--Rom\\\\ LUT-lerp}",
                "quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp",
            ),
        ],
    ),
    (
        "quad8",
        1,
        [
            ("nodal interp.", "quad8_nodal_grey"),
            (
                "\\makecell[c]{Catmull--Rom\\\\ direct}",
                "quad8_tex8_grey_cubic_catmull_rom_direct",
            ),
            (
                "\\makecell[c]{Catmull--Rom\\\\ LUT-lerp}",
                "quad8_tex8_grey_cubic_catmull_rom_lut_lerp",
            ),
        ],
    ),
    (
        "quad9",
        1,
        [
            ("nodal interp.", "quad9_nodal_grey"),
            (
                "\\makecell[c]{Catmull--Rom\\\\ direct}",
                "quad9_tex8_grey_cubic_catmull_rom_direct",
            ),
            (
                "\\makecell[c]{Catmull--Rom\\\\ LUT-lerp}",
                "quad9_tex8_grey_cubic_catmull_rom_lut_lerp",
            ),
        ],
    ),
]

OUT_TABS_NAME = "bench1_tabs.tex"


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

    body_rows: list[str] = []
    for element_name, elems_num, shader_cases in ELEMENT_CASES:
        for shader_label, case_name in shader_cases:
            median_row = median_map[case_name]
            mad_row = mad_map[case_name]
            e2e_text = fmt_triplet(
                median_row,
                mad_row,
                "E2E_ms",
            )
            raster_text = fmt_triplet(
                median_row,
                mad_row,
                "Raster_ms",
            )
            throughput_text = fmt_triplet(
                median_row,
                mad_row,
                "MPx/s",
            )
            body_rows.append(
                "\\texttt{" + element_name + "} & " +
                shader_label + " & " +
                str(elems_num) + " & " +
                e2e_text + " & " +
                raster_text + " & " +
                throughput_text + " \\\\"
            )

    body = "\n".join(body_rows)
    return (
        "\\begin{table}[htbp]\n"
        "\\centering\n"
        "\\caption{Raster-stage benchmark results for representative "
        "rendering cases. The image size is fixed at $1600 \\times 1000$ "
        "pixels, SSAA is fixed at $1 \\times 1$, and all runs are single "
        "threaded. Timings and throughputs are reported as median $\\pm$ MAD "
        "over 10 runs. Wall-clock timings are reported in $10^{-3}$ "
        "seconds. The raster throughput is reported in MPx/s.}\n"
        "\\label{tab:performance_raster_benchmark}\n"
        "\\begin{tabular}{llrlll}\n"
        "\\hline\n"
        "\\makecell[c]{Element\\\\ Type} & Shader & "
        "\\makecell[c]{Element\\\\ Count} & "
        "\\makecell[c]{End-to-end\\\\ {[$10^{-3}$ s]}} & "
        "\\makecell[c]{Raster\\\\ {[$10^{-3}$ s]}} & "
        "\\makecell[c]{Throughput\\\\ {[MPx/s]}} \\\\\n"
        "\\hline\n"
        f"{body}\n"
        "\\hline\n"
        "\\end{tabular}\n"
        "\\end{table}\n"
    )
def main() -> int:
    stats_path = stats_dir(BENCH_NAME, EXPERIMENT_DIR, TEST_CASE_DIR)
    print(f"Using benchmark stats from {stats_path}...")
    tabs_tex = build_table_tex()
    write_tabs_tex(OUT_TABS_NAME, tabs_tex)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
