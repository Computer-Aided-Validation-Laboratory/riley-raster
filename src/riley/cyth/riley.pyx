# cython: language_level=3

from dataclasses import dataclass
from enum import IntEnum

import numpy as np
cimport cython
cimport numpy as cnp
from libc.stddef cimport size_t

from cython.cimports.riley.cyth import riley as cr


@dataclass(slots=True)
class CameraInput:
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
    distortion_p1: float = 0.0
    distortion_p2: float = 0.0
    coord_sys: int = 0


@dataclass(slots=True)
class MeshInputTex:
    mesh_type: int
    coords: np.ndarray
    connect: np.ndarray
    uvs: np.ndarray
    texture: np.ndarray
    sample: int
    sample_mode: int
    bits: int = 8
    scaling_tag: int = 0
    scaling_min: float = 0.0
    scaling_max: float = 0.0


@dataclass(slots=True)
class RasterConfig:
    render_mode: int = 0
    total_threads: int = 1
    save_strategy: int = 1
    subpixel_center_map: int = 1
    report: int = 1
    tile_size_min: int = 8
    tile_size_max: int = 256
    background_value: float = 0.0
    disk_save_overlap: bool = False


class MeshType(IntEnum):
    tri3 = 0
    tri6 = 1
    quad4ibi = 2
    quad4newton = 3
    quad8 = 4
    quad9 = 5


class RenderMode(IntEnum):
    in_order = 0
    offline = 1


class SaveStrategy(IntEnum):
    disk = 0
    memory = 1
    both = 2
    none = 3


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


class CameraCoordSys(IntEnum):
    opengl = 0
    opencv = 1


cdef str _last_error_message():
    cdef object uint8_buf_np = np.zeros((512,), dtype=np.uint8)
    cdef cnp.uint8_t[::1] uint8_t_view = uint8_buf_np
    cr.rileyGetLastError(&uint8_t_view[0], uint8_t_view.shape[0])
    return bytes(uint8_buf_np).split(b"\0", 1)[0].decode("utf-8")


cdef void _raise_last_error() except *:
    msg = _last_error_message()
    if msg:
        raise RuntimeError(msg)
    raise RuntimeError("riley wrapper call failed")


cdef cr.CVec3F64 _make_cvec3(tuple vec_in):
    cdef cr.CVec3F64 vec_out
    vec_out.x = float(vec_in[0])
    vec_out.y = float(vec_in[1])
    vec_out.z = float(vec_in[2])
    return vec_out


cdef cr.CVec2F64 _make_cvec2_f64(tuple vec_in):
    cdef cr.CVec2F64 vec_out
    vec_out.x = float(vec_in[0])
    vec_out.y = float(vec_in[1])
    return vec_out


cdef cr.CVec2U32 _make_cvec2_u32(tuple vec_in):
    cdef cr.CVec2U32 vec_out
    vec_out.x = int(vec_in[0])
    vec_out.y = int(vec_in[1])
    return vec_out


cdef cr.CCameraInput _make_camera_input(object camera):
    cdef cr.CCameraInput camera_out
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
    camera_out.distortion_p1 = float(camera.distortion_p1)
    camera_out.distortion_p2 = float(camera.distortion_p2)
    camera_out.coord_sys = int(camera.coord_sys)
    return camera_out


cdef cr.CRasterConfig _make_raster_config(object config):
    cdef cr.CRasterConfig config_out
    config_out.render_mode = int(config.render_mode)
    config_out.total_threads = int(config.total_threads)
    config_out.save_strategy = int(config.save_strategy)
    config_out.subpixel_center_map = int(config.subpixel_center_map)
    config_out.report = int(config.report)
    config_out.tile_size_min = int(config.tile_size_min)
    config_out.tile_size_max = int(config.tile_size_max)
    config_out.background_value = float(config.background_value)
    config_out.disk_save_overlap = 1 if config.disk_save_overlap else 0
    return config_out


cdef cr.CArray2DF64 _make_array_2d_f64(
    cnp.float64_t[:, ::1] view_in,
    Py_ssize_t rows_num,
    Py_ssize_t cols_num,
):
    cdef cr.CArray2DF64 array_out
    array_out.elems = &view_in[0, 0]
    array_out.rows_num = rows_num
    array_out.cols_num = cols_num
    return array_out


cdef cr.CArray2DUsize _make_array_2d_usize(
    size_t[:, ::1] view_in,
    Py_ssize_t rows_num,
    Py_ssize_t cols_num,
):
    cdef cr.CArray2DUsize array_out
    array_out.elems = &view_in[0, 0]
    array_out.rows_num = rows_num
    array_out.cols_num = cols_num
    return array_out


cdef tuple _as_shape_2d(object array_in):
    if getattr(array_in, "ndim", None) != 2:
        raise ValueError("expected a 2D numpy array")
    return (int(array_in.shape[0]), int(array_in.shape[1]))


@cython.boundscheck(False)
@cython.wraparound(False)
def roi_cent_from_coords(coords_in) -> np.ndarray:
    coords_np = np.ascontiguousarray(coords_in, dtype=np.float64)
    rows_num, cols_num = _as_shape_2d(coords_np)
    if cols_num != 3:
        raise ValueError("coords must have shape (N, 3)")

    cdef cnp.float64_t[:, ::1] coords_view = coords_np
    cdef cr.CArray2DF64 coords_c = _make_array_2d_f64(
        coords_view,
        rows_num,
        cols_num,
    )
    cdef cr.CVec3F64 out_cent

    if cr.rileyRoiCentFromCoords(&coords_c, &out_cent) != 0:
        _raise_last_error()

    return np.array([out_cent.x, out_cent.y, out_cent.z], dtype=np.float64)


