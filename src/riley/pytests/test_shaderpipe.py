"""The public Python boundary prepares native shader pipes without callbacks."""

import numpy as np
import pytest
from dataclasses import replace

import riley


def scene() -> tuple[riley.Mesh, riley.Camera, riley.RasterConfig]:
    coords = np.array(
        ((-0.5, -0.5, 0), (0.5, -0.5, 0), (0, 0.5, 0)),
        dtype=np.float64,
    )
    connect = np.array(((0, 1, 2),), dtype=np.int64)
    convention = riley.ConnectConvention(
        riley.EElemType.TRI3, riley.EConnectAxis.ROW, 0, riley.ENodeOrder.RILEY,
    )
    source = riley.FunctionShader(
        builtin=riley.FuncShaderBuiltin.constant,
        params=riley.FuncShaderParams(constant_value=0.25),
        bits=-1,
        scaling_type=riley.ScaleStrategy.none,
    )
    mesh = riley.create_mesh(
        convention,
        riley.MeshType.tri3,
        coords,
        connect,
        riley.MeshShaderSet(mono=source),
    )
    camera = riley.Camera(
        pixels_num=(32, 32), pixels_size=(1 / 32, 1 / 32),
        pos_world=(0, 0, 1), rot_world=(0, 0, 0),
        roi_cent_world=(0, 0, 0), focal_length=1, sub_sample=1,
        render_format=riley.RenderFormat.mono,
    )
    config = riley.RasterConfig(
        parallel=1, save_strategy=riley.SaveStrategy.memory,

        report_perf=riley.ReportMode.off,
    )

    return mesh, camera, config


def test_python_sum_pipe_matches_two_constant_sources() -> None:
    mesh, camera, config = scene()
    first = mesh.shaders.mono
    second = riley.FunctionShader(
        builtin=riley.FuncShaderBuiltin.constant,
        params=riley.FuncShaderParams(constant_value=0.5),
        bits=-1, scaling_type=riley.ScaleStrategy.none,
    )
    ch0 = riley.Register(riley.RegisterKind.channel, 0)
    ch1 = riley.Register(riley.RegisterKind.channel, 1)
    mesh.shaders = riley.MeshShaderSet(mono=riley.ShaderPipe(
        stages=(
            riley.ShaderSource(first, ch0),
            riley.ShaderSource(second, ch1),
        ),
        resolver=riley.ShaderResolver(riley.ResolverKind.sum, registers=(ch0, ch1)),
    ))
    convention = riley.ConnectConvention(
        riley.EElemType.TRI3, riley.EConnectAxis.ROW, 0, riley.ENodeOrder.RILEY,
    )
    mesh = riley.create_mesh(
        convention,
        riley.MeshType.tri3,
        mesh.coords,
        mesh.connect,
        mesh.shaders,
    )
    image = riley.raster(mesh, camera, config)
    assert image.shape == (1, 1, 1, 32, 32)
    foreground = image[0, 0, 0] > 0
    assert foreground.any() and (~foreground).any()
    np.testing.assert_allclose(image[0, 0, 0, 16, 16], 0.75, atol=1e-12)


@pytest.mark.parametrize("alpha, expected", [(0.25, 9.95), ("register_ref", 5.68)])
def test_python_generic_stage_composition(
    alpha: float | str, expected: float,
) -> None:
    mesh, camera, config = scene()
    source = riley.FunctionShader(
        builtin=riley.FuncShaderBuiltin.constant,
        params=riley.FuncShaderParams(constant_value_rgb=(0.3, 0.4, 0.0)),
        channels=3, bits=-1, scaling_type=riley.ScaleStrategy.none,
    )
    field = lambda index: riley.Register(riley.RegisterKind.field, index)
    channel = lambda index: riley.Register(riley.RegisterKind.channel, index)
    stages = (
        riley.ShaderSource(source, field(0)),
        riley.Normalise(field(0), channel(0), 3),
        riley.AffineMap(channel(0), field(3), 2.0, 0.1),
        riley.LUTMap(field(3), field(4), 0.0, 1.0,
                     np.array((0.0, 10.0, 20.0))),
        riley.Blend(field(4), channel(1), channel(3),
                    channel(0) if alpha == "register_ref" else alpha),
    )
    mesh.shaders = riley.MeshShaderSet(mono=riley.ShaderPipe(
        stages=stages,
        resolver=riley.ShaderResolver(riley.ResolverKind.identity,
                                      registers=(channel(3),)),
    ))
    image = riley.raster(mesh, camera, config)
    np.testing.assert_allclose(image[0, 0, 0, 16, 16], expected, atol=1e-11)


