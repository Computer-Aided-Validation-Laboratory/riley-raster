# --------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher)
# --------------------------------------------------------------------------
import cython
from dataclasses import dataclass, field
from enum import IntEnum
from pathlib import Path
from typing import Any

import numpy as np
from cython.cimports.libc.stdlib import free, malloc
from cython.cimports.riley.cyth import riley as cr
from riley.python.helpers import load_sim_from_csv, load_texture


@dataclass(slots=True)
class Camera:
    pixels_num: tuple[int, int]
    pixels_size: tuple[float, float]
    pos_world: tuple[float, float, float]
    rot_world: tuple[float, float, float]
    roi_cent_world: tuple[float, float, float]
    focal_length: float
    sub_sample: int
    distortion_model: int = 0
    distortion_k1: float = 0.0
    distortion_k2: float = 0.0
    distortion_k3: float = 0.0
    distortion_k4: float = 0.0
    distortion_k5: float = 0.0
    distortion_k6: float = 0.0
    distortion_p1: float = 0.0
    distortion_p2: float = 0.0
    coord_sys: int = 0


CameraInput = Camera


@dataclass(slots=True)
class FuncShaderParams:
    coord_scale: tuple[float, float] = (1.0, 1.0)
    coord_offset: tuple[float, float] = (0.0, 0.0)
    output_scale: float = 1.0
    output_offset: float = 0.0
    wave_num_scalar: tuple[float, float] = (6.0, 5.0)
    wave_num_rgb: tuple[float, float, float] = (6.0, 6.0, 4.0)
    extra: tuple[float, float, float, float] = (
        0.0,
        0.0,
        0.0,
        0.0,
    )




@dataclass(slots=True)
class Mesh:
    mesh_type: int
    coords: np.ndarray
    connect: np.ndarray
    disp: np.ndarray | None = None
    shader_type: int = 0
    uvs: np.ndarray | None = None
    texture: np.ndarray | None = None
    sample: int = 2
    sample_mode: int = 2
    bits: int = 8
    scaling_type: int = 0
    scaling_min: float = 0.0
    scaling_max: float = 0.0
    nodal_field: np.ndarray | None = None
    scale_over: int = 1
    func_shader_builtin: int = 0
    func_shader_params: FuncShaderParams = field(
        default_factory=FuncShaderParams,
    )
    normal_type: int = 0


MeshInput = Mesh


@dataclass(slots=True)
class RasterConfig:
    render_mode: int = 0
    total_threads: int = 1
    frame_batch_size_per_group: int = 1
    max_geom_jobs_in_flight_per_group: int = 1
    max_geom_workers_per_job: int = 1
    geom_scheduling_mode: int = 2
    max_raster_workers_per_job: int = 1
    save_strategy: int = 1
    image_mode: int = 2
    subpixel_center_map: int = 1
    report: int = 1
    tile_size_min: int = 8
    tile_size_max: int = 256
    background_value: float = 0.0
    disk_save_overlap: bool = False


@dataclass(slots=True)
class ParallelConfig:
    render_mode: int = 1
    total_threads: int = 1
    render_group_count: int = 1
    workers_per_group: int | list[int] = 1
    frame_batch_size_per_group: int = 1
    max_geom_jobs_in_flight_per_group: int = 1
    max_geom_workers_per_job: int = 1
    geom_scheduling_mode: int = 0
    max_raster_workers_per_job: int = 1


class MeshType(IntEnum):
    tri3 = 0
    tri6 = 1
    quad4ibi = 2
    quad4newton = 3
    quad8 = 4
    quad9 = 5


class ShaderType(IntEnum):
    tex = 0
    tex_rgb = 1
    nodal = 2
    func = 3
    func_rgb = 4
    nodal_rgb = 5


class RenderMode(IntEnum):
    in_order = 0
    offline = 1


class GeometrySchedulingMode(IntEnum):
    spread = 0
    pack = 1
    auto = 2


class SaveStrategy(IntEnum):
    disk = 0
    memory = 1
    both = 2
    none = 3


class ImageMode(IntEnum):
    grey = 0
    rgb = 1
    multifield = 2


class ReportMode(IntEnum):
    off = 0
    bench = 1
    full_stats = 2


