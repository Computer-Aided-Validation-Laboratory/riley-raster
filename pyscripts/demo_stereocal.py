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
import os
from pathlib import Path
import shutil
from time import perf_counter

import numpy as np
from PIL import Image

import riley


DATA_DIR = Path("data/calplate/tri3_calplate3d")
TEXTURE_PATH = Path("texture/cal_target-simple.tiff")
OUT_DIR = Path("pyout/demo-stereocal")
DICUQ_CAMERA_DIR = Path("pyout/demo-dicuq")
TOTAL_THREADS = 8
SILENT_RENDER = os.environ.get("RILEY_DEMO_SILENT") == "1"


def main() -> None:
    shutil.rmtree(OUT_DIR, ignore_errors=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    coords = np.loadtxt(
        DATA_DIR / "coords.csv",
        delimiter=",",
        dtype=np.float64,
    )
    connect_float = np.loadtxt(
        DATA_DIR / "connect.csv",
        delimiter=",",
        dtype=np.float64,
    )
    connect = np.ascontiguousarray(connect_float, dtype=np.uintp)
    uvs = np.loadtxt(
        DATA_DIR / "uvs.csv",
        delimiter=",",
        dtype=np.float64,
    )
    disp_x = np.loadtxt(
        DATA_DIR / "field_disp_x.csv",
        delimiter=",",
        dtype=np.float64,
    )
    disp_y = np.loadtxt(
        DATA_DIR / "field_disp_y.csv",
        delimiter=",",
        dtype=np.float64,
    )
    disp_z = np.loadtxt(
        DATA_DIR / "field_disp_z.csv",
        delimiter=",",
        dtype=np.float64,
    )
    disp = np.empty((disp_x.shape[1], disp_x.shape[0], 3), dtype=np.float64)
    disp[:, :, 0] = disp_x.T
    disp[:, :, 1] = disp_y.T
    disp[:, :, 2] = disp_z.T
    with Image.open(TEXTURE_PATH) as image_in:
        image_grey = image_in.convert("L")
        image_u8 = np.asarray(image_grey, dtype=np.uint8)
    texture = np.ascontiguousarray(image_u8, dtype=np.float64)

    camera_0, camera_1 = riley.load_stereo_pair(
        str(DICUQ_CAMERA_DIR),
        "stereo_data_opengl.csv",
    )
    roi_pos = np.asarray(riley.roi_cent_from_coords(coords), dtype=np.float64)
    target_roi = np.asarray(camera_0.roi_cent_world, dtype=np.float64)
    roi_shift = target_roi - roi_pos
    coords = np.ascontiguousarray(coords + roi_shift, dtype=np.float64)
    roi_pos = tuple(riley.roi_cent_from_coords(coords))
    camera_0 = replace(camera_0, roi_cent_world=roi_pos)
    camera_1 = replace(camera_1, roi_cent_world=roi_pos)

    mesh = riley.MeshInput(
        mesh_type=riley.MeshType.tri3,
        coords=coords,
        connect=connect,
        disp=disp,
        shader_tag=riley.ShaderType.tex,
        uvs=uvs,
        texture=texture,
        sample=riley.TextureSample.cubic_catmull_rom,
        sample_mode=riley.TextureSampleMode.lut_lerp,
        bits=8,
        scaling_tag=riley.ScaleStrategy.none,
    )
    config = riley.RasterConfig(
        render_mode=riley.RenderMode.offline,
        total_threads=TOTAL_THREADS,
        save_strategy=riley.SaveStrategy.disk,
        tile_size_min=8,
        tile_size_max=128,
        background_value=128.0,
        report=(
            riley.ReportMode.off
            if SILENT_RENDER
            else riley.ReportMode.bench
        ),
    )
    start_time = perf_counter()
    riley.raster(
        [mesh],
        [camera_0, camera_1],
        config,
        out_dir=str(OUT_DIR),
    )
    elapsed_time = perf_counter() - start_time
    if not SILENT_RENDER:
        print(f"render time: {elapsed_time:.6f} s")
        print(f"rendered stereocal to {OUT_DIR}")


if __name__ == "__main__":
    main()
