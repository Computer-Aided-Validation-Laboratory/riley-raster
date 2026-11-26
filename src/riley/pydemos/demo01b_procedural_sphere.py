# --------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher)
# --------------------------------------------------------------------------
"""Track one physical speckle pattern through reference, stretch, and twist frames."""
from __future__ import annotations

import numpy as np

import riley
from riley.pydemos._procedural import demo_speckle_params, procedural_parser


def main(argv: list[str] | None = None) -> None:
    args = procedural_parser("demo01b_procedural_sphere", __doc__).parse_args(argv)
    data_dir = riley.data.sphere200_case_path()
    coords = riley.load_csv(data_dir / "coords.csv")
    connect = riley.load_csv(data_dir / "connect.csv", dtype=np.int64)
    uvs = riley.load_csv(data_dir / "uvs.csv")

    # One immutable pattern stays attached to the material through all frames.
    params = demo_speckle_params(args.pattern, size=0.02)
    shader = riley.SpeckleShader(
        uvs=uvs, params=params, scaling_type=riley.ScaleStrategy.auto,
    )
    convention = riley.ConnectConvention(
        riley.EElemType.TRI6, riley.EConnectAxis.ROW, 0, riley.ENodeOrder.RILEY,
    )
    sphere = riley.create_mesh(
        convention, riley.MeshType.tri6, coords, connect,
        riley.MeshShaderSet(mono=shader), disp=_demo_displacements(coords),
    )

    # Leave extra room for the deformed frames.
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
        background_value=255.0,
        render_format=riley.RenderFormat.mono,
        output_files=[riley.ImageSaveOpts(
            format=riley.ImageFormat.bmp,
            file_bits=8,
            scaling=riley.ScaleStrategy.none,  # Keep gray levels comparable across frames.
        )],
    )
    config = riley.RasterConfig(parallel=4, save_strategy=riley.SaveStrategy.disk)
    print(f"Rendering {args.pattern}: reference, stretch, twist...")
    riley.raster(sphere, camera, config, out_dir=str(args.output))
    print(f"Images saved under {args.output}")


def _demo_displacements(coords: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    x, y, z = (coords - coords.mean(axis=0)).T
    z_extent = max(abs(z.min()), abs(z.max()), 1e-12)
    twist = 0.16 * z / z_extent
    reference = np.zeros_like(z)
    # Python accepts one (nodes, frames) array per displacement component.
    return (
        np.column_stack((reference, 0.18 * x, -twist * y)),
        np.column_stack((reference, -0.08 * y, twist * x)),
        np.column_stack((reference, 0.04 * z, 0.12 * z)),
    )


if __name__ == "__main__":
    main()