def test_python_expression_reads_field_parameter_and_constant() -> None:
    mesh, camera, config = scene()
    temp = riley.FunctionShader(
        builtin=riley.FuncShaderBuiltin.constant,
        params=riley.FuncShaderParams(constant_value=300),
        bits=-1, scaling_type=riley.ScaleStrategy.none,
    )
    emissivity = riley.FunctionShader(
        builtin=riley.FuncShaderBuiltin.constant,
        params=riley.FuncShaderParams(constant_value=0.8),
        bits=-1, scaling_type=riley.ScaleStrategy.none,
    )
    field = riley.Register(riley.RegisterKind.field, 0)
    parameter = riley.Register(riley.RegisterKind.parameter, 0)
    constant = riley.Register(riley.RegisterKind.constant, 0)
    ops = (
        riley.ResolverOp(riley.ResolverOpKind.load, constant),
        riley.ResolverOp(riley.ResolverOpKind.load, parameter),
        riley.ResolverOp(riley.ResolverOpKind.multiply),
        riley.ResolverOp(riley.ResolverOpKind.load, field),
        riley.ResolverOp(riley.ResolverOpKind.power4),
        riley.ResolverOp(riley.ResolverOpKind.multiply),
        riley.ResolverOp(riley.ResolverOpKind.store),
    )
    mesh.shaders = riley.MeshShaderSet(mono=riley.ShaderPipe(
        stages=(
            riley.ShaderSource(temp, field),
            riley.ShaderSource(emissivity, parameter),
        ),
        resolver=riley.ShaderResolver(
            riley.ResolverKind.expression, operations=ops,
        ),
        constants=(5.670374419e-8,),
    ))
    image = riley.raster(mesh, camera, config)
    foreground = image[0, 0, 0] > 0
    assert foreground.any() and (~foreground).any()
    expected = 0.8 * 5.670374419e-8 * 300**4
    np.testing.assert_allclose(image[0, 0, 0, 16, 16], expected, rtol=1e-12)


def test_python_ir_nodal_temperature_and_emissivity_mapping() -> None:
    mesh, camera, config = scene()
    camera.render_format = riley.RenderFormat.ir
    nodal = riley.NodalShader(
        field=np.full((mesh.coords.shape[0], 1, 1), 300.0),
        bits=-1, scaling_type=riley.ScaleStrategy.none,
    )
    grey = riley.FunctionShader(
        builtin=riley.FuncShaderBuiltin.constant,
        params=riley.FuncShaderParams(constant_value=0.25),
        bits=-1, scaling_type=riley.ScaleStrategy.none,
    )
    temperature = riley.Register(riley.RegisterKind.field, 0)
    channel = riley.Register(riley.RegisterKind.channel, 0)
    emissivity = riley.Register(riley.RegisterKind.parameter, 0)
    pipe = riley.MeshShaderSet(ir=riley.ShaderPipe(
        stages=(
            riley.ShaderSource(nodal, temperature),
            riley.ShaderSource(grey, channel),
            riley.GreyToEmissivity(
                channel, emissivity, emissivity_at_black=0.9, emissivity_at_white=0.5
            ),
        ),
        resolver=riley.ShaderResolver(
            riley.ResolverKind.greybody_band,
            temperature=temperature, emissivity=emissivity,
            lookup_first=290, lookup_step=20,
            lookup_values=np.array((10.0, 30.0)),
        ),
    ))
    convention = riley.ConnectConvention(
        riley.EElemType.TRI3, riley.EConnectAxis.ROW, 0, riley.ENodeOrder.RILEY,
    )
    mesh = riley.create_mesh(
        convention, riley.MeshType.tri3, mesh.coords, mesh.connect, pipe,
    )
    image = riley.raster(mesh, camera, config)
    np.testing.assert_allclose(image[0, 0, 0, 16, 16], 16.0, atol=1e-12)


