# --------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher)
# --------------------------------------------------------------------------
"""One mesh, two camera-selected shaders: direct checker and lit checker."""
from __future__ import annotations

import shutil
from pathlib import Path

import numpy as np

import riley


def main() -> None:
    # --------------------------------------------------------------------------
    # 1. Setup paths and parameters
    # --------------------------------------------------------------------------
    out_dir = Path.cwd() / "out_riley_py" / "demo7_shaderpipe_quickstart"
    shutil.rmtree(out_dir, ignore_errors=True)
    out_dir.mkdir(parents=True, exist_ok=True)

    # --------------------------------------------------------------------------
    # 2. Create the mesh geometry and shaders
    # --------------------------------------------------------------------------
    coords = np.array(
        ((-1.0, -1.0, 0.0), (1.0, -1.0, 0.0), (0.0, 1.0, 0.0)),
        dtype=np.float64,
    )
    connect = np.array(((0, 1, 2),), dtype=np.int64)
    convention = riley.ConnectConvention(
        riley.EElemType.TRI3,
        riley.EConnectAxis.ROW,
        0,
        riley.ENodeOrder.RILEY,
    )

    checker = riley.FunctionShader(
        builtin=riley.FuncShaderBuiltin.checker,
        coord_mode=riley.FuncCoordMode.world_reference,
        params=riley.FuncShaderParams(coord_scale=(4.0, 4.0)),
        scaling_type=riley.ScaleStrategy.auto,
    )
    light = riley.FunctionShader(
        builtin=riley.FuncShaderBuiltin.linear,
        coord_mode=riley.FuncCoordMode.world_reference,
        params=riley.FuncShaderParams(linear_coeffs=(0.625, 0.375, 0.0)),
        bits=-1,
        scaling_type=riley.ScaleStrategy.none,
    )

    channel = riley.Slot(riley.SlotKind.channel, 0)
    parameter = riley.Slot(riley.SlotKind.parameter, 0)

    stages = (
        riley.ShaderSource(checker, channel),
        riley.ShaderSource(light, parameter),
    )
    resolver = riley.ShaderResolver(
        riley.ResolverKind.modulate,
        slots=(channel,),
        factor=parameter,
    )
    shaders = riley.MeshShaderSet(
        direct=checker,
        mono=riley.ShaderPipe(stages=stages, resolver=resolver),
    )

    mesh = riley.create_mesh(
        convention,
        riley.MeshType.tri3opt,
        coords,
        connect,
        shaders,
    )

    # --------------------------------------------------------------------------
    # 3. Configure and frame the direct and lit cameras
    # --------------------------------------------------------------------------
    pixels_num = (512, 512)
    pixels_size = (0.02, 0.02)
    focal_length = 1.0
    rotation = (0.0, 0.0, 0.0)
    target = riley.roi_cent_from_coords(coords)
    position = riley.pos_frame_mesh(
        mesh,
        pixels_num,
        pixels_size,
        focal_length,
        rotation,
        target=target,
    )

    direct = riley.Camera(
        pixels_num=pixels_num,
        pixels_size=pixels_size,
        pos_world=position,
        rot_world=rotation,
        roi_cent_world=target,
        focal_length=focal_length,
        sub_sample=4,
    )
    lit = riley.Camera(
        pixels_num=pixels_num,
        pixels_size=pixels_size,
        pos_world=position,
        rot_world=rotation,
        roi_cent_world=target,
        focal_length=focal_length,
        sub_sample=4,
        shader_selection=riley.CameraShaderSelection.mono,
    )

    # --------------------------------------------------------------------------
    # 4. Configure the raster engine and render the scene
    # --------------------------------------------------------------------------
    config = riley.RasterConfig(
        parallel=1,
        save_strategy=riley.SaveStrategy.disk,
        image_save_mode=riley.ImageSaveMode.grey,
    )
    config.save_format = riley.ImageFormat.bmp
    config.save_bits = 8
    config.save_scaling = riley.ScaleStrategy.none
    config.output_name_format = "demo7_cam{camera}_frame{frame}_field{field}"

    riley.raster(mesh, (direct, lit), config, out_dir=str(out_dir))


if __name__ == "__main__":
    main()
