# --------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher)
# --------------------------------------------------------------------------
from __future__ import annotations

import os
from pathlib import Path
import shutil
from time import perf_counter

import numpy as np
from PIL import Image
import riley

DATA_DIR = Path("data/bench/tri6_sphere200")
TEXTURE_PATH = Path("texture/speckle.bmp")
PYOUT_DIR = Path("pyout/demo-sphere200")
PIXELS_NUM = (800, 500)
PIXELS_SIZE = (5.3e-6, 5.3e-6)
FOCAL_LENGTH = 50.0e-3
ROT_WORLD = (0.0, 0.0, 0.0)
FRAME_FILL = 1.0
SAVE_STRATEGY = riley.SaveStrategy.disk
CLEAN_OUT_DIR = True
SILENT_RENDER = os.environ.get("RILEY_DEMO_SILENT") == "1"


def main() -> None:
    if CLEAN_OUT_DIR:
        shutil.rmtree(PYOUT_DIR, ignore_errors=True)
        PYOUT_DIR.mkdir(parents=True, exist_ok=True)
    else:
        PYOUT_DIR.mkdir(parents=True, exist_ok=True)

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
    with Image.open(TEXTURE_PATH) as image_in:
        image_grey = image_in.convert("L")
        image_u8 = np.asarray(image_grey, dtype=np.uint8)
    texture = np.ascontiguousarray(image_u8, dtype=np.float64)

    roi_cent_world = tuple(riley.roi_cent_from_coords(coords))
    pos_world = tuple(
        riley.pos_fill_frame_from_rot(
            coords,
            PIXELS_NUM,
            PIXELS_SIZE,
            FOCAL_LENGTH,
            ROT_WORLD,
            FRAME_FILL,
        ),
    )

    mesh = riley.MeshInputTex(
        mesh_type=riley.MeshType.tri6,
        coords=coords,
        connect=connect,
        uvs=uvs,
        texture=texture,
        sample=riley.TextureSample.cubic_catmull_rom,
        sample_mode=riley.TextureSampleMode.lut_lerp,
        bits=8,
        scaling_tag=riley.ScaleStrategy.none,
    )
    camera = riley.CameraInput(
        pixels_num=PIXELS_NUM,
        pixels_size=PIXELS_SIZE,
        pos_world=pos_world,
        rot_world=ROT_WORLD,
        roi_cent_world=roi_cent_world,
        focal_length=FOCAL_LENGTH,
        sub_sample=2,
        coord_sys=riley.CameraCoordSys.opengl,
    )
    config = riley.RasterConfig(
        save_strategy=SAVE_STRATEGY,
        report=(
            riley.ReportMode.off
            if SILENT_RENDER
            else riley.ReportMode.bench
        ),
    )
    start_time = perf_counter()
    image_array = riley.raster(
        mesh,
        camera,
        config,
        out_dir=str(PYOUT_DIR),
    )
    elapsed_time = perf_counter() - start_time
    if not SILENT_RENDER:
        print(f"render time: {elapsed_time:.6f} s")

    if image_array is None:
        if not SILENT_RENDER:
            print(f"rendered disk output to {PYOUT_DIR}")
    else:
        if not SILENT_RENDER:
            print(
                f"rendered image array with shape {image_array.shape} "
                f"to {PYOUT_DIR}",
            )


if __name__ == "__main__":
    main()