def test_python_camera_selects_mono_and_rgb_pipes() -> None:
    mesh, mono, config = scene()
    rgb = replace(mono, render_format=riley.RenderFormat.rgb)

    rgb_source = riley.FunctionShader(
        builtin=riley.FuncShaderBuiltin.constant,
        params=riley.FuncShaderParams(constant_value_rgb=(0.2, 0.5, 0.8)),
        channels=3, bits=-1, scaling_type=riley.ScaleStrategy.none,
    )
    ch = tuple(riley.Register(riley.RegisterKind.channel, i) for i in range(3))
    mesh.shaders = riley.MeshShaderSet(
        mono=riley.ShaderPipe(
            stages=(riley.ShaderSource(mesh.shaders.mono, ch[0]),),
            resolver=riley.ShaderResolver(
                riley.ResolverKind.identity, registers=(ch[0],),
            ),
        ),
        rgb=riley.ShaderPipe(
            stages=(riley.ShaderSource(rgb_source, ch[0]),),
            resolver=riley.ShaderResolver(
                riley.ResolverKind.identity, registers=ch,
            ),
        ),
    )
    image = riley.raster(mesh, (mono, rgb), config)
    assert image.shape == (2, 1, 3, 32, 32)
    np.testing.assert_allclose(
        image[0, 0, :, 16, 16], (0.25, 0, 0), atol=1e-12,
    )
    np.testing.assert_allclose(
        image[1, 0, :, 16, 16], (0.2, 0.5, 0.8), atol=1e-12,
    )


def test_invalid_python_pipe_fails_during_preparation() -> None:
    mesh, camera, config = scene()
    missing = riley.Register(riley.RegisterKind.channel, 1)
    mesh.shaders = riley.MeshShaderSet(mono=riley.ShaderPipe(
        stages=(
            riley.ShaderSource(
                mesh.shaders.mono,
                riley.Register(riley.RegisterKind.channel, 0),
            ),
        ),
        resolver=riley.ShaderResolver(
            riley.ResolverKind.identity, registers=(missing,),
        ),
    ))
    with pytest.raises(RuntimeError, match="InvalidShaderPipe"):
        riley.raster(mesh, camera, config)


def test_shader_set_three_cameras_share_mesh_and_select_roles() -> None:
    mesh, mono, config = scene()
    source = mesh.shaders.mono
    ch0 = riley.Register(riley.RegisterKind.channel, 0)
    mesh.shaders = riley.MeshShaderSet(
        mono=source,
        ir=riley.ShaderPipe(
            stages=(riley.ShaderSource(source, ch0),),
            resolver=riley.ShaderResolver(
                riley.ResolverKind.identity, registers=(ch0,),
            ),
        ),
    )
    ir = replace(mono, render_format=riley.RenderFormat.ir)
    images = riley.raster(mesh, (mono, ir, mono), config)
    assert images.shape == (3, 1, 1, 32, 32)
    np.testing.assert_array_equal(images[0], images[2])
    np.testing.assert_allclose(images[0], images[1], atol=1e-12)
    assert 0 < np.count_nonzero(images[0]) < images[0].size

    rgb_cam = replace(mono, render_format=riley.RenderFormat.rgb)
    with pytest.raises(RuntimeError, match="NoCompatibleShader"):
        riley.raster(mesh, rgb_cam, config)