class SubPixelCenterMap(IntEnum):
    full_in_mem = 0
    per_tile = 1
    affine_jac = 2


class TextureSample(IntEnum):
    nearest = 0
    linear = 1
    cubic_catmull_rom = 2
    cubic_mitchell_netravali = 3
    lanczos3 = 4
    cubic_bspline = 5
    quintic_bspline = 6


class TextureSampleMode(IntEnum):
    direct = 0
    lut = 1
    lut_lerp = 2


class ScaleStrategy(IntEnum):
    none = 0
    auto = 1
    fixed = 2
    frac = 3


class ScaleOver(IntEnum):
    within_frames = 0
    over_frames = 1


class FuncShaderBuiltin(IntEnum):
    constant = 0
    linear = 1
    quadratic = 2
    sinusoidal = 3
    checker = 4
    checker_smooth = 5
    lambertian_normal_z = 6




class NormalType(IntEnum):
    none = 0
    exact = 1
    averaged = 2


class CameraCoordSys(IntEnum):
    opengl = 0
    opencv = 1


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
def _make_camera_input(camera: Any) -> cr.CCameraInput:
    camera_out: cr.CCameraInput
    camera_out.pixels_num = _make_cvec2_u32(camera.pixels_num)
    camera_out.pixels_size = _make_cvec2_f64(camera.pixels_size)
    camera_out.pos_world = _make_cvec3(camera.pos_world)
    camera_out.rot_world = _make_cvec3(camera.rot_world)
    camera_out.roi_cent_world = _make_cvec3(camera.roi_cent_world)
    camera_out.focal_length = float(camera.focal_length)
    camera_out.sub_sample = int(camera.sub_sample)
    camera_out.distortion_model = int(camera.distortion_model)
    camera_out.distortion_k1 = float(camera.distortion_k1)
    camera_out.distortion_k2 = float(camera.distortion_k2)
    camera_out.distortion_k3 = float(camera.distortion_k3)
    camera_out.distortion_k4 = float(camera.distortion_k4)
    camera_out.distortion_k5 = float(camera.distortion_k5)
    camera_out.distortion_k6 = float(camera.distortion_k6)
    camera_out.distortion_p1 = float(camera.distortion_p1)
    camera_out.distortion_p2 = float(camera.distortion_p2)
    camera_out.coord_sys = int(camera.coord_sys)
    return camera_out


def _camera_input_from_c(camera_in: cr.CCameraInput) -> Camera:
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
        distortion_model=camera_in.distortion_model,
        distortion_k1=camera_in.distortion_k1,
        distortion_k2=camera_in.distortion_k2,
        distortion_k3=camera_in.distortion_k3,
        distortion_k4=camera_in.distortion_k4,
        distortion_k5=camera_in.distortion_k5,
        distortion_k6=camera_in.distortion_k6,
        distortion_p1=camera_in.distortion_p1,
        distortion_p2=camera_in.distortion_p2,
        coord_sys=camera_in.coord_sys,
    )


@cython.cfunc
def _make_raster_config(config: Any) -> cr.CRasterConfig:
    config_out: cr.CRasterConfig
    config_out.render_mode = int(config.render_mode)
    config_out.total_threads = int(config.total_threads)
    config_out.frame_batch_size_per_group = int(
        config.frame_batch_size_per_group,
    )
    config_out.max_geom_jobs_in_flight_per_group = int(
        config.max_geom_jobs_in_flight_per_group,
    )
    config_out.max_geom_workers_per_job = int(config.max_geom_workers_per_job)
    config_out.geom_scheduling_mode = int(config.geom_scheduling_mode)
    config_out.max_raster_workers_per_job = int(
        config.max_raster_workers_per_job,
    )
    config_out.save_strategy = int(config.save_strategy)
    config_out.image_mode = int(config.image_mode)
    config_out.subpixel_center_map = int(config.subpixel_center_map)
    config_out.report = int(config.report)
    config_out.tile_size_min = int(config.tile_size_min)
    config_out.tile_size_max = int(config.tile_size_max)
    config_out.background_value = float(config.background_value)
    config_out.disk_save_overlap = 1 if config.disk_save_overlap else 0
    return config_out


