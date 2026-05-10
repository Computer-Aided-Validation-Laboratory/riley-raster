#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import math
import pathlib
import re
import sys

import numpy as np


FRAME_RE = re.compile(r"cam\d+_frame(\d+)_field\d+_stats\.csv$")

GAUSS_POINTS = np.array(
    [
        -math.sqrt(3.0 / 5.0),
        0.0,
        math.sqrt(3.0 / 5.0),
    ],
    dtype=float,
)
GAUSS_WEIGHTS = np.array([5.0 / 9.0, 8.0 / 9.0, 5.0 / 9.0], dtype=float)


def repo_root() -> pathlib.Path:
    return pathlib.Path(__file__).resolve().parent.parent


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--verif-root",
        type=pathlib.Path,
        default=repo_root() / "verif",
    )
    parser.add_argument(
        "--out-csv",
        type=pathlib.Path,
        default=repo_root() / "verif" / "verif_b_summary.csv",
    )
    parser.add_argument(
        "--subset",
        choices=("high_order_all", "high_order_bulge_tan", "all"),
        default="high_order_all",
    )
    return parser.parse_args()


def parse_stats_csv(stats_path: pathlib.Path) -> dict[str, float]:
    stats: dict[str, float] = {}
    with stats_path.open(newline="") as stats_file:
        reader = csv.reader(stats_file)
        header = next(reader)
        if header != ["key", "unit", "value"]:
            raise ValueError(
                f"{stats_path} does not have key,unit,value layout",
            )
        for row in reader:
            if len(row) != 3:
                continue
            key, _, value = row
            stats[key] = float(value)
    return stats


def load_scalar_csv(image_path: pathlib.Path) -> np.ndarray:
    rows: list[list[float]] = []
    with image_path.open(newline="") as image_file:
        reader = csv.reader(image_file)
        for row in reader:
            if row and row[-1] == "":
                row = row[:-1]
            rows.append([float(value) for value in row])
    return np.asarray(rows, dtype=float)


def calc_image_centroid_and_area(
    image_vals: np.ndarray,
) -> tuple[float, float, float, float]:
    rows_num, cols_num = image_vals.shape
    fill_value = float(np.max(image_vals))
    weighted_area = float(np.sum(image_vals))
    if weighted_area <= 0.0 or fill_value <= 0.0:
        return math.nan, math.nan, 0.0, fill_value

    x_centers = np.arange(cols_num, dtype=float) + 0.5
    y_centers = np.arange(rows_num, dtype=float) + 0.5

    centroid_x = float(np.sum(image_vals * x_centers[None, :]) / weighted_area)
    centroid_y = float(np.sum(image_vals * y_centers[:, None]) / weighted_area)
    area_px2 = weighted_area / fill_value
    return centroid_x, centroid_y, area_px2, fill_value


def parse_case_info(stats_path: pathlib.Path) -> tuple[str, str, str, int]:
    case_name = stats_path.parent.name
    case_parts = case_name.split("_")
    mesh_name = case_parts[1]
    distort_name = case_parts[2]

    frame_match = FRAME_RE.match(stats_path.name)
    if frame_match is None:
        raise ValueError(f"could not parse frame index from {stats_path.name}")

    return case_name, mesh_name, distort_name, int(frame_match.group(1))


def get_node_coords(stats: dict[str, float]) -> list[tuple[float, float]]:
    node_indices: list[int] = []
    for key in stats:
        if key.startswith("N") and key.endswith("_x"):
            node_indices.append(int(key[1:-2]))

    coords = []
    for nn in sorted(node_indices):
        coords.append((stats[f"N{nn}_x"], stats[f"N{nn}_y"]))
    return coords


def linear_edge_nodes(
    node_start: tuple[float, float],
    node_end: tuple[float, float],
    ss: float,
) -> tuple[float, float, float, float]:
    n0 = 0.5 * (1.0 - ss)
    n1 = 0.5 * (1.0 + ss)
    dn0 = -0.5
    dn1 = 0.5

    xx = n0 * node_start[0] + n1 * node_end[0]
    yy = n0 * node_start[1] + n1 * node_end[1]
    dx_ds = dn0 * node_start[0] + dn1 * node_end[0]
    dy_ds = dn0 * node_start[1] + dn1 * node_end[1]
    return xx, yy, dx_ds, dy_ds


