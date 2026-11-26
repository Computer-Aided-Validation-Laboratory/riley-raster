"""Exercise procedural speckles through the public Python renderer."""

from __future__ import annotations

from dataclasses import replace

import numpy as np
import pytest

import riley


_UVS = np.array(((0, 0), (1, 0), (0.5, 1)), dtype=np.float32, order="F")
_PIXELS = 48
_BACKGROUND = -1.0


def _mesh(shader: riley.Shader | riley.ShaderPipe) -> riley.Mesh:
    convention = riley.ConnectConvention(
        riley.EElemType.TRI3, riley.EConnectAxis.ROW, 0, riley.ENodeOrder.RILEY,
    )
    return riley.create_mesh(
        convention,
        riley.MeshType.tri3,
        np.array(((-0.5, -0.5, 0), (0.5, -0.5, 0), (0, 0.5, 0))),
        np.array(((0, 1, 2),), dtype=np.int64),
        riley.MeshShaderSet(mono=shader),
    )


def _raster_mesh(
    mesh: riley.Mesh | list[riley.Mesh],
    validate_input: riley.ValidateInput = riley.ValidateInput.fast,
    *,
    pixels: int = _PIXELS,
    distance: float = 1.0,
    config: riley.RasterConfig | None = None,
) -> np.ndarray:
    camera = riley.Camera(
        pixels_num=(pixels, pixels), pixels_size=(1 / pixels, 1 / pixels),
        pos_world=(0, 0, distance), rot_world=(0, 0, 0),
        roi_cent_world=(0, 0, 0), focal_length=1, sub_sample=1,
        render_format=riley.RenderFormat.mono, background_value=_BACKGROUND,
    )
    if config is None:
        config = riley.RasterConfig(
            parallel=1, save_strategy=riley.SaveStrategy.memory,
            report_perf=riley.ReportMode.off, validate_input=validate_input,
        )
    image = riley.raster(mesh, camera, config)
    assert image is not None
    return image


def _render(shader: riley.Shader | riley.ShaderPipe) -> np.ndarray:
    image = _raster_mesh(_mesh(shader))
    assert image.shape == (1, 1, 1, _PIXELS, _PIXELS)
    return image[0, 0, 0]


def _identity(shader: riley.SpeckleShader) -> riley.ShaderPipe:
    channel = riley.Register(riley.RegisterKind.channel, 0)
    return riley.ShaderPipe(
        stages=(riley.ShaderSource(shader, channel),),
        resolver=riley.ShaderResolver(riley.ResolverKind.identity, registers=(channel,)),
    )


@pytest.mark.parametrize("pattern", ["disk", "gaussian", "perlin"])
def test_speckle_parameters_reach_direct_and_pipe_shaders(pattern: str) -> None:
    # Use an unsigned seed above INT32_MAX, and values different from the Zig defaults.
    seed = 0xF1234567
    if pattern == "perlin":
        params = riley.Perlin2DParams(
            cell_size=0.19, threshold=0.16, transition_width=0.34, seed=seed,
        )
        changes = {"cell_size": 0.24, "threshold": 0, "transition_width": 0}
    else:
        dots = dict(coverage=0.38, radius=0.055, occupancy=0.72, jitter=0.012, seed=seed)
        params = (riley.Disk2DParams(**dots, edge_softness=0.018) if pattern == "disk"
                  else riley.Gaussian2DParams(**dots))
        changes = {"coverage": 0.21, "radius": 0.09, "occupancy": 1, "jitter": 0}
        if pattern == "disk":
            changes["edge_softness"] = 0

    shader = riley.SpeckleShader(uvs=_UVS, params=params)
    raw = _render(shader)
    inside = raw != _BACKGROUND
    assert inside.any() and (~inside).any()
    assert np.ptp(raw[inside]) > 0.1
    assert ((raw[inside] > 0) & (raw[inside] < 1)).any()

    coloured = replace(shader, params=replace(params, foreground=0.125, background=0.875))
    direct = _render(coloured)
    expected = np.where(inside, 0.125 + 0.75 * raw, _BACKGROUND)
    np.testing.assert_allclose(direct, expected, rtol=0, atol=1e-7)
    np.testing.assert_array_equal(_render(_identity(coloured)), direct)
    np.testing.assert_array_equal(_render(replace(shader, uvs=_UVS * 0.5)), raw)

    # A comparison of identical inputs through both paths alone would not detect
    # a dropped parameter shared by both bindings.
    changes["seed"] = seed ^ (1 << 31)
    for name, value in changes.items():
        changed = _render(replace(shader, params=replace(params, **{name: value})))
        assert not np.allclose(changed, raw), f"{pattern}: changing {name} had no effect"