@cython.boundscheck(False)
@cython.wraparound(False)
def pos_fill_frame_from_rot(
    coords_in,
    pixels_num,
    pixels_size,
    focal_length,
    rot_world,
    frame_fill=1.0,
) -> np.ndarray:
    coords_np = np.ascontiguousarray(coords_in, dtype=np.float64)
    rows_num, cols_num = _as_shape_2d(coords_np)
    if cols_num != 3:
        raise ValueError("coords must have shape (N, 3)")

    cdef cnp.float64_t[:, ::1] coords_view = coords_np
    cdef cr.CArray2DF64 coords_c = _make_array_2d_f64(
        coords_view,
        rows_num,
        cols_num,
    )
    cdef cr.CVec3F64 out_pos

    if cr.rileyPosFillFrameFromRot(
        &coords_c,
        _make_cvec2_u32(tuple(pixels_num)),
        _make_cvec2_f64(tuple(pixels_size)),
        float(focal_length),
        _make_cvec3(tuple(rot_world)),
        float(frame_fill),
        &out_pos,
    ) != 0:
        _raise_last_error()

    return np.array([out_pos.x, out_pos.y, out_pos.z], dtype=np.float64)


@cython.boundscheck(False)
@cython.wraparound(False)
def raster(
    mesh,
    camera,
    config,
    out_dir: str | None = None,
) -> np.ndarray | None:
    coords_np = np.ascontiguousarray(mesh.coords, dtype=np.float64)
    connect_np = np.ascontiguousarray(mesh.connect, dtype=np.uintp)
    uvs_np = np.ascontiguousarray(mesh.uvs, dtype=np.float64)
    texture_np = np.ascontiguousarray(mesh.texture, dtype=np.float64)

    coords_rows_num, coords_cols_num = _as_shape_2d(coords_np)
    connect_rows_num, connect_cols_num = _as_shape_2d(connect_np)
    uvs_rows_num, uvs_cols_num = _as_shape_2d(uvs_np)
    texture_rows_num, texture_cols_num = _as_shape_2d(texture_np)

    if coords_cols_num != 3:
        raise ValueError("coords must have shape (N, 3)")
    if uvs_cols_num != 2:
        raise ValueError("uvs must have shape (N, 2)")

    cdef cnp.float64_t[:, ::1] coords_view = coords_np
    cdef size_t[:, ::1] connect_view = connect_np
    cdef cnp.float64_t[:, ::1] uvs_view = uvs_np
    cdef cnp.float64_t[:, ::1] texture_view = texture_np

    cdef cr.CMeshInputTex mesh_c
    cdef cr.CCameraInput camera_c = _make_camera_input(camera)
    cdef cr.CRasterConfig config_c = _make_raster_config(config)
    cdef bytes out_dir_bytes
    cdef const char* out_dir_ptr = <const char*>0
    cdef cr.CDims5Usize dims_c
    cdef object image_np = None
    cdef cnp.float64_t[:, :, :, :, ::1] image_view
    cdef cr.CImageBufferF64 image_c
    cdef cr.CImageBufferF64* image_ptr = <cr.CImageBufferF64*>0

    mesh_c.mesh_type = int(mesh.mesh_type)
    mesh_c.coords = _make_array_2d_f64(
        coords_view,
        coords_rows_num,
        coords_cols_num,
    )
    mesh_c.connect = _make_array_2d_usize(
        connect_view,
        connect_rows_num,
        connect_cols_num,
    )
    mesh_c.uvs = _make_array_2d_f64(
        uvs_view,
        uvs_rows_num,
        uvs_cols_num,
    )
    mesh_c.texture = _make_array_2d_f64(
        texture_view,
        texture_rows_num,
        texture_cols_num,
    )
    mesh_c.sample = int(mesh.sample)
    mesh_c.sample_mode = int(mesh.sample_mode)
    mesh_c.bits = int(mesh.bits)
    mesh_c.scaling_tag = int(mesh.scaling_tag)
    mesh_c.scaling_min = float(mesh.scaling_min)
    mesh_c.scaling_max = float(mesh.scaling_max)

    if out_dir is not None:
        out_dir_bytes = out_dir.encode("utf-8")
        out_dir_ptr = out_dir_bytes

    if config.save_strategy in (SaveStrategy.memory, SaveStrategy.both):
        if cr.rileyCalcOutputDimsTex(&mesh_c, &camera_c, &dims_c) != 0:
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
        image_view = image_np
        image_c.elems = &image_view[0, 0, 0, 0, 0]
        image_c.dims = dims_c
        image_ptr = &image_c

    if cr.rileyRasterTex(
        &mesh_c,
        &camera_c,
        &config_c,
        out_dir_ptr,
        image_ptr,
    ) != 0:
        _raise_last_error()

    return image_np


__all__ = [
    "CameraCoordSys",
    "CameraInput",
    "MeshInputTex",
    "MeshType",
    "RasterConfig",
    "RenderMode",
    "ReportMode",
    "SaveStrategy",
    "ScaleStrategy",
    "SubPixelCenterMap",
    "TextureSample",
    "TextureSampleMode",
    "pos_fill_frame_from_rot",
    "raster",
    "roi_cent_from_coords",
]
