# --------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher)
# --------------------------------------------------------------------------
"""Render the rabbit grid as one monochrome BMP."""

from __future__ import annotations

import shutil
from pathlib import Path
from time import perf_counter

import numpy as np

import riley


def main() -> None:
    # --------------------------------------------------------------------------
    # 1. Load a bundled texture and prepare the output directory
    # --------------------------------------------------------------------------
    out_dir = Path.cwd() / "out_riley_py" / "demo2a_rabbits_mono"
    shutil.rmtree(out_dir, ignore_errors=True)
    out_dir.mkdir(parents=True)

    channels = 1
    texture_path = riley.data.speckle_texture_path()
    texture = riley.load_texture_mono_u8(texture_path)

    # --------------------------------------------------------------------------
    # 2. Load each rabbit pair and assign texture, nodal, and checker shaders
    # --------------------------------------------------------------------------
    rabbit_names = ("riley", "feebs")
    # Shaders are listed in rabbit_names order: Riley first, Feebs second.
    pairs = (
        (riley.MeshType.tri3, riley.EElemType.TRI3, ("texture", "nodal")),
        (riley.MeshType.tri6, riley.EElemType.TRI6, ("checker", "texture")),
        (riley.MeshType.quad4, riley.EElemType.QUAD4, ("nodal", "checker")),
        (riley.MeshType.quad8, riley.EElemType.QUAD8, ("texture", "nodal")),
        (riley.MeshType.quad9, riley.EElemType.QUAD9, ("checker", "texture")),
    )
    checker_squares_per_axis = 36.0
    pair_overlap = riley.SceneBoundsOverlapSpec(
        overlap_frac=(0.85, 0.8, 0.0),
        enabled_axes=(True, True, False),
        direct=(
            riley.ESceneOverlapDirect.POSITIVE,
            riley.ESceneOverlapDirect.NEGATIVE,
            riley.ESceneOverlapDirect.CURRENT,
        ),
    )
    meshes: list[riley.Mesh] = []
    mesh_coords: list[np.ndarray] = []
    rabbit_pairs: list[riley.SceneMeshGroup] = []
    for mesh_type, elem_type, shaders in pairs:
        # Bundled connectivity is zero-based, one element per row, in Riley order.
        convention = riley.ConnectConvention(
            elem_type=elem_type,
            elem_axis=riley.EConnectAxis.ROW,
            index_base=0,
            node_order=riley.ENodeOrder.RILEY,
        )
        pair_start = len(meshes)
        for rabbit_name, shader_kind in zip(rabbit_names, shaders, strict=True):
            data_dir = riley.data.rabbit_case_path(rabbit_name, mesh_type.name)
            coords = riley.load_csv(data_dir / "coords.csv")
            connect = riley.load_csv(data_dir / "connectivity.csv", dtype=np.int64)
            uvs = riley.load_csv(data_dir / "uvs.csv")


            if shader_kind == "texture":
                shader = riley.TextureShader(uvs=uvs, texture=texture)
            elif shader_kind == "nodal":
                # Riley nodal fields have axes (node, frame, channel).
                # Average U and V to get one intensity per node in one static frame.
                uv_average = 0.5 * (uvs[:, 0] + uvs[:, 1])
                field = np.ascontiguousarray(uv_average[:, None, None])
                shader = riley.NodalShader(
                    field=field,
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
            mesh = riley.create_mesh(convention, mesh_type, coords, connect, shader)
            meshes.append(mesh)
            mesh_coords.append(mesh.coords)

        # Move Feebs towards +X and -Y relative to Riley without changing Z.
        # Scene layout functions translate the meshes' coordinate arrays in place.
        riley.scene_overlap_mesh_group_bounds(
            mesh_coords,
            riley.scene_create_mesh_group_single(pair_start),
            riley.scene_create_mesh_group_single(pair_start + 1),
            pair_overlap,
        )
        rabbit_pairs.append(riley.scene_create_mesh_group_span(pair_start, 2))

    # --------------------------------------------------------------------------
    # 3. Arrange the five pairs in a three-column grid on the XY plane
    # --------------------------------------------------------------------------
    riley.scene_arrange_mesh_groups_grid(
        mesh_coords,
        rabbit_pairs,
        riley.SceneGridSpec(gap=(0.18, 0.28, 0.0), max_divs=(3, 2, 1)),
    )

    # --------------------------------------------------------------------------
    # 4. Frame the laid-out scene with a single camera
    # --------------------------------------------------------------------------
    pixels_num = (1600, 800)
    fov_scale = 1.01
    pixels_size = (5.3e-6, 5.3e-6)
    focal_length = 50.0e-3
    rot_world = (0.0, 0.0, 0.0)

    roi_pos = riley.roi_cent_over_meshes(meshes)
    cam_pos = riley.pos_frame_meshes(
        meshes,
        pixels_num,
        pixels_size,
        focal_length,
        rot_world,
        fov_scale=fov_scale,
    )
    camera = riley.Camera(
        pixels_num=pixels_num,
        pixels_size=pixels_size,
        pos_world=cam_pos,
        rot_world=rot_world,
        roi_cent_world=roi_pos,
        focal_length=focal_length,
        sub_sample=4,
    )

    # --------------------------------------------------------------------------
    # 5. Render the scene and save the images
    # --------------------------------------------------------------------------
    # Save the single rendered intensity channel as a monochrome BMP.
    config = riley.RasterConfig(
        parallel=4,
        save_strategy=riley.SaveStrategy.disk,
        image_save_mode=riley.ImageSaveMode.grey,
        save_format=riley.ImageFormat.bmp,
        save_bits=8,
        save_scaling=riley.ScaleStrategy.none,
        background_value=127.5,
    )

    start_time = perf_counter()
    riley.raster(meshes, [camera], config, out_dir=str(out_dir))
    elapsed_time = perf_counter() - start_time
    print(f"grey render time: {elapsed_time:.6f} s")
    print(f"rendered rabbits to {out_dir}")


if __name__ == "__main__":
    main()
