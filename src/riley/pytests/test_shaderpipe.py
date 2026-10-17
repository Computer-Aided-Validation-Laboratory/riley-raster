"""The public Python boundary prepares native shader pipes without callbacks."""

import numpy as np
import pytest
from dataclasses import replace

import riley


def scene() -> tuple[riley.Mesh, riley.Camera, riley.RasterConfig]:
    coords = np.array(((-0.5, -0.5, 0), (0.5, -0.5, 0), (0, 0.5, 0)), dtype=np.float64)
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
    mesh = riley.create_mesh(convention, riley.MeshType.tri3, coords, connect, source)
    camera = riley.Camera(
        pixels_num=(32, 32), pixels_size=(1 / 32, 1 / 32),
        pos_world=(0, 0, 1), rot_world=(0, 0, 0),
        roi_cent_world=(0, 0, 0), focal_length=1, sub_sample=1,
        pipe_family=riley.PipeFamily.mono,
    )
    config = riley.RasterConfig(
        parallel=1, save_strategy=riley.SaveStrategy.memory,
        image_save_mode=riley.ImageSaveMode.grey,
        report=riley.ReportMode.off,
    )
    config.background_value = 0
    config.save_scaling = riley.ScaleStrategy.none
    return mesh, camera, config


def test_python_sum_pipe_matches_two_constant_sources() -> None:
    mesh, camera, config = scene()
    first = mesh.shader
    second = riley.FunctionShader(
        builtin=riley.FuncShaderBuiltin.constant,
        params=riley.FuncShaderParams(constant_value=0.5),
        bits=-1, scaling_type=riley.ScaleStrategy.none,
    )
    ch0 = riley.Slot(riley.SlotKind.channel, 0)
    ch1 = riley.Slot(riley.SlotKind.channel, 1)
    mesh.shader = riley.PipelineShader((riley.ShaderPipe(
        family=riley.PipeFamily.mono,
        stages=(riley.ShaderSource(first, ch0), riley.ShaderSource(second, ch1)),
        resolver=riley.ShaderResolver(riley.ResolverKind.sum, slots=(ch0, ch1)),
    ),))
    convention = riley.ConnectConvention(
        riley.EElemType.TRI3, riley.EConnectAxis.ROW, 0, riley.ENodeOrder.RILEY,
    )
    mesh = riley.create_mesh(
        convention, riley.MeshType.tri3, mesh.coords, mesh.connect, mesh.shader,
    )
    image = riley.raster(mesh, camera, config)
    assert image.shape == (1, 1, 1, 32, 32)
    foreground = image[0, 0, 0] > 0
    assert foreground.any() and (~foreground).any()
    np.testing.assert_allclose(image[0, 0, 0, 16, 16], 0.75, atol=1e-12)


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
    field = riley.Slot(riley.SlotKind.field, 0)
    parameter = riley.Slot(riley.SlotKind.parameter, 0)
    constant = riley.Slot(riley.SlotKind.constant, 0)
    ops = (
        riley.Operation(riley.OperationKind.load, constant),
        riley.Operation(riley.OperationKind.load, parameter),
        riley.Operation(riley.OperationKind.multiply),
        riley.Operation(riley.OperationKind.load, field),
        riley.Operation(riley.OperationKind.power4),
        riley.Operation(riley.OperationKind.multiply),
        riley.Operation(riley.OperationKind.store),
    )
    mesh.shader = riley.PipelineShader((riley.ShaderPipe(
        family=riley.PipeFamily.mono,
        stages=(riley.ShaderSource(temp, field), riley.ShaderSource(emissivity, parameter)),
        resolver=riley.ShaderResolver(riley.ResolverKind.expression, operations=ops),
        constants=(5.670374419e-8,),
    ),))
    image = riley.raster(mesh, camera, config)
    foreground = image[0, 0, 0] > 0
    assert foreground.any() and (~foreground).any()
    np.testing.assert_allclose(image[0, 0, 0, 16, 16], 0.8 * 5.670374419e-8 * 300**4, rtol=1e-12)


