"""Extract Riley surface mesh and CSV datasets from an Exodus simulation."""

from __future__ import annotations

from pathlib import Path
import numpy as np

import riley


def extract_surface_from_exodus(
    exodus_path: Path,
    output_dir: Path,
) -> None:
    """Extract surface mesh, map displacement fields, and save to CSVs."""
    print(f"Loading Exodus file: {exodus_path}")
    sim = riley.load_exodus(
        exodus_path,
        disp_keys=("disp_x", "disp_y", "disp_z"),
    )

    if sim.disp is None or len(sim.disp) < 3:
        raise ValueError("Simulation data does not contain 3D displacements.")

    block = sim.elem_blocks["connect1"]
    convention = riley.ConnectConvention(
        block.elem_type,
        riley.EConnectAxis.ROW,
        1,
        node_order=riley.ENodeOrder.EXODUS,
    )
    volume = riley.convert_mesh(sim.coords, block.connect, convention)
    riley.verify_mesh(volume)

    surface = riley.extract_surface(volume)
    riley.verify_mesh(surface)

    coord_to_idx: dict[tuple[float, ...], int] = {}
    for node_idx, coord in enumerate(volume.coords):
        key = tuple(float(v) for v in coord)
        if key in coord_to_idx:
            raise ValueError("Duplicate node coordinate in volume mesh.")
        coord_to_idx[key] = node_idx

    surface_node_idxs = np.empty(surface.coords.shape[0], dtype=np.int64)
    for ii, coord in enumerate(surface.coords):
        key = tuple(float(v) for v in coord)
        if key not in coord_to_idx:
            raise ValueError(
                f"Surface coordinate {key} not found in volume mesh."
            )
        surface_node_idxs[ii] = coord_to_idx[key]

    disp_x = sim.disp[0][surface_node_idxs]
    disp_y = sim.disp[1][surface_node_idxs]
    disp_z = sim.disp[2][surface_node_idxs]

    uvs = riley.project_uvs_planar_centered(
        surface.coords,
        (2464, 2056),
        uv_span_max=0.8,
        proj_plane=(
            np.array((0.0, 0.0, -1.0), dtype=np.float64),
            np.array((0.0, 0.0, 0.0), dtype=np.float64),
        ),
    )

    output_dir.mkdir(parents=True, exist_ok=True)

    print(80 * "-")
    print(f"Extracted Surface Mesh: {surface.elem_type}")
    print(f"Volume coords shape:    {volume.coords.shape}")
    print(f"Volume connect shape:   {volume.connect.shape}")
    print(f"Surface coords shape:   {surface.coords.shape}")
    print(f"Surface connect shape:  {surface.connect.shape}")
    print(f"Displacement shape:     {disp_x.shape}")
    print(
        f"UV extent:              min={np.min(uvs, axis=0)}, "
        f"max={np.max(uvs, axis=0)}"
    )
    print(80 * "-")

    np.savetxt(output_dir / "coords.csv", surface.coords, delimiter=",")
    np.savetxt(
        output_dir / "connect.csv",
        surface.connect,
        delimiter=",",
        fmt="%d",
    )
    np.savetxt(output_dir / "field_disp_x.csv", disp_x, delimiter=",")
    np.savetxt(output_dir / "field_disp_y.csv", disp_y, delimiter=",")
    np.savetxt(output_dir / "field_disp_z.csv", disp_z, delimiter=",")
    np.savetxt(output_dir / "uvs.csv", uvs, delimiter=",")

    print(f"Saved CSV datasets to {output_dir}")


def main() -> None:
    base_dir = Path(__file__).resolve().parent
    exodus_path = base_dir / "platehole3d_2mr_7f.e"
    output_dir = base_dir / "platehole3d_2mr_7f"

    extract_surface_from_exodus(exodus_path, output_dir)


if __name__ == "__main__":
    main()
