# --------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher)
# --------------------------------------------------------------------------
import numpy as np
from pathlib import Path
from PIL import Image


def load_sim_csvs(
    data_dir: str | Path,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    data_path = Path(data_dir)

    coords = np.loadtxt(
        data_path / "coords.csv",
        delimiter=",",
        dtype=np.float64,
    )
    connect_float = np.loadtxt(
        data_path / "connect.csv",
        delimiter=",",
        dtype=np.float64,
    )
    connect = np.ascontiguousarray(connect_float, dtype=np.uintp)

    uvs = None
    if (data_path / "uvs.csv").is_file():
        uvs = np.loadtxt(
            data_path / "uvs.csv",
            delimiter=",",
            dtype=np.float64,
        )

    disp_shape = None

    disp_x = None
    if (data_path / "field_disp_x.csv").is_file():
        disp_x = np.loadtxt(
            data_path / "field_disp_x.csv",
            delimiter=",",
            dtype=np.float64,
        )
        disp_shape = disp_x.shape

    disp_y = None
    if (data_path / "field_disp_y.csv").is_file():
        disp_y = np.loadtxt(
            data_path / "field_disp_y.csv",
            delimiter=",",
            dtype=np.float64,
        )
        disp_shape = disp_y.shape

    disp_z = None
    if (data_path / "field_disp_z.csv").is_file():
        disp_z = np.loadtxt(
            data_path / "field_disp_z.csv",
            delimiter=",",
            dtype=np.float64,
        )
        disp_shape = disp_z.shape

    disp = None
    if disp_shape is not None:    
        disp = np.zeros((disp_shape[1], disp_shape[0], 3), 
            dtype=np.float64)
        if disp_x is not None:
            disp[:, :, 0] = disp_x.T
        if disp_y is not None:
            disp[:, :, 1] = disp_y.T
        if disp_z is not None:
            disp[:, :, 2] = disp_z.T

    return coords, connect, uvs, disp


def load_texture(texture_path: str | Path) -> np.ndarray:
    with Image.open(Path(texture_path)) as image_in:
        image_grey = image_in.convert("L")
        image_u8 = np.asarray(image_grey, dtype=np.uint8)
    return np.ascontiguousarray(image_u8, dtype=np.uint8)


def project_uvs_planar_bbox(
    coords: np.ndarray,
    texture_size: tuple[int, int] | tuple[float, float],
    px_bbox: tuple[float, float, float, float],
    projection_plane: str | tuple[np.ndarray, np.ndarray],
    mode: str = "best",
) -> np.ndarray:
    if isinstance(projection_plane, str):
        plane = projection_plane.lower()
        if plane == "xy":
            u_axis = np.array([1.0, 0.0, 0.0], dtype=np.float64)
            v_axis = np.array([0.0, 1.0, 0.0], dtype=np.float64)
            origin = np.array([0.0, 0.0, 0.0], dtype=np.float64)
        elif plane == "yz":
            u_axis = np.array([0.0, 1.0, 0.0], dtype=np.float64)
            v_axis = np.array([0.0, 0.0, 1.0], dtype=np.float64)
            origin = np.array([0.0, 0.0, 0.0], dtype=np.float64)
        elif plane == "xz":
            u_axis = np.array([1.0, 0.0, 0.0], dtype=np.float64)
            v_axis = np.array([0.0, 0.0, 1.0], dtype=np.float64)
            origin = np.array([0.0, 0.0, 0.0], dtype=np.float64)
        else:
            raise ValueError(f"Unknown plane: {projection_plane}")
    else:
        normal, origin = projection_plane
        normal = np.asarray(normal, dtype=np.float64)
        origin = np.asarray(origin, dtype=np.float64)
        normal /= np.linalg.norm(normal)

        if np.abs(normal[2]) < 0.999:
            u_axis = np.cross(
                np.array([0.0, 0.0, 1.0], dtype=np.float64),
                normal,
            )
        else:
            u_axis = np.cross(
                normal,
                np.array([0.0, 1.0, 0.0], dtype=np.float64),
            )
        u_axis /= np.linalg.norm(u_axis)
        v_axis = np.cross(normal, u_axis)
        v_axis /= np.linalg.norm(v_axis)

    diff = coords - origin
    x_proj = np.dot(diff, u_axis)
    y_proj = np.dot(diff, v_axis)

    x_min = np.min(x_proj)
    x_max = np.max(x_proj)
    y_min = np.min(y_proj)
    y_max = np.max(y_proj)

    mesh_w = x_max - x_min
    mesh_h = y_max - y_min

    px_x_l, px_y_l, px_x_u, px_y_u = px_bbox
    px_w = px_x_u - px_x_l
    px_h = px_y_u - px_y_l

    scale_x = px_w / mesh_w if mesh_w > 0.0 else 1.0
    scale_y = px_h / mesh_h if mesh_h > 0.0 else 1.0

    if mode == "fit_x":
        scale = scale_x
    elif mode == "fit_y":
        scale = scale_y
    elif mode == "best":
        scale = 0.5 * (scale_x + scale_y)
    else:
        raise ValueError(f"Unknown mode: {mode}")

    mesh_cx = 0.5 * (x_min + x_max)
    mesh_cy = 0.5 * (y_min + y_max)
    px_cx = 0.5 * (px_x_l + px_x_u)
    px_cy = 0.5 * (px_y_l + px_y_u)

    px_x = px_cx + (x_proj - mesh_cx) * scale
    px_y = px_cy + (y_proj - mesh_cy) * scale

    tex_w, tex_h = texture_size
    uvs = np.zeros((coords.shape[0], 2), dtype=np.float64)
    uvs[:, 0] = px_x / tex_w
    uvs[:, 1] = 1.0 - (px_y / tex_h)
    return uvs


def project_uvs_planar_centered(
    coords: np.ndarray,
    texture_size: tuple[int, int] | tuple[float, float],
    uv_span_max: float = 1.0,
    projection_plane: str | tuple[np.ndarray, np.ndarray] = "xy",
) -> np.ndarray:
    tex_w = float(texture_size[0])
    tex_h = float(texture_size[1])

    if isinstance(projection_plane, str):
        plane = projection_plane.lower()
        if plane == "xy":
            proj_coords = coords[:, :2]
        elif plane == "yz":
            proj_coords = coords[:, 1:3]
        elif plane == "xz":
            proj_coords = coords[:, (0, 2)]
        else:
            raise ValueError(f"Unknown plane: {projection_plane}")
    else:
        normal, origin = projection_plane
        normal = np.asarray(normal, dtype=np.float64)
        origin = np.asarray(origin, dtype=np.float64)
        normal /= np.linalg.norm(normal)

        if np.abs(normal[2]) < 0.999:
            u_axis = np.cross(
                np.array([0.0, 0.0, 1.0], dtype=np.float64),
                normal,
            )
        else:
            u_axis = np.cross(
                normal,
                np.array([0.0, 1.0, 0.0], dtype=np.float64),
            )
        u_axis /= np.linalg.norm(u_axis)
        v_axis = np.cross(normal, u_axis)
        v_axis /= np.linalg.norm(v_axis)

        diff = coords - origin
        proj_coords = np.column_stack((
            np.dot(diff, u_axis),
            np.dot(diff, v_axis),
        ))

    x_min = np.min(proj_coords[:, 0])
    x_max = np.max(proj_coords[:, 0])
    y_min = np.min(proj_coords[:, 1])
    y_max = np.max(proj_coords[:, 1])

    mesh_ar = (x_max - x_min) / (y_max - y_min)
    tex_ar = tex_w / tex_h
    aspect_ratio_ratio = mesh_ar / tex_ar

    if aspect_ratio_ratio > 1.0:
        d_u = uv_span_max
        d_v = d_u / aspect_ratio_ratio
        mode = "fit_x"
    else:
        d_v = uv_span_max
        d_u = d_v * aspect_ratio_ratio
        mode = "fit_y"

    u_min = 0.5 * (1.0 - d_u)
    u_max = 1.0 - u_min
    v_min = 0.5 * (1.0 - d_v)
    v_max = 1.0 - v_min

    px_bbox = (
        u_min * tex_w,
        (1.0 - v_max) * tex_h,
        u_max * tex_w,
        (1.0 - v_min) * tex_h,
    )
    return project_uvs_planar_bbox(
        coords,
        texture_size,
        px_bbox,
        projection_plane,
        mode=mode,
    )

def create_raster_config(
    num_frames: int,
    total_threads: int = 1,
    save_strategy: int = 2,  # both
) -> "RasterConfig":
    from riley.cyth.riley import RasterConfig

    total_threads = max(1, int(total_threads))
    frames_available = max(1, int(num_frames))
    if total_threads < frames_available:
        render_group_count = total_threads
    else:
        render_group_count = 1
        for group_count in range(1, frames_available + 1):
            if total_threads % group_count == 0:
                render_group_count = group_count
    workers_per_group = total_threads // render_group_count

    return RasterConfig(
        render_mode=1,  # offline
        total_threads=total_threads,
        geom_scheduling_mode=0,  # spread
        max_raster_workers_per_job=workers_per_group,
        save_strategy=save_strategy,
        image_mode=0,  # grey
        hull_mode=1,  # on_no_fallback
        newton_seed_mode=0,  # centroid
        newton_seed_reuse=0,  # off
        report=1,  # bench
        save_format=3,  # bmp
        save_bits=8,
        save_scaling=1,  # auto
    )
