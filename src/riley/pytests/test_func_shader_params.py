import numpy as np
import pytest

import riley
from riley.cython import riley as bindings


def test_speckle_builtin_is_appended_without_renumbering() -> None:
    assert bindings.FuncShaderBuiltin.constant == 0
    assert bindings.FuncShaderBuiltin.linear == 1
    assert bindings.FuncShaderBuiltin.quadratic == 2
    assert bindings.FuncShaderBuiltin.sinusoidal == 3
    assert bindings.FuncShaderBuiltin.sinusoidal_approx == 4
    assert bindings.FuncShaderBuiltin.checker == 5
    assert bindings.FuncShaderBuiltin.checker_smooth == 6
    assert bindings.FuncShaderBuiltin.lambertian_normal_z == 7
    assert bindings.FuncShaderBuiltin.eggbox == 8
    assert bindings.FuncShaderBuiltin.speckle == 9


def test_speckle_params_defaults_and_conversion_helper() -> None:
    assert riley.Speckle2DParams is bindings.Speckle2DParams
    assert "Speckle2DParams" in riley.__all__
    speckle = riley.Speckle2DParams()

    assert speckle.seed == 0xA511E9B3
    assert speckle.cells_per_uv == (192.0, 160.0)
    assert speckle.uv_offset == (0.0, 0.0)
    assert speckle.occupancy == 0.9
    assert speckle.radius_mean == 0.45
    assert speckle.radius_jitter == 0.0
    assert speckle.edge_softness == 0.0
    assert speckle.perlin_coverage_threshold == 0.0
    assert speckle.perlin_coverage_transition_width == 0.12
    assert speckle.foreground == 0.0
    assert speckle.background == 1.0
    params = speckle.to_func_shader_params()
    assert isinstance(params, riley.FuncShaderParams)
    assert params.speckle is speckle
    assert bindings.FuncShaderParams().speckle == speckle


@pytest.fixture
def speckle_mesh() -> bindings.Mesh:
    return bindings.Mesh(
        mesh_type=bindings.MeshType.tri3,
        coords=np.array(
            [
                [0.0, 0.0, 0.0],
                [1.0, 0.0, 0.0],
                [0.0, 1.0, 0.0],
            ],
        ),
        connect=np.array([[0, 1, 2]]),
        disp=None,
        shader=bindings.FunctionShader(
            builtin=bindings.FuncShaderBuiltin.speckle,
            coord_mode=bindings.FuncCoordMode.uv,
            uvs=np.array(
                [
                    [0.0, 0.0],
                    [1.0, 0.0],
                    [0.0, 1.0],
                ],
            ),
            params=bindings.Speckle2DParams(
                seed=7,
                cells_per_uv=(12.0, 10.0),
                uv_offset=(0.25, -0.5),
                occupancy=0.75,
                radius_mean=0.4,
                radius_jitter=0.0,
                edge_softness=0.0,
                perlin_coverage_threshold=0.1,
                perlin_coverage_transition_width=0.2,
                foreground=0.1,
                background=0.9,
            ).to_func_shader_params(),
            bits=-1,
            scaling_type=bindings.ScaleStrategy.none,
        ),
    )


def _render_speckle_mesh(mesh: bindings.Mesh) -> np.ndarray:
    camera = bindings.Camera(
        pixels_num=(32, 32),
        pixels_size=(1.0 / 32.0, 1.0 / 32.0),
        pos_world=(0.5, 0.5, 2.0),
        rot_world=(0.0, 0.0, 0.0),
        roi_cent_world=(0.5, 0.5, 0.0),
        focal_length=1.0,
        sub_sample=1,
    )
    config = bindings.RasterConfig(
        save_strategy=bindings.SaveStrategy.memory,
        report=bindings.ReportMode.off,
    )
    image = bindings.raster(mesh, camera, config)
    assert image is not None
    return image


def test_speckle_params_pass_through_mesh_conversion(
    speckle_mesh: bindings.Mesh,
) -> None:
    assert bindings.roi_cent_over_meshes(speckle_mesh) == (0.5, 0.5, 0.0)


def test_speckle_params_render_in_memory(speckle_mesh: bindings.Mesh) -> None:
    image = _render_speckle_mesh(speckle_mesh)

    assert image.shape == (1, 1, 1, 32, 32)
    assert np.isfinite(image).all()
    covered = image[image > 0.0]
    assert covered.size > 0
    assert covered.min() >= 0.1 - 1e-12
    assert covered.max() <= 0.9 + 1e-12
    assert np.ptp(covered) > 0.1

    shader = speckle_mesh.shader
    assert isinstance(shader, bindings.FunctionShader)
    shader.params.speckle.seed = 8
    reseeded = _render_speckle_mesh(speckle_mesh)
    assert not np.array_equal(image, reseeded)


