from dataclasses import fields, replace

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
        shader=riley.SpeckleShader(
            uvs=np.array([[0.0, 0.0], [1.0, 0.0], [0.0, 1.0]]),
            params=riley.Speckle2DParams(
                seed=7,
                cells_per_uv=(12.0, 10.0),
                occupancy=0.75,
                radius_mean=0.4,
                perlin_coverage_threshold=0.1,
                perlin_coverage_transition_width=0.2,
                foreground=0.1,
                background=0.9,
            ),
            bits=-1,
            scaling_type=riley.ScaleStrategy.none,
        ),
    )


def test_speckle_shader_public_api() -> None:
    from riley.cython import SpeckleShader

    assert SpeckleShader is riley.SpeckleShader
    uvs = np.zeros((3, 2))
    first = riley.SpeckleShader(uvs)
    second = riley.SpeckleShader(uvs)
    assert first.params is not second.params
    assert (first.output_scale, first.output_offset, first.bits, first.scaling_type) == (
        1.0, 0.0, 8, riley.ScaleStrategy.auto,
    )
    assert not hasattr(riley.FuncShaderBuiltin, "speckle")
    assert [int(builtin) for builtin in riley.FuncShaderBuiltin] == list(range(9))
    assert "speckle" not in {field.name for field in fields(riley.FuncShaderParams)}
    assert not hasattr(riley.Speckle2DParams, "to_func_shader_params")
    with pytest.raises(TypeError):
        riley.SpeckleShader()
    with pytest.raises(TypeError):
        riley.FuncShaderParams(speckle=riley.Speckle2DParams())
    for option in ("channels", "normal_type", "builtin", "coord_mode"):
        with pytest.raises(TypeError):
            riley.SpeckleShader(uvs, **{option: 0})


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
    shader.params.pattern = pattern
    image = _render(speckle_mesh)

    assert image.shape == (1, 1, 1, 32, 32)
    assert np.isfinite(image).all()
    covered = image[image > 0.0]
    assert covered.size > 0
    assert covered.min() >= 0.1 - 1e-12
    assert covered.max() <= 0.9 + 1e-12
    assert np.ptp(covered) > 0.1

    if pattern != riley.SpecklePattern.disk:
        shader.params.pattern = riley.SpecklePattern.disk
        disk_image = _render(speckle_mesh)
        assert not np.array_equal(image, disk_image)
        shader.params.pattern = pattern

    shader.params.seed = 8
    reseeded = _render(speckle_mesh)
    assert not np.array_equal(image, reseeded)


@pytest.mark.parametrize("pattern", list(riley.SpecklePattern))
def test_speckle_output_transform(speckle_mesh: riley.Mesh, pattern: riley.SpecklePattern) -> None:
    shader = speckle_mesh.shader
    shader.params.pattern = pattern
    raw = _render(speckle_mesh)
    shader.output_scale = -0.5
    shader.output_offset = 0.8
    transformed = _render(speckle_mesh)
    covered = raw > 0.0
    np.testing.assert_allclose(transformed[covered], raw[covered] * -0.5 + 0.8, rtol=0.0, atol=1e-12)
    np.testing.assert_array_equal(transformed[~covered], 0.0)


@pytest.mark.parametrize("uvs", [None, np.zeros((3, 3)), np.zeros((2, 2)), np.zeros((0, 2))])
def test_speckle_requires_nodal_uvs(speckle_mesh: riley.Mesh, uvs: np.ndarray | None) -> None:
    speckle_mesh.shader.uvs = uvs
    with pytest.raises((ValueError, RuntimeError), match="uvs|UV|Uv|Uvs"):
        _render(speckle_mesh)


@pytest.mark.parametrize("field", ["output_scale", "output_offset"])
@pytest.mark.parametrize("value", [float("nan"), float("inf"), -float("inf")])
def test_speckle_rejects_nonfinite_output_transform(speckle_mesh: riley.Mesh, field: str, value: float) -> None:
    setattr(speckle_mesh.shader, field, value)
    with pytest.raises(RuntimeError, match="InvalidSpeckleShaderParams"):
        _render(speckle_mesh)


