"""Public scene inputs and native-boundary ownership regressions."""
from types import SimpleNamespace
import gc
import weakref

import numpy as np
import pytest
import riley

from .test_shaderpipe import scene


def test_camera_framing_requires_only_coordinates() -> None:
    coords = np.array(((-0.5, -0.5, 0), (0.5, -0.5, 0), (0, 0.5, 0)), dtype=float)
    geometry = SimpleNamespace(coords=coords)
    np.testing.assert_array_equal(riley.roi_cent_over_meshes([geometry]), (0, 0, 0))
    args = dict(pixels_num=(32, 32), pixels_size=(1 / 32, 1 / 32),
                focal_length=1.0, rot_world=(0, 0, 0))
    for target in (None, (0.1, 0.2, 0.0)):
        expected = riley.pos_frame_coords(coords, target=target, **args)
        actual = riley.pos_frame_meshes([geometry], target=target, **args)
        np.testing.assert_allclose(actual, expected, atol=1e-12)


@pytest.mark.parametrize("count", (2, 8))
@pytest.mark.parametrize("dtype", (np.uint8, np.uint16, np.float64))
def test_multifield_texture_uses_public_dynamic_texture_input(count, dtype) -> None:
    mesh, camera, config = scene()
    values = np.arange(1, count + 1, dtype=dtype)
    texture = np.broadcast_to(values[:, None, None], (count, 2, 2)).copy()
    source = riley.TextureShader(
        uvs=np.array(((0, 0), (1, 0), (0.5, 1)), dtype=float),
        texture=texture, scaling_type=riley.ScaleStrategy.none,
        sample=riley.TextureSample.linear,
    )
    convention = riley.ConnectConvention(
        riley.EElemType.TRI3, riley.EConnectAxis.ROW, 0, riley.ENodeOrder.RILEY,
    )
    mesh = riley.create_mesh(convention, riley.MeshType.tri3,
                             mesh.coords, mesh.connect,
                             riley.MeshShaderSet(multifield=source))
    camera.render_format = riley.RenderFormat.multifield
    camera.render_channels = count
    image = riley.raster(mesh, camera, config)
    np.testing.assert_array_equal(image[0, 0, :, 16, 16], values)


def test_scene_models_are_ordinary_python_objects() -> None:
    assert riley.Camera.__module__ == 'riley.types'
    assert riley.MeshShaderSet.__module__ == 'riley.types'
    assert not hasattr(riley, 'CameraShaderSelection')
    assert not hasattr(riley, 'ImageSaveMode')
    with pytest.raises(TypeError):
        riley.MeshShaderSet(direct=object())


def test_output_option_descriptors_are_released_on_return_and_error(tmp_path, monkeypatch) -> None:
    mesh, camera, config = scene()
    camera.output_files = [riley.ImageSaveOpts(format=riley.ImageFormat.fimg, file_bits=None)]
    references = []
    empty = np.empty

    def tracked_empty(*args, **kwargs):
        array = empty(*args, **kwargs)
        references.append(weakref.ref(array))
        return array

    monkeypatch.setattr(np, 'empty', tracked_empty)
    for _ in range(3):
        riley.save_camera(str(tmp_path), 'camera.csv', 0, camera)
    camera.background_value = float('nan')
    with pytest.raises(RuntimeError, match='InvalidBackgroundValue'):
        riley.raster(mesh, camera, config)
    gc.collect()
    assert references
    assert all(reference() is None for reference in references)


@pytest.mark.parametrize("performance", (riley.ReportMode.off, riley.ReportMode.bench))
@pytest.mark.parametrize("console", (False, True))
def test_console_and_performance_reporting_are_independent(performance, console, capfd) -> None:
    mesh, camera, config = scene()
    config.report_perf = performance
    config.report_console = console
    capfd.readouterr()
    image = riley.raster(mesh, camera, config)
    captured = capfd.readouterr()
    assert bool((captured.out + captured.err).strip()) == console
    assert image[0, 0, 0, 16, 16] == 0.25


def test_empty_coordinates_fail_at_the_native_boundary() -> None:
    coords = np.empty((0, 3), dtype=np.float64)
    with pytest.raises(RuntimeError, match="InvalidCoordsShape"):
        riley.roi_cent_from_coords(coords)


def test_rgb_source_assigned_after_construction_becomes_an_input_pipe() -> None:
    mesh, camera, config = scene()
    mesh.shaders = riley.MeshShaderSet()
    mesh.shaders.rgb = riley.FunctionShader(
        builtin=riley.FuncShaderBuiltin.constant,
        channels=3, scaling_type=riley.ScaleStrategy.none,
    )
    camera.render_format = riley.RenderFormat.rgb
    image = riley.raster(mesh, camera, config)
    assert isinstance(mesh.shaders.rgb, riley.ShaderPipe)
    np.testing.assert_allclose(image[0, 0, :, 16, 16], (0.2, 0.5, 0.8), atol=1e-12)