def test_unselected_pipe_does_not_add_frames_or_channels() -> None:
    mesh, camera, config = scene()
    camera.render_format = riley.RenderFormat.mono
    registers = tuple(riley.Register(riley.RegisterKind.channel, i) for i in range(4))
    unused_source = riley.NodalShader(
        np.full((mesh.coords.shape[0], 6, 4), 0.5),
        bits=-1, scaling_type=riley.ScaleStrategy.none,
    )
    mesh.shaders = riley.MeshShaderSet(
        mono=mesh.shaders.mono,
        multifield=riley.ShaderPipe(
            channels=4,
            stages=(riley.ShaderSource(unused_source, registers[0]),),
            resolver=riley.ShaderResolver(
                riley.ResolverKind.identity, registers=registers,
            ),
        ),
    )
    mesh = riley.create_mesh(
        riley.ConnectConvention(
            riley.EElemType.TRI3,
            riley.EConnectAxis.ROW,
            0,
            riley.ENodeOrder.RILEY,
        ),
        riley.MeshType.tri3,
        mesh.coords,
        mesh.connect,
        mesh.shaders,
    )
    image = riley.raster(mesh, camera, config)
    assert image.shape == (1, 1, 1, 32, 32)
    np.testing.assert_allclose(image[0, 0, 0, 16, 16], 0.25, atol=1e-12)


def test_python_sphere_lit_modulates_speckle_and_lambertian() -> None:
    data_dir = riley.data.sphere200_case_path()
    coords = riley.load_csv(data_dir / "coords.csv")
    connect = riley.load_csv(data_dir / "connect.csv", dtype=np.int64)
    uvs = riley.load_csv(data_dir / "uvs.csv")
    texture = riley.load_texture_mono_u8(riley.data.speckle_texture_path())

    convention = riley.ConnectConvention(
        riley.EElemType.TRI6,
        riley.EConnectAxis.ROW,
        0,
        riley.ENodeOrder.RILEY,
    )
    speckle = riley.TextureShader(uvs=uvs, texture=texture)
    lambertian = riley.FunctionShader(
        builtin=riley.FuncShaderBuiltin.lambertian_normal_z,
        params=riley.FuncShaderParams(lambertian_coeffs=(0.2, 0.8)),
        bits=-1,
        scaling_type=riley.ScaleStrategy.none,
    )
    ch = riley.Register(riley.RegisterKind.channel, 0)
    param = riley.Register(riley.RegisterKind.parameter, 0)
    pipe = riley.ShaderPipe(
        stages=(
            riley.ShaderSource(speckle, ch),
            riley.ShaderSource(lambertian, param),
        ),
        resolver=riley.ShaderResolver(
            riley.ResolverKind.modulate,
            registers=(ch,),
            factor=param,
        ),
    )
    mesh_direct = riley.create_mesh(
        convention,
        riley.MeshType.tri6,
        coords,
        connect,
        riley.MeshShaderSet(mono=speckle),
    )
    mesh_lit = riley.create_mesh(
        convention,
        riley.MeshType.tri6,
        coords,
        connect,
        riley.MeshShaderSet(mono=pipe),
    )
    pixels_num = (64, 64)
    pixels_size = (5.3e-6, 5.3e-6)
    focal_length = 50.0e-3
    rot_world = (0.0, 0.0, 0.0)
    pos_world = riley.pos_frame_coords(
        coords, pixels_num, pixels_size, focal_length, rot_world
    )
    camera = riley.Camera(
        pixels_num=pixels_num,
        pixels_size=pixels_size,
        pos_world=pos_world,
        rot_world=rot_world,
        roi_cent_world=riley.roi_cent_from_coords(coords),
        focal_length=focal_length,
        sub_sample=1,
        render_format=riley.RenderFormat.mono,
    )
    config = riley.RasterConfig(
        parallel=1,
        save_strategy=riley.SaveStrategy.memory,
        report_perf=riley.ReportMode.off,
    )
    img_direct = riley.raster(mesh_direct, camera, config)
    img_lit = riley.raster(mesh_lit, camera, config)
    assert img_direct.shape == (1, 1, 1, 64, 64)
    assert img_lit.shape == (1, 1, 1, 64, 64)
    fg = img_direct > 0
    assert fg.any()
    assert (img_lit[fg] <= img_direct[fg] + 1e-6).all()
    assert mesh_lit.normal_type == riley.NormalType.exact
    mesh_lit.normal_type = riley.NormalType.none
    img_no_normals = riley.raster(mesh_lit, camera, config)
    np.testing.assert_allclose(img_no_normals, img_direct, atol=1e-9)



