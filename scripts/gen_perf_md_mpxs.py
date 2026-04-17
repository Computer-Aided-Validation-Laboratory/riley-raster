#!/usr/bin/env python3

from pathlib import Path
import argparse


ELEMENT_TYPES = [
    "tri3",
    "tri3opt",
    "tri6",
    "quad4ibi",
    "quad4newton",
    "quad8",
    "quad9",
]


def parse_benchmark_md(path: Path) -> dict[tuple[str, str], float]:
    rows: dict[tuple[str, str], float] = {}
    shader_type = None

    for line in path.read_text().splitlines():
        if line.startswith("## Shader Type: "):
            shader_type = line.split(": ", 1)[1].strip()
            continue

        if not line.startswith("|"):
            continue
        if "Case" in line or ":---:" in line:
            continue

        parts = [part.strip() for part in line.strip().split("|")[1:-1]]
        if len(parts) < 5 or shader_type is None:
            continue

        case_name = parts[0]
        try:
            mpx = float(parts[4])
        except ValueError:
            continue

        rows[(shader_type, case_name)] = mpx

    return rows


def format_table(rows: dict[tuple[str, str], float]) -> str:
    lines = [
        "# src-simd2 Fullraster MPx/s",
        "",
        "| Element       | Linear | Linear | Tex Grey | Tex Grey | Tex Grey | Tex RGB | Tex RGB | Tex RGB |",
        "|               | Grey   | RGB    | Linear   | Cubic LL | Quint LL | Linear  | Cubic LL| Quint LL|",
        "|---------------|-------:|-------:|---------:|---------:|---------:|--------:|--------:|--------:|",
    ]

    for element_type in ELEMENT_TYPES:
        values = [
            rows[("flat_grey", f"{element_type}_flat_grey")],
            rows[("flat_rgb", f"{element_type}_flat_rgb")],
            rows[("tex8_grey", f"{element_type}_tex8_grey_linear")],
            rows[("tex8_grey", f"{element_type}_tex8_grey_cubic_lut_lerp")],
            rows[("tex8_grey", f"{element_type}_tex8_grey_quintic_lut_lerp")],
            rows[("tex8_rgb", f"{element_type}_tex8_rgb_linear")],
            rows[("tex8_rgb", f"{element_type}_tex8_rgb_cubic_lut_lerp")],
            rows[("tex8_rgb", f"{element_type}_tex8_rgb_quintic_lut_lerp")],
        ]
        values_fmt = " | ".join(f"{value:7.2f}" for value in values)
        lines.append(f"| `{element_type}`".ljust(16) + f"| {values_fmt} |")

    lines.extend(
        [
            "",
            "`LL` = `lut_lerp`",
        ]
    )

    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate a compact MPx/s markdown table from a fullraster benchmark.md."
    )
    parser.add_argument(
        "--input",
        type=Path,
        default=Path("out-simd2-bench-fullraster/benchmark.md"),
        help="Path to the source benchmark.md file.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("perf_simd_mpxs.md"),
        help="Path to the output markdown file.",
    )
    args = parser.parse_args()

    rows = parse_benchmark_md(args.input)
    output_text = format_table(rows)
    args.output.write_text(output_text)


if __name__ == "__main__":
    main()
