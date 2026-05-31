# --------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher)
# --------------------------------------------------------------------------
from __future__ import annotations

import os
from pathlib import Path
import shutil
from time import perf_counter

import numpy as np
from PIL import Image

import riley


OVERLAP_X = 0.85
OVERLAP_Y = 0.8
BEHIND_FACT = 1.05
PIXELS_NUM = (1600, 800)
FOV_SCALE = 1.01
OUT_DIR = Path("pyout/demo-rabbits")
PAIR_GAP_FACTOR = 0.18
ROW_GAP_FACTOR = 0.28
FEEBS_FRONT_RILEY_SHIFT_FACTOR = 0.1
DEFAULT_PIXEL_SIZE = (5.3e-6, 5.3e-6)
DEFAULT_FOCAL_LENGTH = 50.0e-3
ROT_WORLD = (0.0, np.pi, 0.0)
TEXTURE_PATH = Path("texture/speckle.bmp")
RABBIT_MESH_TYPES = [
    riley.MeshType.tri3,
    riley.MeshType.tri6,
    riley.MeshType.quad4ibi,
    riley.MeshType.quad8,
    riley.MeshType.quad9,
]
SILENT_RENDER = os.environ.get("RILEY_DEMO_SILENT") == "1"


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
    return coords, connect


def load_uvs(data_dir: Path) -> np.ndarray:
    return np.loadtxt(
        data_dir / "uvs.csv",
        delimiter=",",
        dtype=np.float64,
    )


def build_uv_scalar_field(uvs: np.ndarray) -> np.ndarray:
    field = np.empty((1, uvs.shape[0], 1), dtype=np.float64)
    field[0, :, 0] = 0.5 * (uvs[:, 0] + uvs[:, 1])
    return field


def sinusoidal_uv_params() -> riley.TexFuncParams:
    wave_num = 2.0 * np.pi * 6.0
    return riley.TexFuncParams(
        wave_num_scalar=(wave_num, wave_num),
    )


def make_mesh_input(
    mesh_type: riley.MeshType,
    coords: np.ndarray,
    connect: np.ndarray,
    uvs: np.ndarray,
    texture: np.ndarray,
    texture_rgb: np.ndarray,
    shader_index: int,
) -> riley.MeshInput:
    shader_mode = shader_index % 5
    if shader_mode == 0:
        return riley.MeshInput(
            mesh_type=mesh_type,
            coords=coords,
            connect=connect,
            shader_tag=riley.ShaderType.tex,
            uvs=uvs,
            texture=texture,
            sample=riley.TextureSample.cubic_catmull_rom,
            sample_mode=riley.TextureSampleMode.lut_lerp,
            bits=8,
            scaling_tag=riley.ScaleStrategy.none,
            normal_type=riley.NormalType.none,
        )
    if shader_mode == 1:
        return riley.MeshInput(
            mesh_type=mesh_type,
            coords=coords,
            connect=connect,
            shader_tag=riley.ShaderType.tex_rgb,
            uvs=uvs,
            texture=texture_rgb,
            sample=riley.TextureSample.cubic_catmull_rom,
            sample_mode=riley.TextureSampleMode.lut_lerp,
            bits=8,
            scaling_tag=riley.ScaleStrategy.none,
            normal_type=riley.NormalType.none,
        )
    if shader_mode == 2:
        return riley.MeshInput(
            mesh_type=mesh_type,
            coords=coords,
            connect=connect,
            shader_tag=riley.ShaderType.nodal,
            nodal_field=build_uv_scalar_field(uvs),
            bits=8,
            scaling_tag=riley.ScaleStrategy.auto,
            scale_over=riley.ScaleOver.over_frames,
            normal_type=riley.NormalType.none,
        )
    if shader_mode == 3:
        return riley.MeshInput(
            mesh_type=mesh_type,
            coords=coords,
            connect=connect,
            shader_tag=riley.ShaderType.tex_func,
            uvs=uvs,
            tex_func_builtin=riley.TexFuncBuiltin.sinusoidal,
            tex_func_params=sinusoidal_uv_params(),
            bits=8,
            scaling_tag=riley.ScaleStrategy.auto,
            normal_type=riley.NormalType.none,
        )
    return riley.MeshInput(
        mesh_type=mesh_type,
        coords=coords,
        connect=connect,
        shader_tag=riley.ShaderType.tex_func_rgb,
        uvs=uvs,
        tex_func_builtin=riley.TexFuncBuiltin.sinusoidal,
        tex_func_params=sinusoidal_uv_params(),
        bits=8,
        scaling_tag=riley.ScaleStrategy.auto,
        normal_type=riley.NormalType.none,
    )


