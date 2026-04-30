from pathlib import Path

import numpy as np


TIME_STEPS = 13
MIDSIDE_OFFSET_FACTOR = 0.3


def save_case(
    base_dir,
    name,
    coords,
    connect,
    disp_x,
    disp_y,
    disp_z,
    uvs,
):
    out_dir = Path(base_dir) / name
    out_dir.mkdir(parents=True, exist_ok=True)
    np.savetxt(out_dir / "coords.csv", coords, delimiter=",")
    np.savetxt(
        out_dir / "connect.csv",
        connect.astype(int),
        delimiter=",",
        fmt="%d",
    )
    np.savetxt(out_dir / "field_disp_x.csv", disp_x, delimiter=",")
    np.savetxt(out_dir / "field_disp_y.csv", disp_y, delimiter=",")
    np.savetxt(out_dir / "field_disp_z.csv", disp_z, delimiter=",")
    np.savetxt(out_dir / "uvs.csv", uvs, delimiter=",")


def compute_uvs(coords, u_range=(0.4, 0.6), v_range=(0.4, 0.6)):
    xmin, ymin, _ = np.min(coords, axis=0)
    xmax, ymax, _ = np.max(coords, axis=0)
    xrng = max(xmax - xmin, 1.0)
    yrng = max(ymax - ymin, 1.0)

    return np.array(
        [
            [
                u_range[0] + (u_range[1] - u_range[0]) * (pt[0] - xmin) / xrng,
                v_range[0] + (v_range[1] - v_range[0]) * (pt[1] - ymin) / yrng,
            ]
            for pt in coords
        ]
    )


def get_midside_direction(v1, v2, centroid):
    midpoint = 0.5 * (v1 + v2)
    direction = midpoint - centroid
    direction_norm = np.linalg.norm(direction)
    if direction_norm < 1e-12:
        return np.array([0.0, 0.0, 0.0])
    return direction / direction_norm


def build_disp_fields_distort(coords, midside_info, time_steps, max_offset):
    node_num = coords.shape[0]
    disp_x = np.zeros((node_num, time_steps))
    disp_y = np.zeros((node_num, time_steps))
    disp_z = np.zeros((node_num, time_steps))

    for tt in range(time_steps):
        alpha = tt / (time_steps - 1)
        beta = -2.0 * alpha  # 0 (starts at outward) to -2 (ends at inward)
        for midside_ind, direction in midside_info:
            delta = beta * max_offset * direction
            disp_x[midside_ind, tt] = delta[0]
            disp_y[midside_ind, tt] = delta[1]
            disp_z[midside_ind, tt] = delta[2]

    return disp_x, disp_y, disp_z


def generate_tri6(base_dir, edge_length, time_steps):
    height = np.sqrt(3.0) * edge_length / 2.0
    vertices = np.array(
        [
            [0.0, 0.0, 0.0],
            [edge_length, 0.0, 0.0],
            [0.5 * edge_length, height, 0.0],
        ]
    )
    centroid = np.array([0.5 * edge_length, height / 3.0, 0.0])
    max_offset = MIDSIDE_OFFSET_FACTOR * edge_length

    midside_directions = [
        get_midside_direction(vertices[0], vertices[1], centroid),
        get_midside_direction(vertices[1], vertices[2], centroid),
        get_midside_direction(vertices[2], vertices[0], centroid),
    ]

    midsides = np.array(
        [
            0.5 * (vertices[0] + vertices[1]) + max_offset * midside_directions[0],
            0.5 * (vertices[1] + vertices[2]) + max_offset * midside_directions[1],
            0.5 * (vertices[2] + vertices[0]) + max_offset * midside_directions[2],
        ]
    )
    midside_info = [
        (3, midside_directions[0]),
        (4, midside_directions[1]),
        (5, midside_directions[2]),
    ]

    coords = np.vstack([vertices, midsides])
    disp_x, disp_y, disp_z = build_disp_fields_distort(
        coords,
        midside_info,
        time_steps,
        max_offset,
    )
    save_case(
        base_dir,
        "tri6_distort-midside",
        coords,
        np.array([[0, 1, 2, 3, 4, 5]]),
        disp_x,
        disp_y,
        disp_z,
        compute_uvs(coords),
    )


def generate_quad8(base_dir, edge_length, time_steps, include_center):
    vertices = np.array(
        [
            [0.0, 0.0, 0.0],
            [edge_length, 0.0, 0.0],
            [edge_length, edge_length, 0.0],
            [0.0, edge_length, 0.0],
        ]
    )
    centroid = np.array([0.5 * edge_length, 0.5 * edge_length, 0.0])
    max_offset = MIDSIDE_OFFSET_FACTOR * edge_length

    midside_directions = [
        get_midside_direction(vertices[0], vertices[1], centroid),
        get_midside_direction(vertices[1], vertices[2], centroid),
        get_midside_direction(vertices[2], vertices[3], centroid),
        get_midside_direction(vertices[3], vertices[0], centroid),
    ]

    midsides = np.array(
        [
            0.5 * (vertices[0] + vertices[1]) + max_offset * midside_directions[0],
            0.5 * (vertices[1] + vertices[2]) + max_offset * midside_directions[1],
            0.5 * (vertices[2] + vertices[3]) + max_offset * midside_directions[2],
            0.5 * (vertices[3] + vertices[0]) + max_offset * midside_directions[3],
        ]
    )

    midside_info = [
        (4, midside_directions[0]),
        (5, midside_directions[1]),
        (6, midside_directions[2]),
        (7, midside_directions[3]),
    ]

    node_list = [vertices[0], vertices[1], vertices[2], vertices[3]]
    node_list.extend([midsides[0], midsides[1], midsides[2], midsides[3]])
    if include_center:
        node_list.append(centroid)
    coords = np.array(node_list)

    disp_x, disp_y, disp_z = build_disp_fields_distort(
        coords,
        midside_info,
        time_steps,
        max_offset,
    )
    mesh_name = "quad9_distort-midside" if include_center else "quad8_distort-midside"
    connect = np.array([list(range(9 if include_center else 8))])
    save_case(
        base_dir,
        mesh_name,
        coords,
        connect,
        disp_x,
        disp_y,
        disp_z,
        compute_uvs(coords),
    )


def main():
    if TIME_STEPS % 2 == 0:
        print("Warning: TIME_STEPS should be odd to include the square case.")

    base_dir = "data-edge"
    edge_length = 10.0
    time_steps = TIME_STEPS

    generate_tri6(base_dir, edge_length, time_steps)
    generate_quad8(base_dir, edge_length, time_steps, False)
    generate_quad8(base_dir, edge_length, time_steps, True)

    print(f"Generated distort-midside edge data with {time_steps} time steps.")


if __name__ == "__main__":
    main()
