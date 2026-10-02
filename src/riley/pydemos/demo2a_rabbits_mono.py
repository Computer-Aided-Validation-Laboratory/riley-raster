# --------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher)
# --------------------------------------------------------------------------
from __future__ import annotations

import shutil
from pathlib import Path
from time import perf_counter

import riley
from riley.pydemos import demo_rabbits_common as common


def main() -> None:
    # --------------------------------------------------------------------------
    # 1. Setup paths and parameters
    # --------------------------------------------------------------------------
    out_dir = Path.cwd() / "out_riley_py" / "demo2a_rabbits_mono"
    shutil.rmtree(out_dir, ignore_errors=True)
    out_dir.mkdir(parents=True)

    channels = 1
    texture_path = riley.data.speckle_texture_path()
    texture = riley.load_texture_mono_u8(texture_path)

    rabbit_mesh_types = [
        riley.MeshType.tri3,
        riley.MeshType.tri6,
        riley.MeshType.quad4,
        riley.MeshType.quad8,
        riley.MeshType.quad9,
    ]

    # --------------------------------------------------------------------------
    # 2. Build and position rabbit mesh pairs
    # --------------------------------------------------------------------------
    overlap_frac_xy = (0.85, 0.8)
    checker_squares_per_axis = 36.0
    mesh_inputs = common.build_scene(
        texture,
        channels,
        rabbit_mesh_types,
        overlap_frac_xy,
        checker_squares_per_axis,
        gap=(0.18, 0.28, 0.0),
        max_divs=(3, 2, 1),
    )

    # --------------------------------------------------------------------------
    # 4. Position camera and configure raster engine
    # --------------------------------------------------------------------------
    pixels_num = (1600, 800)
    fov_scale = 1.01
    default_pixel_size = (5.3e-6, 5.3e-6)
    default_focal_length = 50.0e-3
    rot_world = (0.0, 0.0, 0.0)

    roi_pos = riley.roi_cent_over_meshes(mesh_inputs)
    cam_pos = riley.pos_frame_meshes(
        mesh_inputs,
        pixels_num,
        default_pixel_size,
        default_focal_length,
        rot_world,
        fov_scale=fov_scale,
    )
    camera = riley.Camera(
        pixels_num=pixels_num,
        pixels_size=default_pixel_size,
        pos_world=cam_pos,
        rot_world=rot_world,
        roi_cent_world=roi_pos,
        focal_length=default_focal_length,
        sub_sample=2,
    )

    background_value = 127.5
    config = riley.create_raster_config(
        num_frames=1,
        total_threads=4,
        save_strategy=riley.SaveStrategy.disk,
    )
    config.image_save_mode = riley.ImageSaveMode.grey
    config.background_value = background_value
    config.save_scaling = riley.ScaleStrategy.none

    # --------------------------------------------------------------------------
    # 5. Render rabbit multi-mesh scene
    # --------------------------------------------------------------------------
    start_time = perf_counter()
    riley.raster(mesh_inputs, [camera], config, out_dir=str(out_dir))
    elapsed_time = perf_counter() - start_time
    print(f"grey render time: {elapsed_time:.6f} s")
    print(f"rendered rabbits to {out_dir}")


if __name__ == "__main__":
    main()
