from __future__ import annotations

import shutil
from pathlib import Path

import numpy as np
from PIL import Image


def load_csv_f64(path_in: Path) -> np.ndarray:
    return np.loadtxt(path_in, delimiter=",", dtype=np.float64)


def load_csv_uintp(path_in: Path) -> np.ndarray:
    return np.loadtxt(path_in, delimiter=",", dtype=np.uintp)


def load_texture_grey_f64(path_in: Path) -> np.ndarray:
    with Image.open(path_in) as image_in:
        image_grey = image_in.convert("L")
        image_u8 = np.asarray(image_grey, dtype=np.uint8)
    return np.ascontiguousarray(image_u8, dtype=np.float64)


def copy_coords(coords_in: np.ndarray) -> np.ndarray:
    return np.ascontiguousarray(np.array(coords_in, copy=True), dtype=np.float64)


def ensure_clean_dir(path_in: Path) -> None:
    shutil.rmtree(path_in, ignore_errors=True)
    path_in.mkdir(parents=True, exist_ok=True)


def translate_coords(
    coords_in: np.ndarray,
    translation: tuple[float, float, float],
) -> None:
    coords_in[:, 0] += translation[0]
    coords_in[:, 1] += translation[1]
    coords_in[:, 2] += translation[2]


def find_aligned_centroid(
    coords_in: np.ndarray,
) -> tuple[np.ndarray, np.ndarray]:
    coords_min = np.min(coords_in, axis=0)
    coords_max = np.max(coords_in, axis=0)
    centroid = 0.5 * (coords_min + coords_max)
    extent = coords_max - coords_min
    return centroid, extent
