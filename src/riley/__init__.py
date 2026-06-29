# --------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher)
# --------------------------------------------------------------------------
import os
import platform
from pathlib import Path

# Add DLL directory to the search path on Windows to avoid "DLL load failed"
if platform.system().lower() == "windows":
    _current_dir = Path(__file__).resolve().parent
    # Search zig/ and cyth/ subdirectories where DLLs are located
    for _sub_dir in ("zig", "cyth"):
        _dll_dir = _current_dir / _sub_dir
        if _dll_dir.is_dir():
            try:
                os.add_dll_directory(str(_dll_dir))
            except AttributeError:
                # Fallback for older Python versions
                pass

from riley.cyth.riley import (
    Camera,
    CameraInput,
    CameraCoordSys,
    HullMode,
    Mesh,
    MeshInput,
    MeshType,
    GeometrySchedulingMode,
    ImageMode,
    NewtonSeedMode,
    NewtonSeedReuse,
    NormalType,
    build_config,
    RasterConfig,
    RenderMode,
    ReportMode,
    SaveStrategy,
    ScaleOver,
    ScaleStrategy,
    ShaderType,
    SubPixelCenterMap,
    FuncShaderBuiltin,
    FuncCoordMode,
    FuncShaderParams,
    TextureSample,
    TextureSampleMode,
    PsfType,
    ImageFormat,
    load_sim_csvs,
    load_texture,
    load_camera,
    load_stereo_pair,
    pos_fill_frame_from_rot,
    pos_fill_frame_from_rot_over_meshes,
    raster,
    roi_cent_from_coords,
    roi_cent_over_meshes,
    save_camera,
    save_stereo_pair,
)

__all__ = [
    "Camera",
    "CameraInput",
    "CameraCoordSys",
    "HullMode",
    "Mesh",
    "MeshInput",
    "MeshType",
    "GeometrySchedulingMode",
    "ImageMode",
    "NewtonSeedMode",
    "NewtonSeedReuse",
    "NormalType",
    "build_config",
    "RasterConfig",
    "RenderMode",
    "ReportMode",
    "SaveStrategy",
    "ScaleOver",
    "ScaleStrategy",
    "ShaderType",
    "SubPixelCenterMap",
    "FuncShaderBuiltin",
    "FuncCoordMode",
    "FuncShaderParams",
    "TextureSample",
    "TextureSampleMode",
    "PsfType",
    "ImageFormat",
    "load_sim_csvs",
    "load_texture",
    "load_camera",
    "load_stereo_pair",
    "pos_fill_frame_from_rot",
    "pos_fill_frame_from_rot_over_meshes",
    "raster",
    "roi_cent_from_coords",
    "roi_cent_over_meshes",
    "save_camera",
    "save_stereo_pair",
]