def _build_default_parallel_config(config: RasterConfig) -> ParallelConfig:
    total_threads = max(1, int(config.total_threads))
    return ParallelConfig(
        render_mode=int(RenderMode.offline),
        total_threads=total_threads,
        render_group_count=total_threads,
        workers_per_group=1,
        frame_batch_size_per_group=max(
            1,
            int(config.frame_batch_size_per_group),
        ),
        max_geom_jobs_in_flight_per_group=max(
            1,
            int(config.max_geom_jobs_in_flight_per_group),
        ),
        max_geom_workers_per_job=max(
            1,
            int(config.max_geom_workers_per_job),
        ),
        geom_scheduling_mode=int(GeometrySchedulingMode.spread),
        max_raster_workers_per_job=max(
            1,
            int(config.max_raster_workers_per_job),
        ),
    )


def _normalize_workers_per_group(
    workers_per_group: int | list[int],
    render_group_count: int,
) -> np.ndarray:
    if isinstance(workers_per_group, int):
        return np.full(
            (render_group_count,),
            max(1, int(workers_per_group)),
            dtype=np.uint16,
        )

    workers_array = np.ascontiguousarray(
        np.asarray(workers_per_group, dtype=np.uint16),
    )
    if workers_array.ndim != 1:
        raise ValueError("workers_per_group must be a 1D list or an int")
    if workers_array.shape[0] != render_group_count:
        raise ValueError(
            "workers_per_group list length must match render_group_count",
        )
    return np.ascontiguousarray(
        np.maximum(workers_array, np.uint16(1)),
        dtype=np.uint16,
    )


@cython.cfunc
def _fill_parallel_config(
    config_out: cython.pointer[cr.CParallelConfig],
    parallel_config: ParallelConfig,
) -> list[Any]:
    keepalive: list[Any] = []
    render_group_count = max(1, int(parallel_config.render_group_count))
    workers_array = _normalize_workers_per_group(
        parallel_config.workers_per_group,
        render_group_count,
    )
    workers_view: cython.ushort[::1] = workers_array
    keepalive.append(workers_array)

    config_out[0].render_mode = int(parallel_config.render_mode)
    config_out[0].total_threads = max(1, int(parallel_config.total_threads))
    config_out[0].render_group_count = render_group_count
    config_out[0].workers_per_group_len = workers_array.shape[0]
    config_out[0].workers_per_group = cython.cast(
        cython.pointer[cython.ushort],
        cython.address(workers_view[0]),
    )
    config_out[0].frame_batch_size_per_group = max(
        1,
        int(parallel_config.frame_batch_size_per_group),
    )
    config_out[0].max_geom_jobs_in_flight_per_group = max(
        1,
        int(parallel_config.max_geom_jobs_in_flight_per_group),
    )
    config_out[0].max_geom_workers_per_job = max(
        1,
        int(parallel_config.max_geom_workers_per_job),
    )
    config_out[0].geom_scheduling_mode = int(
        parallel_config.geom_scheduling_mode,
    )
    config_out[0].max_raster_workers_per_job = max(
        1,
        int(parallel_config.max_raster_workers_per_job),
    )
    return keepalive


@cython.cfunc
def _make_func_params(params_in: Any) -> cr.CFuncShaderParams:
    return cr.CFuncShaderParams(
        float(params_in.coord_scale[0]),
        float(params_in.coord_scale[1]),
        float(params_in.coord_offset[0]),
        float(params_in.coord_offset[1]),
        float(params_in.output_scale),
        float(params_in.output_offset),
        float(params_in.wave_num_scalar[0]),
        float(params_in.wave_num_scalar[1]),
        float(params_in.wave_num_rgb[0]),
        float(params_in.wave_num_rgb[1]),
        float(params_in.wave_num_rgb[2]),
        float(params_in.extra[0]),
        float(params_in.extra[1]),
        float(params_in.extra[2]),
        float(params_in.extra[3]),
    )


@cython.cfunc
def _make_array_2d_f64(
    view_in: cython.double[:, ::1],
    rows_num: cython.Py_ssize_t,
    cols_num: cython.Py_ssize_t,
) -> cr.CArray2DF64:
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
def _empty_array_2d_f64() -> cr.CArray2DF64:
    return cr.CArray2DF64(cython.NULL, 0, 0)


