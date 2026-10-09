from dataclasses import replace

import numpy as np
import pytest

import riley


@pytest.fixture
def speckle_mesh() -> riley.Mesh:
    return riley.Mesh(
        mesh_type=riley.MeshType.tri3,
        coords=np.array([[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0]]),
        connect=np.array([[0, 1, 2]]),
        disp=None,
        shader=riley.FunctionShader(
            builtin=riley.FuncShaderBuiltin.speckle,
            coord_mode=riley.FuncCoordMode.uv,
            uvs=np.array([[0.0, 0.0], [1.0, 0.0], [0.0, 1.0]]),
            params=riley.Speckle2DParams(
                seed=7,
                cells_per_uv=(12.0, 10.0),
                uv_offset=(0.25, -0.5),
                occupancy=0.75,
                radius_mean=0.4,
                perlin_coverage_threshold=0.1,
                perlin_coverage_transition_width=0.2,
                foreground=0.1,
                background=0.9,
            ).to_func_shader_params(),
            bits=-1,
            scaling_type=riley.ScaleStrategy.none,
        ),
    )


def _render(
    meshes: riley.Mesh | list[riley.Mesh],
    *,
    pixels: int = 32,
    pos_world: tuple[float, float, float] = (0.5, 0.5, 2.0),
    config: riley.RasterConfig | None = None,
) -> np.ndarray:
    camera = riley.Camera(
        pixels_num=(pixels, pixels),
        pixels_size=(1.0 / pixels, 1.0 / pixels),
        pos_world=pos_world,
        rot_world=(0.0, 0.0, 0.0),
        roi_cent_world=(pos_world[0], pos_world[1], 0.0),
        focal_length=1.0,
        sub_sample=1,
    )
    if config is None:
        config = riley.RasterConfig(
            save_strategy=riley.SaveStrategy.memory,
            report=riley.ReportMode.off,
        )
    image = riley.raster(meshes, camera, config)
    assert image is not None
    return image


@pytest.mark.parametrize("pattern", list(riley.SpecklePattern))
def test_speckle_params_render_in_memory(
    speckle_mesh: riley.Mesh,
    pattern: riley.SpecklePattern,
) -> None:
    shader = speckle_mesh.shader
    assert isinstance(shader, riley.FunctionShader)
    shader.params.speckle.pattern = pattern
    image = _render(speckle_mesh)

    assert image.shape == (1, 1, 1, 32, 32)
    assert np.isfinite(image).all()
    covered = image[image > 0.0]
    assert covered.size > 0
    assert covered.min() >= 0.1 - 1e-12
    assert covered.max() <= 0.9 + 1e-12
    assert np.ptp(covered) > 0.1

    if pattern != riley.SpecklePattern.disk:
        shader.params.speckle.pattern = riley.SpecklePattern.disk
        disk_image = _render(speckle_mesh)
        assert not np.array_equal(image, disk_image)
        shader.params.speckle.pattern = pattern

    shader.params.speckle.seed = 8
    reseeded = _render(speckle_mesh)
    assert not np.array_equal(image, reseeded)


def test_soft_disks_render_with_default_evaluator(speckle_mesh: riley.Mesh) -> None:
    hard = _render(speckle_mesh)
    shader = speckle_mesh.shader
    assert isinstance(shader, riley.FunctionShader)
    shader.params.speckle.edge_softness = 0.08
    soft = _render(speckle_mesh)

    assert np.isfinite(soft).all()
    assert not np.array_equal(hard, soft)
    assert np.any((soft > 0.1 + 1e-12) & (soft < 0.9 - 1e-12))


def test_mixed_speckle_patterns_remain_fixed_across_frames(
    speckle_mesh: riley.Mesh,
) -> None:
    template = speckle_mesh.shader
    assert isinstance(template, riley.FunctionShader)
    cases = (
        (riley.SpecklePattern.disk, 0.0, (0.0, 0.0, 0.0)),
        (riley.SpecklePattern.disk, 0.08, (1.25, 0.0, 0.0)),
        (riley.SpecklePattern.gaussian, 0.0, (0.0, 1.25, 0.0)),
        (riley.SpecklePattern.perlin, 0.0, (1.25, 1.25, 0.0)),
    )
    meshes: list[riley.Mesh] = []
    for pattern, softness, offset in cases:
        params = replace(
            template.params.speckle, pattern=pattern, edge_softness=softness,
        )
        shader = replace(template, params=params.to_func_shader_params())
        meshes.append(
            replace(
                speckle_mesh,
                coords=speckle_mesh.coords + np.array(offset),
                # Two identical displacement frames must reuse the same pattern.
                disp=np.zeros((2, speckle_mesh.coords.shape[0], 3)),
                shader=shader,
            ),
        )
    mixed = _render(meshes, pixels=64, pos_world=(1.125, 1.125, 3.0))
    assert mixed.shape == (1, 2, 1, 64, 64)
    assert np.isfinite(mixed).all()
    np.testing.assert_array_equal(mixed[:, 0], mixed[:, 1])

    expected = np.zeros_like(mixed)
    for mesh in meshes:
        individual = _render(mesh, pixels=64, pos_world=(1.125, 1.125, 3.0))
        assert np.any(individual > 0.0)
        np.testing.assert_array_equal(individual[:, 0], individual[:, 1])
        # These meshes do not overlap and the raster background is zero.
        expected += individual
    np.testing.assert_allclose(mixed, expected, rtol=0.0, atol=1e-12)