@pytest.mark.parametrize("channels", [1, 3])
def test_function_shader_rejects_removed_builtin(speckle_mesh: riley.Mesh, channels: int) -> None:
    speckle_mesh.shader = riley.FunctionShader(builtin=9, channels=channels)
    with pytest.raises(RuntimeError, match="InvalidFuncShaderBuiltin"):
        _render(speckle_mesh)


def test_soft_disks_render_with_default_evaluator(speckle_mesh: riley.Mesh) -> None:
    hard = _render(speckle_mesh)
    shader = speckle_mesh.shader
    shader.params.edge_softness = 0.08
    soft = _render(speckle_mesh)

    assert np.isfinite(soft).all()
    assert not np.array_equal(hard, soft)
    assert np.any((soft > 0.1 + 1e-12) & (soft < 0.9 - 1e-12))


def test_mixed_speckle_patterns_remain_fixed_across_frames(
    speckle_mesh: riley.Mesh,
) -> None:
    template = speckle_mesh.shader
    cases = (
        (riley.SpecklePattern.disk, 0.0, (0.0, 0.0, 0.0)),
        (riley.SpecklePattern.disk, 0.08, (1.25, 0.0, 0.0)),
        (riley.SpecklePattern.gaussian, 0.0, (0.0, 1.25, 0.0)),
        (riley.SpecklePattern.perlin, 0.0, (1.25, 1.25, 0.0)),
    )
    meshes: list[riley.Mesh] = []
    for pattern, softness, offset in cases:
        params = replace(
            template.params, pattern=pattern, edge_softness=softness,
        )
        shader = replace(template, params=params)
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


