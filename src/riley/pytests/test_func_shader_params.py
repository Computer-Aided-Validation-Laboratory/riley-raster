from dataclasses import fields, replace

import numpy as np
import pytest

import riley


PATTERNS = (*riley.SpecklePattern, "perlin")


def _params(pattern: riley.SpecklePattern | str) -> riley.Speckle2DParams | riley.Perlin2DParams:
    colors = dict(seed=7, foreground=0.1, background=0.9)
    if pattern == "perlin":
        return riley.Perlin2DParams(
            cell_size=0.08, threshold=0.1, transition_width=0.2, **colors,
        )
    return riley.Speckle2DParams(
        coverage=0.35, radius=0.04, occupancy=0.75, pattern=pattern, **colors,
    )


@pytest.fixture
def speckle_mesh() -> riley.Mesh:
    return riley.Mesh(
        mesh_type=riley.MeshType.tri3,
        coords=np.array([[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0]]),
        connect=np.array([[0, 1, 2]]),
        disp=None,
        shader=riley.SpeckleShader(
            uvs=np.array([[0.0, 0.0], [1.0, 0.0], [0.0, 1.0]]),
            params=_params(riley.SpecklePattern.disk),
            bits=-1,
            scaling_type=riley.ScaleStrategy.none,
        ),
    )


def test_speckle_shader_public_api() -> None:
    from riley.cython import SpeckleShader

    assert SpeckleShader is riley.SpeckleShader
    uvs = np.zeros((3, 2))
    params = riley.Speckle2DParams(0.4, 0.02)
    shader = riley.SpeckleShader(uvs, params)
    assert shader.params is params
    assert (shader.output_scale, shader.output_offset, shader.bits, shader.scaling_type) == (
        1.0, 0.0, 8, riley.ScaleStrategy.auto,
    )
    assert (params.occupancy, params.jitter, params.edge_softness) == (1.0, 0.0, 0.0)
    assert [(field.name, field.kw_only) for field in fields(params)] == [
        ("coverage", False), ("radius", False),
        *[(name, True) for name in ("occupancy", "jitter", "edge_softness", "pattern",
                                   "seed", "foreground", "background")],
    ]
    assert [pattern.name for pattern in riley.SpecklePattern] == ["disk", "gaussian"]

    for args in ((), (uvs,)):
        with pytest.raises(TypeError):
            riley.SpeckleShader(*args)
    for kwargs in ({}, {"coverage": 0.4}, {"radius": 0.02}):
        with pytest.raises(TypeError):
            riley.Speckle2DParams(**kwargs)

    with pytest.raises(TypeError, match="cell_size"):
        riley.Perlin2DParams()
    perlin = riley.Perlin2DParams(0.08)
    assert [(field.name, field.kw_only) for field in fields(perlin)] == [
        ("cell_size", False),
        *[(name, True) for name in ("threshold", "transition_width", "seed",
                                   "foreground", "background")],
    ]
    assert riley.SpeckleShader(uvs, perlin).params is perlin
    assert params.seed == perlin.seed == 0xA511E9B3
    assert perlin.transition_width == 0.12


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


@pytest.mark.parametrize("pattern", PATTERNS)
def test_speckle_params_render_in_memory(
    speckle_mesh: riley.Mesh,
    pattern: riley.SpecklePattern | str,
) -> None:
    shader = speckle_mesh.shader
    shader.params = _params(pattern)
    image = _render(speckle_mesh)

    assert image.shape == (1, 1, 1, 32, 32)
    assert np.isfinite(image).all()
    covered = image[image > 0.0]
    assert covered.size > 0
    assert covered.min() >= 0.1 - 1e-12
    assert covered.max() <= 0.9 + 1e-12
    assert np.ptp(covered) > 0.1

    if pattern != riley.SpecklePattern.disk:
        shader.params = _params(riley.SpecklePattern.disk)
        disk_image = _render(speckle_mesh)
        assert not np.array_equal(image, disk_image)


