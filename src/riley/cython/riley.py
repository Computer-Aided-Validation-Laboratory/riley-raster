# --------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher)
# --------------------------------------------------------------------------
import cython
from pathlib import Path
from typing import Any

import numpy as np
from cython.cimports.riley.cython import riley as cr
from riley.types import (
    EPolyMode,
    PolyMap,
    RenderFormat,
    CodePacking,
    ImageSaveOpts,
    Camera,
    FuncShaderParams,
    RenderMode,
    RasterConfig,
    MeshType,
    ShaderType,
    TextureStorage,
    SaveStrategy,
    ReportMode,
    BufferMode,
    SubPixelCenterMap,
    TextureSample,
    TextureSampleMode,
    ScaleStrategy,
    ScaleOver,
    FuncShaderBuiltin,
    FuncCoordMode,
    NormalType,
    HullMode,
    NewtonSeedMode,
    NewtonSeedReuse,
    MultirootSolverMode,
    EdgeFunMode,
    ValidateInput,
    CameraCoordSys,
    PsfType,
    TextureShader,
    NodalShader,
    FunctionShader,
    FunctionChannel,
    FunctionMultiShader,
    RegisterKind,
    ResolverKind,
    ResolverOpKind,
    Register,
    ResolverOp,
    ShaderResolver,
    ShaderSource,
    GreyToEmissivity,
    ClampStage,
    AffineMap,
    LUTMap,
    Blend,
    Normalise,
    ShaderPipe,
    MeshShaderSet,
    Mesh,
    ImageFormat,
    FrameFitMode,
    RileyShader,
    Shader,
    _check_parallel,
    _fit_mode_to_int,
)


