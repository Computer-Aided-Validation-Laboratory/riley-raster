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
DISTORTION = True


def load_disp_field() -> np.ndarray:
    disp_x = load_csv_f64(DATA_DIR / "field_disp_x.csv")
    disp_y = load_csv_f64(DATA_DIR / "field_disp_y.csv")
    disp_z = load_csv_f64(DATA_DIR / "field_disp_z.csv")
    field = np.empty((disp_x.shape[1], disp_x.shape[0], 3), dtype=np.float64)
    field[:, :, 0] = disp_x.T
    field[:, :, 1] = disp_y.T
    field[:, :, 2] = disp_z.T
    return field


def build_distortion() -> dict[str, float]:
    if not DISTORTION:
        return {}
    return {
        "distortion_model": 1,
        "distortion_k1": -0.19,
        "distortion_k2": -1.17,
        "distortion_k3": 25.0,
        "distortion_p1": 0.0004,
        "distortion_p2": -0.0007,
    }


def build_camera(
    roi_pos: tuple[float, float, float],
    rot_world: tuple[float, float, float],
    coords: np.ndarray,
) -> riley.CameraInput:
    pos_world = tuple(
        riley.pos_fill_frame_from_rot(
            coords,
            PIXELS_NUM,
            PIXELS_SIZE,
            FOCAL_LENGTH,
            rot_world,
            FOV_SCALE_FACTOR,
        ),
    )
    return riley.CameraInput(
        pixels_num=PIXELS_NUM,
        pixels_size=PIXELS_SIZE,
        pos_world=pos_world,
        rot_world=rot_world,
        roi_cent_world=roi_pos,
        focal_length=FOCAL_LENGTH,
        sub_sample=SUB_SAMPLE,
        **build_distortion(),
    )


def run_demo(out_dir: Path = OUT_DIR) -> np.ndarray | None:
    ensure_clean_dir(out_dir)
    coords = load_csv_f64(DATA_DIR / "coords.csv")
    connect = load_csv_uintp(DATA_DIR / "connect.csv")
    uvs = load_csv_f64(DATA_DIR / "uvs.csv")
    disp = load_disp_field()
    texture = load_texture_grey_f64(TEXTURE_PATH)

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
    camera_0 = build_camera(roi_pos, (0.0, 0.0, 0.0), coords)
    camera_1 = build_camera(
        roi_pos,
        (0.0, np.deg2rad(STEREO_ANGLE_DEG), 0.0),
        coords,
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

    image_array = riley.raster(
        [mesh],
        [camera_0, camera_1],
        config,
        out_dir=str(out_dir),
    )

    riley.save_stereo_pair(
        str(out_dir),
        "stereo_data_opengl.csv",
        camera_0,
        camera_1,
    )
    riley.save_stereo_pair(
        str(out_dir),
        "stereo_data_opencv.csv",
        replace(camera_0, coord_sys=riley.CameraCoordSys.opencv),
        replace(camera_1, coord_sys=riley.CameraCoordSys.opencv),
    )
    return image_array


def main() -> None:
    run_demo()
    print(f"rendered dicuq to {OUT_DIR}")


if __name__ == "__main__":
    main()
