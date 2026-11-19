# --------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher)
# --------------------------------------------------------------------------
"""Six small ShaderPipe compositions sharing one procedural scene."""
from __future__ import annotations

from pathlib import Path

import numpy as np

import riley


def linear(
    x: float,
    y: float,
    bias: float = 0.5,
) -> riley.FunctionShader:
    return riley.FunctionShader(
        builtin=riley.FuncShaderBuiltin.linear,
        coord_mode=riley.FuncCoordMode.world_reference,
        params=riley.FuncShaderParams(linear_coeffs=(bias, x, y)),
        bits=-1,
        scaling_type=riley.ScaleStrategy.none,
    )


def main() -> None:
    # --------------------------------------------------------------------------
    # 1. Setup paths, base mesh geometry, and shared camera
    # --------------------------------------------------------------------------
    coords = np.array(
        ((-1.0, -1.0, 0.0), (1.0, -1.0, 0.0), (0.0, 1.0, 0.0)),
        dtype=np.float64,
    )
    connect = np.array(((0, 1, 2),), dtype=np.int64)
    convention = riley.ConnectConvention(
        riley.EElemType.TRI3,
        riley.EConnectAxis.ROW,
        0,
        riley.ENodeOrder.RILEY,
    )
    pixels_num = (512, 512)
    pixels_size = (0.02, 0.02)
    target = riley.roi_cent_from_coords(coords)

    base_mesh = riley.create_mesh(
        convention,
        riley.MeshType.tri3opt,
        coords,
        connect,
        riley.MeshShaderSet(mono=linear(0.0, 0.0)),
    )
    position = riley.pos_frame_mesh(
        base_mesh,
        pixels_num,
        pixels_size,
        1.0,
        (0.0, 0.0, 0.0),
        target=target,
    )
    camera = riley.Camera(
        pixels_num,
        pixels_size,
        position,
        (0.0, 0.0, 0.0),
        target,
        1.0,
        4,
        render_format=riley.RenderFormat.mono,
    )

    config = riley.RasterConfig(
        parallel=1,
        save_strategy=riley.SaveStrategy.disk,
    )

    ch = tuple(riley.Register(riley.RegisterKind.channel, ii) for ii in range(3))
    fields = tuple(riley.Register(riley.RegisterKind.field, ii) for ii in range(2))
    param = riley.Register(riley.RegisterKind.parameter, 0)
    constants = tuple(
        riley.Register(riley.RegisterKind.constant, ii) for ii in range(3)
    )

    checker = riley.FunctionShader(
        builtin=riley.FuncShaderBuiltin.checker,
        coord_mode=riley.FuncCoordMode.world_reference,
        params=riley.FuncShaderParams(coord_scale=(4.0, 4.0)),
        bits=-1,
        scaling_type=riley.ScaleStrategy.none,
    )

    def render(
        name: str,
        shaders: riley.MeshShaderSet,
        role: riley.RenderFormat = riley.RenderFormat.mono,
        channels: int = 1,
    ) -> None:
        mesh = riley.create_mesh(
            convention,
            riley.MeshType.tri3opt,
            coords,
            connect,
            shaders,
        )
        camera.render_format = role
        camera.render_channels = 3 if role == riley.RenderFormat.rgb else channels
        if role == riley.RenderFormat.rgb:
            camera.output_files = [
                riley.ImageSaveOpts(
                    format=riley.ImageFormat.bmp,
                    file_bits=8,
                    scaling=riley.ScaleStrategy.fixed,
                    scaling_min=0.0,
                    scaling_max=1.0,
                )
            ]
        else:
            camera.output_files = [
                riley.ImageSaveOpts(
                    format=riley.ImageFormat.tiff,
                    file_bits=16,
                    scaling=riley.ScaleStrategy.fixed,
                    scaling_min=0.0,
                    scaling_max=1.0,
                )
            ]
        out_dir = str(
            Path.cwd() / "out_riley_py" / "demo08_shaderpipe_gallery" / name
        )
        riley.raster(mesh, camera, config, out_dir=out_dir)

    # --------------------------------------------------------------------------
    # 2. Composition A: Spatially modulated illumination
    # --------------------------------------------------------------------------
    render(
        "a_modulation",
        riley.MeshShaderSet(
            mono=riley.ShaderPipe(
                stages=(
                    riley.ShaderSource(checker, ch[0]),
                    riley.ShaderSource(linear(0.375, 0.0, 0.625), param),
                ),
                resolver=riley.ShaderResolver(
                    riley.ResolverKind.modulate,
                    registers=(ch[0],),
                    factor=param,
                ),
            ),
        ),
        riley.RenderFormat.mono,
    )

    # --------------------------------------------------------------------------
    # 3. Composition B: Multi-channel RGB gradient composition
    # --------------------------------------------------------------------------
    render(
        "b_rgb",
        riley.MeshShaderSet(
            rgb=riley.ShaderPipe(
                stages=tuple(
                    riley.ShaderSource(shader, register_ref)
                    for shader, register_ref in zip(
                        (
                            linear(0.5, 0.0),
                            linear(0.0, 0.5),
                            linear(0.25, -0.25),
                        ),
                        ch,
                    )
                ),
                resolver=riley.ShaderResolver(
                    riley.ResolverKind.identity,
                    registers=ch,
                ),
            ),
        ),
        riley.RenderFormat.rgb,
    )

    # --------------------------------------------------------------------------
    # 4. Composition C: Bounded expression blend
    # --------------------------------------------------------------------------
    expression = (
        riley.ResolverOp(riley.ResolverOpKind.load, fields[0]),
        riley.ResolverOp(riley.ResolverOpKind.load, constants[0]),
        riley.ResolverOp(riley.ResolverOpKind.multiply),
        riley.ResolverOp(riley.ResolverOpKind.load, fields[1]),
        riley.ResolverOp(riley.ResolverOpKind.load, constants[1]),
        riley.ResolverOp(riley.ResolverOpKind.multiply),
        riley.ResolverOp(riley.ResolverOpKind.add),
        riley.ResolverOp(riley.ResolverOpKind.clamp01),
        riley.ResolverOp(riley.ResolverOpKind.store),
    )
    render(
        "c_expression",
        riley.MeshShaderSet(
            mono=riley.ShaderPipe(
                stages=(
                    riley.ShaderSource(linear(0.5, 0.0), fields[0]),
                    riley.ShaderSource(linear(0.0, 0.5), fields[1]),
                ),
                resolver=riley.ShaderResolver(
                    riley.ResolverKind.expression,
                    operations=expression,
                ),
                constants=(0.65, 0.35),
            ),
        ),
        riley.RenderFormat.mono,
    )

    # --------------------------------------------------------------------------
    # 5. Composition D: Emissivity material parameter mapping
    # --------------------------------------------------------------------------
    emissivity_ops = (
        riley.ResolverOp(riley.ResolverOpKind.load, param),
        riley.ResolverOp(riley.ResolverOpKind.load, constants[0]),
        riley.ResolverOp(riley.ResolverOpKind.subtract),
        riley.ResolverOp(riley.ResolverOpKind.load, constants[1]),
        riley.ResolverOp(riley.ResolverOpKind.multiply),
        riley.ResolverOp(riley.ResolverOpKind.clamp01),
        riley.ResolverOp(riley.ResolverOpKind.store),
    )
    render(
        "d_emissivity_visualisation",
        riley.MeshShaderSet(
            mono=riley.ShaderPipe(
                stages=(
                    riley.ShaderSource(checker, ch[0]),
                    riley.GreyToEmissivity(
                        ch[0],
                        param,
                        emissivity_at_black=0.96,
                        emissivity_at_white=0.90,
                    ),
                ),
                resolver=riley.ShaderResolver(
                    riley.ResolverKind.expression,
                    operations=emissivity_ops,
                ),
                constants=(0.90, 1.0 / 0.06),
            ),
        ),
        riley.RenderFormat.mono,
    )

    # --------------------------------------------------------------------------
    # 6. Composition E: RGB expression with one result per colour channel
    # --------------------------------------------------------------------------
    rgb_expression_ops = (
        # R = clamp(0.65 * field0 + 0.35 * field1, 0, 1)
        riley.ResolverOp(riley.ResolverOpKind.load, fields[0]),
        riley.ResolverOp(riley.ResolverOpKind.load, constants[0]),
        riley.ResolverOp(riley.ResolverOpKind.multiply),
        riley.ResolverOp(riley.ResolverOpKind.load, fields[1]),
        riley.ResolverOp(riley.ResolverOpKind.load, constants[1]),
        riley.ResolverOp(riley.ResolverOpKind.multiply),
        riley.ResolverOp(riley.ResolverOpKind.add),
        riley.ResolverOp(riley.ResolverOpKind.clamp01),
        riley.ResolverOp(riley.ResolverOpKind.store, riley.Register(riley.RegisterKind.channel, 0)),

        # G = clamp(field0 * field1, 0, 1)
        riley.ResolverOp(riley.ResolverOpKind.load, fields[0]),
        riley.ResolverOp(riley.ResolverOpKind.load, fields[1]),
        riley.ResolverOp(riley.ResolverOpKind.multiply),
        riley.ResolverOp(riley.ResolverOpKind.clamp01),
        riley.ResolverOp(riley.ResolverOpKind.store, riley.Register(riley.RegisterKind.channel, 1)),

        # B = clamp(1 - field0, 0, 1)
        riley.ResolverOp(riley.ResolverOpKind.load, constants[2]),
        riley.ResolverOp(riley.ResolverOpKind.load, fields[0]),
        riley.ResolverOp(riley.ResolverOpKind.subtract),
        riley.ResolverOp(riley.ResolverOpKind.clamp01),
        riley.ResolverOp(riley.ResolverOpKind.store, riley.Register(riley.RegisterKind.channel, 2)),
    )
    render(
        "e_rgb_expression",
        riley.MeshShaderSet(
            rgb=riley.ShaderPipe(
                stages=(
                    riley.ShaderSource(linear(0.5, 0.0), fields[0]),
                    riley.ShaderSource(linear(0.0, 0.5), fields[1]),
                ),
                resolver=riley.ShaderResolver(
                    riley.ResolverKind.expression,
                    operations=rgb_expression_ops,
                ),
                constants=(0.65, 0.35, 1.0),
            ),
        ),
        riley.RenderFormat.rgb,
    )

    # --------------------------------------------------------------------------
    # 7. Composition F: Four-field expression outputs
    # --------------------------------------------------------------------------
    multifield_expression_ops = (
        # Output 0: horizontal gradient
        riley.ResolverOp(riley.ResolverOpKind.load, fields[0]),
        riley.ResolverOp(riley.ResolverOpKind.store, riley.Register(riley.RegisterKind.channel, 0)),

        # Output 1: vertical gradient
        riley.ResolverOp(riley.ResolverOpKind.load, fields[1]),
        riley.ResolverOp(riley.ResolverOpKind.store, riley.Register(riley.RegisterKind.channel, 1)),

        # Output 2: product of the gradients
        riley.ResolverOp(riley.ResolverOpKind.load, fields[0]),
        riley.ResolverOp(riley.ResolverOpKind.load, fields[1]),
        riley.ResolverOp(riley.ResolverOpKind.multiply),
        riley.ResolverOp(riley.ResolverOpKind.store, riley.Register(riley.RegisterKind.channel, 2)),

        # Output 3: squared difference of the gradients
        riley.ResolverOp(riley.ResolverOpKind.load, fields[0]),
        riley.ResolverOp(riley.ResolverOpKind.load, fields[1]),
        riley.ResolverOp(riley.ResolverOpKind.subtract),
        riley.ResolverOp(riley.ResolverOpKind.load, fields[0]),
        riley.ResolverOp(riley.ResolverOpKind.load, fields[1]),
        riley.ResolverOp(riley.ResolverOpKind.subtract),
        riley.ResolverOp(riley.ResolverOpKind.multiply),
        riley.ResolverOp(riley.ResolverOpKind.store, riley.Register(riley.RegisterKind.channel, 3)),
    )
    render(
        "f_multifield_expression",
        riley.MeshShaderSet(
            multifield=riley.ShaderPipe(
                stages=(
                    riley.ShaderSource(linear(0.5, 0.0), fields[0]),
                    riley.ShaderSource(linear(0.0, 0.5), fields[1]),
                ),
                resolver=riley.ShaderResolver(
                    riley.ResolverKind.expression,
                    operations=multifield_expression_ops,
                ),
            ),
        ),
        riley.RenderFormat.multifield,
        channels=4,
    )


if __name__ == "__main__":
    main()
