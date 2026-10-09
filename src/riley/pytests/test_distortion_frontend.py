from __future__ import annotations

import numpy as np
import pytest

import riley


@pytest.mark.parametrize("map_mode", tuple(riley.SubPixelCenterMap))
@pytest.mark.parametrize("buffer_mode", tuple(riley.BufferMode))
def test_distorted_triangle_interior_survives_tile_culling(
    map_mode: riley.SubPixelCenterMap,
    buffer_mode: riley.BufferMode,
) -> None:
    """The analytic k1 triangle has foreground at observed pixel (110, 100)."""
    coords = np.array(
        [[0.1, 0.5, 0.0], [0.1, -0.5, 0.0], [0.2, 0.0, 0.0]],
        dtype=np.float64,
    )
    connect = np.array([[0, 1, 2]], dtype=np.int64)
    convention = riley.ConnectConvention(
        riley.EElemType.TRI3,
        riley.EConnectAxis.ROW,
        0,
        riley.ENodeOrder.RILEY,
    )
    shader = riley.FunctionShader(
        builtin=riley.FuncShaderBuiltin.constant,
        params=riley.FuncShaderParams(constant_value=1.0),
        scaling_type=riley.ScaleStrategy.none,
    )
    mesh = riley.create_mesh(convention, riley.MeshType.tri3, coords, connect, shader)
    camera = riley.Camera(
        pixels_num=(200, 200),
        pixels_size=(0.01, 0.01),
        pos_world=(0.0, 0.0, 1.0),
        rot_world=(0.0, 0.0, 0.0),
        roi_cent_world=(0.0, 0.0, 0.0),
        focal_length=1.0,
        sub_sample=1,
        subpixel_center_map=map_mode,
        distort_model=1,
        distort_k1=1.0,
    )
    config = riley.RasterConfig(
        parallel=1,
        save_strategy=riley.SaveStrategy.memory,
    )
    config.report = riley.ReportMode.off
    config.buffer_mode = buffer_mode
    config.background_value = 0.0
    config.save_scaling = riley.ScaleStrategy.none
    config.edge_spacing_px = 1.0

    image = np.squeeze(riley.raster(mesh, camera, config))
    assert image.shape == (200, 200)
    assert image[100, 110] > 0.5
    assert image[100, 105] == 0.0
