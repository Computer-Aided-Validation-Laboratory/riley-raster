# --------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher)
# --------------------------------------------------------------------------
from __future__ import annotations

from dataclasses import replace
from pathlib import Path
from time import perf_counter

import numpy as np
import riley


def main() -> None:
    data_dir = Path("data/calplate/tri3_calplate3d")
    texture_path = Path("texture/cal_target-simple.tiff")
    out_dir = Path("pyout/demo-stereocal")
    dicuq_camera_dir = Path("pyout/demo-dicuq")
    total_threads = 8

    import shutil
    shutil.rmtree(out_dir, ignore_errors=True)
    out_dir.mkdir(parents=True, exist_ok=True)

    coords, connect, uvs, disp = riley.load_sim_from_csv(data_dir)
    texture = riley.load_texture(texture_path)

    camera_0, camera_1 = riley.load_stereo_pair(
        str(dicuq_camera_dir),
        "stereo_data_opengl.csv",
    )
    roi_pos = np.asarray(riley.roi_cent_from_coords(coords), dtype=np.float64)
    target_roi = np.asarray(camera_0.roi_cent_world, dtype=np.float64)
    roi_shift = target_roi - roi_pos
    coords = np.ascontiguousarray(coords + roi_shift, dtype=np.float64)
    roi_pos = riley.roi_cent_from_coords(coords)
    camera_0 = replace(camera_0, roi_cent_world=roi_pos)
    camera_1 = replace(camera_1, roi_cent_world=roi_pos)

    mesh = riley.Mesh(
        mesh_type=riley.MeshType.tri3,
        coords=coords,
        connect=connect,
        disp=disp,
        shader_type=riley.ShaderType.tex,
        uvs=uvs,
        texture=texture,
        sample=riley.TextureSample.cubic_catmull_rom,
        sample_mode=riley.TextureSampleMode.lut_lerp,
        bits=8,
        scaling_type=riley.ScaleStrategy.none,
    )
    config = riley.RasterConfig(
        render_mode=riley.RenderMode.offline,
        total_threads=total_threads,
        save_strategy=riley.SaveStrategy.disk,
        tile_size_min=8,
        tile_size_max=128,
        background_value=128.0,
        report=riley.ReportMode.bench,
    )
    start_time = perf_counter()
    riley.raster(
        [mesh],
        [camera_0, camera_1],
        config,
        out_dir=str(out_dir),
    )
    elapsed_time = perf_counter() - start_time
    print(f"render time: {elapsed_time:.6f} s")
    print(f"rendered stereocal to {out_dir}")


if __name__ == "__main__":
    main()