def test_python_ir_nodal_temperature_and_emissivity_mapping() -> None:
    mesh, camera, config = scene()
    camera.pipe_family = riley.PipeFamily.ir
    nodal = riley.NodalShader(
        field=np.full((mesh.coords.shape[0], 1, 1), 300.0),
        bits=-1, scaling_type=riley.ScaleStrategy.none,
    )
    grey = riley.FunctionShader(
        builtin=riley.FuncShaderBuiltin.constant,
        params=riley.FuncShaderParams(constant_value=0.25),
        bits=-1, scaling_type=riley.ScaleStrategy.none,
    )
    temperature = riley.Slot(riley.SlotKind.field, 0)
    channel = riley.Slot(riley.SlotKind.channel, 0)
    emissivity = riley.Slot(riley.SlotKind.parameter, 0)
    pipe = riley.PipelineShader((riley.ShaderPipe(
        family=riley.PipeFamily.ir,
        stages=(
            riley.ShaderSource(nodal, temperature),
            riley.ShaderSource(grey, channel),
            riley.GreyToEmissivity(channel, emissivity, black=0.9, white=0.5),
        ),
        resolver=riley.ShaderResolver(
            riley.ResolverKind.greybody_band,
            temperature=temperature, emissivity=emissivity,
            lookup_first=290, lookup_step=20,
            lookup_values=np.array((10.0, 30.0)),
        ),
    ),))
    convention = riley.ConnectConvention(
        riley.EElemType.TRI3, riley.EConnectAxis.ROW, 0, riley.ENodeOrder.RILEY,
    )
    mesh = riley.create_mesh(convention, riley.MeshType.tri3, mesh.coords, mesh.connect, pipe)
    image = riley.raster(mesh, camera, config)
    np.testing.assert_allclose(image[0, 0, 0, 16, 16], 16.0, atol=1e-12)


def test_python_camera_selects_mono_and_rgb_pipes() -> None:
    mesh, mono, config = scene()
    rgb = replace(mono, pipe_family=riley.PipeFamily.rgb)
    config.image_save_mode = riley.ImageSaveMode.multifield
    rgb_source = riley.FunctionShader(
        builtin=riley.FuncShaderBuiltin.constant,
        params=riley.FuncShaderParams(constant_value_rgb=(0.2, 0.5, 0.8)),
        channels=3, bits=-1, scaling_type=riley.ScaleStrategy.none,
    )
    ch = tuple(riley.Slot(riley.SlotKind.channel, i) for i in range(3))
    mesh.shader = riley.PipelineShader((
        riley.ShaderPipe(
            family=riley.PipeFamily.mono,
            stages=(riley.ShaderSource(mesh.shader, ch[0]),),
            resolver=riley.ShaderResolver(riley.ResolverKind.identity, slots=(ch[0],)),
        ),
        riley.ShaderPipe(
            family=riley.PipeFamily.rgb,
            stages=(riley.ShaderSource(rgb_source, ch[0]),),
            resolver=riley.ShaderResolver(riley.ResolverKind.identity, slots=ch),
        ),
    ))
    image = riley.raster(mesh, (mono, rgb), config)
    assert image.shape == (2, 1, 3, 32, 32)
    np.testing.assert_allclose(image[0, 0, :, 16, 16], (0.25, 0, 0), atol=1e-12)
    np.testing.assert_allclose(image[1, 0, :, 16, 16], (0.2, 0.5, 0.8), atol=1e-12)


def test_invalid_python_pipe_fails_during_preparation() -> None:
    mesh, camera, config = scene()
    missing = riley.Slot(riley.SlotKind.channel, 1)
    mesh.shader = riley.PipelineShader((riley.ShaderPipe(
        family=riley.PipeFamily.mono,
        stages=(riley.ShaderSource(mesh.shader, riley.Slot(riley.SlotKind.channel, 0)),),
        resolver=riley.ShaderResolver(riley.ResolverKind.identity, slots=(missing,)),
    ),))
    with pytest.raises(RuntimeError, match="InvalidShaderPipe"):
        riley.raster(mesh, camera, config)
