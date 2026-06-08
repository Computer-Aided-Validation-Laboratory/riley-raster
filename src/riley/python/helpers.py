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


def load_sim_from_csv(
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
    uvs = np.loadtxt(
        data_path / "uvs.csv",
        delimiter=",",
        dtype=np.float64,
    )
    disp_x = np.loadtxt(
        data_path / "field_disp_x.csv",
        delimiter=",",
        dtype=np.float64,
    )
    disp_y = np.loadtxt(
        data_path / "field_disp_y.csv",
        delimiter=",",
        dtype=np.float64,
    )
    disp_z = np.loadtxt(
        data_path / "field_disp_z.csv",
        delimiter=",",
        dtype=np.float64,
    )
    disp = np.empty((disp_x.shape[1], disp_x.shape[0], 3), dtype=np.float64)
    disp[:, :, 0] = disp_x.T
    disp[:, :, 1] = disp_y.T
    disp[:, :, 2] = disp_z.T
    return coords, connect, uvs, disp


def load_texture(texture_path: str | Path) -> np.ndarray:
    with Image.open(Path(texture_path)) as image_in:
        image_grey = image_in.convert("L")
        image_u8 = np.asarray(image_grey, dtype=np.uint8)
    return np.ascontiguousarray(image_u8, dtype=np.float64)