@cython.cfunc
def _descriptor_bytes(size: cython.size_t, keepalive: list[Any]) -> cython.p_void:
    # Every ABI descriptor is aligned no more strictly than double. NumPy owns
    # these blocks, so errors and early returns cannot leak native allocations.
    storage = np.empty(max(1, (size + 7) // 8), dtype=np.float64)
    keepalive.append(storage)
    view: cython.double[::1] = storage
    return cython.cast(cython.p_void, cython.address(view[0]))


@cython.cfunc
def _make_cvec3(vec_in: tuple[float, float, float]) -> cr.CVec3F64:
    return cr.CVec3F64(
        float(vec_in[0]),
        float(vec_in[1]),
        float(vec_in[2]),
    )


@cython.cfunc
def _make_cvec2_f64(vec_in: tuple[float, float]) -> cr.CVec2F64:
    return cr.CVec2F64(float(vec_in[0]), float(vec_in[1]))


@cython.cfunc
def _make_cvec2_u32(vec_in: tuple[int, int]) -> cr.CVec2U32:
    return cr.CVec2U32(int(vec_in[0]), int(vec_in[1]))


@cython.cfunc
def _make_camera_input(
    camera: Any, keepalive: list[Any]
) -> cr.CCameraInput:
    camera_out: cr.CCameraInput
    poly_coeffs: cython.double[::1]
    camera_out.distort.distort_poly_degree = 0
    camera_out.distort.distort_poly_mode = 1
    camera_out.distort.distort_poly_coeffs = cython.NULL
    camera_out.distort.distort_poly_coeffs_len = 0
    if int(camera.distort_model) in (3, 4, 5):
        poly = camera.distort_poly
        if poly is None:
            raise ValueError("polynomial camera requires distort_poly")
        if not isinstance(poly.degree, (int, np.integer)) or isinstance(
            poly.degree, bool
        ):
            raise ValueError("polynomial degree must be an integer")
        if not 1 <= poly.degree <= 7:
            raise ValueError("polynomial degree must be between 1 and 7")
        mode = EPolyMode(poly.mode)
        count = (poly.degree + 1) * (poly.degree + 2) // 2
        values = np.asarray(poly.coeffs)
        if values.shape != (count, 2):
            raise ValueError(
                "polynomial coefficients require shape (term_count, 2)"
            )
        if np.iscomplexobj(values):
            raise ValueError("polynomial coefficients must be real")
        snapshot = np.array(
            values, dtype=np.float64, order="C", copy=True
        ).reshape(-1)
        if not np.isfinite(snapshot).all():
            raise ValueError("polynomial coefficients must be finite")
        keepalive.append(snapshot)
        poly_coeffs = snapshot
        camera_out.distort.distort_poly_degree = poly.degree
        camera_out.distort.distort_poly_mode = int(mode)
        camera_out.distort.distort_poly_coeffs = cython.address(poly_coeffs[0])
        camera_out.distort.distort_poly_coeffs_len = poly_coeffs.shape[0]
    camera_out.pixels_num = _make_cvec2_u32(camera.pixels_num)
    camera_out.pixels_size = _make_cvec2_f64(camera.pixels_size)
    camera_out.pos_world = _make_cvec3(camera.pos_world)
    camera_out.rot_world = _make_cvec3(camera.rot_world)
    camera_out.roi_cent_world = _make_cvec3(camera.roi_cent_world)
    camera_out.focal_length = float(camera.focal_length)
    camera_out.sub_sample = int(camera.sub_sample)
    camera_out.background_value = float(camera.background_value)
    camera_out.distort.distort_model = int(camera.distort_model)
    camera_out.distort.distort_k1 = float(camera.distort_k1)
    camera_out.distort.distort_k2 = float(camera.distort_k2)
    camera_out.distort.distort_k3 = float(camera.distort_k3)
    camera_out.distort.distort_k4 = float(camera.distort_k4)
    camera_out.distort.distort_k5 = float(camera.distort_k5)
    camera_out.distort.distort_k6 = float(camera.distort_k6)
    camera_out.distort.distort_p1 = float(camera.distort_p1)
    camera_out.distort.distort_p2 = float(camera.distort_p2)
    camera_out.distort.distort_s1 = float(camera.distort_s1)
    camera_out.distort.distort_s2 = float(camera.distort_s2)
    camera_out.distort.distort_s3 = float(camera.distort_s3)
    camera_out.distort.distort_s4 = float(camera.distort_s4)
    camera_out.distort.distort_tau_x = float(camera.distort_tau_x)
    camera_out.distort.distort_tau_y = float(camera.distort_tau_y)
    camera_out.coord_sys = int(camera.coord_sys)
    camera_out.subpixel_center_map = int(camera.subpixel_center_map)

    camera_out.render_format_tag = int(camera.render_format)
    camera_out.render_channels = (3 if camera.render_format == RenderFormat.rgb else
                                  camera.render_channels if camera.render_format == RenderFormat.multifield else 1)

    camera_out.output_files = cython.NULL
    camera_out.output_files_len = 0
    out_files = getattr(camera, "output_files", None)
    if out_files:
        files_len: cython.size_t = len(out_files)
        c_files = cython.cast(cython.pointer[cr.CImageSaveOpts],
                              _descriptor_bytes(files_len * cython.sizeof(cr.CImageSaveOpts), keepalive))
        for fi in range(files_len):
            item = out_files[fi]
            c_files[fi].format = int(item.format)
            c_files[fi].file_bits = -1 if item.file_bits is None else int(item.file_bits)
            c_files[fi].adc_bits = -1 if item.adc_bits is None else int(item.adc_bits)
            c_files[fi].scaling_tag = int(item.scaling)
            c_files[fi].scaling_min = float(getattr(item, "scaling_min", 0.0))
            c_files[fi].scaling_max = float(getattr(item, "scaling_max", 1.0))
            c_files[fi].packing = int(item.packing)
        camera_out.output_files = c_files
        camera_out.output_files_len = files_len

    camera_out.psf.psf_type = int(camera.psf_type)
    camera_out.psf.psf_sigma_x = float(camera.psf_sigma_x)
    camera_out.psf.psf_sigma_y = float(camera.psf_sigma_y)
    camera_out.psf.psf_theta = float(camera.psf_theta)
    camera_out.psf.psf_supp_rad = float(camera.psf_support_rad)
    camera_out.psf.psf_separable = int(camera.psf_separable)
    return camera_out


@cython.cfunc
def _camera_input_from_c(camera_in: cr.CCameraInput) -> Camera:
    poly: PolyMap | None = None
    if camera_in.distort.distort_poly_coeffs_len:
        count = camera_in.distort.distort_poly_coeffs_len
        values = np.empty(count, dtype=np.float64)
        for ii in range(count):
            values[ii] = camera_in.distort.distort_poly_coeffs[ii]
        poly = PolyMap(
            degree=camera_in.distort.distort_poly_degree,
            mode=EPolyMode(camera_in.distort.distort_poly_mode),
            coeffs=values.reshape((-1, 2)),
        )
    return Camera(
        pixels_num=(camera_in.pixels_num.x, camera_in.pixels_num.y),
        pixels_size=(camera_in.pixels_size.x, camera_in.pixels_size.y),
        pos_world=(
            camera_in.pos_world.x,
            camera_in.pos_world.y,
            camera_in.pos_world.z,
        ),
        rot_world=(
            camera_in.rot_world.x,
            camera_in.rot_world.y,
            camera_in.rot_world.z,
        ),
        roi_cent_world=(
            camera_in.roi_cent_world.x,
            camera_in.roi_cent_world.y,
            camera_in.roi_cent_world.z,
        ),
        focal_length=camera_in.focal_length,
        sub_sample=camera_in.sub_sample,
        background_value=camera_in.background_value,
        distort_model=camera_in.distort.distort_model,
        distort_k1=camera_in.distort.distort_k1,
        distort_k2=camera_in.distort.distort_k2,
        distort_k3=camera_in.distort.distort_k3,
        distort_k4=camera_in.distort.distort_k4,
        distort_k5=camera_in.distort.distort_k5,
        distort_k6=camera_in.distort.distort_k6,
        distort_p1=camera_in.distort.distort_p1,
        distort_p2=camera_in.distort.distort_p2,
        distort_s1=camera_in.distort.distort_s1,
        distort_s2=camera_in.distort.distort_s2,
        distort_s3=camera_in.distort.distort_s3,
        distort_s4=camera_in.distort.distort_s4,
        distort_tau_x=camera_in.distort.distort_tau_x,
        distort_tau_y=camera_in.distort.distort_tau_y,
        distort_poly=poly,
        coord_sys=camera_in.coord_sys,
        subpixel_center_map=camera_in.subpixel_center_map,
        psf_type=camera_in.psf.psf_type,
        psf_sigma_x=camera_in.psf.psf_sigma_x,
        psf_sigma_y=camera_in.psf.psf_sigma_y,
        psf_theta=camera_in.psf.psf_theta,
        psf_support_rad=camera_in.psf.psf_supp_rad,
        psf_separable=camera_in.psf.psf_separable,
        render_format=RenderFormat(camera_in.render_format_tag),
        render_channels=camera_in.render_channels,
    )


@cython.cfunc
def _make_raster_config(config: Any, keepalive: list[Any]) -> cr.CRasterConfig:
    config_out: cr.CRasterConfig
    config_out.render_mode = int(config.render_mode)
    _check_parallel(config.parallel)
    if config.parallel is None:
        config_out.parallel_mode = 0
        config_out.thread_count = 0
    elif config.parallel == 1:
        config_out.parallel_mode = 1
        config_out.thread_count = 1
    else:
        config_out.parallel_mode = 2
        config_out.thread_count = int(config.parallel)
    config_out.save_strategy = int(config.save_strategy)
    config_out.oneroot_hull_mode = int(config.oneroot_hull_mode)
    config_out.oneroot_newton_seed_mode = int(config.oneroot_newton_seed_mode)
    config_out.oneroot_newton_seed_reuse = int(
        config.oneroot_newton_seed_reuse,
    )
    config_out.oneroot_edge_fun_mode = int(config.oneroot_edge_fun_mode)
    config_out.multiroot_mode = int(config.multiroot_mode)
    config_out.multiroot_edge_fun_mode = int(config.multiroot_edge_fun_mode)
    config_out.validate_input = int(config.validate_input)
    config_out.report_perf = int(config.report_perf)
    config_out.report_console = int(config.report_console)
    config_out.tile_size_min = int(config.tile_size_min)
    config_out.tile_size_max = int(config.tile_size_max)
    config_out.disk_save_overlap = 1 if config.disk_save_overlap else 0
    config_out.tile_size_override = int(config.tile_size_override)
    config_out.global_subpx_tile_size_min = int(
        config.global_subpx_tile_size_min
    )
    config_out.global_subpx_tile_size_max = int(
        config.global_subpx_tile_size_max
    )
    config_out.global_subpx_tile_size_override = int(
        config.global_subpx_tile_size_override,
    )
    config_out.global_subpx_stripe_size_min = int(
        config.global_subpx_stripe_size_min,
    )
    config_out.global_subpx_stripe_size_max = int(
        config.global_subpx_stripe_size_max,
    )
    config_out.global_subpx_stripe_size_override = int(
        config.global_subpx_stripe_size_override,
    )
    config_out.raster_halo_px_override = int(config.raster_halo_px_override)
    config_out.save_frame_buff_count = int(config.save_frame_buffer_count)
    config_out.buffer_mode = int(config.buffer_mode)
    config_out.edge_spacing_px = float(config.edge_spacing_px)
    output_name_format = config.output_name_format.encode("utf-8")
    config_out.output_name_format = output_name_format
    keepalive.append(output_name_format)
    return config_out


@cython.cfunc
def _make_func_params(params_in: Any) -> cr.CFuncShaderParams:
    params_out: cr.CFuncShaderParams
    ii: cython.size_t
    jj: cython.size_t
    for ii in range(2):
        params_out.coord_scale[ii] = float(params_in.coord_scale[ii])
    for ii in range(2):
        params_out.coord_offset[ii] = float(params_in.coord_offset[ii])
    for ii in range(3):
        params_out.constant_value_rgb[ii] = float(params_in.constant_value_rgb[ii])
    for ii in range(3):
        params_out.linear_coeff[ii] = float(params_in.linear_coeffs[ii])
    for ii in range(3):
        for jj in range(3):
            params_out.linear_coeff_rgb[ii][jj] = float(params_in.linear_coeffs_rgb[ii][jj])
    for ii in range(6):
        params_out.quadratic_coeff[ii] = float(params_in.quadratic_coeffs[ii])
    for ii in range(3):
        for jj in range(6):
            params_out.quadratic_coeff_rgb[ii][jj] = float(params_in.quadratic_coeffs_rgb[ii][jj])
    for ii in range(2):
        params_out.wave_num_scalar[ii] = float(params_in.wave_num_scalar[ii])
    for ii in range(3):
        params_out.wave_num_rgb[ii] = float(params_in.wave_num_rgb[ii])
    for ii in range(2):
        params_out.sinusoidal_amp[ii] = float(params_in.sinusoidal_amplitudes[ii])
    for ii in range(3):
        params_out.sinusoidal_bias_rgb[ii] = float(params_in.sinusoidal_bias_rgb[ii])
    for ii in range(3):
        params_out.sinusoidal_amp_rgb[ii] = float(params_in.sinusoidal_amplitudes_rgb[ii])
    for ii in range(2):
        params_out.checker_level[ii] = float(params_in.checker_levels[ii])
    for ii in range(2):
        params_out.lambertian_coeff[ii] = float(params_in.lambertian_coeffs[ii])
    for ii in range(3):
        for jj in range(2):
            params_out.lambertian_coeff_rgb[ii][jj] = float(params_in.lambertian_coeffs_rgb[ii][jj])
    for ii in range(2):
        params_out.eggbox_pitch[ii] = float(params_in.eggbox_pitch[ii])
    for ii in range(2):
        params_out.eggbox_phase[ii] = float(params_in.eggbox_phase[ii])
    params_out.constant_value = float(params_in.constant_value)
    params_out.sinusoidal_bias = float(params_in.sinusoidal_bias)
    params_out.checker_smooth_frequency = float(params_in.checker_smooth_frequency)
    params_out.eggbox_mean = float(params_in.eggbox_mean)
    params_out.eggbox_contrast = float(params_in.eggbox_contrast)
    return params_out


@cython.cfunc
def _make_array_2d_f64(
    view_in: cython.double[:, ::1],
    rows_num: cython.Py_ssize_t,
    cols_num: cython.Py_ssize_t,
) -> cr.CArray2DF64:
    if rows_num == 0 or cols_num == 0:
        return cr.CArray2DF64(cython.NULL, rows_num, cols_num)
    return cr.CArray2DF64(
        cython.address(view_in[0, 0]),
        rows_num,
        cols_num,
    )


@cython.cfunc
def _make_array_2d_usize(
    view_in: cython.size_t[:, ::1],
    rows_num: cython.Py_ssize_t,
    cols_num: cython.Py_ssize_t,
) -> cr.CArray2DUsize:
    if rows_num == 0 or cols_num == 0:
        return cr.CArray2DUsize(cython.NULL, rows_num, cols_num)
    return cr.CArray2DUsize(
        cython.address(view_in[0, 0]),
        rows_num,
        cols_num,
    )


@cython.cfunc
def _make_array_3d_f64(
    view_in: cython.double[:, :, ::1],
    dim0: cython.Py_ssize_t,
    dim1: cython.Py_ssize_t,
    dim2: cython.Py_ssize_t,
) -> cr.CArray3DF64:
    return cr.CArray3DF64(
        cython.address(view_in[0, 0, 0]),
        dim0,
        dim1,
        dim2,
    )


@cython.cfunc
def _make_array_3d_u8(
    view_in: cython.uchar[:, :, ::1],
    dim0: cython.Py_ssize_t,
    dim1: cython.Py_ssize_t,
    dim2: cython.Py_ssize_t,
) -> cr.CArray3DU8:
    return cr.CArray3DU8(cython.address(view_in[0, 0, 0]), dim0, dim1, dim2)


@cython.cfunc
def _make_array_3d_u16(
    view_in: cython.ushort[:, :, ::1],
    dim0: cython.Py_ssize_t,
    dim1: cython.Py_ssize_t,
    dim2: cython.Py_ssize_t,
) -> cr.CArray3DU16:
    return cr.CArray3DU16(cython.address(view_in[0, 0, 0]), dim0, dim1, dim2)


@cython.cfunc
def _empty_array_2d_f64() -> cr.CArray2DF64:
    return cr.CArray2DF64(cython.NULL, 0, 0)


@cython.cfunc
def _empty_array_2d_usize() -> cr.CArray2DUsize:
    return cr.CArray2DUsize(cython.NULL, 0, 0)


@cython.cfunc
def _empty_array_3d_f64() -> cr.CArray3DF64:
    return cr.CArray3DF64(cython.NULL, 0, 0, 0)


@cython.cfunc
def _empty_array_3d_u8() -> cr.CArray3DU8:
    return cr.CArray3DU8(cython.NULL, 0, 0, 0)


@cython.cfunc
def _empty_array_3d_u16() -> cr.CArray3DU16:
    return cr.CArray3DU16(cython.NULL, 0, 0, 0)


def _last_error_message() -> str:
    uint8_buf_np = np.zeros((512,), dtype=np.uint8)
    uint8_view: cython.uchar[::1] = uint8_buf_np
    cr.rileyGetLastError(cython.address(uint8_view[0]), uint8_view.shape[0])
    return bytes(uint8_buf_np).split(b"\0", 1)[0].decode("utf-8")


def _raise_last_error() -> None:
    msg = _last_error_message()
    if msg:
        raise RuntimeError(msg)
    raise RuntimeError("riley wrapper call failed")


def _as_shape_2d(array_in: Any) -> tuple[int, int]:
    if getattr(array_in, "ndim", None) != 2:
        raise ValueError("expected a 2D numpy array")
    return int(array_in.shape[0]), int(array_in.shape[1])


def _as_shape_3d(array_in: Any) -> tuple[int, int, int]:
    if getattr(array_in, "ndim", None) != 3:
        raise ValueError("expected a 3D numpy array")
    return (
        int(array_in.shape[0]),
        int(array_in.shape[1]),
        int(array_in.shape[2]),
    )


def _normalize_meshes(meshes_in: Any) -> list[Any]:
    if isinstance(meshes_in, (list, tuple)):
        return list(meshes_in)
    return [meshes_in]


def _normalize_cameras(cameras_in: Any) -> list[Any]:
    if isinstance(cameras_in, (list, tuple)):
        return list(cameras_in)
    return [cameras_in]


def _contig_f64_2d(array_in: Any, label: str) -> np.ndarray:
    array_np = np.ascontiguousarray(array_in, dtype=np.float64)
    _as_shape_2d(array_np)
    return array_np


def _contig_u_size_2d(array_in: Any) -> np.ndarray:
    array_np = np.ascontiguousarray(array_in, dtype=np.uintp)
    _as_shape_2d(array_np)
    return array_np


def _contig_f64_3d(array_in: Any, label: str) -> np.ndarray:
    array_np = np.ascontiguousarray(array_in, dtype=np.float64)
    _as_shape_3d(array_np)
    return array_np


def _contig_texture(
    texture_in: Any,
    channels_num: int,
    storage: int,
) -> np.ndarray:
    texture_base = np.asarray(texture_in)
    texture_np = np.array(texture_base, copy=True, order="C")
    if getattr(texture_np, "ndim", None) == 2:
        if channels_num != 1:
            raise ValueError("rgb texture must have shape (3, rows, cols)")
        texture_np = np.ascontiguousarray(texture_np[None, :, :])
    if getattr(texture_np, "ndim", None) != 3:
        raise ValueError("texture must have shape (channels, rows, cols)")
    if int(texture_np.shape[0]) != channels_num:
        raise ValueError("texture channel count does not match shader type")
    if storage == int(TextureStorage.u8):
        if texture_np.dtype != np.uint8:
            raise ValueError("u8 texture storage requires a uint8 array")
    elif storage == int(TextureStorage.u16):
        if texture_np.dtype != np.uint16:
            raise ValueError("u16 texture storage requires a uint16 array")
    elif storage == int(TextureStorage.floating):
        if texture_np.dtype not in (np.float32, np.float64):
            raise ValueError(
                "floating texture storage requires a float32 or float64 array"
            )
        texture_np = np.ascontiguousarray(texture_np, dtype=np.float64)
    else:
        raise ValueError("unsupported texture storage")
    return texture_np


@cython.boundscheck(False)
@cython.wraparound(False)
def roi_cent_from_coords(coords_in: Any) -> tuple[float, float, float]:
    coords_np = _contig_f64_2d(coords_in, "coords")
    rows_num, cols_num = _as_shape_2d(coords_np)
    if cols_num != 3:
        raise ValueError("coords must have shape (N, 3)")

    coords_view: cython.double[:, ::1] = coords_np
    coords_c = _make_array_2d_f64(coords_view, rows_num, cols_num)
    out_cent: cr.CVec3F64

    if (
        cr.rileyRoiCentFromCoords(
            cython.address(coords_c),
            cython.address(out_cent),
        )
        != 0
    ):
        _raise_last_error()

    return (out_cent.x, out_cent.y, out_cent.z)


def coverage_to_fov_scale(coverage: float) -> float:
    return float(cr.rileyCoverageToFovScale(float(coverage)))


def fov_scale_to_coverage(fov_scale: float) -> float:
    return float(cr.rileyFovScaleToCoverage(float(fov_scale)))


@cython.boundscheck(False)
@cython.wraparound(False)
def pos_frame_coords(
    coords_in: Any,
    pixels_num: tuple[int, int],
    pixels_size: tuple[float, float],
    focal_length: float,
    rot_world: tuple[float, float, float],
    fov_scale: float = 1.0,
    fit_mode: FrameFitMode | str | int = FrameFitMode.contain,
    target: tuple[float, float, float] | None = None,
) -> tuple[float, float, float]:
    coords_np = _contig_f64_2d(coords_in, "coords")
    rows_num, cols_num = _as_shape_2d(coords_np)
    if cols_num != 3:
        raise ValueError("coords must have shape (N, 3)")

    coords_view: cython.double[:, ::1] = coords_np
    coords_c = _make_array_2d_f64(coords_view, rows_num, cols_num)
    out_pos: cr.CVec3F64
    mode_int: cython.uint = _fit_mode_to_int(fit_mode)

    target_c: cr.CVec3F64
    target_ptr: cython.pointer[cr.CVec3F64] = cython.NULL
    if target is not None:
        target_c = _make_cvec3(tuple(target))
        target_ptr = cython.address(target_c)
    if cr.rileyPosFrameCoords(
        cython.address(coords_c), _make_cvec2_u32(tuple(pixels_num)),
        _make_cvec2_f64(tuple(pixels_size)), float(focal_length),
        _make_cvec3(tuple(rot_world)), float(fov_scale), mode_int,
        target_ptr, cython.address(out_pos),
    ) != 0:
        _raise_last_error()

    return (out_pos.x, out_pos.y, out_pos.z)


def pos_frame_mesh(
    mesh_in: Any,
    pixels_num: tuple[int, int],
    pixels_size: tuple[float, float],
    focal_length: float,
    rot_world: tuple[float, float, float],
    fov_scale: float = 1.0,
    fit_mode: FrameFitMode | str | int = FrameFitMode.contain,
    target: tuple[float, float, float] | None = None,
) -> tuple[float, float, float]:
    coords = getattr(mesh_in, "coords", mesh_in)
    return pos_frame_coords(
        coords,
        pixels_num,
        pixels_size,
        focal_length,
        rot_world,
        fov_scale=fov_scale,
        fit_mode=fit_mode,
        target=target,
    )


@cython.cfunc
def _make_register(register_ref: Register) -> cr.CRegister:
    return cr.CRegister(int(register_ref.kind), int(register_ref.index))


@cython.cfunc
def _fill_shader_input(
    shader: Any,
    out_shader: cython.pointer[cr.CShaderInput],
    keepalive: list[Any],

) -> None:
    gain = float(getattr(shader, "output_gain", 1.0))
    scaling = int(getattr(shader, "scaling_type", ScaleStrategy.none))
    if gain == 1.0 and scaling != int(ScaleStrategy.none):
        bits = getattr(shader, "bits", None)
        if bits is not None:
            gain = float((1 << int(bits)) - 1)
    out_shader.output_gain = gain
    out_shader.output_offset = float(getattr(shader, "output_offset", 0.0))
    out_shader.scaling_tag = scaling
    out_shader.scaling_min = float(getattr(shader, "scaling_min", 0.0))
    out_shader.scaling_max = float(getattr(shader, "scaling_max", 0.0))

    if isinstance(shader, TextureShader):
        count = int(shader.texture.shape[0])
        storage = (TextureStorage.u8 if shader.texture.dtype == np.uint8 else
                   TextureStorage.u16 if shader.texture.dtype == np.uint16 else TextureStorage.floating)
        out_shader.shader_tag = int(ShaderType.tex if count == 1 else
                                    ShaderType.tex_rgb if count == 3 else ShaderType.tex_multi)
        out_shader.value.texture.storage = int(storage)
        out_shader.value.texture.sample = int(shader.sample)
        out_shader.value.texture.sample_mode = int(shader.sample_mode)
        uvs = _contig_f64_2d(shader.uvs, "uvs")
        keepalive.append(uvs)
        uv_view: cython.double[:, ::1] = uvs
        out_shader.value.texture.uvs = _make_array_2d_f64(uv_view, uvs.shape[0], uvs.shape[1])
        texture = _contig_texture(shader.texture, count, int(storage))
        keepalive.append(texture)
        if storage == TextureStorage.u8:
            tex_u8: cython.uchar[:, :, ::1] = texture
            out_shader.value.texture.data.u8 = _make_array_3d_u8(tex_u8, texture.shape[0], texture.shape[1], texture.shape[2])
        elif storage == TextureStorage.u16:
            tex_u16: cython.ushort[:, :, ::1] = texture
            out_shader.value.texture.data.u16 = _make_array_3d_u16(tex_u16, texture.shape[0], texture.shape[1], texture.shape[2])
        else:
            tex_f: cython.double[:, :, ::1] = texture
            out_shader.value.texture.data.f = _make_array_3d_f64(tex_f, texture.shape[0], texture.shape[1], texture.shape[2])

    elif isinstance(shader, NodalShader):
        field = _contig_f64_3d(shader.field, "nodal_field")
        keepalive.append(field)
        field_view: cython.double[:, :, ::1] = field
        out_shader.shader_tag = int(ShaderType.nodal_rgb if field.shape[2] == 3 else ShaderType.nodal)
        out_shader.value.nodal.field = _make_array_3d_f64(field_view, field.shape[0], field.shape[1], field.shape[2])
        out_shader.value.nodal.scale_over = int(shader.scale_over)

    elif isinstance(shader, (FunctionShader, FunctionMultiShader)):
        out_shader.value.func.channels = cython.NULL
        out_shader.value.func.channels_len = 0
        out_shader.value.func.coord_mode = int(shader.coord_mode)
        out_shader.value.func.uvs = _empty_array_2d_f64()
        if shader.uvs is not None:
            func_uvs = _contig_f64_2d(shader.uvs, "uvs")
            keepalive.append(func_uvs)
            func_uv_view: cython.double[:, ::1] = func_uvs
            out_shader.value.func.uvs = _make_array_2d_f64(func_uv_view, func_uvs.shape[0], func_uvs.shape[1])
        if isinstance(shader, FunctionMultiShader):
            count_c: cython.size_t = len(shader.channels)
            if not 1 <= count_c <= 8:
                raise ValueError("function source requires between one and eight channels")
            out_shader.shader_tag = int(ShaderType.func_multi)
            channels = cython.cast(cython.pointer[cr.CFuncChannel], _descriptor_bytes(count_c * cython.sizeof(cr.CFuncChannel), keepalive))
            if channels == cython.NULL:
                raise MemoryError()

            out_shader.value.func.channels = channels
            out_shader.value.func.channels_len = count_c
            ci: cython.size_t
            for ci in range(count_c):
                channel = shader.channels[ci]
                if not isinstance(channel, FunctionChannel):
                    raise TypeError("function source channels must be FunctionChannel objects")
                channels[ci].builtin = int(channel.builtin)
                channels[ci].params = _make_func_params(channel.params)
                channels[ci].output_gain = float(channel.output_gain)
                channels[ci].output_offset = float(channel.output_offset)
                channels[ci].scaling_tag = int(channel.scaling_type)
                channels[ci].scaling_min = float(channel.scaling_min)
                channels[ci].scaling_max = float(channel.scaling_max)
        else:
            if shader.channels not in (1, 3):
                raise ValueError("FunctionShader.channels must be 1 or 3; use FunctionMultiShader for independent channels")
            out_shader.shader_tag = int(ShaderType.func_rgb if shader.channels == 3 else ShaderType.func)
            out_shader.value.func.builtin = int(shader.builtin)
            out_shader.value.func.params = _make_func_params(shader.params)
    else:
        raise TypeError("source must be a texture, nodal, or function shader")


@cython.cfunc
def _fill_pipe_single(
    pipe: ShaderPipe,
    out_pipe: cython.pointer[cr.CPipe],
    keepalive: list[Any],

) -> None:
    stages_len: cython.size_t = len(pipe.stages)
    if not 1 <= stages_len <= 8:
        raise ValueError("pipe requires between one and eight stages")
    stages = cython.cast(
        cython.pointer[cr.CPipeStage],
        _descriptor_bytes(stages_len * cython.sizeof(cr.CPipeStage), keepalive),
    )
    if stages == cython.NULL:
        raise MemoryError()

    out_pipe.stages = stages
    out_pipe.stages_len = stages_len
    si: cython.size_t
    for si in range(stages_len):
        stage = pipe.stages[si]
        stages[si].shader = cython.NULL
        stages[si].lower = 0.0
        stages[si].upper = 0.0
        stages[si].black = 0.0
        stages[si].white = 0.0
        if isinstance(stage, ShaderSource):
            valid_shaders = (TextureShader, NodalShader, FunctionShader, FunctionMultiShader)
            if not isinstance(stage.shader, valid_shaders):
                raise TypeError(
                    "source stage requires a texture, nodal, or function"
                    " shader"
                )
            stages[si].tag = 0
            stages[si].register_dest = _make_register(stage.register_dest)
            source = cython.cast(
                cython.pointer[cr.CShaderInput],
                _descriptor_bytes(cython.sizeof(cr.CShaderInput), keepalive),
            )
            if source == cython.NULL:
                raise MemoryError()

            _fill_shader_input(stage.shader, source, keepalive)
            stages[si].shader = source
        elif isinstance(stage, GreyToEmissivity):
            stages[si].tag = 1
            stages[si].register_source = _make_register(stage.register_source)
            stages[si].register_dest = _make_register(stage.register_dest)
            stages[si].lower = float(stage.greylevel_at_black)
            stages[si].upper = float(stage.greylevel_at_white)
            stages[si].black = float(stage.emissivity_at_black)
            stages[si].white = float(stage.emissivity_at_white)
        elif isinstance(stage, ClampStage):
            stages[si].tag = 2
            stages[si].register_source = _make_register(stage.register_source)
            stages[si].register_dest = _make_register(stage.register_dest)
            stages[si].lower = float(stage.lower)
            stages[si].upper = float(stage.upper)
        elif isinstance(stage, AffineMap):
            stages[si].tag = 3
            stages[si].register_source = _make_register(stage.register_source)
            stages[si].register_dest = _make_register(stage.register_dest)
            stages[si].gain = float(stage.gain)
            stages[si].offset = float(stage.offset)
        elif isinstance(stage, LUTMap):
            stages[si].tag = 4
            stages[si].register_source = _make_register(stage.register_source)
            stages[si].register_dest = _make_register(stage.register_dest)
            stages[si].lookup.first = float(stage.first)
            stages[si].lookup.step = float(stage.step)
            lookup_np = np.ascontiguousarray(
                stage.values, dtype=np.float64
            )
            if lookup_np.ndim != 1 or lookup_np.size < 2:
                raise ValueError(
                    "LUTMap needs a one-dimensional table of at least two"
                    " values"
                )
            keepalive.append(lookup_np)
            stage_lookup_view: cython.double[::1] = lookup_np
            stages[si].lookup.values = cython.address(stage_lookup_view[0])
            stages[si].lookup.values_len = len(lookup_np)
        elif isinstance(stage, Blend):
            stages[si].tag = 5
            stages[si].register_source = _make_register(stage.a)
            stages[si].register_source_b = _make_register(stage.b)
            stages[si].register_dest = _make_register(stage.register_dest)
            if isinstance(stage.alpha, Register):
                stages[si].alpha_from_register = 1
                stages[si].alpha_register = _make_register(stage.alpha)
            else:
                stages[si].alpha_from_register = 0
                stages[si].alpha = float(stage.alpha)
        elif isinstance(stage, Normalise):
            stages[si].tag = 6
            stages[si].register_source = _make_register(stage.register_source)
            stages[si].register_dest = _make_register(stage.register_dest)
            stages[si].components = int(stage.components)
        else:
            raise TypeError("unsupported shader-pipe stage")

    resolver = pipe.resolver
    out_pipe.resolver.tag = int(resolver.kind)
    out_pipe.resolver.factor = _make_register(resolver.factor)
    out_pipe.resolver.temperature = _make_register(resolver.temperature)
    out_pipe.resolver.emissivity = _make_register(resolver.emissivity)
    out_pipe.resolver.ambient = float(resolver.ambient)
    out_pipe.resolver.gain = float(resolver.gain)
    out_pipe.resolver.registers = cython.NULL
    out_pipe.resolver.registers_len = len(resolver.registers)
    if resolver.registers:
        registers = cython.cast(
            cython.pointer[cr.CRegister],
            _descriptor_bytes(len(resolver.registers) * cython.sizeof(cr.CRegister), keepalive),
        )
        if registers == cython.NULL:
            raise MemoryError()

        for si in range(len(resolver.registers)):
            registers[si] = _make_register(resolver.registers[si])
        out_pipe.resolver.registers = registers

    out_pipe.resolver.weights = cython.NULL
    out_pipe.resolver.weights_len = len(resolver.weights)
    if resolver.weights:
        weights_np = np.ascontiguousarray(
            resolver.weights, dtype=np.float64
        )
        keepalive.append(weights_np)
        weights_view: cython.double[::1] = weights_np
        out_pipe.resolver.weights = cython.address(weights_view[0])

    out_pipe.resolver.lookup.values = cython.NULL
    out_pipe.resolver.lookup.values_len = 0
    out_pipe.resolver.lookup.first = float(resolver.lookup_first)
    out_pipe.resolver.lookup.step = float(resolver.lookup_step)
    if resolver.lookup_values is not None:
        lookup_np = np.ascontiguousarray(
            resolver.lookup_values, dtype=np.float64
        )
        if lookup_np.ndim != 1 or lookup_np.size < 2:
            raise ValueError("resolver lookup needs at least two values")
        keepalive.append(lookup_np)
        lookup_view: cython.double[::1] = lookup_np
        out_pipe.resolver.lookup.values = cython.address(lookup_view[0])
        out_pipe.resolver.lookup.values_len = len(lookup_np)

    out_pipe.resolver.operations = cython.NULL
    out_pipe.resolver.operations_len = len(resolver.operations)
    if resolver.operations:
        operations = cython.cast(
            cython.pointer[cr.CResolverOp],
            _descriptor_bytes(len(resolver.operations) * cython.sizeof(cr.CResolverOp), keepalive),
        )
        if operations == cython.NULL:
            raise MemoryError()

        for si in range(len(resolver.operations)):
            operation = resolver.operations[si]
            operations[si].tag = int(operation.kind)
            operations[si].register_ref = _make_register(operation.register_ref)
            operations[si].lower = float(operation.lower)
            operations[si].upper = float(operation.upper)
        out_pipe.resolver.operations = operations

    out_pipe.constants = cython.NULL
    out_pipe.constants_len = len(pipe.constants)
    if pipe.constants:
        constants_np = np.ascontiguousarray(
            pipe.constants, dtype=np.float64
        )
        keepalive.append(constants_np)
        constants_view: cython.double[::1] = constants_np
        out_pipe.constants = cython.address(constants_view[0])


@cython.cfunc
def _fill_mesh_array(
    mesh_list: list[Any],
    mesh_array: cython.pointer[cr.CMeshInput],
    keepalive: list[Any],

) -> None:
    nn: cython.size_t
    for nn in range(len(mesh_list)):
        mesh = mesh_list[nn]
        coords_np = _contig_f64_2d(mesh.coords, "coords")
        connect_np = _contig_u_size_2d(mesh.connect)
        coords_shape = _as_shape_2d(coords_np)
        if coords_shape[1] != 3:
            raise ValueError("coords must have shape (N, 3)")

        coords_view: cython.double[:, ::1] = coords_np
        connect_view: cython.size_t[:, ::1] = connect_np
        mesh_array[nn].mesh_type = int(mesh.mesh_type)
        mesh_array[nn].normal_type = int(mesh.normal_type)
        mesh_array[nn].coords = _make_array_2d_f64(
            coords_view,
            coords_np.shape[0],
            coords_np.shape[1],
        )
        mesh_array[nn].connect = _make_array_2d_usize(
            connect_view,
            connect_np.shape[0],
            connect_np.shape[1],
        )

        if mesh.disp is None:
            mesh_array[nn].disp = _empty_array_3d_f64()
        else:
            disp_np = _contig_f64_3d(mesh.disp, "disp")
            disp_shape = _as_shape_3d(disp_np)
            disp_view: cython.double[:, :, ::1] = disp_np
            mesh_array[nn].disp = _make_array_3d_f64(
                disp_view,
                disp_shape[0],
                disp_shape[1],
                disp_shape[2],
            )
            keepalive.append(disp_np)

        mesh.shaders._normalise_sources()
        choices = []
        for role, entry in (
            (RenderFormat.mono, mesh.shaders.mono),
            (RenderFormat.rgb, mesh.shaders.rgb),
            (RenderFormat.ir, mesh.shaders.ir),
            (RenderFormat.multifield, mesh.shaders.multifield),
        ):
            if entry is not None:
                choices.append((role, entry))

        shaders_len: cython.size_t = len(choices)
        if shaders_len == 0:
            raise ValueError("mesh needs at least one shader choice")

        shaders = cython.cast(
            cython.pointer[cr.CShaderEntry],
            _descriptor_bytes(shaders_len * cython.sizeof(cr.CShaderEntry), keepalive),
        )
        if shaders == cython.NULL:
            raise MemoryError()

        mesh_array[nn].shaders = shaders
        mesh_array[nn].shaders_len = shaders_len

        si: cython.size_t
        for si in range(shaders_len):
            role, entry = choices[si]
            shaders[si].format_tag = int(role)
            if isinstance(entry, ShaderPipe):
                shaders[si].execution_tag = 1
                _fill_pipe_single(
                    entry,
                    cython.address(shaders[si].value.pipe),
                    keepalive,

                )
            elif isinstance(
                entry, (TextureShader, NodalShader, FunctionShader, FunctionMultiShader)
            ):
                shaders[si].execution_tag = 0
                _fill_shader_input(
                    entry,
                    cython.address(shaders[si].value.direct),
                    keepalive,

                )
            else:
                raise TypeError(
                    f"unsupported shader entry type: {type(entry)}"
                )

        keepalive.append(coords_np)
        keepalive.append(connect_np)


@cython.cfunc
def _fill_geometry(meshes: list[Any], keepalive: list[Any]) -> cython.pointer[cr.CArray2DF64]:
    if not meshes:
        raise ValueError("geometry must contain at least one coordinate array")
    descriptors = cython.cast(cython.pointer[cr.CArray2DF64],
                              _descriptor_bytes(len(meshes) * cython.sizeof(cr.CArray2DF64), keepalive))
    index: cython.size_t
    for index in range(len(meshes)):
        coords = _contig_f64_2d(meshes[index].coords, "coords")
        if coords.shape[1] != 3 or coords.shape[0] == 0:
            raise ValueError("coords must have shape (N, 3) with N > 0")
        keepalive.append(coords)
        view: cython.double[:, ::1] = coords
        descriptors[index] = _make_array_2d_f64(view, coords.shape[0], coords.shape[1])
    return descriptors


def roi_cent_over_meshes(meshes: Any) -> tuple[float, float, float]:
    keepalive: list[Any] = []
    mesh_list = _normalize_meshes(meshes)
    geometry = _fill_geometry(mesh_list, keepalive)
    out_cent: cr.CVec3F64
    if cr.rileyRoiCentOverMeshes(geometry, len(mesh_list), cython.address(out_cent)) != 0:
        _raise_last_error()
    return (out_cent.x, out_cent.y, out_cent.z)


def pos_frame_meshes(
    meshes: Any,
    pixels_num: tuple[int, int],
    pixels_size: tuple[float, float],
    focal_length: float,
    rot_world: tuple[float, float, float],
    fov_scale: float = 1.0,
    fit_mode: FrameFitMode | str | int = FrameFitMode.contain,
    target: tuple[float, float, float] | None = None,
) -> tuple[float, float, float]:
    keepalive: list[Any] = []
    mesh_list = _normalize_meshes(meshes)
    geometry = _fill_geometry(mesh_list, keepalive)
    out_pos: cr.CVec3F64
    target_c: cr.CVec3F64
    target_ptr: cython.pointer[cr.CVec3F64] = cython.NULL
    if target is not None:
        target_c = _make_cvec3(tuple(target))
        target_ptr = cython.address(target_c)
    if cr.rileyPosFrameMeshes(
        geometry, len(mesh_list), _make_cvec2_u32(tuple(pixels_num)),
        _make_cvec2_f64(tuple(pixels_size)), float(focal_length),
        _make_cvec3(tuple(rot_world)), float(fov_scale), _fit_mode_to_int(fit_mode),
        target_ptr, cython.address(out_pos),
    ) != 0:
        _raise_last_error()
    return (out_pos.x, out_pos.y, out_pos.z)


def pos_orbit_cam(
    target: tuple[float, float, float],
    azimuth_rad: float,
    elevation_rad: float,
    distance: float,
) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    out_pos: cr.CVec3F64
    out_rot: cr.CVec3F64
    if (
        cr.rileyPosOrbitCam(
            _make_cvec3(tuple(target)),
            float(azimuth_rad),
            float(elevation_rad),
            float(distance),
            cython.address(out_pos),
            cython.address(out_rot),
        )
        != 0
    ):
        _raise_last_error()
    return (
        (out_pos.x, out_pos.y, out_pos.z),
        (out_rot.x, out_rot.y, out_rot.z),
    )


def pos_stereo_pair(
    target: tuple[float, float, float],
    distance: float,
    stereo_angle_rad: float,
    baseline_angle_rad: float = 0.0,
) -> tuple[
    tuple[float, float, float],
    tuple[float, float, float],
    tuple[float, float, float],
    tuple[float, float, float],
]:
    cam0_pos: cr.CVec3F64
    cam0_rot: cr.CVec3F64
    cam1_pos: cr.CVec3F64
    cam1_rot: cr.CVec3F64
    if (
        cr.rileyPosStereoPair(
            _make_cvec3(tuple(target)),
            float(distance),
            float(stereo_angle_rad),
            float(baseline_angle_rad),
            cython.address(cam0_pos),
            cython.address(cam0_rot),
            cython.address(cam1_pos),
            cython.address(cam1_rot),
        )
        != 0
    ):
        _raise_last_error()
    return (
        (cam0_pos.x, cam0_pos.y, cam0_pos.z),
        (cam0_rot.x, cam0_rot.y, cam0_rot.z),
        (cam1_pos.x, cam1_pos.y, cam1_pos.z),
        (cam1_rot.x, cam1_rot.y, cam1_rot.z),
    )


def calc_pixel_resolution(
    camera: Any,
    target: tuple[float, float, float],
) -> float:
    keepalive: list[Any] = []
    cam_c = _make_camera_input(camera, keepalive)
    out_res: cython.double = 0.0
    if (
        cr.rileyCalcPixelResolution(
            cython.address(cam_c),
            _make_cvec3(tuple(target)),
            cython.address(out_res),
        )
        != 0
    ):
        _raise_last_error()
    return float(out_res)


def save_stereo_pair(
    out_dir: str,
    stereo_file_name: str,
    camera_0: Camera,
    camera_1: Camera,
) -> None:
    keepalive: list[Any] = []
    cam0_c = _make_camera_input(camera_0, keepalive)
    cam1_c = _make_camera_input(camera_1, keepalive)
    out_dir_bytes = out_dir.encode("utf-8")
    file_name_bytes = stereo_file_name.encode("utf-8")
    if (
        cr.rileySaveStereoPair(
            out_dir_bytes,
            file_name_bytes,
            cython.address(cam0_c),
            cython.address(cam1_c),
        )
        != 0
    ):
        _raise_last_error()


def save_camera(
    out_dir: str,
    file_name: str,
    camera_idx: int,
    camera: Camera,
) -> None:
    keepalive: list[Any] = []
    camera_c = _make_camera_input(camera, keepalive)
    out_dir_bytes = out_dir.encode("utf-8")
    file_name_bytes = file_name.encode("utf-8")
    if (
        cr.rileySaveCamera(
            out_dir_bytes,
            file_name_bytes,
            camera_idx,
            cython.address(camera_c),
        )
        != 0
    ):
        _raise_last_error()


def load_camera(dir_path: str, file_name: str) -> Camera:
    """Load a camera into Python-owned storage through the caller-buffer
    C API."""
    dir_bytes = dir_path.encode("utf-8")
    file_bytes = file_name.encode("utf-8")
    camera_c: cr.CCameraInput
    if (
        cr.rileyLoadCamera(
            dir_bytes,
            file_bytes,
            cython.NULL,
            0,
            cython.address(camera_c),
        )
        != 0
    ):
        _raise_last_error()
    # Maximum supported capacity also handles file changes between query
    # and load.
    storage = np.empty(72, dtype=np.float64)
    coeffs: cython.double[::1] = storage
    if (
        cr.rileyLoadCamera(
            dir_bytes,
            file_bytes,
            cython.address(coeffs[0]),
            72,
            cython.address(camera_c),
        )
        != 0
    ):
        _raise_last_error()
    return _camera_input_from_c(camera_c)


def load_stereo_pair(
    dir_path: str,
    stereo_file_name: str,
) -> tuple[Camera, Camera]:
    """Load both cameras with independent caller-owned coefficient buffers."""
    dir_bytes = dir_path.encode("utf-8")
    file_bytes = stereo_file_name.encode("utf-8")
    cam0_c: cr.CCameraInput
    cam1_c: cr.CCameraInput
    storage0 = np.empty(72, dtype=np.float64)
    storage1 = np.empty(72, dtype=np.float64)
    coeffs0: cython.double[::1] = storage0
    coeffs1: cython.double[::1] = storage1
    if (
        cr.rileyLoadStereoPair(
            dir_bytes,
            file_bytes,
            cython.address(coeffs0[0]),
            72,
            cython.address(coeffs1[0]),
            72,
            cython.address(cam0_c),
            cython.address(cam1_c),
        )
        != 0
    ):
        _raise_last_error()
    return (_camera_input_from_c(cam0_c), _camera_input_from_c(cam1_c))


@cython.boundscheck(False)
@cython.wraparound(False)
def raster(
    meshes: Any,
    cameras: Any,
    config: RasterConfig,
    out_dir: str | None = None,
) -> np.ndarray | None:
    keepalive: list[Any] = []
    mesh_list = _normalize_meshes(meshes)
    camera_list = _normalize_cameras(cameras)
    meshes_len: cython.size_t = len(mesh_list)
    cameras_len: cython.size_t = len(camera_list)
    mesh_array = cython.cast(
        cython.pointer[cr.CMeshInput],
        _descriptor_bytes(meshes_len * cython.sizeof(cr.CMeshInput), keepalive),
    )
    camera_array = cython.cast(
        cython.pointer[cr.CCameraInput],
        _descriptor_bytes(cameras_len * cython.sizeof(cr.CCameraInput), keepalive),
    )
    config_c: cr.CRasterConfig
    image_np: np.ndarray | None = None
    image_ptr: cython.pointer[cr.CImageBuffF64] = cython.cast(
        cython.pointer[cr.CImageBuffF64],
        cython.NULL,
    )
    image_c: cr.CImageBuffF64

    config_c = _make_raster_config(config, keepalive)

    try:
        _fill_mesh_array(mesh_list, mesh_array, keepalive)

        nn: cython.size_t
        for nn in range(cameras_len):
            camera_array[nn] = _make_camera_input(camera_list[nn], keepalive)

        out_dir_ptr: cython.p_char = cython.cast(cython.p_char, cython.NULL)
        if out_dir is not None:
            out_dir_bytes: bytes = out_dir.encode("utf-8")
            out_dir_ptr = out_dir_bytes
            keepalive.append(out_dir_bytes)

        if config.save_strategy in (SaveStrategy.memory, SaveStrategy.both):
            dims_c: cr.CDims5Usize
            if (
                cr.rileyCalcOutputDimsScene(
                    mesh_array,
                    meshes_len,
                    camera_array,
                    cameras_len,
                    cython.address(config_c),
                    cython.address(dims_c),
                )
                != 0
            ):
                _raise_last_error()

            image_np = np.empty(
                (
                    dims_c.dim0,
                    dims_c.dim1,
                    dims_c.dim2,
                    dims_c.dim3,
                    dims_c.dim4,
                ),
                dtype=np.float64,
            )
            image_view: cython.double[:, :, :, :, ::1] = image_np
            image_c.elems = cython.address(image_view[0, 0, 0, 0, 0])
            image_c.dims = dims_c
            image_ptr = cython.address(image_c)

        if (
            cr.rileyRaster(
                mesh_array,
                meshes_len,
                camera_array,
                cameras_len,
                cython.address(config_c),
                out_dir_ptr,
                image_ptr,
            )
            != 0
        ):
            _raise_last_error()
    finally:
        keepalive.clear()

    return image_np


__all__ = [
    "raster", "roi_cent_from_coords", "roi_cent_over_meshes",
    "pos_frame_coords", "pos_frame_mesh", "pos_frame_meshes",
    "pos_orbit_cam", "pos_stereo_pair", "calc_pixel_resolution",
    "coverage_to_fov_scale", "fov_scale_to_coverage",
    "save_camera", "save_stereo_pair", "load_camera", "load_stereo_pair",
]
