# --------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher)
# --------------------------------------------------------------------------
"""Use procedural speckles as a shader-pipe source on the TRI6 rabbit mesh."""
from __future__ import annotations

import numpy as np

import riley
from riley.pydemos._procedural import demo_speckle_params, procedural_parser


def main(argv: list[str] | None = None) -> None:
    args = procedural_parser("demo02d_rabbit_procedural", __doc__).parse_args(argv)
    data_dir = riley.data.rabbit_case_path("riley", "tri6")
    coords = riley.load_csv(data_dir / "coords.csv")
    connect = riley.load_csv(data_dir / "connectivity.csv", dtype=np.int64)
    uvs = riley.load_csv(data_dir / "uvs.csv")
    # The atlas dips just below V = 0 between quadratic nodes. Translate it
    # into the unit domain without changing its physical calibration.
    uvs[:, 1] += 0.001

    # Use speckles as a mono pipe source, with sizes in reference-mesh units.
    params = demo_speckle_params(args.pattern, size=0.005)
    shader = riley.SpeckleShader(
        uvs=uvs, params=params, scaling_type=riley.ScaleStrategy.auto,
    )
    channel = riley.Register(riley.RegisterKind.channel, 0)
    pipe = riley.ShaderPipe(
        stages=(riley.ShaderSource(shader, channel),),
        resolver=riley.ShaderResolver(riley.ResolverKind.identity, registers=(channel,)),
    )
    convention = riley.ConnectConvention(
        riley.EElemType.TRI6, riley.EConnectAxis.ROW, 0, riley.ENodeOrder.RILEY,
    )
    rabbit = riley.create_mesh(
        convention, riley.MeshType.tri6, coords, connect, riley.MeshShaderSet(mono=pipe),
    )

    # Frame the rabbit with a small margin.
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
        render_format=riley.RenderFormat.mono,
        output_files=[riley.ImageSaveOpts(
            format=riley.ImageFormat.bmp,
            file_bits=8,
            scaling=riley.ScaleStrategy.auto,
        )],
    )
    config = riley.RasterConfig(parallel=4, save_strategy=riley.SaveStrategy.disk)
    riley.raster(rabbit, camera, config, out_dir=str(args.output))
    print(f"Saved {args.output / 'cam0_frame0_field0.bmp'}")


if __name__ == "__main__":
    main()
