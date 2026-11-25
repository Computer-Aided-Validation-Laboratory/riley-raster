# --------------------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
# --------------------------------------------------------------------------------------
"""Track one physical speckle pattern through reference, stretch, and twist frames."""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np

import riley


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        prog="python -m riley demo1b_procedural_sphere", description=__doc__,
    )
    parser.add_argument("--pattern", choices=("disk", "gaussian", "perlin"), default="disk")
    parser.add_argument(
        "--output", type=Path, default=Path("out_riley_py/demo1b_procedural_sphere"),
    )
    args = parser.parse_args(argv)

    # 1. Load the quadratic triangle mesh and UV atlas, then generate displacements.
    data_dir = riley.data.sphere200_case_path()
    coords = riley.load_csv(data_dir / "coords.csv")
    connect = riley.load_csv(data_dir / "connect.csv", dtype=np.int64)
    uvs = riley.load_csv(data_dir / "uvs.csv")
    convention = riley.ConnectConvention(
        riley.EElemType.TRI6, riley.EConnectAxis.ROW, 0, riley.ENodeOrder.RILEY,
    )

    rel_x, rel_y, rel_z = (coords - coords.mean(axis=0)).T
    z_extent = max(np.abs(rel_z).max(), 1e-12)
    twist = 0.16 * rel_z / z_extent
    reference = np.zeros_like(rel_z)
    # Each component is indexed as (node, frame); the reference frame stays zero.
    disp = (
        np.column_stack((reference, 0.18 * rel_x, -twist * rel_y)),
        np.column_stack((reference, -0.08 * rel_y, twist * rel_x)),
        np.column_stack((reference, 0.04 * rel_z, 0.12 * rel_z)),
    )

    # 2. Attach one UV pattern in reference-mesh units for all three frames.
    seed = 0xA511E9B3
    if args.pattern == "perlin":
        params = riley.Perlin2DParams(cell_size=0.02, seed=seed)
    else:
        params = riley.Dot2DParams(
            coverage=0.5, radius=0.02, seed=seed, pattern=riley.SpecklePattern[args.pattern],
        )
    shader = riley.SpeckleShader(uvs=uvs, params=params)
    mesh = riley.create_mesh(convention, riley.MeshType.tri6, coords, connect, shader, disp=disp)

    # 3. Frame the reference mesh with extra room for the deformed frames.
    pixels_num = (720, 450)
    pixels_size = (5.3e-6, 5.3e-6)
    focal_length = 50e-3
    rotation = (0.0, 0.0, 0.0)
    camera = riley.Camera(
        pixels_num=pixels_num,
        pixels_size=pixels_size,
        pos_world=riley.pos_frame_coords(
            coords, pixels_num, pixels_size, focal_length, rotation, fov_scale=1.28,
        ),
        rot_world=rotation,
        roi_cent_world=riley.roi_cent_from_coords(coords),
        focal_length=focal_length,
        sub_sample=2,
    )

    # 4. Keep the shader's nominal 8-bit range across all frames and a white background.
    config = riley.RasterConfig(
        parallel=4,
        save_strategy=riley.SaveStrategy.disk,
        image_save_mode=riley.ImageSaveMode.grey,
        save_format=riley.ImageFormat.bmp,
        save_bits=8,
        save_scaling=riley.ScaleStrategy.none,
        background_value=255.0,
        report=riley.ReportMode.off,
    )
    riley.raster(mesh, camera, config, out_dir=str(args.output))
    print(f"Saved reference, stretch, and twist images under {args.output}")


if __name__ == "__main__":
    main()