@cython.cfunc
def _empty_array_2d_usize() -> cr.CArray2DUsize:
    return cr.CArray2DUsize(cython.NULL, 0, 0)


@cython.cfunc
def _empty_array_3d_f64() -> cr.CArray3DF64:
    return cr.CArray3DF64(cython.NULL, 0, 0, 0)


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


def _contig_texture(texture_in: Any, channels_num: int) -> np.ndarray:
    texture_np = np.ascontiguousarray(texture_in, dtype=np.float64)
    if getattr(texture_np, "ndim", None) == 2:
        if channels_num != 1:
            raise ValueError("rgb texture must have shape (3, rows, cols)")
        texture_np = np.ascontiguousarray(
            texture_np[None, :, :],
            dtype=np.float64,
        )
    if getattr(texture_np, "ndim", None) != 3:
        raise ValueError("texture must have shape (channels, rows, cols)")
    if int(texture_np.shape[0]) != channels_num:
        raise ValueError("texture channel count does not match shader type")
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

    if cr.rileyRoiCentFromCoords(
        cython.address(coords_c),
        cython.address(out_cent),
    ) != 0:
        _raise_last_error()

    return (out_cent.x, out_cent.y, out_cent.z)


@cython.boundscheck(False)
@cython.wraparound(False)
def pos_fill_frame_from_rot(
    coords_in: Any,
    pixels_num: tuple[int, int],
    pixels_size: tuple[float, float],
    focal_length: float,
    rot_world: tuple[float, float, float],
    frame_fill: float = 1.0,
) -> tuple[float, float, float]:
    coords_np = _contig_f64_2d(coords_in, "coords")
    rows_num, cols_num = _as_shape_2d(coords_np)
    if cols_num != 3:
        raise ValueError("coords must have shape (N, 3)")

    coords_view: cython.double[:, ::1] = coords_np
    coords_c = _make_array_2d_f64(coords_view, rows_num, cols_num)
    out_pos: cr.CVec3F64

    if cr.rileyPosFillFrameFromRot(
        cython.address(coords_c),
        _make_cvec2_u32(tuple(pixels_num)),
        _make_cvec2_f64(tuple(pixels_size)),
        float(focal_length),
        _make_cvec3(tuple(rot_world)),
        float(frame_fill),
        cython.address(out_pos),
    ) != 0:
        _raise_last_error()

    return (out_pos.x, out_pos.y, out_pos.z)


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

        shader_tag = int(mesh.shader_type)
        mesh_array[nn].shader_tag = shader_tag
        mesh_array[nn].sample = int(mesh.sample)
        mesh_array[nn].sample_mode = int(mesh.sample_mode)
        mesh_array[nn].bits = int(mesh.bits)
        mesh_array[nn].scaling_tag = int(mesh.scaling_type)
        mesh_array[nn].scaling_min = float(mesh.scaling_min)
        mesh_array[nn].scaling_max = float(mesh.scaling_max)
        mesh_array[nn].scale_over = int(mesh.scale_over)
        mesh_array[nn].func_shader_builtin = int(mesh.func_shader_builtin)
        mesh_array[nn].func_shader_params = _make_func_params(
            mesh.func_shader_params,
        )
        mesh_array[nn].normal_type = int(mesh.normal_type)

        if mesh.uvs is None:
            mesh_array[nn].uvs = _empty_array_2d_f64()
        else:
            uvs_np = _contig_f64_2d(mesh.uvs, "uvs")
            uvs_shape = _as_shape_2d(uvs_np)
            uvs_view: cython.double[:, ::1] = uvs_np
            mesh_array[nn].uvs = _make_array_2d_f64(
                uvs_view,
                uvs_shape[0],
                uvs_shape[1],
            )
            keepalive.append(uvs_np)

        texture_channels = 0
        if shader_tag == int(ShaderType.tex):
            texture_channels = 1
        elif shader_tag == int(ShaderType.tex_rgb):
            texture_channels = 3

        if mesh.texture is None:
            mesh_array[nn].texture = _empty_array_3d_f64()
        else:
            if texture_channels == 0:
                raise ValueError("texture provided for non-texture shader")
            texture_np = _contig_texture(mesh.texture, texture_channels)
            texture_shape = _as_shape_3d(texture_np)
            texture_view: cython.double[:, :, ::1] = texture_np
            mesh_array[nn].texture = _make_array_3d_f64(
                texture_view,
                texture_shape[0],
                texture_shape[1],
                texture_shape[2],
            )
            keepalive.append(texture_np)

        if mesh.nodal_field is None:
            mesh_array[nn].nodal_field = _empty_array_3d_f64()
        else:
            nodal_field_np = _contig_f64_3d(mesh.nodal_field, "nodal_field")
            nodal_shape = _as_shape_3d(nodal_field_np)
            if (
                shader_tag == int(ShaderType.nodal_rgb)
                and nodal_shape[2] != 3
            ):
                raise ValueError(
                    "nodal_rgb field must have shape (time, nodes, 3)",
                )
            nodal_view: cython.double[:, :, ::1] = nodal_field_np
            mesh_array[nn].nodal_field = _make_array_3d_f64(
                nodal_view,
                nodal_shape[0],
                nodal_shape[1],
                nodal_shape[2],
            )
            keepalive.append(nodal_field_np)

        keepalive.append(coords_np)
        keepalive.append(connect_np)


