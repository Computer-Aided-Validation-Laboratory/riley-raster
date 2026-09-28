# --------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher)
# --------------------------------------------------------------------------
from __future__ import annotations

from pathlib import Path

import numpy as np

import riley
from riley.python import sceneops


def build_uv_field(uvs: np.ndarray, channels: int) -> np.ndarray:
    """Build a field with axes (nodes, one frame, channels)."""
    uv_scalar = 0.5 * (uvs[:, 0] + uvs[:, 1])
    values = uv_scalar[:, None] if channels == 1 else np.column_stack((uvs, uv_scalar))
    return np.ascontiguousarray(values[:, None, :], dtype=np.float64)


def mesh_data_name(mesh_type: riley.MeshType) -> str:
    return mesh_type.name


def build_rabbit_dir(rabbit_name: str, mesh_type: riley.MeshType) -> Path:
    return riley.data.rabbit_case_path(rabbit_name, mesh_data_name(mesh_type))


def load_static_mesh(data_dir: Path) -> tuple[np.ndarray, np.ndarray]:
    coords = riley.load_csv(data_dir / "coords.csv")
    connect = riley.load_csv(data_dir / "connectivity.csv", dtype=np.int64)
    return coords, connect


def load_uvs(data_dir: Path) -> np.ndarray:
    return riley.load_csv(data_dir / "uvs.csv")


def make_mesh_input(
    mesh_type: riley.MeshType,
    mesh_idx: int,
    coords: np.ndarray,
    connect: np.ndarray,
    uvs: np.ndarray,
    texture: np.ndarray,
    channels: int,
    checker_squares_per_axis: float,
) -> riley.Mesh:
    shader_idx = mesh_idx % 3
    elem_type = {
        riley.MeshType.tri3: riley.EElemType.TRI3,
        riley.MeshType.tri6: riley.EElemType.TRI6,
        riley.MeshType.quad4: riley.EElemType.QUAD4,
        riley.MeshType.quad8: riley.EElemType.QUAD8,
        riley.MeshType.quad9: riley.EElemType.QUAD9,
    }[mesh_type]
    convention = riley.ConnectConvention(
        elem_type,
        riley.EConnectAxis.ROW,
        0,
        riley.ENodeOrder.RILEY,
    )

    if shader_idx == 0:
        shader = riley.TextureShader(uvs=uvs, texture=texture)
    elif shader_idx == 1:
        shader = riley.NodalShader(
            field=build_uv_field(uvs, channels),
            scaling_type=riley.ScaleStrategy.auto,
        )
    else:
        shader = riley.FunctionShader(
            builtin=riley.FuncShaderBuiltin.checker,
            coord_mode=riley.FuncCoordMode.uv,
            params=riley.FuncShaderParams(
                coord_scale=(checker_squares_per_axis,) * 2,
            ),
            channels=channels,
            uvs=uvs,
            scaling_type=riley.ScaleStrategy.auto,
        )
    return riley.create_mesh(
        convention,
        mesh_type,
        np.array(coords, copy=True),
        connect,
        shader=shader,
    )


def build_scene(
    texture: np.ndarray,
    channels: int,
    mesh_types: list[riley.MeshType],
    overlap_frac_xy: tuple[float, float],
    checker_squares_per_axis: float,
    gap: tuple[float, float, float],
    max_divs: tuple[int, int, int],
) -> list[riley.Mesh]:
    mesh_inputs: list[riley.Mesh] = []
    group_list: list[sceneops.SceneMeshGroup] = []

    for mesh_type in mesh_types:
        riley_dir = build_rabbit_dir("riley", mesh_type)
        feebs_dir = build_rabbit_dir("feebs", mesh_type)

        riley_coords, riley_connect = load_static_mesh(riley_dir)
        feebs_coords, feebs_connect = load_static_mesh(feebs_dir)
        riley_uvs = load_uvs(riley_dir)
        feebs_uvs = load_uvs(feebs_dir)

        pair_start = len(mesh_inputs)
        mesh_inputs.append(
            make_mesh_input(
                mesh_type,
                pair_start,
                riley_coords,
                riley_connect,
                riley_uvs,
                texture,
                channels,
                checker_squares_per_axis,
            ),
        )
        mesh_inputs.append(
            make_mesh_input(
                mesh_type,
                pair_start + 1,
                feebs_coords,
                feebs_connect,
                feebs_uvs,
                texture,
                channels,
                checker_squares_per_axis,
            ),
        )

        coords_list = [m.coords for m in mesh_inputs]

        sceneops.scene_overlap_mesh_group_bounds(
            coords_list,
            sceneops.scene_create_mesh_group_single(pair_start),
            sceneops.scene_create_mesh_group_single(pair_start + 1),
            sceneops.SceneBoundsOverlapSpec(
                overlap_frac=(*overlap_frac_xy, 0.0),
                enabled_axes=(True, True, False),
                direct=(
                    sceneops.ESceneOverlapDirect.POSITIVE,
                    sceneops.ESceneOverlapDirect.NEGATIVE,
                    sceneops.ESceneOverlapDirect.CURRENT,
                ),
            ),
        )
        group_list.append(
            sceneops.scene_create_mesh_group_span(pair_start, 2),
        )

    # --------------------------------------------------------------------------
    # 3. Arrange rabbit groups in grid layout
    # --------------------------------------------------------------------------
    coords_list = [m.coords for m in mesh_inputs]

    sceneops.scene_arrange_mesh_groups_grid(
        coords_list,
        group_list,
        sceneops.SceneGridSpec(gap=gap, max_divs=max_divs),
    )

    return mesh_inputs
