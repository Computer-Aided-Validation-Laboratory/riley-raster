# --------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher)
# --------------------------------------------------------------------------
"""One deforming FE plate observed by stereo DIC and a calibrated LWIR
camera."""
from __future__ import annotations

from dataclasses import replace
from pathlib import Path

import numpy as np

import riley


def build_temperature_field(coords: np.ndarray, frames: int) -> np.ndarray:
    y = coords[:, 1]  # The plate's vertical axis is world y in this dataset.
    extent = float(y.max() - y.min())
    if not np.isfinite(extent) or extent <= 0:
        raise ValueError("degenerate vertical extent")
    kelvin = 323.15 + 150.0 * (y - y.min()) / extent
    assert np.isclose(kelvin.min(), 323.15) and np.isclose(kelvin.max(), 473.15)
    return np.repeat(kelvin[:, None, None], frames, axis=1)


def band_radiance_lookup() -> np.ndarray:
    wavelengths = (8.0 + 0.25 * np.arange(25, dtype=np.float64)) * 1e-6
    temperatures = 270.0 + 0.25 * np.arange(921, dtype=np.float64)
    h, c, k = 6.62607015e-34, 299792458.0, 1.380649e-23
    spectral = np.empty(
        (temperatures.size, wavelengths.size),
        dtype=np.float64,
    )
    for ii, wavelength in enumerate(wavelengths):
        numerator = 2 * h * c * c
        exponent = h * c / (wavelength * k * temperatures)
        denominator = (wavelength**5) * (np.exp(exponent) - 1.0)
        spectral[:, ii] = numerator / denominator

    trapz_step = wavelengths[1:] - wavelengths[:-1]
    trapz_avg = (spectral[:, :-1] + spectral[:, 1:]) / 2.0
    return np.sum(trapz_avg * trapz_step, axis=1)


