# --------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher)
# --------------------------------------------------------------------------
"""Render a physical speckle pattern on a flat, front-facing plane."""
from __future__ import annotations

import numpy as np

import riley
from riley.pydemos._procedural import demo_speckle_params, procedural_parser


def main(argv: list[str] | None = None) -> None:
    parser = procedural_parser("demo00b_procedural_quickstart", __doc__)
    parser.add_argument(
        "--width", type=int, default=1024, help="image width (default: 1024)",
    )
    parser.add_argument(
        "--height", type=int, default=1024, help="image height (default: 1024)",
    )
    args = parser.parse_args(argv)
    width, height = args.width, args.height
    if min(width, height) <= 0:
        parser.error("--width and --height must be positive integers")
    # Riley writes a 54-byte header and padded rows of 24-bit BMP pixels.
    row_bytes = (3 * width + 3) & ~3
    if max(width, height) >= 2**31 or 54 + row_bytes * height >= 2**32:
        parser.error("--width and --height exceed BMP size limits")

    # Pattern sizes are in physical plane units, independent of image resolution.
    params = demo_speckle_params(args.pattern, size=0.25)

    # Map the full UV square onto one 40 x 40 quad, with V growing down.
    side = 40.0
    h = side / 2
    coords = np.array(((-h, -h, 0), (h, -h, 0), (h, h, 0), (-h, h, 0)))
    connect = np.array(((0, 1, 2, 3),), dtype=np.int64)
    uvs = np.array(((0.0, 1.0), (1.0, 1.0), (1.0, 0.0), (0.0, 0.0)))
    shader = riley.SpeckleShader(uvs=uvs, params=params)
    convention = riley.ConnectConvention(
        riley.EElemType.QUAD4, riley.EConnectAxis.ROW, 0, riley.ENodeOrder.RILEY,
    )
    plane = riley.create_mesh(
        convention, riley.MeshType.quad4, coords, connect,
        riley.MeshShaderSet(mono=shader),
    )

    # Fill the sensor even for unequal width and height (non-square pixels).
    focal_length = 50e-3
    camera = riley.Camera(
        pixels_num=(width, height),
        pixels_size=(focal_length / width, focal_length / height),
        pos_world=(0.0, 0.0, side),
        rot_world=(0.0, 0.0, 0.0),
        roi_cent_world=(0.0, 0.0, 0.0),
        focal_length=focal_length,
        sub_sample=1,
        render_format=riley.RenderFormat.mono,
        output_files=[riley.ImageSaveOpts(
            format=riley.ImageFormat.bmp,
            file_bits=8,
            scaling=riley.ScaleStrategy.fixed,  # Map raw [0, 1] to 8-bit gray.
            scaling_min=0.0,
            scaling_max=1.0,
        )],
    )
    config = riley.RasterConfig(
        parallel=4,
        save_strategy=riley.SaveStrategy.disk,
        output_name_format=args.pattern,
    )
    riley.raster(plane, camera, config, out_dir=str(args.output))
    output_file = args.output / f"{args.pattern}.bmp"
    print(f"Saved {output_file}")


if __name__ == "__main__":
    main()
