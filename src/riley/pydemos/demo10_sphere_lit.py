# --------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher)
# --------------------------------------------------------------------------
"""Renders three sphere images: direct speckle, lambertian, and pipe."""
from __future__ import annotations

import shutil
from pathlib import Path
from dataclasses import replace

import numpy as np

import riley


def main() -> None:
    # --------------------------------------------------------------------------
    # 1. Setup paths and parameters
    # --------------------------------------------------------------------------
    data_dir = riley.data.sphere200_case_path()
    texture_path = riley.data.speckle_texture_path()

    out_dir = Path.cwd() / "out_riley_py" / "demo10_sphere_lit"
    shutil.rmtree(out_dir, ignore_errors=True)
    out_dir.mkdir(parents=True, exist_ok=True)

    pixels_num = (800, 500)
    pixels_size = (5.3e-6, 5.3e-6)
    focal_length = 50.0e-3
    rot_world = (0.0, 0.0, 0.0)
    frame_fill = 1.0
    total_threads = 4

    # --------------------------------------------------------------------------
    # 2. Load sphere simulation data, texture, and shaders
    # --------------------------------------------------------------------------
    coords = riley.load_csv(data_dir / "coords.csv")
    connect = riley.load_csv(data_dir / "connect.csv", dtype=np.int64)

    uvs = riley.load_csv(data_dir / "uvs.csv")
    texture = riley.load_texture_mono_u8(texture_path)

    convention = riley.ConnectConvention(
        riley.EElemType.TRI6,
        riley.EConnectAxis.ROW,
        0,
        riley.ENodeOrder.RILEY,
    )

    speckle = riley.TextureShader(uvs=uvs, texture=texture)

    lambertian = riley.FunctionShader(
        builtin=riley.FuncShaderBuiltin.lambertian_normal_z,
        params=riley.FuncShaderParams(lambertian_coeffs=(0.2, 0.8)),
        bits=-1,
        scaling_type=riley.ScaleStrategy.none,
    )

    channel_slot = riley.Slot(riley.SlotKind.channel, 0)
    param_slot = riley.Slot(riley.SlotKind.parameter, 0)

    lit_stages = (
        riley.ShaderSource(speckle, channel_slot),
        riley.ShaderSource(lambertian, param_slot),
    )
    lit_resolver = riley.ShaderResolver(
        riley.ResolverKind.modulate,
        slots=(channel_slot,),
        factor=param_slot,
    )
    lit_pipe = riley.ShaderPipe(stages=lit_stages, resolver=lit_resolver)

    # --------------------------------------------------------------------------
    # 3. Position and frame the camera
    # --------------------------------------------------------------------------
    roi_cent_world = riley.roi_cent_from_coords(coords)
    pos_world = riley.pos_frame_coords(
        coords,
        pixels_num,
        pixels_size,
        focal_length,
        rot_world,
        fov_scale=frame_fill,
    )

    camera = riley.Camera(
        pixels_num=pixels_num,
        pixels_size=pixels_size,
        pos_world=pos_world,
        rot_world=rot_world,
        roi_cent_world=roi_cent_world,
        focal_length=focal_length,
        sub_sample=4,
        coord_sys=riley.CameraCoordSys.opengl,
        render_format=riley.RenderFormat.mono,
        output_files=[
            riley.ImageSaveOpts(
                format=riley.ImageFormat.bmp,
                bits=8,
                scaling=riley.ScaleStrategy.auto,
            )
        ],
    )

    # --------------------------------------------------------------------------
    # 4. Configure raster engine
    # --------------------------------------------------------------------------
    config = riley.RasterConfig(
        parallel=total_threads,
        save_strategy=riley.SaveStrategy.disk,
    )

    # --------------------------------------------------------------------------
    # 5. Render the three sphere images
    # --------------------------------------------------------------------------
    # 1) Direct speckle shader (like the normal sphere demo)
    mesh = riley.create_mesh(
        convention=convention,
        mesh_type=riley.MeshType.tri6,
        coords=coords,
        connect=connect,
        shaders=riley.MeshShaderSet(direct=speckle),
    )
    config.output_name_format = "demo10_1_direct_speckle"
    riley.raster(mesh, camera, config, out_dir=str(out_dir))

    # 2) Direct lambertian function shader
    mesh.shaders = riley.MeshShaderSet(direct=lambertian)
    config.output_name_format = "demo10_2_direct_lambertian"
    riley.raster(mesh, camera, config, out_dir=str(out_dir))

    # 3) Combined speckle texture and lambertian shader via shader pipe
    mesh.shaders = riley.MeshShaderSet(mono=lit_pipe)
    config.output_name_format = "demo10_3_combined_lit"
    riley.raster(mesh, camera, config, out_dir=str(out_dir))


if __name__ == "__main__":
    main()
