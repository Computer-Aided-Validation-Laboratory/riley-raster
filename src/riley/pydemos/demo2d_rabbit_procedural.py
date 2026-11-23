# --------------------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
# --------------------------------------------------------------------------------------
"""Apply a physical speckle shader to the TRI6 Riley rabbit mesh."""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np

import riley


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        prog="python -m riley demo2d_rabbit_procedural", description=__doc__,
    )
    parser.add_argument("--pattern", choices=("disk", "gaussian", "perlin"), default="disk")
    parser.add_argument(
        "--output", type=Path, default=Path("out_riley_py/demo2d_rabbit_procedural"),
    )
    args = parser.parse_args(argv)

    # 1. Load the static quadratic triangle mesh and nodal UV atlas.
    data_dir = riley.data.rabbit_case_path("riley", "tri6")
    coords = riley.load_csv(data_dir / "coords.csv")
    connect = riley.load_csv(data_dir / "connectivity.csv", dtype=np.int64)
    uvs = riley.load_csv(data_dir / "uvs.csv")
    # The quadratic atlas dips below V = 0 between nodes. Translate it into
    # the unit domain without changing its physical calibration.
    uvs[:, 1] += 0.001
    convention = riley.ConnectConvention(
        riley.EElemType.TRI6, riley.EConnectAxis.ROW, 0, riley.ENodeOrder.RILEY,
    )

    # 2. Specify the pattern scale in reference-mesh units.
    seed = 0xA511E9B3
    if args.pattern == "perlin":
        params = riley.Perlin2DParams(cell_size=0.005, seed=seed)
    else:
        params = riley.Dot2DParams(
            coverage=0.5, radius=0.005, seed=seed, pattern=riley.SpecklePattern[args.pattern],
        )
    shader = riley.SpeckleShader(uvs=uvs, params=params)
    mesh = riley.create_mesh(convention, riley.MeshType.tri6, coords, connect, shader)

    # 3. Frame the rabbit with a small margin.
    pixels_num = (800, 500)
    pixels_size = (5.3e-6, 5.3e-6)
    focal_length = 50e-3
    rotation = (0.0, 0.0, 0.0)
    camera = riley.Camera(
        pixels_num=pixels_num,
        pixels_size=pixels_size,
        pos_world=riley.pos_frame_coords(
            coords, pixels_num, pixels_size, focal_length, rotation, fov_scale=1.01,
        ),
        rot_world=rotation,
        roi_cent_world=riley.roi_cent_from_coords(coords),
        focal_length=focal_length,
        sub_sample=2,
    )

    # 4. Stretch the saved image to the full 8-bit range, including the black background.
    config = riley.RasterConfig(
        parallel=4,
        save_strategy=riley.SaveStrategy.disk,
        image_save_mode=riley.ImageSaveMode.multifield,
        save_format=riley.ImageFormat.bmp,
        save_bits=8,
        save_scaling=riley.ScaleStrategy.auto,
        background_value=0.0,
        report=riley.ReportMode.off,
    )
    riley.raster(mesh, camera, config, out_dir=str(args.output))
    print(f"Saved {args.output / 'cam0_frame0_field0.bmp'}")


if __name__ == "__main__":
    main()
