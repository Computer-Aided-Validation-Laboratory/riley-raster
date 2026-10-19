"""One mesh, two camera-selected shaders: direct checker and lit checker."""
from pathlib import Path

import numpy as np
import riley


def main() -> None:
    coords = np.array(((-1, -1, 0), (1, -1, 0), (0, 1, 0)), dtype=np.float64)
    connect = np.array(((0, 1, 2),), dtype=np.int64)
    convention = riley.ConnectConvention(riley.EElemType.TRI3, riley.EConnectAxis.ROW, 0, riley.ENodeOrder.RILEY)
    checker = riley.FunctionShader(
        builtin=riley.FuncShaderBuiltin.checker,
        coord_mode=riley.FuncCoordMode.world_reference,
        params=riley.FuncShaderParams(coord_scale=(4, 4)),
        scaling_type=riley.ScaleStrategy.auto,
    )
    light = riley.FunctionShader(
        builtin=riley.FuncShaderBuiltin.linear,
        coord_mode=riley.FuncCoordMode.world_reference,
        params=riley.FuncShaderParams(linear_coeffs=(0.625, 0.375, 0)),
        bits=-1, scaling_type=riley.ScaleStrategy.none,
    )
    channel = riley.Slot(riley.SlotKind.channel, 0)
    parameter = riley.Slot(riley.SlotKind.parameter, 0)
    shaders = riley.MeshShaderSet(
        direct=checker,
        mono=riley.ShaderPipe(
            stages=(riley.ShaderSource(checker, channel), riley.ShaderSource(light, parameter)),
            resolver=riley.ShaderResolver(riley.ResolverKind.modulate, slots=(channel,), factor=parameter),
        ),
    )
    mesh = riley.create_mesh(convention, riley.MeshType.tri3opt, coords, connect, shaders)
    pixels_num = (512, 512)
    pixels_size = (0.02, 0.02)
    target = riley.roi_cent_from_coords(coords)
    position = riley.pos_frame_mesh(mesh, pixels_num, pixels_size, 1, (0, 0, 0), target=target)
    direct = riley.Camera(pixels_num, pixels_size, position, (0, 0, 0), target, 1, 4)
    lit = riley.Camera(pixels_num, pixels_size, position, (0, 0, 0), target, 1, 4,
                       shader_selection=riley.CameraShaderSelection.mono)
    config = riley.RasterConfig(parallel=1, save_strategy=riley.SaveStrategy.disk,
                                image_save_mode=riley.ImageSaveMode.grey)
    config.save_format = riley.ImageFormat.bmp
    config.save_bits = 8
    config.save_scaling = riley.ScaleStrategy.none
    config.output_name_format = "demo7_cam{camera}_frame{frame}_field{field}"
    riley.raster(mesh, (direct, lit), config, out_dir=str(Path.cwd() / "out_riley_py" / "demo7_shaderpipe_quickstart"))


if __name__ == "__main__":
    main()