def test_speckle_odd_width_buffer_modes_match(speckle_mesh: riley.Mesh) -> None:
    images: list[np.ndarray] = []
    for buffer_mode in (
        riley.BufferMode.tile_local,
        riley.BufferMode.global_subpx_full,
        riley.BufferMode.global_subpx_stripe,
    ):
        config = riley.RasterConfig(
            total_threads=2,
            max_raster_workers_per_job=2,
            save_strategy=riley.SaveStrategy.memory,
            report=riley.ReportMode.off,
            buffer_mode=buffer_mode,
            tile_size_override=16,
            global_subpx_tile_size_min=16,
            global_subpx_tile_size_override=16,
            global_subpx_stripe_size_min=16,
            global_subpx_stripe_size_override=16,
        )
        image = _render(
            speckle_mesh, pixels=33, pos_world=(0.25, 0.25, 1.0), config=config,
        )
        assert image.shape == (1, 1, 1, 33, 33)
        assert np.isfinite(image).all()
        images.append(image)

    # The odd-width tail must contain shaded pixels, not just raster background.
    assert np.any(images[0][0, 0, 0, :, -1] > 0.0)
    for image in images[1:]:
        np.testing.assert_allclose(image, images[0], rtol=0.0, atol=1e-12)


# Each runtime pattern uses the defaults-only native evaluator policy.
@pytest.mark.parametrize(
    "params",
    [
        pytest.param(
            riley.Speckle2DParams(cells_per_uv=(0.0, 10.0)), id="cells-u-zero",
        ),
        pytest.param(
            riley.Speckle2DParams(uv_offset=(float("nan"), 0.0)), id="offset-u-nan",
        ),
        pytest.param(
            riley.Speckle2DParams(cells_per_uv=(2.0**45, 10.0)),
            id="cells-exceed-coordinate-limit",
        ),
        pytest.param(riley.Speckle2DParams(occupancy=-0.1), id="occupancy-negative"),
        pytest.param(riley.Speckle2DParams(radius_mean=0.0), id="radius-zero"),
        pytest.param(
            riley.Speckle2DParams(radius_jitter=0.5), id="jitter-exceeds-radius",
        ),
        pytest.param(
            riley.Speckle2DParams(radius_mean=0.6, radius_jitter=0.5),
            id="support-exceeds-neighborhood",
        ),
        pytest.param(
            riley.Speckle2DParams(
                pattern=riley.SpecklePattern.gaussian, edge_softness=0.01,
            ),
            id="gaussian-requires-zero-softness",
        ),
        pytest.param(
            riley.Speckle2DParams(
                pattern=riley.SpecklePattern.perlin, edge_softness=0.01,
            ),
            id="perlin-requires-zero-softness",
        ),
        pytest.param(
            riley.Speckle2DParams(
                pattern=riley.SpecklePattern.perlin,
                perlin_coverage_threshold=float("nan"),
            ),
            id="perlin-threshold-nan",
        ),
        pytest.param(
            riley.Speckle2DParams(
                pattern=riley.SpecklePattern.perlin,
                perlin_coverage_transition_width=-0.1,
            ),
            id="perlin-transition-negative",
        ),
        pytest.param(
            riley.Speckle2DParams(
                pattern=riley.SpecklePattern.perlin,
                perlin_coverage_transition_width=float("inf"),
            ),
            id="perlin-transition-infinite",
        ),
        pytest.param(riley.Speckle2DParams(foreground=1.1), id="foreground-above-one"),
        pytest.param(
            riley.Speckle2DParams(background=float("inf")), id="background-infinite",
        ),
    ],
)
def test_speckle_render_rejects_invalid_params(
    speckle_mesh: riley.Mesh,
    params: riley.Speckle2DParams,
) -> None:
    shader = speckle_mesh.shader
    assert isinstance(shader, riley.FunctionShader)
    shader.params.speckle = params

    # Default fast validation maps speckle parameter errors to this public error.
    with pytest.raises(RuntimeError, match="InvalidFuncShaderParams"):
        _render(speckle_mesh)


@pytest.mark.parametrize("pattern", list(riley.SpecklePattern))
@pytest.mark.parametrize("softness", [-0.1, float("nan")])
def test_every_pattern_rejects_negative_or_nonfinite_softness(
    speckle_mesh: riley.Mesh,
    pattern: riley.SpecklePattern,
    softness: float,
) -> None:
    shader = speckle_mesh.shader
    assert isinstance(shader, riley.FunctionShader)
    shader.params.speckle.pattern = pattern
    shader.params.speckle.edge_softness = softness
    with pytest.raises(RuntimeError, match="InvalidFuncShaderParams"):
        _render(speckle_mesh)


@pytest.mark.parametrize("pattern", [-1, 3, 2**32, 0.5])
def test_speckle_binding_rejects_invalid_pattern(
    speckle_mesh: riley.Mesh,
    pattern: int | float,
) -> None:
    shader = speckle_mesh.shader
    assert isinstance(shader, riley.FunctionShader)
    shader.params.speckle.pattern = pattern
    with pytest.raises(ValueError, match="SpecklePattern"):
        _render(speckle_mesh)