@pytest.mark.parametrize("pattern", list(riley.SpecklePattern))
def test_speckle_odd_width_buffer_modes_match(
    speckle_mesh: riley.Mesh,
    pattern: riley.SpecklePattern,
) -> None:
    shader = speckle_mesh.shader
    shader.params.pattern = pattern
    images: list[np.ndarray] = []
    for buffer_mode in (
        riley.BufferMode.tile_local,
        riley.BufferMode.global_subpx_full,
        riley.BufferMode.global_subpx_stripe,
    ):
        config = riley.RasterConfig(
            parallel=2,
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


@pytest.mark.parametrize("buffer_mode", list(riley.BufferMode))
@pytest.mark.parametrize("value", [float("nan"), float("inf"), -float("inf")])
def test_speckle_fast_vs_full_uv_payload_validation(
    speckle_mesh: riley.Mesh,
    buffer_mode: riley.BufferMode,
    value: float,
) -> None:
    config = riley.RasterConfig(
        parallel=2,
        save_strategy=riley.SaveStrategy.memory,
        report=riley.ReportMode.off,
        buffer_mode=buffer_mode,
        validate_input=riley.ValidateInput.fast,
    )
    expected = _render(speckle_mesh, config=config)
    shader = speckle_mesh.shader
    # Keep the invalid payload on an unreferenced node: fast validation trusts
    # array contents, but sampling non-finite UVs is outside the render contract.
    speckle_mesh.coords = np.vstack((speckle_mesh.coords, [0.25, 0.25, 0.0]))
    shader.uvs = np.vstack((shader.uvs, [value, value]))
    actual = _render(speckle_mesh, config=config)
    np.testing.assert_array_equal(actual, expected)

    config.validate_input = riley.ValidateInput.full
    with pytest.raises(RuntimeError, match="NonFiniteUvs"):
        _render(speckle_mesh, config=config)

    shader.uvs[-1] = [0.25, 0.25]
    np.testing.assert_array_equal(_render(speckle_mesh, config=config), expected)


@pytest.mark.parametrize("buffer_mode", list(riley.BufferMode))
@pytest.mark.parametrize("pattern", list(riley.SpecklePattern))
def test_mixed_shader_deformation_matches_static_frame_references(
    speckle_mesh: riley.Mesh,
    buffer_mode: riley.BufferMode,
    pattern: riley.SpecklePattern,
) -> None:
    speckle_shader = speckle_mesh.shader
    speckle_shader.params.pattern = pattern
    raw_output = dict(bits=-1, scaling_type=riley.ScaleStrategy.none)
    shaders = (
        speckle_shader,
        riley.TextureShader(
            uvs=speckle_shader.uvs.copy(),
            texture=np.full((1, 4, 4), 0.35),
            **raw_output,
        ),
        riley.NodalShader(field=np.array([[[0.2], [0.5], [0.8]]]), **raw_output),
        riley.FunctionShader(
            builtin=riley.FuncShaderBuiltin.constant,
            params=riley.FuncShaderParams(constant_value=0.65),
            **raw_output,
        ),
    )
    displacements = np.zeros((3, 3, 3))
    displacements[1, 1, 0] = 0.15
    displacements[1, 2, 1] = 0.1
    displacements[2, :, 0] = -0.1
    displacements[2, 2, 0] += 0.12
    offsets = ((0.0, 0.0, 0.0), (1.25, 0.0, 0.0),
               (0.0, 1.25, 0.0), (1.25, 1.25, 0.0))
    meshes = [
        replace(
            speckle_mesh,
            coords=speckle_mesh.coords + np.array(offset),
            disp=displacements.copy(),
            shader=shader,
        )
        for shader, offset in zip(shaders, offsets, strict=True)
    ]
    config = riley.RasterConfig(
        parallel=2,
        save_strategy=riley.SaveStrategy.memory,
        report=riley.ReportMode.off,
        buffer_mode=buffer_mode,
        validate_input=riley.ValidateInput.full,
    )
    render_args = dict(pixels=65, pos_world=(1.125, 1.125, 3.0), config=config)
    actual = _render(meshes, **render_args)
    assert actual.shape == (1, 3, 1, 65, 65)
    assert np.isfinite(actual).all()
    assert not np.array_equal(actual[:, 0], actual[:, 2])

    for frame in range(3):
        expected = np.zeros_like(actual[:, frame:frame + 1])
        for mesh in meshes:
            static_mesh = replace(
                mesh, coords=mesh.coords + displacements[frame], disp=None,
            )
            individual = _render(static_mesh, **render_args)
            assert np.any(individual > 0.0)
            # Meshes remain disjoint under deformation; zero backgrounds add.
            expected += individual
        np.testing.assert_allclose(
            actual[:, frame:frame + 1], expected, rtol=0.0, atol=1e-12,
        )


# Each runtime pattern uses the defaults-only native evaluator policy.
@pytest.mark.parametrize(
    "params",
    [
        pytest.param(
            riley.Speckle2DParams(cells_per_uv=(0.0, 10.0)), id="cells-u-zero",
        ),
        pytest.param(
            riley.Speckle2DParams(cells_per_uv=(float("nan"), 1.0)), id="cells-u-nan",
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
    shader.params = params

    # Default fast validation maps speckle parameter errors to this public error.
    with pytest.raises(RuntimeError, match="InvalidSpeckleShaderParams"):
        _render(speckle_mesh)


@pytest.mark.parametrize("pattern", list(riley.SpecklePattern))
@pytest.mark.parametrize("softness", [-0.1, float("nan")])
def test_every_pattern_rejects_negative_or_nonfinite_softness(
    speckle_mesh: riley.Mesh,
    pattern: riley.SpecklePattern,
    softness: float,
) -> None:
    shader = speckle_mesh.shader
    shader.params.pattern = pattern
    shader.params.edge_softness = softness
    with pytest.raises(RuntimeError, match="InvalidSpeckleShaderParams"):
        _render(speckle_mesh)


@pytest.mark.parametrize("pattern", [-1, 3, 2**32, 0.5])
def test_speckle_binding_rejects_invalid_pattern(
    speckle_mesh: riley.Mesh,
    pattern: int | float,
) -> None:
    shader = speckle_mesh.shader
    shader.params.pattern = pattern
    with pytest.raises(ValueError, match="SpecklePattern"):
        _render(speckle_mesh)
