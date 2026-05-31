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


DATA_DIR = Path("data/FE/platehole3d_2mr_63f")
TEXTURE_PATH = Path("texture/speckle.bmp")
OUT_DIR = Path("pyout/demo-dicuq")
PIXELS_NUM = (2464, 2056)
PIXELS_SIZE = (3.45e-6, 3.45e-6)
FOCAL_LENGTH = 50.0e-3
FOV_SCALE_FACTOR = 0.65
SUB_SAMPLE = 2
STEREO_ANGLE_DEG = 20.0
TOTAL_THREADS = 8
DISTORTION_KWARGS = {
    "distortion_model": 2,
    "distortion_k1": -0.19,
    "distortion_k2": -1.17,
    "distortion_k3": 25.0,
    "distortion_k4": -0.04,
    "distortion_k5": 0.18,
    "distortion_k6": -0.02,
    "distortion_p1": 0.0004,
    "distortion_p2": -0.0007,
}
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

    mesh = riley.MeshInput(
        mesh_type=riley.MeshType.quad8,
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

    roi_pos = tuple(riley.roi_cent_from_coords(coords))
    camera_0_pos = tuple(
        riley.pos_fill_frame_from_rot(
            coords,
            PIXELS_NUM,
            PIXELS_SIZE,
            FOCAL_LENGTH,
            (0.0, 0.0, 0.0),
            FOV_SCALE_FACTOR,
        ),
    )
    camera_0 = riley.CameraInput(
        pixels_num=PIXELS_NUM,
        pixels_size=PIXELS_SIZE,
        pos_world=camera_0_pos,
        rot_world=(0.0, 0.0, 0.0),
        roi_cent_world=roi_pos,
        focal_length=FOCAL_LENGTH,
        sub_sample=SUB_SAMPLE,
        **DISTORTION_KWARGS,
    )
    camera_1_rot = (0.0, np.deg2rad(STEREO_ANGLE_DEG), 0.0)
    camera_1_pos = tuple(
        riley.pos_fill_frame_from_rot(
            coords,
            PIXELS_NUM,
            PIXELS_SIZE,
            FOCAL_LENGTH,
            camera_1_rot,
            FOV_SCALE_FACTOR,
        ),
    )
    camera_1 = riley.CameraInput(
        pixels_num=PIXELS_NUM,
        pixels_size=PIXELS_SIZE,
        pos_world=camera_1_pos,
        rot_world=camera_1_rot,
        roi_cent_world=roi_pos,
        focal_length=FOCAL_LENGTH,
        sub_sample=SUB_SAMPLE,
        **DISTORTION_KWARGS,
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

    riley.save_stereo_pair(
        str(OUT_DIR),
        "stereo_data_opengl.csv",
        camera_0,
        camera_1,
    )
    riley.save_stereo_pair(
        str(OUT_DIR),
        "stereo_data_opencv.csv",
        replace(camera_0, coord_sys=riley.CameraCoordSys.opencv),
        replace(camera_1, coord_sys=riley.CameraCoordSys.opencv),
    )
    if not SILENT_RENDER:
        print(f"rendered dicuq to {OUT_DIR}")


if __name__ == "__main__":
    main()
