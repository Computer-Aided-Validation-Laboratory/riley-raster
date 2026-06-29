# --------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher)
# --------------------------------------------------------------------------
from __future__ import annotations

import shutil
from dataclasses import replace
from pathlib import Path
from time import perf_counter

import numpy as np
from pyvale.mooseherder import ExodusLoader
from pyvale.sensorsim import extract_surf_mesh
import riley


def main() -> None:
    exodus_path = Path("data/FE/platehole3d_2mr_63f.e")
    texture_path = Path("texture/speckle.bmp")
    out_dir = Path("pyout/demo-dicuq-from-exodus")
    pixels_num = (2464, 2056)
    pixels_size = (3.45e-6, 3.45e-6)
    focal_length = 50.0e-3
    fov_scale_factor = 0.65
    sub_sample = 2
    stereo_angle_deg = 20.0
    total_threads = 8
    distortion_model = {
        "distortion_model": 1,
        "distortion_k1": -0.2,
        "distortion_k2": 0.1,
        "distortion_k3": 0.0,
        "distortion_p1": 0.0001,
        "distortion_p2": -0.0001,
    }

    shutil.rmtree(out_dir, ignore_errors=True)
    out_dir.mkdir(parents=True, exist_ok=True)

    coords, connect, disp = load_surface_sim(exodus_path)
    uvs = riley.project_uvs_planar_centered(
        coords,
        pixels_num,
        uv_span_max=0.8,
        projection_plane=(
            np.array([0.0, 0.0, -1.0], dtype=np.float64),
            np.array([0.0, 0.0, 0.0], dtype=np.float64),
        ),
    )
    texture = riley.load_texture(texture_path)

    mesh = riley.Mesh(
        mesh_type=riley.MeshType.quad8,
        coords=coords,
        connect=connect,
        disp=disp,
        shader_type=riley.ShaderType.tex,
        uvs=uvs,
        texture=texture,
        sample=riley.TextureSample.cubic_catmull_rom,
        sample_mode=riley.TextureSampleMode.lut_lerp,
        bits=8,
        scaling_type=riley.ScaleStrategy.none,
    )

    roi_pos = riley.roi_cent_from_coords(coords)
    camera_0_pos = riley.pos_fill_frame_from_rot(
        coords,
        pixels_num,
        pixels_size,
        focal_length,
        (0.0, 0.0, 0.0),
        fov_scale_factor,
    )
    camera_0 = riley.Camera(
        pixels_num=pixels_num,
        pixels_size=pixels_size,
        pos_world=camera_0_pos,
        rot_world=(0.0, 0.0, 0.0),
        roi_cent_world=roi_pos,
        focal_length=focal_length,
        sub_sample=sub_sample,
        **distortion_model,
    )
    camera_1_rot = (0.0, np.deg2rad(stereo_angle_deg), 0.0)
    camera_1_pos = riley.pos_fill_frame_from_rot(
        coords,
        pixels_num,
        pixels_size,
        focal_length,
        camera_1_rot,
        fov_scale_factor,
    )
    camera_1 = riley.Camera(
        pixels_num=pixels_num,
        pixels_size=pixels_size,
        pos_world=camera_1_pos,
        rot_world=camera_1_rot,
        roi_cent_world=roi_pos,
        focal_length=focal_length,
        sub_sample=sub_sample,
        **distortion_model,
    )

    config = riley.create_raster_config(
        num_frames=2,
        total_threads=total_threads,
        save_strategy=riley.SaveStrategy.disk,
    )
    config.background_value = 128.0
    config.tile_size_max = 128
    config.save_scaling = riley.ScaleStrategy.none

    start_time = perf_counter()
    riley.raster(
        [mesh],
        [camera_0, camera_1],
        config,
        out_dir=str(out_dir),
    )
    elapsed_time = perf_counter() - start_time
    print(f"render time: {elapsed_time:.6f} s")

    riley.save_stereo_pair(
        str(out_dir),
        "stereo_data_opengl.csv",
        camera_0,
        camera_1,
    )
    riley.save_stereo_pair(
        str(out_dir),
        "stereo_data_opencv.csv",
        replace(camera_0, coord_sys=riley.CameraCoordSys.opencv),
        replace(camera_1, coord_sys=riley.CameraCoordSys.opencv),
    )
    print(f"rendered dicuq from exodus to {out_dir}")