@cython.boundscheck(False)
@cython.wraparound(False)
def roi_cent_over_meshes(meshes: Any) -> tuple[float, float, float]:
    mesh_list = _normalize_meshes(meshes)
    meshes_len: cython.size_t = len(mesh_list)
    mesh_array = cython.cast(
        cython.pointer[cr.CMeshInput],
        malloc(meshes_len * cython.sizeof(cr.CMeshInput)),
    )
    out_cent: cr.CVec3F64
    keepalive: list[Any] = []
    image_c: cr.CImageBufferF64
    if mesh_array == cython.NULL:
        raise MemoryError()
    try:
        _fill_mesh_array(mesh_list, mesh_array, keepalive)
        if cr.rileyRoiCentOverMeshes(
            mesh_array,
            meshes_len,
            cython.address(out_cent),
        ) != 0:
            _raise_last_error()
    finally:
        free(mesh_array)
    return (out_cent.x, out_cent.y, out_cent.z)


@cython.boundscheck(False)
@cython.wraparound(False)
def pos_fill_frame_from_rot_over_meshes(
    meshes: Any,
    pixels_num: tuple[int, int],
    pixels_size: tuple[float, float],
    focal_length: float,
    rot_world: tuple[float, float, float],
    frame_fill: float = 1.0,
) -> tuple[float, float, float]:
    mesh_list = _normalize_meshes(meshes)
    meshes_len: cython.size_t = len(mesh_list)
    mesh_array = cython.cast(
        cython.pointer[cr.CMeshInput],
        malloc(meshes_len * cython.sizeof(cr.CMeshInput)),
    )
    out_pos: cr.CVec3F64
    keepalive: list[Any] = []
    if mesh_array == cython.NULL:
        raise MemoryError()
    try:
        _fill_mesh_array(mesh_list, mesh_array, keepalive)
        if cr.rileyPosFillFrameFromRotOverMeshes(
            mesh_array,
            meshes_len,
            _make_cvec2_u32(tuple(pixels_num)),
            _make_cvec2_f64(tuple(pixels_size)),
            float(focal_length),
            _make_cvec3(tuple(rot_world)),
            float(frame_fill),
            cython.address(out_pos),
        ) != 0:
            _raise_last_error()
    finally:
        free(mesh_array)
    return (out_pos.x, out_pos.y, out_pos.z)


def save_stereo_pair(
    out_dir: str,
    stereo_file_name: str,
    camera_0: Camera,
    camera_1: Camera,
) -> None:
    cam0_c = _make_camera_input(camera_0)
    cam1_c = _make_camera_input(camera_1)
    out_dir_bytes = out_dir.encode("utf-8")
    file_name_bytes = stereo_file_name.encode("utf-8")
    if cr.rileySaveStereoPair(
        out_dir_bytes,
        file_name_bytes,
        cython.address(cam0_c),
        cython.address(cam1_c),
    ) != 0:
        _raise_last_error()