def test_gaussian_radius_is_full_support_not_sigma() -> None:
    dots = dict(coverage=0.35, radius=0.08, occupancy=0.75, seed=7)
    disk = riley.SpeckleShader(uvs=_UVS, params=riley.Disk2DParams(**dots))
    gaussian = replace(disk, params=riley.Gaussian2DParams(**dots))
    disk_image = _raster_mesh(_mesh(disk), pixels=128)
    gaussian_image = _raster_mesh(_mesh(gaussian), pixels=128)
    inside = disk_image != _BACKGROUND
    np.testing.assert_array_equal(gaussian_image != _BACKGROUND, inside)
    support = disk_image[inside] == 0
    assert support.any()
    np.testing.assert_array_equal(gaussian_image[inside] < 1, support)
    opacity = 1 - gaussian_image[inside][support]
    assert np.unique(opacity).size > 20
    assert opacity.min() == pytest.approx(np.exp(-4.5), rel=0.05)


def test_perlin_hard_threshold_and_numpy_integer_seed() -> None:
    params = riley.Perlin2DParams(
        cell_size=0.19, transition_width=0, seed=np.int64(2**32 - 1),
        foreground=0.125, background=0.875,
    )
    shader = riley.SpeckleShader(uvs=_UVS, params=params)
    mixed = _render(shader)
    inside = mixed != _BACKGROUND
    assert set(np.unique(mixed[inside])) == {params.foreground, params.background}
    np.testing.assert_array_equal(
        _render(replace(shader, params=replace(params, seed=int(params.seed)))), mixed,
    )
    for threshold, colour in ((-2, params.foreground), (2, params.background)):
        image = _render(replace(shader, params=replace(params, threshold=threshold)))
        np.testing.assert_array_equal(image, np.where(inside, colour, _BACKGROUND))


def test_mixed_shaders_reuse_patterns_and_match_single_frame_references() -> None:
    dots = dict(coverage=0.35, radius=0.22, occupancy=0.75, seed=7)
    params = (
        riley.Disk2DParams(**dots),
        riley.Disk2DParams(**dots, edge_softness=0.06),
        riley.Gaussian2DParams(**dots),
        riley.Perlin2DParams(cell_size=0.24),
    )
    speckles = tuple(riley.SpeckleShader(uvs=_UVS, params=p) for p in params)
    raw_output = dict(bits=-1, scaling_type=riley.ScaleStrategy.none)
    shaders = (
        *speckles,
        riley.TextureShader(uvs=_UVS.copy(), texture=np.full((1, 4, 4), 0.35), **raw_output),
        riley.NodalShader(field=np.array([[0.2], [0.5], [0.8]]), **raw_output),
        riley.FunctionShader(
            builtin=riley.FuncShaderBuiltin.constant,
            params=riley.FuncShaderParams(constant_value=0.65),
            **raw_output,
        ),
    )
    offsets = (
        (-1.25, -1.25, 0), (0, -1.25, 0), (1.25, -1.25, 0),
        (-1.25, 0, 0), (0, 0, 0), (1.25, 0, 0), (0, 1.25, 0),
    )
    disp = np.zeros((3, 3, 3))
    disp[2, 1, 0] = 0.15
    disp[2, 2, 1] = 0.10
    meshes = []
    for shader, offset in zip(shaders, offsets, strict=True):
        mesh = _mesh(shader)
        meshes.append(replace(mesh, coords=mesh.coords + offset, disp=disp.copy()))

    render = dict(pixels=65, distance=4.0, validate_input=riley.ValidateInput.full)
    actual = _raster_mesh(meshes, **render)
    assert actual.shape == (1, 3, 1, 65, 65)
    np.testing.assert_array_equal(actual[:, 0], actual[:, 1])
    assert not np.array_equal(actual[:, 0], actual[:, 2])

    for frame in (0, 2):
        expected = np.full_like(actual[:, frame:frame + 1], _BACKGROUND)
        for mesh, shader in zip(meshes, shaders, strict=True):
            if isinstance(shader, riley.SpeckleShader):
                # Keep reference geometry for physical speckle calibration.
                single = replace(mesh, disp=disp[frame:frame + 1])
            else:
                single = replace(mesh, coords=mesh.coords + disp[frame], disp=None)
            individual = _raster_mesh(single, **render)
            covered = individual != _BACKGROUND
            assert covered.any() and np.isfinite(individual[covered]).all()
            assert np.all(expected[covered] == _BACKGROUND)  # Non-overlapping meshes.
            expected[covered] = individual[covered]
        np.testing.assert_allclose(actual[:, frame:frame + 1], expected, rtol=0, atol=1e-12)


