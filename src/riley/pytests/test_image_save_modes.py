# --------------------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
# --------------------------------------------------------------------------------------
"""Image field layout and explicit colour-conversion tests."""

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
    mesh = riley.create_mesh(
        convention,
        riley.MeshType.tri3,
        coords,
        connect,
        shader,
    )
    camera = riley.Camera(
        pixels_num=(32, 32),
        pixels_size=(1.0 / 32, 1.0 / 32),
        pos_world=(0.0, 0.0, 1.0),
        rot_world=(0.0, 0.0, 0.0),
        roi_cent_world=(0.0, 0.0, 0.0),
        focal_length=1.0,
        sub_sample=1,
    )
    return mesh, camera


def render_memory(
    mesh: riley.Mesh,
    camera: riley.Camera,
    mode: riley.ImageSaveMode,
) -> np.ndarray:
    config = riley.RasterConfig(
        parallel=1,
        save_strategy=riley.SaveStrategy.memory,
        image_save_mode=mode,
        report=riley.ReportMode.off,
    )
    image = riley.raster(mesh, camera, config)
    assert image is not None
    return image


def test_multifield_bmps_match_packed_rgb_channels(tmp_path: Path) -> None:
    mesh, camera = make_scene(3)
    for mode in (riley.ImageSaveMode.rgb, riley.ImageSaveMode.multifield):
        config = riley.RasterConfig(
            parallel=1,
            save_strategy=riley.SaveStrategy.disk,
            image_save_mode=mode,
            save_format=riley.ImageFormat.bmp,
            save_scaling=riley.ScaleStrategy.fixed,
            save_scaling_min=0.0,
            save_scaling_max=1.0,
            background_value=0.0,
            report=riley.ReportMode.off,
        )
        riley.raster(mesh, camera, config, out_dir=str(tmp_path / mode.name))

    rgb_dir = tmp_path / "rgb"
    fields_dir = tmp_path / "multifield"
    names = [f"cam0_frame0_field{channel}.bmp" for channel in range(3)]
    assert sorted(path.name for path in rgb_dir.glob("*.bmp")) == names[:1]
    assert sorted(path.name for path in fields_dir.glob("*.bmp")) == names

    with Image.open(rgb_dir / names[0]) as image:
        assert image.mode == "RGB"
        rgb = np.asarray(image)

    for channel, name in enumerate(names):
        with Image.open(fields_dir / name) as image:
            field = np.asarray(image.convert("L"))
        assert np.any(field > 0), f"{name} contains only background"
        np.testing.assert_array_equal(field, rgb[:, :, channel])


def test_rgb_to_grey_matches_weighted_source_fields() -> None:
    mesh, camera = make_scene(3)
    source = render_memory(mesh, camera, riley.ImageSaveMode.rgb)
    converted = render_memory(mesh, camera, riley.ImageSaveMode.rgb_to_grey)
    assert source.shape == (1, 1, 3, 32, 32)
    assert converted.shape == (1, 1, 1, 32, 32)
    assert np.any(source > 0)
    expected = (
        0.299 * source[:, :, 0]
        + 0.587 * source[:, :, 1]
        + 0.114 * source[:, :, 2]
    )
    np.testing.assert_allclose(converted[:, :, 0], expected, atol=1e-12)


def test_grey_to_rgb_replicates_source_field() -> None:
    mesh, camera = make_scene(1)
    source = render_memory(mesh, camera, riley.ImageSaveMode.grey)
    converted = render_memory(mesh, camera, riley.ImageSaveMode.grey_to_rgb)
    assert source.shape == (1, 1, 1, 32, 32)
    assert converted.shape == (1, 1, 3, 32, 32)
    assert np.any(source > 0)
    for channel in range(3):
        np.testing.assert_array_equal(converted[:, :, channel], source[:, :, 0])


@pytest.mark.parametrize(
    ("channels", "mode"),
    (
        (1, riley.ImageSaveMode.rgb),
        (1, riley.ImageSaveMode.rgb_to_grey),
        (3, riley.ImageSaveMode.grey),
        (3, riley.ImageSaveMode.grey_to_rgb),
    ),
)
def test_incompatible_modes_fail_with_validation(
    channels: int,
    mode: riley.ImageSaveMode,
) -> None:
    mesh, camera = make_scene(channels)
    with pytest.raises(RuntimeError, match="UnsuppedImageModeFieldCount"):
        render_memory(mesh, camera, mode)


@pytest.mark.parametrize(
    ("channels", "mode"),
    (
        (1, riley.ImageSaveMode.grey_to_rgb),
        (3, riley.ImageSaveMode.rgb_to_grey),
    ),
)
def test_disk_save_overlap_matches_synchronous_output(
    tmp_path: Path,
    channels: int,
    mode: riley.ImageSaveMode,
) -> None:
    mesh, camera = make_scene(channels)
    for overlap in (False, True):
        config = riley.RasterConfig(
            parallel=1,
            save_strategy=riley.SaveStrategy.disk,
            image_save_mode=mode,
            disk_save_overlap=overlap,
            report=riley.ReportMode.off,
        )
        out_dir = tmp_path / ("overlap" if overlap else "synchronous")
        riley.raster(mesh, camera, config, out_dir=str(out_dir))

    filename = "cam0_frame0_field0.bmp"
    assert (tmp_path / "synchronous" / filename).read_bytes() == (
        tmp_path / "overlap" / filename
    ).read_bytes()