def load_stereo_pair(
    dir_path: str,
    stereo_file_name: str,
) -> tuple[Camera, Camera]:
    dir_bytes = dir_path.encode("utf-8")
    file_bytes = stereo_file_name.encode("utf-8")
    cam0_c: cr.CCameraInput
    cam1_c: cr.CCameraInput
    if cr.rileyLoadStereoPair(
        dir_bytes,
        file_bytes,
        cython.address(cam0_c),
        cython.address(cam1_c),
    ) != 0:
        _raise_last_error()
    return (
        _camera_input_from_c(cam0_c),
        _camera_input_from_c(cam1_c),
    )


@cython.boundscheck(False)
@cython.wraparound(False)
def raster(
    meshes: Any,
    cameras: Any,
    config: RasterConfig,
    parallel_config: ParallelConfig | None = None,
    out_dir: str | None = None,
) -> np.ndarray | None:
    mesh_list = _normalize_meshes(meshes)
    camera_list = _normalize_cameras(cameras)
    meshes_len: cython.size_t = len(mesh_list)
    cameras_len: cython.size_t = len(camera_list)
    mesh_array = cython.cast(
        cython.pointer[cr.CMeshInput],
        malloc(meshes_len * cython.sizeof(cr.CMeshInput)),
    )
    camera_array = cython.cast(
        cython.pointer[cr.CCameraInput],
        malloc(cameras_len * cython.sizeof(cr.CCameraInput)),
    )
    config_c: cr.CRasterConfig = _make_raster_config(config)
    if parallel_config is None:
        parallel_config = _build_default_parallel_config(config)
    parallel_config_c: cr.CParallelConfig
    parallel_keepalive = _fill_parallel_config(
        cython.address(parallel_config_c),
        parallel_config,
    )
    image_np: np.ndarray | None = None
    image_ptr: cython.pointer[cr.CImageBufferF64] = cython.cast(
        cython.pointer[cr.CImageBufferF64],
        cython.NULL,
    )
    image_c: cr.CImageBufferF64
    keepalive: list[Any] = []
    keepalive.extend(parallel_keepalive)

    if mesh_array == cython.NULL or camera_array == cython.NULL:
        if mesh_array != cython.NULL:
            free(mesh_array)
        if camera_array != cython.NULL:
            free(camera_array)
        raise MemoryError()

    try:
        _fill_mesh_array(mesh_list, mesh_array, keepalive)

        nn: cython.size_t
        for nn in range(cameras_len):
            camera_array[nn] = _make_camera_input(camera_list[nn])

        out_dir_ptr: cython.p_char = cython.cast(cython.p_char, cython.NULL)
        if out_dir is not None:
            out_dir_bytes: bytes = out_dir.encode("utf-8")
            out_dir_ptr = out_dir_bytes
            keepalive.append(out_dir_bytes)

        if config.save_strategy in (SaveStrategy.memory, SaveStrategy.both):
            dims_c: cr.CDims5Usize
            if cr.rileyCalcOutputDimsScene(
                mesh_array,
                meshes_len,
                camera_array,
                cameras_len,
                cython.address(config_c),
                cython.address(dims_c),
            ) != 0:
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

        if cr.rileyRasterScene(
            mesh_array,
            meshes_len,
            camera_array,
            cameras_len,
            cython.address(config_c),
            cython.address(parallel_config_c),
            out_dir_ptr,
            image_ptr,
        ) != 0:
            _raise_last_error()
    finally:
        free(mesh_array)
        free(camera_array)

    return image_np





__all__ = [
    "Camera",
    "CameraInput",
    "CameraCoordSys",
    "Mesh",
    "MeshInput",
    "MeshType",
    "NormalType",
    "GeometrySchedulingMode",
    "ImageMode",
    "ParallelConfig",
    "RasterConfig",
    "RenderMode",
    "ReportMode",
    "SaveStrategy",
    "ScaleOver",
    "ScaleStrategy",
    "ShaderType",
    "SubPixelCenterMap",
    "FuncShaderBuiltin",
    "FuncShaderParams",
    "TextureSample",
    "TextureSampleMode",
    "load_sim_from_csv",
    "load_texture",
    "load_stereo_pair",
    "pos_fill_frame_from_rot",
    "pos_fill_frame_from_rot_over_meshes",
    "raster",
    "roi_cent_from_coords",
    "roi_cent_over_meshes",
    "save_stereo_pair",
]