@pytest.mark.parametrize("pattern", PATTERNS)
def test_speckle_output_transform(speckle_mesh: riley.Mesh, pattern: riley.SpecklePattern | str) -> None:
    shader = speckle_mesh.shader
    shader.params = _params(pattern)
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
    with pytest.raises(RuntimeError, match="InvalidSpeckleOutputTransform"):
        _render(speckle_mesh)


@pytest.mark.parametrize("channels", [1, 3])
def test_function_shader_rejects_invalid_builtin(speckle_mesh: riley.Mesh, channels: int) -> None:
    speckle_mesh.shader = riley.FunctionShader(builtin=9, channels=channels)
    with pytest.raises(RuntimeError, match="InvalidFuncShaderBuiltin"):
        _render(speckle_mesh)


@pytest.mark.parametrize("pattern", PATTERNS)
def test_speckle_uv_reparameterization_preserves_physical_field(
    speckle_mesh: riley.Mesh, pattern: riley.SpecklePattern | str,
) -> None:
    params = _params(pattern)
    speckle_mesh.shader.params = params
    expected = _render(speckle_mesh, pixels=65)
    speckle_mesh.shader.uvs = speckle_mesh.shader.uvs * 0.5
    np.testing.assert_array_equal(_render(speckle_mesh, pixels=65), expected)


def test_physical_coverage_and_radius_control_opaque_footprints(speckle_mesh: riley.Mesh) -> None:
    images = []
    fractions = []
    for coverage, radius in ((0.25, 0.008), (0.5, 0.008), (0.5, 0.016)):
        speckle_mesh.shader.params = riley.Speckle2DParams(
            coverage, radius, seed=7, foreground=0.1, background=0.9,
        )
        image = _render(speckle_mesh, pixels=256)
        covered = image[image > 0]
        fraction = np.mean(covered < 0.5)
        assert abs(fraction - coverage) < 0.06
        images.append(image)
        fractions.append(fraction)
    assert fractions[1] > fractions[0] + 0.15
    assert not np.array_equal(images[1], images[2])


def test_gaussian_uses_disk_full_support_not_sigma(speckle_mesh: riley.Mesh) -> None:
    params = _params(riley.SpecklePattern.disk)
    params.radius = 0.08
    speckle_mesh.shader.params = params
    disk = _render(speckle_mesh, pixels=128)
    params.pattern = riley.SpecklePattern.gaussian
    gaussian = _render(speckle_mesh, pixels=128)
    surface = disk > 0
    # Equal coverage/radius/seed yields equal complete support; Gaussian values
    # inside that support form a profile instead of opaque foreground plateaus.
    np.testing.assert_array_equal(
        gaussian[surface] < params.background, disk[surface] < params.background,
    )
    interior = gaussian[(gaussian > params.foreground) & (gaussian < params.background)]
    assert np.unique(interior).size > 20
    # At the full three-sigma cutoff, relative opacity approaches exp(-9/2).
    opacity = (params.background - interior) / (params.background - params.foreground)
    assert opacity.min() == pytest.approx(np.exp(-4.5), rel=0.05)


def test_perlin_hard_threshold_selects_foreground_or_background(speckle_mesh: riley.Mesh) -> None:
    params = riley.Perlin2DParams(
        cell_size=0.08, threshold=-2.0, transition_width=0.0,
        foreground=0.1, background=0.9,
    )
    speckle_mesh.shader.params = params
    foreground = _render(speckle_mesh)
    params.threshold = 2.0
    background = _render(speckle_mesh)
    surface = foreground > 0
    assert np.any(surface)
    np.testing.assert_allclose(foreground[surface], params.foreground, rtol=0, atol=1e-12)
    np.testing.assert_allclose(background[surface], params.background, rtol=0, atol=1e-12)
    np.testing.assert_array_equal(background[~surface], 0.0)


