from __future__ import annotations

import argparse
import shutil
from pathlib import Path

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


def load_csv_f64(path_in: Path) -> np.ndarray:
    return np.loadtxt(path_in, delimiter=",", dtype=np.float64)


def load_csv_uintp(path_in: Path) -> np.ndarray:
    return np.loadtxt(path_in, delimiter=",", dtype=np.uintp)


def load_texture_f64(path_in: Path) -> np.ndarray:
    with Image.open(path_in) as image_in:
        image_grey = image_in.convert("L")
        texture_u8 = np.asarray(image_grey, dtype=np.uint8)
    return np.ascontiguousarray(texture_u8, dtype=np.float64)


def build_demo_inputs(
    save_strategy: riley.SaveStrategy,
) -> tuple[riley.MeshInputTex, riley.CameraInput, riley.RasterConfig]:
    coords = load_csv_f64(DATA_DIR / "coords.csv")
    connect = load_csv_uintp(DATA_DIR / "connect.csv")
    uvs = load_csv_f64(DATA_DIR / "uvs.csv")
    texture = load_texture_f64(TEXTURE_PATH)

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
        save_strategy=save_strategy,
        report=riley.ReportMode.bench,
    )

    return mesh, camera, config


def run_demo(
    save_strategy: riley.SaveStrategy = riley.SaveStrategy.disk,
    out_dir: Path = PYOUT_DIR,
    clean_out_dir: bool = True,
) -> np.ndarray | None:
    if clean_out_dir:
        shutil.rmtree(out_dir, ignore_errors=True)
    out_dir.mkdir(parents=True, exist_ok=True)

    mesh, camera, config = build_demo_inputs(save_strategy)
    return riley.raster(
        mesh,
        camera,
        config,
        out_dir=str(out_dir),
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--save-strategy",
        choices=["disk", "memory", "both", "none"],
        default="disk",
    )
    parser.add_argument(
        "--out-dir",
        default=str(PYOUT_DIR),
    )
    parser.add_argument(
        "--keep-out-dir",
        action="store_true",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    save_strategy = getattr(riley.SaveStrategy, args.save_strategy)
    out_dir = Path(args.out_dir)
    image_array = run_demo(
        save_strategy=save_strategy,
        out_dir=out_dir,
        clean_out_dir=not args.keep_out_dir,
    )
    if image_array is None:
        print(f"rendered disk output to {out_dir}")
    else:
        print(f"rendered image array with shape {image_array.shape} to {out_dir}")


if __name__ == "__main__":
    main()
