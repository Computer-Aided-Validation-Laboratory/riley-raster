# --------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher)
# --------------------------------------------------------------------------
from __future__ import annotations

from pathlib import Path
from time import perf_counter

import numpy as np
import riley


def main() -> None:
    data_dir = Path("data/bench/tri6_sphere200")
    texture_path = Path("texture/speckle.bmp")
    pyout_dir = Path("pyout/demo-sphere200")
    pixels_num = (800, 500)
    pixels_size = (5.3e-6, 5.3e-6)
    focal_length = 50.0e-3
    rot_world = (0.0, 0.0, 0.0)
    frame_fill = 1.0
    save_strategy = riley.SaveStrategy.disk
    clean_out_dir = True

    import shutil
    if clean_out_dir:
        shutil.rmtree(pyout_dir, ignore_errors=True)
        pyout_dir.mkdir(parents=True, exist_ok=True)
    else:
        pyout_dir.mkdir(parents=True, exist_ok=True)

    coords = np.loadtxt(
        data_dir / "coords.csv",
        delimiter=",",
        dtype=np.float64,
    )
    connect_float = np.loadtxt(
        data_dir / "connect.csv",
        delimiter=",",
        dtype=np.float64,
    )
    connect = np.ascontiguousarray(connect_float, dtype=np.uintp)
    uvs = np.loadtxt(
        data_dir / "uvs.csv",
        delimiter=",",
        dtype=np.float64,
    )
    texture = riley.load_texture(texture_path)

    roi_cent_world = riley.roi_cent_from_coords(coords)
    pos_world = riley.pos_fill_frame_from_rot(
        coords,
        pixels_num,
        pixels_size,
        focal_length,
        rot_world,
        frame_fill,
    )

    mesh = riley.Mesh(
        mesh_type=riley.MeshType.tri6,
        coords=coords,
        connect=connect,
        uvs=uvs,
        texture=texture,
        sample=riley.TextureSample.cubic_catmull_rom,
        sample_mode=riley.TextureSampleMode.lut_lerp,
        bits=8,
        scaling_type=riley.ScaleStrategy.none,
    )
    camera = riley.Camera(
        pixels_num=pixels_num,
        pixels_size=pixels_size,
        pos_world=pos_world,
        rot_world=rot_world,
        roi_cent_world=roi_cent_world,
        focal_length=focal_length,
        sub_sample=2,
        coord_sys=riley.CameraCoordSys.opengl,
    )
    config = riley.build_config(
        num_frames=1,
        total_threads=1,
        save_strategy=save_strategy,
    )
    start_time = perf_counter()
    image_array = riley.raster(
        mesh,
        camera,
        config,
        out_dir=str(pyout_dir),
    )
    elapsed_time = perf_counter() - start_time
    print(f"render time: {elapsed_time:.6f} s")

    if image_array is None:
        print(f"rendered disk output to {pyout_dir}")
    else:
        print(
            f"rendered image array with shape {image_array.shape} "
            f"to {pyout_dir}",
        )


if __name__ == "__main__":
    main()