def quadratic_edge_nodes(
    node_start: tuple[float, float],
    node_mid: tuple[float, float],
    node_end: tuple[float, float],
    ss: float,
) -> tuple[float, float, float, float]:
    n0 = 0.5 * ss * (ss - 1.0)
    n1 = 1.0 - ss * ss
    n2 = 0.5 * ss * (ss + 1.0)
    dn0 = ss - 0.5
    dn1 = -2.0 * ss
    dn2 = ss + 0.5

    xx = n0 * node_start[0] + n1 * node_mid[0] + n2 * node_end[0]
    yy = n0 * node_start[1] + n1 * node_mid[1] + n2 * node_end[1]
    dx_ds = dn0 * node_start[0] + dn1 * node_mid[0] + dn2 * node_end[0]
    dy_ds = dn0 * node_start[1] + dn1 * node_mid[1] + dn2 * node_end[1]
    return xx, yy, dx_ds, dy_ds


def iter_edges(
    mesh_name: str,
    node_coords: list[tuple[float, float]],
) -> list[tuple[str, tuple[float, float], ...]]:
    if mesh_name == "tri3":
        return [
            ("linear", node_coords[0], node_coords[1]),
            ("linear", node_coords[1], node_coords[2]),
            ("linear", node_coords[2], node_coords[0]),
        ]
    if mesh_name == "tri6":
        return [
            ("quadratic", node_coords[0], node_coords[3], node_coords[1]),
            ("quadratic", node_coords[1], node_coords[4], node_coords[2]),
            ("quadratic", node_coords[2], node_coords[5], node_coords[0]),
        ]
    if mesh_name == "quad4":
        return [
            ("linear", node_coords[0], node_coords[1]),
            ("linear", node_coords[1], node_coords[2]),
            ("linear", node_coords[2], node_coords[3]),
            ("linear", node_coords[3], node_coords[0]),
        ]
    if mesh_name == "quad8":
        return [
            ("quadratic", node_coords[0], node_coords[4], node_coords[1]),
            ("quadratic", node_coords[1], node_coords[5], node_coords[2]),
            ("quadratic", node_coords[2], node_coords[6], node_coords[3]),
            ("quadratic", node_coords[3], node_coords[7], node_coords[0]),
        ]
    if mesh_name == "quad9":
        return [
            ("quadratic", node_coords[0], node_coords[4], node_coords[1]),
            ("quadratic", node_coords[1], node_coords[5], node_coords[2]),
            ("quadratic", node_coords[2], node_coords[6], node_coords[3]),
            ("quadratic", node_coords[3], node_coords[7], node_coords[0]),
        ]
    raise ValueError(f"unsupported mesh name {mesh_name}")


def calc_edge_area(
    edge_kind: str,
    edge_nodes: tuple[tuple[float, float], ...],
) -> float:
    edge_area = 0.0
    for ss, ww in zip(GAUSS_POINTS, GAUSS_WEIGHTS, strict=True):
        if edge_kind == "linear":
            xx, yy, dx_ds, dy_ds = linear_edge_nodes(
                edge_nodes[0],
                edge_nodes[1],
                float(ss),
            )
        else:
            xx, yy, dx_ds, dy_ds = quadratic_edge_nodes(
                edge_nodes[0],
                edge_nodes[1],
                edge_nodes[2],
                float(ss),
            )
        edge_area += ww * (xx * dy_ds - yy * dx_ds)
    return 0.5 * edge_area


def calc_reference_area_px2(
    mesh_name: str,
    node_coords: list[tuple[float, float]],
) -> float:
    signed_area = 0.0
    for edge in iter_edges(mesh_name, node_coords):
        signed_area += calc_edge_area(edge[0], edge[1:])
    return abs(signed_area)


def run_self_test() -> None:
    side_leng = 10.0
    tri_height = 0.5 * math.sqrt(3.0) * side_leng
    tri3_nodes = [
        (0.0, 0.0),
        (side_leng, 0.0),
        (0.5 * side_leng, tri_height),
    ]
    tri6_nodes = [
        tri3_nodes[0],
        tri3_nodes[1],
        tri3_nodes[2],
        (0.5 * side_leng, 0.0),
        (0.75 * side_leng, 0.5 * tri_height),
        (0.25 * side_leng, 0.5 * tri_height),
    ]
    area_exact = 0.25 * math.sqrt(3.0) * side_leng * side_leng

    tri3_area = calc_reference_area_px2("tri3", tri3_nodes)
    tri6_area = calc_reference_area_px2("tri6", tri6_nodes)

    if not math.isclose(tri3_area, area_exact, rel_tol=0.0, abs_tol=1.0e-10):
        raise RuntimeError("tri3 area self-test failed")
    if not math.isclose(tri6_area, area_exact, rel_tol=0.0, abs_tol=1.0e-10):
        raise RuntimeError("tri6 area self-test failed")


