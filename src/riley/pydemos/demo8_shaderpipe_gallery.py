"""Four small ShaderPipe compositions sharing one procedural scene."""
from pathlib import Path

import numpy as np
import riley


def linear(x: float, y: float, bias: float = 0.5) -> riley.FunctionShader:
    return riley.FunctionShader(
        builtin=riley.FuncShaderBuiltin.linear,
        coord_mode=riley.FuncCoordMode.world_reference,
        params=riley.FuncShaderParams(linear_coeffs=(bias, x, y)),
        bits=-1, scaling_type=riley.ScaleStrategy.none,
    )


def main() -> None:
    coords = np.array(((-1, -1, 0), (1, -1, 0), (0, 1, 0)), dtype=np.float64)
    connect = np.array(((0, 1, 2),), dtype=np.int64)
    convention = riley.ConnectConvention(riley.EElemType.TRI3, riley.EConnectAxis.ROW, 0, riley.ENodeOrder.RILEY)
    pixels_num = (512, 512)
    pixels_size = (0.02, 0.02)
    target = riley.roi_cent_from_coords(coords)
    base_mesh = riley.create_mesh(convention, riley.MeshType.tri3opt, coords, connect,
                                  riley.MeshShaderSet(direct=linear(0, 0)))
    position = riley.pos_frame_mesh(base_mesh, pixels_num, pixels_size, 1, (0, 0, 0), target=target)
    camera = riley.Camera(pixels_num, pixels_size, position, (0, 0, 0), target, 1, 4)
    config = riley.RasterConfig(parallel=1, save_strategy=riley.SaveStrategy.disk,
                                image_save_mode=riley.ImageSaveMode.multifield)
    config.save_format = riley.ImageFormat.tiff
    config.save_bits = 16
    config.save_scaling = riley.ScaleStrategy.fixed
    config.save_scaling_min = 0.0
    config.save_scaling_max = 1.0
    ch = tuple(riley.Slot(riley.SlotKind.channel, i) for i in range(3))
    fields = tuple(riley.Slot(riley.SlotKind.field, i) for i in range(2))
    param = riley.Slot(riley.SlotKind.parameter, 0)
    constants = tuple(riley.Slot(riley.SlotKind.constant, i) for i in range(2))
    checker = riley.FunctionShader(
        builtin=riley.FuncShaderBuiltin.checker,
        coord_mode=riley.FuncCoordMode.world_reference,
        params=riley.FuncShaderParams(coord_scale=(4, 4)),
        bits=-1, scaling_type=riley.ScaleStrategy.none,
    )

    def render(
        name: str,
        shaders: riley.MeshShaderSet,
        role: riley.CameraShaderSelection,
    ) -> None:
        mesh = riley.create_mesh(
            convention, riley.MeshType.tri3opt, coords, connect, shaders
        )
        camera.shader_selection = role
        out_dir = str(
            Path.cwd() / "out_riley_py" / "demo8_shaderpipe_gallery" / name
        )
        riley.raster(mesh, camera, config, out_dir=out_dir)

    # A: checker intensity multiplied by a spatially varying illumination parameter.
    render("a_modulation", riley.MeshShaderSet(mono=riley.ShaderPipe(
        stages=(riley.ShaderSource(checker, ch[0]), riley.ShaderSource(linear(0.375, 0, 0.625), param)),
        resolver=riley.ShaderResolver(riley.ResolverKind.modulate, slots=(ch[0],), factor=param),
    )), riley.CameraShaderSelection.mono)

    # B: each RGB channel receives a distinct procedural gradient.
    render("b_rgb", riley.MeshShaderSet(rgb=riley.ShaderPipe(
        stages=tuple(riley.ShaderSource(shader, slot) for shader, slot in zip(
            (linear(0.5, 0), linear(0, 0.5), linear(0.25, -0.25)), ch)),
        resolver=riley.ShaderResolver(riley.ResolverKind.identity, slots=ch),
    )), riley.CameraShaderSelection.rgb)

    # C: two fields are blended by a bounded expression with explicit constants.
    expression = (
        riley.Operation(riley.OperationKind.load, fields[0]),
        riley.Operation(riley.OperationKind.load, constants[0]),
        riley.Operation(riley.OperationKind.multiply),
        riley.Operation(riley.OperationKind.load, fields[1]),
        riley.Operation(riley.OperationKind.load, constants[1]),
        riley.Operation(riley.OperationKind.multiply),
        riley.Operation(riley.OperationKind.add),
        riley.Operation(riley.OperationKind.clamp01),
        riley.Operation(riley.OperationKind.store),
    )
    render("c_expression", riley.MeshShaderSet(mono=riley.ShaderPipe(
        stages=(riley.ShaderSource(linear(0.5, 0), fields[0]), riley.ShaderSource(linear(0, 0.5), fields[1])),
        resolver=riley.ShaderResolver(riley.ResolverKind.expression, operations=expression),
        constants=(0.65, 0.35),
    )), riley.CameraShaderSelection.mono)

    # D: emissivity is a material parameter; output is a labelled 0.90–0.96 visualisation.
    emissivity_ops = (
        riley.Operation(riley.OperationKind.load, param),
        riley.Operation(riley.OperationKind.load, constants[0]),
        riley.Operation(riley.OperationKind.subtract),
        riley.Operation(riley.OperationKind.load, constants[1]),
        riley.Operation(riley.OperationKind.multiply),
        riley.Operation(riley.OperationKind.clamp01),
        riley.Operation(riley.OperationKind.store),
    )
    render(
        "d_emissivity_visualisation",
        riley.MeshShaderSet(mono=riley.ShaderPipe(
            stages=(
                riley.ShaderSource(checker, ch[0]),
                riley.GreyToEmissivity(
                    ch[0], param, black=0.96, white=0.90
                ),
            ),
            resolver=riley.ShaderResolver(
                riley.ResolverKind.expression, operations=emissivity_ops
            ),
            constants=(0.90, 1 / 0.06),
        )),
        riley.CameraShaderSelection.mono,
    )


if __name__ == "__main__":
    main()