def test_speckles_match_across_buffer_modes_at_odd_width() -> None:
    shader = riley.SpeckleShader(uvs=_UVS, params=riley.Disk2DParams(coverage=0.38, radius=0.055))
    mesh = _mesh(shader)
    mesh = replace(mesh, coords=mesh.coords + (0.25, 0, 0))
    config = riley.RasterConfig(
        parallel=2, save_strategy=riley.SaveStrategy.memory, report_perf=riley.ReportMode.off,
        buffer_mode=riley.BufferMode.tile_local, tile_size_override=16,
        global_subpx_tile_size_min=16, global_subpx_tile_size_override=16,
        global_subpx_stripe_size_min=16, global_subpx_stripe_size_override=16,
    )
    expected = _raster_mesh(mesh, pixels=33, config=config)
    assert expected.shape == (1, 1, 1, 33, 33)
    assert (expected[..., -1] != _BACKGROUND).any()
    for mode in (riley.BufferMode.global_subpx_full, riley.BufferMode.global_subpx_stripe):
        actual = _raster_mesh(mesh, pixels=33, config=replace(config, buffer_mode=mode))
        np.testing.assert_allclose(actual, expected, rtol=0, atol=1e-12)


def test_speckle_default_bits_scale_once() -> None:
    shader = riley.SpeckleShader(uvs=_UVS, params=riley.Disk2DParams(coverage=0.38, radius=0.055))
    raw = _render(shader)
    assert set(np.unique(raw)) == {_BACKGROUND, 0.0, 1.0}
    auto = _render(replace(shader, scaling_type=riley.ScaleStrategy.auto))
    np.testing.assert_array_equal(auto, np.where(raw == _BACKGROUND, _BACKGROUND, raw * 255))

    fixed = replace(
        shader, bits=None, output_gain=0.5, output_offset=0.25,
        scaling_type=riley.ScaleStrategy.fixed, scaling_min=0.25, scaling_max=0.75,
    )
    np.testing.assert_array_equal(_render(fixed), raw)
    np.testing.assert_array_equal(_render(_identity(fixed)), raw)


@pytest.mark.parametrize(
    "bits, full_scale",
    [(None, 1), (8, 255), (np.int64(10), 1023), (12, 4095), (14, 16383), (16, 65535)],
)
def test_speckle_transforms_before_scaling_and_composition(
    bits: int | None, full_scale: int,
) -> None:
    shader = riley.SpeckleShader(uvs=_UVS, params=riley.Disk2DParams(coverage=0.38, radius=0.055))
    raw = _render(shader)
    transformed = replace(
        shader, bits=bits, output_gain=0.5, output_offset=0.25,
        scaling_type=riley.ScaleStrategy.frac, scaling_min=0.125, scaling_max=0.875,
    )
    expected = full_scale * (0.125 + 0.75 * (0.5 * raw + 0.25))
    inside = raw != _BACKGROUND
    np.testing.assert_array_equal(_render(transformed), np.where(inside, expected, _BACKGROUND))

    channel = riley.Register(riley.RegisterKind.channel, 0)
    factor = riley.Register(riley.RegisterKind.parameter, 0)
    multiplier = riley.FunctionShader(
        builtin=riley.FuncShaderBuiltin.constant,
        params=riley.FuncShaderParams(constant_value=0.25),
        bits=-1, scaling_type=riley.ScaleStrategy.none,
    )
    pipe = riley.ShaderPipe(
        stages=(riley.ShaderSource(transformed, channel), riley.ShaderSource(multiplier, factor)),
        resolver=riley.ShaderResolver(riley.ResolverKind.modulate, registers=(channel,), factor=factor),
    )
    np.testing.assert_array_equal(_render(pipe), np.where(inside, 0.25 * expected, _BACKGROUND))