@pytest.mark.parametrize("buffer_mode", list(riley.BufferMode))
def test_camera_backgrounds_are_independent(buffer_mode) -> None:
    mesh, camera, config = scene()
    config.buffer_mode = buffer_mode
    config.parallel = 4
    cameras = [replace(camera, background_value=value) for value in (7.25, 19.5)]
    image = riley.raster(mesh, cameras, config)
    for index, value in enumerate((7.25, 19.5)):
        assert image[index, 0, 0, 0, 0] == value
        assert image[index, 0, 0, 16, 16] == 0.25
    assert not hasattr(config, "background_value")


@pytest.mark.parametrize("count", [1, 2, 3, 8])
def test_independent_function_channels_cross_native_boundary(count: int) -> None:
    mesh, camera, config = scene()
    channels = tuple(
        riley.FunctionChannel(
            builtin=riley.FuncShaderBuiltin.constant,
            params=riley.FuncShaderParams(constant_value=0.25 * (index + 1)),
            output_gain=2.0, output_offset=0.125,
        ) for index in range(count)
    )
    registers = tuple(riley.Register(riley.RegisterKind.channel, index) for index in range(count))
    mesh.shaders = riley.MeshShaderSet(multifield=riley.ShaderPipe(
        stages=(riley.ShaderSource(riley.FunctionMultiShader(channels), registers[0]),),
        resolver=riley.ShaderResolver(riley.ResolverKind.identity, registers=registers),
    ))
    convention = riley.ConnectConvention(
        riley.EElemType.TRI3, riley.EConnectAxis.ROW, 0, riley.ENodeOrder.RILEY,
    )
    mesh = riley.create_mesh(convention, riley.MeshType.tri3,
                             mesh.coords, mesh.connect, mesh.shaders)
    camera = replace(camera, render_format=riley.RenderFormat.multifield, render_channels=count)
    image = riley.raster(mesh, camera, config)
    assert image.shape == (1, 1, count, 32, 32)
    np.testing.assert_array_equal(image[0, 0, :, 16, 16],
                                  [0.5 * (index + 1) + 0.125 for index in range(count)])


@pytest.mark.parametrize("count", [0, 9])
def test_invalid_function_channel_count_is_rejected(count: int) -> None:
    mesh, camera, config = scene()
    channel = riley.FunctionChannel(builtin=riley.FuncShaderBuiltin.constant)
    register_ref = riley.Register(riley.RegisterKind.channel, 0)
    mesh.shaders = riley.MeshShaderSet(mono=riley.ShaderPipe(
        stages=(riley.ShaderSource(riley.FunctionMultiShader((channel,) * count), register_ref),),
        resolver=riley.ShaderResolver(riley.ResolverKind.identity, registers=(register_ref,)),
    ))
    with pytest.raises(ValueError, match="between one and eight"):
        riley.raster(mesh, camera, config)


@pytest.mark.parametrize("background", [float("nan"), float("inf")])
def test_invalid_camera_background_is_rejected(background: float) -> None:
    mesh, camera, config = scene()
    camera.background_value = background
    with pytest.raises((ValueError, RuntimeError), match="InvalidBackgroundValue"):
        riley.raster(mesh, camera, config)


def test_function_shader_does_not_silently_drop_requested_channels() -> None:
    mesh, camera, config = scene()
    mesh.shaders.mono.channels = 2
    with pytest.raises(ValueError, match="FunctionShader.channels must be 1 or 3"):
        riley.raster(mesh, camera, config)