def test_mixed_speckle_patterns_remain_fixed_across_frames(
    speckle_mesh: riley.Mesh,
) -> None:
    template = speckle_mesh.shader
    cases = (
        (riley.SpecklePattern.disk, 0.0, (0.0, 0.0, 0.0)),
        (riley.SpecklePattern.disk, 0.008, (1.25, 0.0, 0.0)),
        (riley.SpecklePattern.gaussian, 0.0, (0.0, 1.25, 0.0)),
        ("perlin", 0.0, (1.25, 1.25, 0.0)),
    )
    meshes: list[riley.Mesh] = []
    for pattern, softness, offset in cases:
        params = _params(pattern)
        if isinstance(params, riley.Speckle2DParams):
            params.edge_softness = softness
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


@pytest.mark.parametrize("pattern", PATTERNS)
def test_speckle_odd_width_buffer_modes_match(
    speckle_mesh: riley.Mesh,
    pattern: riley.SpecklePattern | str,
) -> None:
    shader = speckle_mesh.shader
    shader.params = _params(pattern)
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


def test_speckle_fast_vs_full_uv_payload_validation(speckle_mesh: riley.Mesh) -> None:
    config = riley.RasterConfig(
        save_strategy=riley.SaveStrategy.memory,
        report=riley.ReportMode.off,
        validate_input=riley.ValidateInput.fast,
    )
    expected = _render(speckle_mesh, config=config)
    shader = speckle_mesh.shader
    # Even in fast mode, calibration rejects nonfinite referenced UVs.
    shader.uvs[0, 0] = np.nan
    with pytest.raises(RuntimeError, match=r"InvalidSpeckleUvDomain\b"):
        _render(speckle_mesh, config=config)
    shader.uvs[0, 0] = 0.0

    # Only full validation scans the unreferenced UV payload.
    speckle_mesh.coords = np.vstack((speckle_mesh.coords, [0.25, 0.25, 0.0]))
    shader.uvs = np.vstack((shader.uvs, [np.nan, np.nan]))
    actual = _render(speckle_mesh, config=config)
    np.testing.assert_array_equal(actual, expected)

    config.validate_input = riley.ValidateInput.full
    with pytest.raises(RuntimeError, match="NonFiniteUvs"):
        _render(speckle_mesh, config=config)

    shader.uvs[-1] = [0.25, 0.25]
    np.testing.assert_array_equal(_render(speckle_mesh, config=config), expected)


@pytest.mark.parametrize("pattern", PATTERNS)
def test_mixed_shader_deformation_matches_static_frame_references(
    speckle_mesh: riley.Mesh,
    pattern: riley.SpecklePattern | str,
) -> None:
    speckle_shader = speckle_mesh.shader
    speckle_shader.params = _params(pattern)
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
            # Physical calibration belongs to the reference mesh, not each
            # deformed frame. Keep that reference for the speckle-only oracle.
            if isinstance(mesh.shader, riley.SpeckleShader):
                static_mesh = replace(mesh, disp=displacements[frame:frame + 1])
            else:
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


@pytest.mark.parametrize("params", [None, {}, riley.FuncShaderParams()])
def test_speckle_binding_rejects_wrong_params_type(speckle_mesh: riley.Mesh, params: object) -> None:
    speckle_mesh.shader.params = params
    with pytest.raises(TypeError, match="SpeckleShader.params must be Speckle2DParams or Perlin2DParams"):
        _render(speckle_mesh)


@pytest.mark.parametrize("seed,error", [
    (-1, ValueError), (2**32, ValueError), (1.5, TypeError),
    (True, TypeError), (np.bool_(True), TypeError),
])
def test_speckle_binding_rejects_invalid_seed(
    speckle_mesh: riley.Mesh, seed: int | float | np.bool_, error: type[Exception],
) -> None:
    speckle_mesh.shader.params.seed = seed
    with pytest.raises(error):
        _render(speckle_mesh)


def test_perlin_binding_accepts_numpy_integer_seed(speckle_mesh: riley.Mesh) -> None:
    speckle_mesh.shader.params = riley.Perlin2DParams(0.08, seed=np.int64(2**32 - 1))
    expected = _render(speckle_mesh)
    speckle_mesh.shader.params.seed = int(speckle_mesh.shader.params.seed)
    np.testing.assert_array_equal(_render(speckle_mesh), expected)