@pytest.mark.parametrize("readonly_lut", ["stage", "resolver"])
def test_speckle_pipe_accepts_readonly_lookup_tables(readonly_lut: str) -> None:
    shader = riley.SpeckleShader(
        uvs=_UVS, params=riley.Gaussian2DParams(coverage=0.38, radius=0.055),
        bits=None,
    )
    channel = riley.Register(riley.RegisterKind.channel, 0)
    mapped = riley.Register(riley.RegisterKind.field, 0)
    stage_values = np.array((0.125, 0.75, 0.5))
    resolver_values = np.array((0.25, 0.5, 0.875))
    readonly_values = stage_values if readonly_lut == "stage" else resolver_values
    readonly_values.setflags(write=False)
    pipe = riley.ShaderPipe(
        stages=(
            riley.ShaderSource(shader, channel),
            riley.LUTMap(channel, mapped, 0.0, 0.5, stage_values),
        ),
        resolver=riley.ShaderResolver(
            riley.ResolverKind.expression,
            lookup_first=0.0, lookup_step=0.5, lookup_values=resolver_values,
            operations=(
                riley.ResolverOp(riley.ResolverOpKind.load, mapped),
                riley.ResolverOp(riley.ResolverOpKind.lut),
                riley.ResolverOp(riley.ResolverOpKind.store, channel),
            ),
        ),
    )
    raw = _render(shader)
    inside = raw != _BACKGROUND
    assert inside.any() and (~inside).any()
    assert ((raw[inside] > 0) & (raw[inside] < 1)).any()
    knots = (0.0, 0.5, 1.0)
    expected = np.full_like(raw, _BACKGROUND)
    expected[inside] = np.interp(
        np.interp(raw[inside], knots, stage_values), knots, resolver_values,
    )
    np.testing.assert_allclose(_render(pipe), expected, rtol=0, atol=1e-12)


def test_speckle_pipe_uvs_follow_the_mesh_conversion_node_map() -> None:
    shader = riley.SpeckleShader(uvs=_UVS, params=riley.Disk2DParams(coverage=0.38, radius=0.055))
    reference = _mesh(shader)
    conversion = riley.MeshConversion(
        mesh_type=reference.mesh_type,
        geometry=riley.MeshGeometry(riley.EElemType.TRI3, reference.coords, reference.connect),
        source_node_indices=np.array([3, 0, 1], dtype=np.uintp),
        source_node_count=4,
    )
    # The discarded UV lies outside the valid domain and must never reach Zig.
    source_uvs = np.vstack((_UVS[1:], (2, 2), _UVS[0]))
    mesh = riley.create_mesh_from_conversion(
        conversion, riley.MeshShaderSet(mono=_identity(replace(shader, uvs=source_uvs))),
    )
    np.testing.assert_array_equal(_raster_mesh(mesh), _raster_mesh(reference))


@pytest.mark.parametrize("layout", ["unaligned", "strided", "read-only"])
def test_raw_mesh_accepts_speckle_uv_buffer_layouts(layout: str) -> None:
    shader = riley.SpeckleShader(uvs=_UVS, params=riley.Disk2DParams(coverage=0.38, radius=0.055))
    reference = _mesh(shader)
    if layout == "unaligned":
        storage = np.empty(_UVS.size + 1, dtype=np.float64)
        uvs = np.ndarray(_UVS.shape, dtype=np.float64, buffer=storage, offset=1)
        assert uvs.flags.c_contiguous and not uvs.flags.aligned
    elif layout == "strided":
        uvs = np.empty((len(_UVS), 4), dtype=np.float64)[::-1, ::2]
        assert not uvs.flags.c_contiguous
    else:
        uvs = np.empty(_UVS.shape, dtype=np.float64)
    uvs[:] = _UVS
    if layout == "read-only":
        uvs.setflags(write=False)

    # Bypass create_mesh's node remapping, which would already copy the UVs.
    raw = replace(reference, shaders=riley.MeshShaderSet(mono=replace(shader, uvs=uvs)))
    np.testing.assert_array_equal(_raster_mesh(raw), _raster_mesh(reference))