def load_surface_sim(
    exodus_path: Path,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    sim_data = ExodusLoader(
        exodus_path,
        enforce_convention=True,
    ).load_all_sim_data()
    surface_data = extract_surf_mesh(sim_data, enforce_convention=True)

    connect_keys = sorted(surface_data.connect.keys())
    if len(connect_keys) != 1:
        raise ValueError(
            f"{exodus_path} extracted {len(connect_keys)} connectivity tables; "
            "Riley expects one surface connectivity table here.",
        )

    coords = np.ascontiguousarray(surface_data.coords, dtype=np.float64)
    connect = np.ascontiguousarray(
        surface_data.connect[connect_keys[0]],
        dtype=np.uintp,
    )
    connect = normalize_quad8_mid_nodes(coords, connect)
    disp = build_disp_array(surface_data.node_vars)
    return coords, connect, disp


def build_disp_array(node_vars: dict[str, np.ndarray]) -> np.ndarray:
    disp_x = np.asarray(node_vars["disp_x"], dtype=np.float64)
    disp_y = np.asarray(node_vars["disp_y"], dtype=np.float64)
    disp_z = np.asarray(node_vars["disp_z"], dtype=np.float64)

    disp = np.zeros(
        (disp_x.shape[1], disp_x.shape[0], 3),
        dtype=np.float64,
    )
    disp[:, :, 0] = disp_x.T
    disp[:, :, 1] = disp_y.T
    disp[:, :, 2] = disp_z.T
    return disp


def normalize_quad8_mid_nodes(
    coords: np.ndarray,
    connect: np.ndarray,
) -> np.ndarray:
    connect_norm = np.array(connect, copy=True)
    flip_perm = np.array((0, 3, 2, 1, 7, 6, 5, 4), dtype=np.uintp)
    solid_cent = np.mean(coords, axis=0)
    bbox_min = np.min(coords, axis=0)
    bbox_max = np.max(coords, axis=0)
    bbox_cent = 0.5 * (bbox_min + bbox_max)
    tol_x = 1.0e-6 * max(1.0, bbox_max[0] - bbox_min[0])
    tol_y = 1.0e-6 * max(1.0, bbox_max[1] - bbox_min[1])

    for ee, elem_connect in enumerate(connect_norm):
        corner_inds = elem_connect[:4]
        corner_coords = coords[corner_inds]
        face_normal = np.cross(
            corner_coords[1] - corner_coords[0],
            corner_coords[2] - corner_coords[0],
        )
        face_cent = np.mean(corner_coords, axis=0)
        outward_vec = face_cent - solid_cent

        if np.dot(face_normal, outward_vec) < 0.0:
            elem_connect = elem_connect[flip_perm]
            connect_norm[ee] = elem_connect
            corner_inds = elem_connect[:4]
            corner_coords = coords[corner_inds]
            face_normal = np.cross(
                corner_coords[1] - corner_coords[0],
                corner_coords[2] - corner_coords[0],
            )
            face_cent = np.mean(corner_coords, axis=0)

        is_vertical_face = abs(face_normal[2]) < max(
            abs(face_normal[0]),
            abs(face_normal[1]),
        )
        is_interior_xy = (
            face_cent[0] > bbox_min[0] + tol_x and
            face_cent[0] < bbox_max[0] - tol_x and
            face_cent[1] > bbox_min[1] + tol_y and
            face_cent[1] < bbox_max[1] - tol_y
        )
        radial_vec = face_cent[:2] - bbox_cent[:2]

        if is_vertical_face and is_interior_xy:
            if np.dot(face_normal[:2], radial_vec) > 0.0:
                elem_connect = elem_connect[flip_perm]
                connect_norm[ee] = elem_connect

        corner_inds = elem_connect[:4]
        mid_inds = elem_connect[4:8]

        corner_coords = coords[corner_inds]
        mid_coords = coords[mid_inds]
        edge_midpoints = np.array((
            0.5 * (corner_coords[0] + corner_coords[1]),
            0.5 * (corner_coords[1] + corner_coords[2]),
            0.5 * (corner_coords[2] + corner_coords[3]),
            0.5 * (corner_coords[3] + corner_coords[0]),
        ))
        edge_dists = np.linalg.norm(
            mid_coords[:, None, :] - edge_midpoints[None, :, :],
            axis=2,
        )
        edge_perm = np.argmin(edge_dists, axis=0)
        connect_norm[ee, 4:8] = mid_inds[edge_perm]

    return np.ascontiguousarray(connect_norm, dtype=np.uintp)


if __name__ == "__main__":
    main()