def analyse_stats_file(stats_path: pathlib.Path) -> dict[str, object]:
    stats = parse_stats_csv(stats_path)
    image_path = stats_path.with_name(stats_path.name.replace("_stats.csv", ".csv"))
    image_vals = load_scalar_csv(image_path)

    case_name, mesh_name, distort_name, frame_idx = parse_case_info(stats_path)
    centroid_num_x, centroid_num_y, area_num_px2, fill_value = calc_image_centroid_and_area(
        image_vals,
    )

    node_coords = get_node_coords(stats)
    area_ref_px2 = calc_reference_area_px2(mesh_name, node_coords)

    centroid_ref_x = stats["cent_ideal_x"]
    centroid_ref_y = stats["cent_ideal_y"]
    centroid_diff_x = centroid_num_x - centroid_ref_x
    centroid_diff_y = centroid_num_y - centroid_ref_y
    centroid_dist = math.hypot(centroid_diff_x, centroid_diff_y)

    area_diff_px2 = area_num_px2 - area_ref_px2
    area_rel_diff = area_diff_px2 / area_ref_px2 if area_ref_px2 != 0.0 else math.nan

    return {
        "case_name": case_name,
        "mesh_name": mesh_name,
        "distort_name": distort_name,
        "frame_idx": frame_idx,
        "node_count": len(node_coords),
        "fill_value": fill_value,
        "centroid_ref_x_px": centroid_ref_x,
        "centroid_ref_y_px": centroid_ref_y,
        "centroid_num_x_px": centroid_num_x,
        "centroid_num_y_px": centroid_num_y,
        "centroid_diff_x_px": centroid_diff_x,
        "centroid_diff_y_px": centroid_diff_y,
        "centroid_dist_px": centroid_dist,
        "area_ref_px2": area_ref_px2,
        "area_num_px2": area_num_px2,
        "area_diff_px2": area_diff_px2,
        "area_rel_diff": area_rel_diff,
        "stats_path": str(stats_path.relative_to(repo_root())),
        "image_path": str(image_path.relative_to(repo_root())),
    }


def write_summary_csv(
    out_csv: pathlib.Path,
    rows: list[dict[str, object]],
) -> None:
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    field_names = [
        "case_name",
        "mesh_name",
        "distort_name",
        "frame_idx",
        "node_count",
        "fill_value",
        "centroid_ref_x_px",
        "centroid_ref_y_px",
        "centroid_num_x_px",
        "centroid_num_y_px",
        "centroid_diff_x_px",
        "centroid_diff_y_px",
        "centroid_dist_px",
        "area_ref_px2",
        "area_num_px2",
        "area_diff_px2",
        "area_rel_diff",
        "stats_path",
        "image_path",
    ]
    with out_csv.open("w", newline="") as out_file:
        writer = csv.DictWriter(out_file, fieldnames=field_names)
        writer.writeheader()
        writer.writerows(rows)


def keep_row(row: dict[str, object], subset: str) -> bool:
    if subset == "all":
        return True

    mesh_name = str(row["mesh_name"])
    distort_name = str(row["distort_name"])
    if subset == "high_order_bulge_tan":
        return mesh_name in {"tri6", "quad8", "quad9"} and distort_name in {
            "bulge",
            "tan",
        }

    return mesh_name in {"tri6", "quad8", "quad9"} and distort_name in {
        "bulge",
        "tan",
        "stretch",
        "shear",
    }


def main() -> int:
    args = parse_args()
    run_self_test()

    stats_files = sorted(args.verif_root.glob("b_*/*_stats.csv"))
    if not stats_files:
        raise FileNotFoundError(f"no stats files found under {args.verif_root}")

    rows = [analyse_stats_file(stats_path) for stats_path in stats_files]
    rows = [row for row in rows if keep_row(row, args.subset)]
    rows.sort(key=lambda row: (str(row["case_name"]), int(row["frame_idx"])))
    write_summary_csv(args.out_csv, rows)

    max_centroid = max(abs(float(row["centroid_dist_px"])) for row in rows)
    max_area_rel = max(abs(float(row["area_rel_diff"])) for row in rows)
    print(f"Processed {len(rows)} verif_b frames")
    print(f"Wrote summary to {args.out_csv}")
    print(f"Max centroid error: {max_centroid:.6f} px")
    print(f"Max area rel error: {max_area_rel:.6e}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