@pytest.mark.parametrize("dtype", [np.int64, np.bool_, np.complex128, np.str_, object])
def test_speckle_requires_floating_uv_dtype(dtype: type) -> None:
    shader = riley.SpeckleShader(uvs=_UVS, params=riley.Disk2DParams(coverage=0.38, radius=0.055))
    reference = _mesh(shader)
    invalid = replace(shader, uvs=_UVS.astype(dtype))
    with pytest.raises(TypeError, match="uvs must have a floating-point dtype"):
        _mesh(invalid)
    raw = replace(reference, shaders=riley.MeshShaderSet(mono=invalid))
    with pytest.raises(TypeError, match="uvs must have a floating-point dtype"):
        _raster_mesh(raw)


def test_speckle_fast_checks_referenced_uvs_full_scans_payload() -> None:
    shader = riley.SpeckleShader(uvs=_UVS, params=riley.Disk2DParams(coverage=0.38, radius=0.055))
    reference = _mesh(shader)
    uvs = _UVS.copy()
    uvs[0, 0] = np.nan
    invalid = replace(shader, uvs=uvs)
    with pytest.raises(ValueError, match="uvs must contain only finite values"):
        _mesh(invalid)
    raw = replace(reference, shaders=riley.MeshShaderSet(mono=invalid))
    with pytest.raises(RuntimeError, match=r"\bInvalidSpeckleUvDomain\b"):
        _raster_mesh(raw)
    with pytest.raises(RuntimeError, match=r"\bNonFiniteUvs\b"):
        _raster_mesh(raw, validate_input=riley.ValidateInput.full)

    expected = _raster_mesh(reference)
    # The fourth node is absent from connectivity but still in the UV buffer.
    extra_uv = np.vstack((_UVS, (np.nan, np.nan)))
    raw = replace(
        reference, coords=np.vstack((reference.coords, (0, 0, 0))),
        shaders=riley.MeshShaderSet(mono=replace(shader, uvs=extra_uv)),
    )
    np.testing.assert_array_equal(_raster_mesh(raw), expected)
    with pytest.raises(RuntimeError, match=r"\bNonFiniteUvs\b"):
        _raster_mesh(raw, validate_input=riley.ValidateInput.full)
    extra_uv[-1] = (0.5, 0.5)
    np.testing.assert_array_equal(_raster_mesh(raw, validate_input=riley.ValidateInput.full), expected)


@pytest.mark.parametrize("case, error", [
    ("degenerate_uv", "InvalidSpeckleUvGeometry"),
    ("degenerate_reference", "InvalidSpeckleReferenceGeometry"),
    ("out_of_domain", "InvalidSpeckleUvDomain"),
])
def test_speckle_rejects_invalid_calibration_geometry(case: str, error: str) -> None:
    shader = riley.SpeckleShader(uvs=_UVS, params=riley.Disk2DParams(coverage=0.38, radius=0.055))
    mesh = _mesh(shader)
    if case == "degenerate_reference":
        mesh.coords[1] = mesh.coords[0]
    else:
        uvs = _UVS.copy()
        uvs[1] = uvs[0] if case == "degenerate_uv" else (2, 0)
        mesh = replace(mesh, shaders=riley.MeshShaderSet(mono=replace(shader, uvs=uvs)))
    with pytest.raises(RuntimeError, match=rf"\b{error}\b"):
        _raster_mesh(mesh)


def test_speckle_is_not_an_rgb_shorthand() -> None:
    shader = riley.SpeckleShader(uvs=_UVS, params=riley.Disk2DParams(coverage=0.38, radius=0.055))
    with pytest.raises(ValueError, match="explicit ShaderPipe for RGB"):
        riley.MeshShaderSet(rgb=shader)


@pytest.mark.parametrize("params_type, kwargs", [
    (riley.Disk2DParams, {"coverage": 0.38, "radius": 0.055}),
    (riley.Gaussian2DParams, {"coverage": 0.38, "radius": 0.055}),
    (riley.Perlin2DParams, {"cell_size": 0.19}),
])
def test_speckle_shader_accepts_positional_fields_and_keyword_only_params(
    params_type: type, kwargs: dict,
) -> None:
    params = params_type(**kwargs)
    shader = riley.SpeckleShader(_UVS, params, 12, 0.75, 0.125)
    assert shader.uvs is _UVS
    assert shader.params is params
    assert (shader.bits, shader.output_gain, shader.output_offset) == (12, 0.75, 0.125)
    assert riley.SpeckleShader(uvs=_UVS, params=params).params is params
    with pytest.raises(TypeError):
        params_type(*kwargs.values())
    with pytest.raises(TypeError, match="pattern"):
        riley.SpeckleShader(uvs=_UVS, params=params, pattern="disk")