def main() -> None:
    # --------------------------------------------------------------------------
    # 1. Setup paths and parameters
    # --------------------------------------------------------------------------
    data_dir = riley.data.platehole_csv_case_path()
    out_dir = Path.cwd() / "out_riley_py" / "demo9_diciruq"
    out_dir.mkdir(parents=True, exist_ok=True)

    # --------------------------------------------------------------------------
    # 2. Load simulation data, displacement, and temperature fields
    # --------------------------------------------------------------------------
    coords = riley.load_csv(data_dir / "coords.csv")
    connect = riley.load_csv(data_dir / "connect.csv", dtype=np.int64)
    uvs = riley.load_csv(data_dir / "uvs.csv")
    disp_components = tuple(
        riley.load_csv(data_dir / f"field_disp_{axis}.csv") for axis in "xyz"
    )
    frame_indices = riley.frames_first_last_idxs(disp_components[0].shape[1])
    disp = tuple(component[:, frame_indices] for component in disp_components)
    temperature = build_temperature_field(coords, len(frame_indices))

    # --------------------------------------------------------------------------
    # 3. Setup shaders, pipe stages, and radiance lookup
    # --------------------------------------------------------------------------
    texture = riley.load_texture_mono_u8(riley.data.speckle_texture_path())
    speckle = riley.TextureShader(uvs=uvs, texture=texture)

    channel = riley.Slot(riley.SlotKind.channel, 0)
    field = riley.Slot(riley.SlotKind.field, 0)
    parameter = riley.Slot(riley.SlotKind.parameter, 0)

    nodal_temp = riley.NodalShader(
        temperature,
        bits=-1,
        scaling_type=riley.ScaleStrategy.none,
    )
    ir_pipe = riley.ShaderPipe(
        stages=(
            riley.ShaderSource(speckle, channel),
            riley.GreyToEmissivity(
                channel,
                parameter,
                black=0.96,
                white=0.90,
                grey_black=0.0,
                grey_white=255.0,
            ),
            riley.ShaderSource(nodal_temp, field),
        ),
        resolver=riley.ShaderResolver(
            riley.ResolverKind.greybody_band_apparent_c,
            temperature=field,
            emissivity=parameter,
            ambient=293.15,
            lookup_first=270.0,
            lookup_step=0.25,
            lookup_values=band_radiance_lookup(),
        ),
    )

    convention = riley.ConnectConvention(
        riley.EElemType.QUAD8,
        riley.EConnectAxis.ROW,
        0,
        riley.ENodeOrder.RILEY,
    )
    mesh = riley.create_mesh(
        convention,
        riley.MeshType.quad8,
        coords,
        connect,
        riley.MeshShaderSet(direct=speckle, ir=ir_pipe),
        disp=disp,
    )

    # --------------------------------------------------------------------------
    # 4. Configure stereo DIC and IR cameras
    # --------------------------------------------------------------------------
    target = riley.roi_cent_from_coords(coords)
    dic_pixels = (2464, 2056)
    dic_pitch = (3.45e-6, 3.45e-6)
    dic_focal = 0.05
    ir_pixels = (640, 480)
    ir_pitch = (17e-6, 17e-6)
    ir_focal = 0.035

    left_rot = (0.0, -np.deg2rad(10.0), 0.0)
    right_rot = (0.0, np.deg2rad(10.0), 0.0)
    ir_rot = (0.0, 0.0, 0.0)

    left_pos = riley.pos_frame_coords(
        coords,
        dic_pixels,
        dic_pitch,
        dic_focal,
        left_rot,
        fov_scale=0.65,
        target=target,
    )
    left = riley.Camera(
        pixels_num=dic_pixels,
        pixels_size=dic_pitch,
        pos_world=left_pos,
        rot_world=left_rot,
        roi_cent_world=target,
        focal_length=dic_focal,
        sub_sample=4,
        distort_model=1,
        distort_k1=-0.2,
        distort_k2=0.1,
        distort_p1=0.0001,
        distort_p2=-0.0001,
        output_encoding=riley.OutputEncoding.grid12_to_u16,
        encoding_min=0.0,
        encoding_max=255.0,
        output_files=[
            riley.ImageSaveOpts(
                format=riley.ImageFormat.tiff,
                bits=16,
                scaling=riley.ScaleStrategy.none,
            )
        ],
    )

    right_pos = riley.pos_frame_coords(
        coords,
        dic_pixels,
        dic_pitch,
        dic_focal,
        right_rot,
        fov_scale=0.65,
        target=target,
    )
    right = replace(
        left,
        rot_world=right_rot,
        pos_world=right_pos,
    )

    ir_pos = riley.pos_frame_coords(
        coords,
        ir_pixels,
        ir_pitch,
        ir_focal,
        ir_rot,
        fov_scale=0.65,
        target=target,
    )
    ir = riley.Camera(
        pixels_num=ir_pixels,
        pixels_size=ir_pitch,
        pos_world=ir_pos,
        rot_world=ir_rot,
        roi_cent_world=target,
        focal_length=ir_focal,
        sub_sample=4,
        render_format=riley.RenderFormat.ir,
        output_encoding=riley.OutputEncoding.linear_u16,
        encoding_min=0.0,
        encoding_max=250.0,
        output_files=[
            riley.ImageSaveOpts(
                format=riley.ImageFormat.tiff,
                bits=16,
                scaling=riley.ScaleStrategy.none,
            )
        ],
    )

    # --------------------------------------------------------------------------
    # 5. Configure raster engine and render multimodal scene
    # --------------------------------------------------------------------------
    config = riley.RasterConfig(
        parallel=4,
        save_strategy=riley.SaveStrategy.disk,
    )

    riley.raster(mesh, (left, ir, right), config, out_dir=str(out_dir))

    # --------------------------------------------------------------------------
    # 6. Save calibration data and acquisition metadata
    # --------------------------------------------------------------------------
    riley.save_stereo_pair(str(out_dir), "stereo_data_opengl.csv", left, right)
    (out_dir / "acquisition_metadata.txt").write_text(
        "cam0=left DIC (-10 deg), cam1=IR (0 deg), cam2=right DIC (+10 deg)\n"
        "Frames: first and last FE displacement frames from demo3 dataset.\n"
        "DIC: source 0..255 -> round(source/255*4095)*16 in uint16 TIFF; "
        "4096 effective codes, range 0..65520.\n"
        "IR: flat 8-14 um band, ambient 293.15 K, "
        "black/white emissivity 0.96/0.90.\n"
        "IR pixel is blackbody-equivalent apparent temperature C, "
        "encoded round(clamp(C/250,0,1)*65535).\n"
        "Decode IR: C = code*250/65535. "
        "This is not emissivity-corrected true temperature.\n"
    )


if __name__ == "__main__":
    main()
