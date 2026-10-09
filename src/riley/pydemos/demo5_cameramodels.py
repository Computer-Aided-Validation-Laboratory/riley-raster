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

import riley


def main() -> None:
    # --------------------------------------------------------------------------
    # 1. Setup paths and parameters
    # --------------------------------------------------------------------------
    data_dir = riley.data.sphere200_case_path()
    texture_path = riley.data.speckle_texture_path()
    out_dir_root = Path.cwd() / "out_riley_py" / "demo5_cameramodels"
    shutil.rmtree(out_dir_root, ignore_errors=True)
    out_dir_root.mkdir(parents=True)

    raster_threads = 4
    pixels_num = (800, 500)
    pixels_size = (5.3e-6, 5.3e-6)
    focal_length = 50.0e-3
    rot_world = (0.0, 0.0, 0.0)

    # --------------------------------------------------------------------------
    # 2. Load mesh data and texture shader
    # --------------------------------------------------------------------------
    coords = riley.load_csv(data_dir / "coords.csv")
    connect = riley.load_csv(data_dir / "connect.csv", dtype=np.int64)
    uvs = riley.load_csv(data_dir / "uvs.csv")
    texture = riley.load_texture_mono_u8(texture_path)

    convention = riley.ConnectConvention(
        riley.EElemType.TRI6,
        riley.EConnectAxis.ROW,
        0,
        riley.ENodeOrder.RILEY,
    )
    mesh = riley.create_mesh(
        convention=convention,
        mesh_type=riley.MeshType.tri6,
        coords=coords,
        connect=connect,
        shader=riley.TextureShader(uvs=uvs, texture=texture),
    )

    # --------------------------------------------------------------------------
    # 3. Position the base camera
    # --------------------------------------------------------------------------
    roi_cent_world = riley.roi_cent_from_coords(coords)
    pos_world = riley.pos_frame_coords(
        coords,
        pixels_num,
        pixels_size,
        focal_length,
        rot_world,
        fov_scale=1.0,
    )

    camera = riley.Camera(
        pixels_num=pixels_num,
        pixels_size=pixels_size,
        pos_world=pos_world,
        rot_world=rot_world,
        roi_cent_world=roi_cent_world,
        focal_length=focal_length,
        sub_sample=2,
        coord_sys=riley.CameraCoordSys.opengl,
    )

    # --------------------------------------------------------------------------
    # 4. Compare every distortion family and PSF path across buffer modes
    # --------------------------------------------------------------------------
    # Polynomial coefficients describe displacement, not the full mapped point.
    poly = {
        "distort_poly": riley.PolyMap(
            degree=2,
            mode=riley.EPolyMode.displacement,
            coeffs=np.array(
                [
                    [0, 0],
                    [0.02, -0.01],
                    [0.01, -0.015],
                    [0.01, 0.005],
                    [0.005, -0.005],
                    [-0.005, 0.01],
                ]
            ),
        ),
    }
    brown = {
        "distort_k1": -0.12,
        "distort_k2": 0.035,
        "distort_p1": 0.0002,
        "distort_p2": -0.0001,
    }
    brown_ext = {
        **brown,
        "distort_k4": -0.04,
        "distort_k5": 0.018,
        "distort_s1": 0.00001,
        "distort_s2": -0.000002,
        "distort_tau_x": 0.005,
        "distort_tau_y": -0.003,
    }
    distorts = (
        ("none", {"distort_model": 0}),
        ("brown_conrady", {"distort_model": 1, **brown}),
        ("brown_conrady_ext", {"distort_model": 2, **brown_ext}),
        ("polynomial", {"distort_model": 3, **poly}),
        ("brown_conrady_polynomial", {"distort_model": 4, **brown, **poly}),
        (
            "brown_conrady_ext_polynomial",
            {"distort_model": 5, **brown_ext, **poly},
        ),
    )
    psfs = (
        ("pixel_box", {"psf_type": riley.PsfType.pixel_box}),
        (
            "gaussian_separable",
            {
                "psf_type": riley.PsfType.gaussian,
                "psf_sigma_x": 1.0,
                "psf_support_rad": 3.0,
                "psf_separable": 1,
            },
        ),
        (
            "gaussian_nonseparable",
            {
                "psf_type": riley.PsfType.gaussian,
                "psf_sigma_x": 1.0,
                "psf_support_rad": 3.0,
                "psf_separable": 0,
            },
        ),
        (
            "anisotropic_separable",
            {
                "psf_type": riley.PsfType.anisotropic_gaussian,
                "psf_sigma_x": 1.2,
                "psf_sigma_y": 0.4,
                "psf_support_rad": 3.0,
                "psf_separable": 1,
            },
        ),
        (
            "anisotropic_rotated",
            {
                "psf_type": riley.PsfType.anisotropic_gaussian,
                "psf_sigma_x": 1.2,
                "psf_sigma_y": 0.4,
                "psf_theta": 0.35,
                "psf_support_rad": 3.0,
                "psf_separable": 0,
            },
        ),
    )

    modes = (
        riley.BufferMode.tile_local,
        riley.BufferMode.global_subpx_full,
        riley.BufferMode.global_subpx_stripe,
    )

    config = riley.RasterConfig(
        parallel=raster_threads,
        save_strategy=riley.SaveStrategy.disk,
        image_save_mode=riley.ImageSaveMode.grey,
        save_scaling=riley.ScaleStrategy.auto,
    )

    for distort_name, distort in distorts:
        for psf_name, psf in psfs:
            case_camera = replace(camera, **distort, **psf)
            for mode in modes:
                config.buffer_mode = mode
                out_dir = out_dir_root / distort_name / psf_name / mode.name
                out_dir.mkdir(parents=True, exist_ok=True)
                print(f"Rendering {distort_name}/{psf_name}/{mode.name}...")
                start_time = perf_counter()
                riley.raster(mesh, case_camera, config, out_dir=str(out_dir))
                elapsed_time = perf_counter() - start_time
                print(f"Render time: {elapsed_time:.6f} s")


if __name__ == "__main__":
    main()
