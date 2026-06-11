# --------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher)
# --------------------------------------------------------------------------
import numpy as np
from pathlib import Path
from PIL import Image


def load_sim_csvs(
    data_dir: str | Path,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    data_path = Path(data_dir)

    coords = np.loadtxt(
        data_path / "coords.csv",
        delimiter=",",
        dtype=np.float64,
    )
    connect_float = np.loadtxt(
        data_path / "connect.csv",
        delimiter=",",
        dtype=np.float64,
    )
    connect = np.ascontiguousarray(connect_float, dtype=np.uintp)

    uvs = None
    if (data_path / "uvs.csv").is_file():
        uvs = np.loadtxt(
            data_path / "uvs.csv",
            delimiter=",",
            dtype=np.float64,
        )

    disp_shape = None

    disp_x = None
    if (data_path / "field_disp_x.csv").is_file():
        disp_x = np.loadtxt(
            data_path / "field_disp_x.csv",
            delimiter=",",
            dtype=np.float64,
        )
        disp_shape = disp_x.shape

    disp_y = None
    if (data_path / "field_disp_y.csv").is_file():
        disp_y = np.loadtxt(
            data_path / "field_disp_y.csv",
            delimiter=",",
            dtype=np.float64,
        )
        disp_shape = disp_y.shape

    disp_z = None
    if (data_path / "field_disp_z.csv").is_file():
        disp_z = np.loadtxt(
            data_path / "field_disp_z.csv",
            delimiter=",",
            dtype=np.float64,
        )
        disp_shape = disp_z.shape

    disp = None
    if disp_shape is not None:    
        disp = np.zeros((disp_shape[1], disp_shape[0], 3), 
            dtype=np.float64)
        if disp_x is not None:
            disp[:, :, 0] = disp_x.T
        if disp_y is not None:
            disp[:, :, 1] = disp_y.T
        if disp_z is not None:
            disp[:, :, 2] = disp_z.T

    return coords, connect, uvs, disp


def load_texture(texture_path: str | Path) -> np.ndarray:
    with Image.open(Path(texture_path)) as image_in:
        image_grey = image_in.convert("L")
        image_u8 = np.asarray(image_grey, dtype=np.uint8)
    return np.ascontiguousarray(image_u8, dtype=np.float64)


def build_config(
    num_frames: int,
    total_threads: int = 1,
    save_strategy: int = 2,  # both
) -> "RasterConfig":
    from riley.cyth.riley import RasterConfig

    total_threads = max(1, int(total_threads))
    frames_available = max(1, int(num_frames))
    if total_threads < frames_available:
        render_group_count = total_threads
    else:
        render_group_count = 1
        for group_count in range(1, frames_available + 1):
            if total_threads % group_count == 0:
                render_group_count = group_count
    workers_per_group = total_threads // render_group_count

    return RasterConfig(
        render_mode=1,  # offline
        total_threads=total_threads,
        geom_scheduling_mode=0,  # spread
        max_raster_workers_per_job=workers_per_group,
        save_strategy=save_strategy,
        image_mode=0,  # grey
        subpixel_center_map=1,  # per_tile
        report=1,  # bench
    )