@pytest.mark.parametrize("params", [None, {}, riley.FuncShaderParams()])
def test_speckle_binding_rejects_wrong_params_type(params: object) -> None:
    shader = riley.SpeckleShader(uvs=_UVS, params=params)
    with pytest.raises(TypeError, match="speckle params must be"):
        _render(shader)


@pytest.mark.parametrize("params, error", [
    (riley.Disk2DParams(coverage=0.5, radius=0), "InvalidSpeckleRadius"),
    (riley.Gaussian2DParams(coverage=0.8, radius=0.04, occupancy=0.1),
     "UnattainableSpeckleCoverage"),
    (riley.Disk2DParams(coverage=0.7, radius=0.04, jitter=0.02, edge_softness=0.04),
     "UnsupportedSpeckleSupport"),
    (riley.Perlin2DParams(cell_size=0), "InvalidSpeckleCellSize"),
    (riley.Perlin2DParams(cell_size=0.08, threshold=np.nan), "InvalidSpecklePerlinThreshold"),
    (riley.Perlin2DParams(cell_size=0.08, transition_width=-0.1), "InvalidSpecklePerlinTransitionWidth"),
    # Positive radius, but the resource grid is too large to represent.
    (riley.Disk2DParams(coverage=0.35, radius=2.0**-44), "SpeckleDensityOutOfRange"),
])
def test_invalid_speckle_parameters_return_native_errors(
    params: riley.Disk2DParams | riley.Gaussian2DParams | riley.Perlin2DParams, error: str,
) -> None:
    shader = riley.SpeckleShader(uvs=_UVS, params=params)
    with pytest.raises(RuntimeError, match=rf"\b{error}\b"):
        _render(shader)


@pytest.mark.parametrize("transform", [{"output_gain": np.nan}, {"output_offset": np.inf}])
def test_speckle_rejects_nonfinite_output_transform(transform: dict) -> None:
    shader = riley.SpeckleShader(
        uvs=_UVS, params=riley.Disk2DParams(coverage=0.38, radius=0.055), **transform,
    )
    with pytest.raises(RuntimeError, match=r"\bInvalidSpeckleOutputTransform\b"):
        _render(shader)


@pytest.mark.parametrize(
    "seed, error",
    [(-1, ValueError), (1 << 32, ValueError), (3.5, TypeError),
     (True, TypeError), (np.bool_(True), TypeError)],
)
def test_invalid_speckle_seed_is_not_truncated(
    seed: object, error: type[Exception],
) -> None:
    with pytest.raises(error, match="seed"):
        params = riley.Disk2DParams(coverage=0.38, radius=0.055, seed=seed)
        _render(riley.SpeckleShader(uvs=_UVS, params=params))


@pytest.mark.parametrize(
    "bits, error, message",
    [
        (True, TypeError, "must be an integer or None"),
        (np.bool_(False), TypeError, "must be an integer or None"),
        (8.0, TypeError, "must be an integer or None"),
        (-1, ValueError, "must use None to disable quantisation"),
        (1 << 100, ValueError, "must fit in a C int"),
        (0, RuntimeError, r"\bInvalidBits\b"),
        (9, RuntimeError, r"\bInvalidBits\b"),
    ],
)
def test_invalid_speckle_bits_are_rejected(
    bits: object, error: type[Exception], message: str,
) -> None:
    shader = riley.SpeckleShader(uvs=_UVS, params=riley.Disk2DParams(coverage=0.38, radius=0.055), bits=bits)
    with pytest.raises(error, match=message):
        _render(_identity(shader))


@pytest.mark.parametrize("shape", [(2, 2), (3, 1), (6,)])
def test_speckle_requires_two_uv_values_per_node(shape: tuple[int, ...]) -> None:
    params = riley.Disk2DParams(coverage=0.38, radius=0.055)
    shader = riley.SpeckleShader(uvs=np.zeros(shape), params=params)
    with pytest.raises(ValueError, match=r"uvs must have shape"):
        _render(_identity(shader))
