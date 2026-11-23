# --------------------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
# --------------------------------------------------------------------------------------
"""Render a physical speckle pattern on a flat, front-facing plane."""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np

import riley


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        prog="python -m riley demo0b_procedural_quickstart", description=__doc__,
    )
    parser.add_argument("--pattern", choices=("disk", "gaussian", "perlin"), default="disk")
    parser.add_argument(
        "--output", type=Path, default=Path("out_riley_py/demo0b_procedural_quickstart"),
    )
    args = parser.parse_args(argv)

    # 1. Map the full UV square onto a 40 × 40 quad. V grows down the image.
    side = 40.0
    h = side / 2
    coords = np.array(((-h, -h, 0), (h, -h, 0), (h, h, 0), (-h, h, 0)))
    connect = np.array(((0, 1, 2, 3),), dtype=np.int64)
    uvs = np.array(((0.0, 1.0), (1.0, 1.0), (1.0, 0.0), (0.0, 0.0)))
    convention = riley.ConnectConvention(
        riley.EElemType.QUAD4, riley.EConnectAxis.ROW, 0, riley.ENodeOrder.RILEY,
    )

    # 2. Specify the pattern scale in plane units, not in pixels.
    seed = 0xA511E9B3
    if args.pattern == "perlin":
        params = riley.Perlin2DParams(cell_size=0.25, seed=seed)
    else:
        params = riley.Dot2DParams(
            coverage=0.5, radius=0.25, seed=seed, pattern=riley.SpecklePattern[args.pattern],
        )
    shader = riley.SpeckleShader(
        uvs=uvs, params=params, bits=-1, scaling_type=riley.ScaleStrategy.none,
    )
    mesh = riley.create_mesh(convention, riley.MeshType.quad4, coords, connect, shader)

    # 3. Look down -Z. The projected square fills the sensor.
    width, height = 1024, 1024
    focal_length = 50e-3
    camera = riley.Camera(
        pixels_num=(width, height),
        pixels_size=(focal_length / width, focal_length / height),
        pos_world=(0.0, 0.0, side),
        rot_world=(0.0, 0.0, 0.0),
        roi_cent_world=(0.0, 0.0, 0.0),
        focal_length=focal_length,
        sub_sample=1,
    )

    # 4. Map raw [0, 1] values to 8-bit gray without a contrast stretch.
    config = riley.RasterConfig(
        parallel=4,
        save_strategy=riley.SaveStrategy.disk,
        image_save_mode=riley.ImageSaveMode.multifield,
        save_format=riley.ImageFormat.bmp,
        save_bits=8,
        save_scaling=riley.ScaleStrategy.fixed,
        save_scaling_min=0.0,
        save_scaling_max=1.0,
        report=riley.ReportMode.off,
        output_name_format=args.pattern,
    )
    riley.raster(mesh, camera, config, out_dir=str(args.output))
    print(f"Saved {args.output / (args.pattern + '.bmp')}")


if __name__ == "__main__":
    main()
