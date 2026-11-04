from pathlib import Path
import shutil

import numpy as np

import riley


ROOT_DIR = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT_DIR / "data" / "shapes" / "cylinder_surf" / "tri6"
OUT_DIR = ROOT_DIR / "out_riley_py" / "check_cylinders"
PIXELS_NUM = (1024, 1024)
PIXELS_SIZE = (5.3e-6, 5.3e-6)
FOCAL_LENGTH = 50.0e-3


def render_check(
    case_name: str,
    rotation: tuple[float, float, float],
    sub_sample: int,
    use_distortion: bool,
) -> None:
    coords = riley.load_csv(DATA_DIR / "coords.csv")
    connect = riley.load_csv(DATA_DIR / "connect.csv", dtype=np.int64)
    uvs = riley.load_csv(DATA_DIR / "uvs.csv")
    texture = riley.load_texture_mono_u8(
        ROOT_DIR / "texture" / "speck128_mono_u8.png"
    )
    convention = riley.ConnectConvention(
        riley.EElemType.TRI6,
        riley.EConnectAxis.ROW,
        0,
        riley.ENodeOrder.RILEY,
    )
    shaders = (
        (
            "checker",
            riley.FunctionShader(
                builtin=riley.FuncShaderBuiltin.checker,
                coord_mode=riley.FuncCoordMode.world_reference,
                params=riley.FuncShaderParams(coord_scale=(1000.0, 1000.0)),
                channels=1,
                bits=8,
                scaling_type=riley.ScaleStrategy.auto,
            ),
        ),
        (
            "texture",
            riley.TextureShader(
                uvs=uvs,
                texture=texture,
                sample=riley.TextureSample.linear,
                sample_mode=riley.TextureSampleMode.direct,
                bits=8,
                scaling_type=riley.ScaleStrategy.auto,
            ),
        ),
    )
    target = riley.roi_cent_from_coords(coords)
    position = riley.pos_frame_coords(
        coords,
        PIXELS_NUM,
        PIXELS_SIZE,
        FOCAL_LENGTH,
        rotation,
        fov_scale=1.05,
        target=target,
    )
    camera_options = {}
    if use_distortion:
        camera_options = {
            "distort_model": 1,
            "distort_k1": -0.12,
            "distort_k2": 0.035,
            "distort_p1": 0.0002,
            "distort_p2": -0.0001,
        }
    camera = riley.Camera(
        pixels_num=PIXELS_NUM,
        pixels_size=PIXELS_SIZE,
        pos_world=position,
        rot_world=rotation,
        roi_cent_world=target,
        focal_length=FOCAL_LENGTH,
        sub_sample=sub_sample,
        render_format=riley.RenderFormat.mono,
        background_value=127.5,
        output_files=[riley.ImageSaveOpts(format=riley.ImageFormat.bmp, file_bits=8)],
        **camera_options,
    )
    case_dir = OUT_DIR / case_name
    shutil.rmtree(case_dir, ignore_errors=True)
    for shader_name, shader in shaders:
        mesh = riley.create_mesh(
            convention,
            riley.MeshType.tri6,
            coords,
            connect,
            riley.MeshShaderSet(mono=shader),
            normal_type=riley.NormalType.none,
        )
        config = riley.RasterConfig(
            parallel=4,
            save_strategy=riley.SaveStrategy.disk,
        )




        riley.raster(
            mesh,
            camera,
            config,
            out_dir=str(case_dir / shader_name),
        )
