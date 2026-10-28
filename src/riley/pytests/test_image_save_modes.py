"""Image field layout, camera save options, and disk-overlap tests."""

from dataclasses import replace
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

import riley


def make_scene(channels: int) -> tuple[riley.Mesh, riley.Camera]:
    coords = np.array(
        ((-0.5, -0.5, 0.0), (0.5, -0.5, 0.0), (0.0, 0.5, 0.0)),
        dtype=np.float64,
    )
    connect = np.array(((0, 1, 2),), dtype=np.int64)
    convention = riley.ConnectConvention(
        riley.EElemType.TRI3,
        riley.EConnectAxis.ROW,
        0,
        riley.ENodeOrder.RILEY,
    )
    shader = riley.FunctionShader(
        builtin=riley.FuncShaderBuiltin.constant,
        params=riley.FuncShaderParams(
            constant_value=0.25,
            constant_value_rgb=(0.2, 0.5, 0.8),
        ),
        channels=channels,
        scaling_type=riley.ScaleStrategy.none,
    )
    shaders = (
        riley.MeshShaderSet(rgb=shader)
        if channels == 3
        else riley.MeshShaderSet(mono=shader)
    )
    mesh = riley.create_mesh(
        convention,
        riley.MeshType.tri3,
        coords,
        connect,
        shaders,
    )
    render_format = (
        riley.RenderFormat.rgb if channels == 3 else riley.RenderFormat.mono
    )
    camera = riley.Camera(
        pixels_num=(32, 32),
        pixels_size=(1.0 / 32, 1.0 / 32),
        pos_world=(0.0, 0.0, 1.0),
        rot_world=(0.0, 0.0, 0.0),
        roi_cent_world=(0.0, 0.0, 0.0),
        focal_length=1.0,
        sub_sample=1,
        render_format=render_format,
        output_files=[
            riley.ImageSaveOpts(
                format=3,
                file_bits=8,
                scaling=0,
            )
        ],
    )
    return mesh, camera


def render_memory(mesh: riley.Mesh, camera: riley.Camera) -> np.ndarray:
    config = riley.RasterConfig(
        parallel=1,
        save_strategy=riley.SaveStrategy.memory,
        report=riley.ReportMode.off,
    )
    image = riley.raster(mesh, camera, config)
    assert image is not None
    return image


def test_rgb_camera_renders_three_channels() -> None:
    mesh, camera = make_scene(3)
    image = render_memory(mesh, camera)
    assert image.shape == (1, 1, 3, 32, 32)
    assert np.any(image > 0)


def test_mono_camera_renders_single_channel() -> None:
    mesh, camera = make_scene(1)
    image = render_memory(mesh, camera)
    assert image.shape == (1, 1, 1, 32, 32)
    assert np.any(image > 0)


@pytest.mark.parametrize(
    ("channels", "incompatible_format"),
    (
        (1, riley.RenderFormat.rgb),
        (3, riley.RenderFormat.mono),
    ),
)
def test_incompatible_camera_format_fails(
    channels: int,
    incompatible_format: riley.RenderFormat,
) -> None:
    mesh, camera = make_scene(channels)
    bad_camera = replace(camera, render_format=incompatible_format)
    with pytest.raises(RuntimeError, match="NoCompatibleShader"):
        render_memory(mesh, bad_camera)


@pytest.mark.parametrize("channels", (1, 3))
def test_disk_save_overlap_matches_synchronous_output(
    tmp_path: Path,
    channels: int,
) -> None:
    mesh, camera = make_scene(channels)
    for overlap in (False, True):
        config = riley.RasterConfig(
            parallel=1,
            save_strategy=riley.SaveStrategy.disk,
            disk_save_overlap=overlap,
            report=riley.ReportMode.off,
        )
        out_dir = tmp_path / ("overlap" if overlap else "synchronous")
        riley.raster(mesh, camera, config, out_dir=str(out_dir))

    filename = "cam0_frame0_field0.bmp"
    sync_bytes = (tmp_path / "synchronous" / filename).read_bytes()
    overlap_bytes = (tmp_path / "overlap" / filename).read_bytes()
    assert sync_bytes == overlap_bytes


def test_float_csv_and_packed_tiff_from_one_camera(tmp_path: Path) -> None:
    mesh, camera = make_scene(1)
    camera = replace(
        camera,
        output_files=[
            riley.ImageSaveOpts(format=riley.ImageFormat.csv, file_bits=None),
            riley.ImageSaveOpts(
                format=riley.ImageFormat.tiff,
                file_bits=16,
                adc_bits=12,
                scaling=riley.ScaleStrategy.fixed,
                scaling_min=0.0,
                scaling_max=1.0,
                packing=riley.CodePacking.upper,
            ),
        ],
    )
    config = riley.RasterConfig(
        parallel=1,
        save_strategy=riley.SaveStrategy.both,
        report=riley.ReportMode.off,
    )
    image = riley.raster(mesh, camera, config, out_dir=str(tmp_path))
    assert image is not None
    raw = image[0, 0, 0]
    csv = np.loadtxt(tmp_path / "cam0_frame0_field0.csv", delimiter=",")
    tiff = np.asarray(Image.open(tmp_path / "cam0_frame0_field0.tiff"))
    np.testing.assert_allclose(csv, raw, atol=1e-6)
    expected = np.rint(np.clip(raw, 0, 1) * 4095).astype(np.uint16) << 4
    np.testing.assert_array_equal(tiff, expected)