def bounds_for_coords(
    coords_a: np.ndarray,
    coords_b: np.ndarray,
) -> tuple[float, float, float, float]:
    min_x = min(float(np.min(coords_a[:, 0])), float(np.min(coords_b[:, 0])))
    max_x = max(float(np.max(coords_a[:, 0])), float(np.max(coords_b[:, 0])))
    min_y = min(float(np.min(coords_a[:, 1])), float(np.min(coords_b[:, 1])))
    max_y = max(float(np.max(coords_a[:, 1])), float(np.max(coords_b[:, 1])))
    return min_x, max_x, min_y, max_y


def main() -> None:
    shutil.rmtree(OUT_DIR, ignore_errors=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    with Image.open(TEXTURE_PATH) as image_in:
        image_grey = image_in.convert("L")
        image_u8 = np.asarray(image_grey, dtype=np.uint8)
        image_rgb = image_in.convert("RGB")
        image_rgb_u8 = np.asarray(image_rgb, dtype=np.uint8)
    texture = np.ascontiguousarray(image_u8, dtype=np.float64)
    texture_rgb = np.ascontiguousarray(
        np.transpose(image_rgb_u8, (2, 0, 1)),
        dtype=np.float64,
    )
    mesh_inputs: list[riley.MeshInput] = []
    pair_widths = np.zeros((len(RABBIT_MESH_TYPES),), dtype=np.float64)
    pair_heights = np.zeros((len(RABBIT_MESH_TYPES),), dtype=np.float64)
    pair_center_xs = np.zeros((len(RABBIT_MESH_TYPES),), dtype=np.float64)
    pair_center_ys = np.zeros((len(RABBIT_MESH_TYPES),), dtype=np.float64)
    max_pair_width = 0.0
    max_pair_height = 0.0

    for ii, mesh_type in enumerate(RABBIT_MESH_TYPES):
        riley_dir = build_rabbit_dir("riley", mesh_type)
        feebs_dir = build_rabbit_dir("feebs", mesh_type)

        riley_coords, riley_connect = load_static_mesh(riley_dir)
        feebs_coords, feebs_connect = load_static_mesh(feebs_dir)
        riley_uvs = load_uvs(riley_dir)
        feebs_uvs = load_uvs(feebs_dir)

        riley_coords = np.ascontiguousarray(
            np.array(riley_coords, copy=True),
            dtype=np.float64,
        )
        feebs_coords = np.ascontiguousarray(
            np.array(feebs_coords, copy=True),
            dtype=np.float64,
        )

        coords_min = np.min(riley_coords, axis=0)
        coords_max = np.max(riley_coords, axis=0)
        base_extent = coords_max - coords_min
        x_sep = float(base_extent[0]) * (1.0 - OVERLAP_X)
        y_sep = float(base_extent[1]) * (1.0 - OVERLAP_Y)
        feebs_front_riley_shift = (
            FEEBS_FRONT_RILEY_SHIFT_FACTOR * float(base_extent[0]),
            FEEBS_FRONT_RILEY_SHIFT_FACTOR * float(base_extent[1]),
            0.0,
        )

        riley_front = (ii % 2) == 0
        front_idx = ii * 2
        back_idx = front_idx + 1

        if riley_front:
            front_mesh = make_mesh_input(
                mesh_type,
                riley_coords,
                riley_connect,
                riley_uvs,
                texture,
                texture_rgb,
                front_idx,
            )
            back_mesh = make_mesh_input(
                mesh_type,
                feebs_coords,
                feebs_connect,
                feebs_uvs,
                texture,
                texture_rgb,
                back_idx,
            )
        else:
            front_mesh = make_mesh_input(
                mesh_type,
                feebs_coords,
                feebs_connect,
                feebs_uvs,
                texture,
                texture_rgb,
                front_idx,
            )
            back_mesh = make_mesh_input(
                mesh_type,
                riley_coords,
                riley_connect,
                riley_uvs,
                texture,
                texture_rgb,
                back_idx,
            )

        front_mesh.coords[:, 0] += 0.5 * x_sep
        front_mesh.coords[:, 1] -= 0.5 * y_sep
        back_mesh.coords[:, 0] -= 0.5 * x_sep
        back_mesh.coords[:, 1] += 0.5 * y_sep
        if not riley_front:
            back_mesh.coords[:, 0] += feebs_front_riley_shift[0]
            back_mesh.coords[:, 1] += feebs_front_riley_shift[1]
            back_mesh.coords[:, 2] += feebs_front_riley_shift[2]

        temp_meshes = [front_mesh, back_mesh]
        roi_pos = riley.roi_cent_over_meshes(temp_meshes)
        cam_pos = riley.pos_fill_frame_from_rot_over_meshes(
            temp_meshes,
            PIXELS_NUM,
            DEFAULT_PIXEL_SIZE,
            DEFAULT_FOCAL_LENGTH,
            ROT_WORLD,
            FOV_SCALE,
        )

        front_min = np.min(front_mesh.coords, axis=0)
        front_max = np.max(front_mesh.coords, axis=0)
        front_centroid = 0.5 * (front_min + front_max)
        cam_axis = np.asarray(cam_pos, dtype=np.float64) - np.asarray(
            roi_pos,
            dtype=np.float64,
        )
        cam_axis_unit = cam_axis / np.linalg.norm(cam_axis)
        front_dist = float(
            np.dot(
                np.asarray(cam_pos, dtype=np.float64) - front_centroid,
                cam_axis_unit,
            ),
        )
        behind_extra = (BEHIND_FACT - 1.0) * front_dist
        back_mesh.coords[:, 0] -= cam_axis_unit[0] * behind_extra
        back_mesh.coords[:, 1] -= cam_axis_unit[1] * behind_extra
        back_mesh.coords[:, 2] -= cam_axis_unit[2] * behind_extra

        min_x, max_x, min_y, max_y = bounds_for_coords(
            front_mesh.coords,
            back_mesh.coords,
        )
        pair_widths[ii] = max_x - min_x
        pair_heights[ii] = max_y - min_y
        pair_center_xs[ii] = 0.5 * (min_x + max_x)
        pair_center_ys[ii] = 0.5 * (min_y + max_y)
        max_pair_width = max(max_pair_width, float(pair_widths[ii]))
        max_pair_height = max(max_pair_height, float(pair_heights[ii]))

        mesh_inputs.extend([front_mesh, back_mesh])

    pair_gap_x = PAIR_GAP_FACTOR * max_pair_width
    row_gap_y = ROW_GAP_FACTOR * max_pair_height
    top_row_total_width = float(np.sum(pair_widths[0:2]) + pair_gap_x)
    bottom_row_total_width = float(np.sum(pair_widths[2:]) + 2.0 * pair_gap_x)
    top_row_max_height = max(float(pair_heights[0]), float(pair_heights[1]))
    bottom_row_max_height = float(np.max(pair_heights[2:]))
    top_row_center_y = 0.5 * (bottom_row_max_height + row_gap_y)
    bottom_row_center_y = -0.5 * (top_row_max_height + row_gap_y)

    top_cursor = -0.5 * top_row_total_width
    for ii in range(2):
        desired_center_x = top_cursor + 0.5 * float(pair_widths[ii])
        delta_x = desired_center_x - float(pair_center_xs[ii])
        delta_y = top_row_center_y - float(pair_center_ys[ii])
        mesh_inputs[ii * 2].coords[:, 0] += delta_x
        mesh_inputs[ii * 2].coords[:, 1] += delta_y
        mesh_inputs[ii * 2 + 1].coords[:, 0] += delta_x
        mesh_inputs[ii * 2 + 1].coords[:, 1] += delta_y
        top_cursor += float(pair_widths[ii]) + pair_gap_x

    bottom_cursor = -0.5 * bottom_row_total_width
    for ii in range(2, len(RABBIT_MESH_TYPES)):
        desired_center_x = bottom_cursor + 0.5 * float(pair_widths[ii])
        delta_x = desired_center_x - float(pair_center_xs[ii])
        delta_y = bottom_row_center_y - float(pair_center_ys[ii])
        mesh_inputs[ii * 2].coords[:, 0] += delta_x
        mesh_inputs[ii * 2].coords[:, 1] += delta_y
        mesh_inputs[ii * 2 + 1].coords[:, 0] += delta_x
        mesh_inputs[ii * 2 + 1].coords[:, 1] += delta_y
        bottom_cursor += float(pair_widths[ii]) + pair_gap_x

    roi_pos = tuple(riley.roi_cent_over_meshes(mesh_inputs))
    cam_pos = tuple(
        riley.pos_fill_frame_from_rot_over_meshes(
            mesh_inputs,
            PIXELS_NUM,
            DEFAULT_PIXEL_SIZE,
            DEFAULT_FOCAL_LENGTH,
            ROT_WORLD,
            FOV_SCALE,
        ),
    )
    camera = riley.CameraInput(
        pixels_num=PIXELS_NUM,
        pixels_size=DEFAULT_PIXEL_SIZE,
        pos_world=cam_pos,
        rot_world=ROT_WORLD,
        roi_cent_world=roi_pos,
        focal_length=DEFAULT_FOCAL_LENGTH,
        sub_sample=2,
    )
    config = riley.RasterConfig(
        save_strategy=riley.SaveStrategy.disk,
        background_value=0.0,
        report=(
            riley.ReportMode.off
            if SILENT_RENDER
            else riley.ReportMode.bench
        ),
    )
    start_time = perf_counter()
    riley.raster(mesh_inputs, [camera], config, out_dir=str(OUT_DIR))
    elapsed_time = perf_counter() - start_time
    if not SILENT_RENDER:
        print(f"render time: {elapsed_time:.6f} s")
        print(f"rendered rabbits to {OUT_DIR}")


if __name__ == "__main__":
    main()
