from __future__ import annotations

from dataclasses import replace
from pathlib import Path

import numpy as np

import riley

from demo_common import (
    ensure_clean_dir,
    load_csv_f64,
    load_csv_uintp,
    load_texture_grey_f64,
)


DATA_DIR = Path("data/calplate/tri3_calplate3d")
TEXTURE_PATH = Path("texture/cal_target-simple.tiff")
OUT_DIR = Path("pyout/demo-stereocal")
DICUQ_CAMERA_DIR = Path("pyout/demo-dicuq")
TOTAL_THREADS = 8


def load_disp_field() -> np.ndarray:
    disp_x = load_csv_f64(DATA_DIR / "field_disp_x.csv")
    disp_y = load_csv_f64(DATA_DIR / "field_disp_y.csv")
    disp_z = load_csv_f64(DATA_DIR / "field_disp_z.csv")
    field = np.empty((disp_x.shape[1], disp_x.shape[0], 3), dtype=np.float64)
    field[:, :, 0] = disp_x.T
    field[:, :, 1] = disp_y.T
    field[:, :, 2] = disp_z.T
    return field


def run_demo(
    out_dir: Path = OUT_DIR,
    camera_dir: Path = DICUQ_CAMERA_DIR,
) -> np.ndarray | None:
    ensure_clean_dir(out_dir)
    coords = load_csv_f64(DATA_DIR / "coords.csv")
    connect = load_csv_uintp(DATA_DIR / "connect.csv")
    uvs = load_csv_f64(DATA_DIR / "uvs.csv")
    disp = load_disp_field()
    texture = load_texture_grey_f64(TEXTURE_PATH)

    camera_0, camera_1 = riley.load_stereo_pair(
        str(camera_dir),
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
        report=riley.ReportMode.off,
    )
    return riley.raster(
        [mesh],
        [camera_0, camera_1],
        config,
        out_dir=str(out_dir),
    )


def main() -> None:
    run_demo()
    print(f"rendered stereocal to {OUT_DIR}")


if __name__ == "__main__":
    main()