def test_speckle_odd_width_buffer_modes_match(speckle_mesh: bindings.Mesh) -> None:
    camera = bindings.Camera(
        pixels_num=(33, 33),
        pixels_size=(1.0 / 33.0, 1.0 / 33.0),
        pos_world=(0.25, 0.25, 1.0),
        rot_world=(0.0, 0.0, 0.0),
        roi_cent_world=(0.25, 0.25, 0.0),
        focal_length=1.0,
        sub_sample=1,
    )
    images: list[np.ndarray] = []
    for buffer_mode in (
        bindings.BufferMode.tile_local,
        bindings.BufferMode.global_subpx_full,
        bindings.BufferMode.global_subpx_stripe,
    ):
        config = bindings.RasterConfig(
            total_threads=2,
            max_raster_workers_per_job=2,
            save_strategy=bindings.SaveStrategy.memory,
            report=bindings.ReportMode.off,
            buffer_mode=buffer_mode,
            tile_size_override=16,
            global_subpx_tile_size_min=16,
            global_subpx_tile_size_override=16,
            global_subpx_stripe_size_min=16,
            global_subpx_stripe_size_override=16,
        )
        image = bindings.raster(speckle_mesh, camera, config)
        assert image is not None
        assert image.shape == (1, 1, 1, 33, 33)
        assert np.isfinite(image).all()
        images.append(image)

    # The odd-width tail must contain shaded pixels, not just raster background.
    assert np.any(images[0][0, 0, 0, :, -1] > 0.0)
    for image in images[1:]:
        np.testing.assert_allclose(image, images[0], rtol=0.0, atol=1e-12)


# These cases target the default f64/classified-indexed/disk/nine-neighbor binding.
@pytest.mark.parametrize(
    "params",
    [
        pytest.param(
            bindings.Speckle2DParams(cells_per_uv=(0.0, 10.0)), id="cells-u-zero",
        ),
        pytest.param(
            bindings.Speckle2DParams(cells_per_uv=(12.0, -1.0)), id="cells-v-negative",
        ),
        pytest.param(
            bindings.Speckle2DParams(cells_per_uv=(float("nan"), 10.0)),
            id="cells-u-nan",
        ),
        pytest.param(
            bindings.Speckle2DParams(cells_per_uv=(12.0, float("inf"))),
            id="cells-v-infinite",
        ),
        pytest.param(
            bindings.Speckle2DParams(uv_offset=(float("nan"), 0.0)), id="offset-u-nan",
        ),
        pytest.param(
            bindings.Speckle2DParams(uv_offset=(0.0, float("inf"))),
            id="offset-v-infinite",
        ),
        pytest.param(
            bindings.Speckle2DParams(cells_per_uv=(2.0**45, 10.0)),
            id="cells-exceed-coordinate-limit",
        ),
        pytest.param(
            bindings.Speckle2DParams(uv_offset=(-(2.0**45), 0.0)),
            id="offset-below-coordinate-limit",
        ),
        pytest.param(
            bindings.Speckle2DParams(uv_offset=(0.0, 2.0**45)),
            id="offset-above-coordinate-limit",
        ),
        pytest.param(bindings.Speckle2DParams(occupancy=-0.1), id="occupancy-negative"),
        pytest.param(bindings.Speckle2DParams(occupancy=1.1), id="occupancy-above-one"),
        pytest.param(
            bindings.Speckle2DParams(occupancy=float("nan")), id="occupancy-nan",
        ),
        pytest.param(bindings.Speckle2DParams(radius_mean=0.0), id="radius-zero"),
        pytest.param(
            bindings.Speckle2DParams(radius_mean=float("nan")), id="radius-nan",
        ),
        pytest.param(
            bindings.Speckle2DParams(radius_jitter=-0.1), id="jitter-negative",
        ),
        pytest.param(
            bindings.Speckle2DParams(radius_jitter=float("nan")), id="jitter-nan",
        ),
        pytest.param(
            bindings.Speckle2DParams(radius_jitter=0.5), id="jitter-exceeds-radius",
        ),
        pytest.param(
            bindings.Speckle2DParams(radius_mean=0.6, radius_jitter=0.5),
            id="support-exceeds-neighborhood",
        ),
        pytest.param(
            bindings.Speckle2DParams(edge_softness=-0.1), id="softness-negative",
        ),
        pytest.param(
            bindings.Speckle2DParams(edge_softness=float("nan")), id="softness-nan",
        ),
        pytest.param(
            bindings.Speckle2DParams(edge_softness=float("inf")),
            id="softness-infinite",
        ),
        pytest.param(
            bindings.Speckle2DParams(edge_softness=0.01),
            id="classified-indexed-requires-hard-disks",
        ),
        pytest.param(
            bindings.Speckle2DParams(foreground=-0.1), id="foreground-negative",
        ),
        pytest.param(
            bindings.Speckle2DParams(foreground=1.1), id="foreground-above-one",
        ),
        pytest.param(
            bindings.Speckle2DParams(foreground=float("nan")), id="foreground-nan",
        ),
        pytest.param(
            bindings.Speckle2DParams(background=-0.1), id="background-negative",
        ),
        pytest.param(
            bindings.Speckle2DParams(background=1.1), id="background-above-one",
        ),
        pytest.param(
            bindings.Speckle2DParams(background=float("inf")), id="background-infinite",
        ),
    ],
)
def test_speckle_render_rejects_invalid_params(
    speckle_mesh: bindings.Mesh,
    params: bindings.Speckle2DParams,
) -> None:
    shader = speckle_mesh.shader
    assert isinstance(shader, bindings.FunctionShader)
    shader.params.speckle = params

    # Default fast validation maps speckle parameter errors to this public error.
    with pytest.raises(RuntimeError, match="InvalidFuncShaderParams"):
        _render_speckle_mesh(speckle_mesh)
