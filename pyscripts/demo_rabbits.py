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
from time import perf_counter

import numpy as np
import riley


def main() -> None:
    pixels_num = (1600, 800)
    fov_scale = 1.01
    out_dir = Path("pyout/demo-rabbits")
    default_pixel_size = (5.3e-6, 5.3e-6)
    default_focal_length = 50.0e-3
    rot_world = (0.0, np.pi, 0.0)
    texture_path = Path("texture/speckle.bmp")
    rabbit_mesh_types = [
        riley.MeshType.tri3,
        riley.MeshType.tri6,
        riley.MeshType.quad4ibi,
        riley.MeshType.quad8,
        riley.MeshType.quad9,
    ]

    import shutil
    from riley.python import sceneops

    shutil.rmtree(out_dir, ignore_errors=True)
    out_dir.mkdir(parents=True, exist_ok=True)

    def mesh_data_name(mesh_type: riley.MeshType) -> str:
        if mesh_type in (riley.MeshType.quad4ibi, riley.MeshType.quad4newton):
            return "quad4"
        return mesh_type.name

    def build_rabbit_dir(rabbit_name: str, mesh_type: riley.MeshType) -> Path:
        return Path("data/rabbits") / f"{rabbit_name}_{mesh_data_name(mesh_type)}"

    def load_static_mesh(data_dir: Path) -> tuple[np.ndarray, np.ndarray]:
        coords = np.loadtxt(
            data_dir / "coords.csv",
            delimiter=",",
            dtype=np.float64,
        )
        connect_float = np.loadtxt(
            data_dir / "connectivity.csv",
            delimiter=",",
            dtype=np.float64,
        )
        connect = np.ascontiguousarray(connect_float, dtype=np.uintp)
        return np.ascontiguousarray(coords, dtype=np.float64), connect

    def load_uvs(data_dir: Path) -> np.ndarray:
        return np.loadtxt(
            data_dir / "uvs.csv",
            delimiter=",",
            dtype=np.float64,
        )

    def make_grey_mesh_input(
        mesh_type: riley.MeshType,
        coords: np.ndarray,
        connect: np.ndarray,
        uvs: np.ndarray,
        texture: np.ndarray,
    ) -> riley.Mesh:
        return riley.Mesh(
            mesh_type=mesh_type,
            coords=np.ascontiguousarray(np.array(coords, copy=True), dtype=np.float64),
            connect=connect,
            shader_type=riley.ShaderType.tex,
            uvs=uvs,
            texture=texture,
            sample=riley.TextureSample.cubic_catmull_rom,
            sample_mode=riley.TextureSampleMode.lut_lerp,
            bits=8,
            scaling_type=riley.ScaleStrategy.none,
            normal_type=riley.NormalType.none,
        )

    texture = riley.load_texture(texture_path)
    mesh_inputs: list[riley.Mesh] = []
    group_list: list[sceneops.MeshGroup] = []

    for mesh_type in rabbit_mesh_types:
        riley_dir = build_rabbit_dir("riley", mesh_type)
        feebs_dir = build_rabbit_dir("feebs", mesh_type)

        riley_coords, riley_connect = load_static_mesh(riley_dir)
        feebs_coords, feebs_connect = load_static_mesh(feebs_dir)
        riley_uvs = load_uvs(riley_dir)
        feebs_uvs = load_uvs(feebs_dir)

        pair_start = len(mesh_inputs)
        mesh_inputs.append(
            make_grey_mesh_input(
                mesh_type,
                riley_coords,
                riley_connect,
                riley_uvs,
                texture,
            ),
        )
        mesh_inputs.append(
            make_grey_mesh_input(
                mesh_type,
                feebs_coords,
                feebs_connect,
                feebs_uvs,
                texture,
            ),
        )

        sceneops.overlap_mesh_group_bounds(
            mesh_inputs,
            sceneops.mesh_group_single(pair_start),
            sceneops.mesh_group_single(pair_start + 1),
            sceneops.BoundsOverlapSpec(
                overlap_frac=(0.85, 0.8, 0.0),
                enabled_axes=(True, True, False),
                direction=(
                    sceneops.OverlapDirection.POSITIVE,
                    sceneops.OverlapDirection.NEGATIVE,
                    sceneops.OverlapDirection.CURRENT,
                ),
            ),
        )
        group_list.append(sceneops.mesh_group_span(pair_start, 2))

    sceneops.arrange_mesh_groups_grid(
        mesh_inputs,
        group_list,
        sceneops.GridSpec(
            gap=(0.18, 0.28, 0.0),
            max_divs=(3, 2, 1),
        ),
    )

    roi_pos = riley.roi_cent_over_meshes(mesh_inputs)
    cam_pos = riley.pos_fill_frame_from_rot_over_meshes(
        mesh_inputs,
        pixels_num,
        default_pixel_size,
        default_focal_length,
        rot_world,
        fov_scale,
    )
    camera = riley.Camera(
        pixels_num=pixels_num,
        pixels_size=default_pixel_size,
        pos_world=cam_pos,
        rot_world=rot_world,
        roi_cent_world=roi_pos,
        focal_length=default_focal_length,
        sub_sample=2,
    )

    config = riley.build_config(
        num_frames=1,
        total_threads=1,
        save_strategy=riley.SaveStrategy.disk,
    )
    config.image_mode = riley.ImageMode.grey

    start_time = perf_counter()
    riley.raster(
        mesh_inputs,
        [camera],
        config,
        out_dir=str(out_dir),
    )
    elapsed_time = perf_counter() - start_time
    print(f"grey render time: {elapsed_time:.6f} s")
    print(f"rendered rabbits to {out_dir}")


if __name__ == "__main__":
    main()