@pytest.mark.parametrize("case,error", [
    ("degenerate_uv", r"InvalidSpeckleUvGeometry\b"),
    ("degenerate_reference", r"InvalidSpeckleReferenceGeometry\b"),
    ("uv_out_of_range", r"InvalidSpeckleUvDomain\b"),
])
def test_speckle_rejects_invalid_calibration_geometry(
    speckle_mesh: riley.Mesh,
    case: str,
    error: str,
) -> None:
    if case == "uv_out_of_range":
        speckle_mesh.shader.uvs = speckle_mesh.shader.uvs * 2
    elif case == "degenerate_uv":
        speckle_mesh.shader.uvs[1] = speckle_mesh.shader.uvs[0]
    else:
        speckle_mesh.coords[1] = speckle_mesh.coords[0]
    with pytest.raises(RuntimeError, match=error):
        _render(speckle_mesh)


@pytest.mark.parametrize("pattern,option,value", [
    (riley.SpecklePattern.disk, "occupancy", 0.9),
    (riley.SpecklePattern.disk, "jitter", 0.02),
    (riley.SpecklePattern.disk, "edge_softness", 0.008),
    (riley.SpecklePattern.disk, "seed", 8),
    (riley.SpecklePattern.disk, "foreground", 0.2),
    (riley.SpecklePattern.disk, "background", 0.8),
    ("perlin", "cell_size", 0.13),
    ("perlin", "threshold", 0.3),
    ("perlin", "transition_width", 0.4),
    ("perlin", "foreground", 0.2),
    ("perlin", "background", 0.8),
])
def test_speckle_binding_forwards_render_controls(
    speckle_mesh: riley.Mesh,
    pattern: riley.SpecklePattern | str,
    option: str,
    value: object,
) -> None:
    shader = speckle_mesh.shader
    shader.params = _params(pattern)
    original = _render(speckle_mesh, pixels=65)
    setattr(shader.params, option, value)
    changed = _render(speckle_mesh, pixels=65)
    assert not np.array_equal(changed, original)
    if option == "seed":
        np.testing.assert_array_equal(_render(speckle_mesh, pixels=65), changed)
    elif option == "edge_softness":
        assert np.any((changed > 0.1 + 1e-12) & (changed < 0.9 - 1e-12))


@pytest.mark.parametrize("params,error", [
    (riley.Speckle2DParams(0.5, 0.0), r"InvalidSpeckleRadius\b"),
    (riley.Speckle2DParams(0.8, 0.04, occupancy=0.1), r"UnattainableSpeckleCoverage\b"),
    (riley.Speckle2DParams(0.7, 0.04, jitter=0.02, edge_softness=0.04),
     r"UnsupportedSpeckleSupport\b"),
    (riley.Perlin2DParams(0.0), r"InvalidSpeckleCellSize\b"),
    (riley.Perlin2DParams(0.08, threshold=float("nan")), r"InvalidSpecklePerlinThreshold\b"),
    (riley.Perlin2DParams(0.08, transition_width=-0.1), r"InvalidSpecklePerlinTransitionWidth\b"),
])
def test_speckle_render_rejects_invalid_params(
    speckle_mesh: riley.Mesh,
    params: riley.Speckle2DParams | riley.Perlin2DParams,
    error: str,
) -> None:
    speckle_mesh.shader.params = params
    with pytest.raises(RuntimeError, match=error):
        _render(speckle_mesh)


def test_unrepresentable_speckle_storage_returns_a_native_error(speckle_mesh: riley.Mesh) -> None:
    # Valid resolved coordinates, but unrepresentable resource-grid product.
    speckle_mesh.shader.params.radius = 2.0**-44
    with pytest.raises(RuntimeError, match=r"SpeckleDensityOutOfRange\b"):
        _render(speckle_mesh)


@pytest.mark.parametrize("pattern", [-1, 2, 3, 2**32, 0.5])
def test_speckle_binding_rejects_invalid_pattern(
    speckle_mesh: riley.Mesh,
    pattern: int | float,
) -> None:
    speckle_mesh.shader.params.pattern = pattern
    with pytest.raises(ValueError, match="SpecklePattern"):
        _render(speckle_mesh)
