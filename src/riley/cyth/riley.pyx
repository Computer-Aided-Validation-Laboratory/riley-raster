# cython: language_level=3

from dataclasses import dataclass, field
from enum import IntEnum
from libc.stddef cimport size_t
from libc.stdlib cimport free, malloc

import numpy as np
cimport cython
cimport numpy as cnp

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
class TexFuncParams:
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
class MeshInput:
    mesh_type: int
    coords: np.ndarray
    connect: np.ndarray
    disp: np.ndarray | None = None
    shader_tag: int = 0
    uvs: np.ndarray | None = None
    texture: np.ndarray | None = None
    sample: int = 2
    sample_mode: int = 2
    bits: int = 8
    scaling_tag: int = 0
    scaling_min: float = 0.0
    scaling_max: float = 0.0
    nodal_field: np.ndarray | None = None
    scale_over: int = 1
    tex_func_builtin: int = 0
    tex_func_params: TexFuncParams = field(default_factory=TexFuncParams)
    normal_type: int = 0


MeshInputTex = MeshInput


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


class ShaderType(IntEnum):
    tex = 0
    nodal = 1
    tex_func = 2


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


class ScaleOver(IntEnum):
    within_frames = 0
    over_frames = 1


class TexFuncBuiltin(IntEnum):
    constant = 0
    linear = 1
    quadratic = 2
    sinusoidal = 3
    checker_smooth = 4
    lambertian_normal_z = 5


class NormalType(IntEnum):
    none = 0
    exact = 1
    averaged = 2


class CameraCoordSys(IntEnum):
    opengl = 0
    opencv = 1


cdef str _last_error_message():
    cdef object uint8_buf_np = np.zeros((512,), dtype=np.uint8)
    cdef cnp.uint8_t[::1] uint8_view = uint8_buf_np
    cr.rileyGetLastError(&uint8_view[0], uint8_view.shape[0])
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


cdef object _camera_input_from_c(cr.CCameraInput camera_in):
    return CameraInput(
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
        distortion_p1=camera_in.distortion_p1,
        distortion_p2=camera_in.distortion_p2,
        coord_sys=camera_in.coord_sys,
    )


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


cdef cr.CTexFuncParams _make_tex_func_params(object params_in):
    cdef cr.CTexFuncParams params_out
    params_out.coord_scale_0 = float(params_in.coord_scale[0])
    params_out.coord_scale_1 = float(params_in.coord_scale[1])
    params_out.coord_offset_0 = float(params_in.coord_offset[0])
    params_out.coord_offset_1 = float(params_in.coord_offset[1])
    params_out.output_scale = float(params_in.output_scale)
    params_out.output_offset = float(params_in.output_offset)
    params_out.wave_num_scalar_0 = float(params_in.wave_num_scalar[0])
    params_out.wave_num_scalar_1 = float(params_in.wave_num_scalar[1])
    params_out.wave_num_rgb_0 = float(params_in.wave_num_rgb[0])
    params_out.wave_num_rgb_1 = float(params_in.wave_num_rgb[1])
    params_out.wave_num_rgb_2 = float(params_in.wave_num_rgb[2])
    params_out.extra_0 = float(params_in.extra[0])
    params_out.extra_1 = float(params_in.extra[1])
    params_out.extra_2 = float(params_in.extra[2])
    params_out.extra_3 = float(params_in.extra[3])
    return params_out


cdef tuple _as_shape_2d(object array_in):
    if getattr(array_in, "ndim", None) != 2:
        raise ValueError("expected a 2D numpy array")
    return (int(array_in.shape[0]), int(array_in.shape[1]))


cdef tuple _as_shape_3d(object array_in):
    if getattr(array_in, "ndim", None) != 3:
        raise ValueError("expected a 3D numpy array")
    return (
        int(array_in.shape[0]),
        int(array_in.shape[1]),
        int(array_in.shape[2]),
    )


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


cdef cr.CArray3DF64 _make_array_3d_f64(
    cnp.float64_t[:, :, ::1] view_in,
    Py_ssize_t dim0,
    Py_ssize_t dim1,
    Py_ssize_t dim2,
):
    cdef cr.CArray3DF64 array_out
    array_out.elems = &view_in[0, 0, 0]
    array_out.dim0 = dim0
    array_out.dim1 = dim1
    array_out.dim2 = dim2
    return array_out


cdef cr.CArray2DF64 _empty_array_2d_f64():
    cdef cr.CArray2DF64 array_out
    array_out.elems = <const double*>0
    array_out.rows_num = 0
    array_out.cols_num = 0
    return array_out


cdef cr.CArray2DUsize _empty_array_2d_usize():
    cdef cr.CArray2DUsize array_out
    array_out.elems = <const size_t*>0
    array_out.rows_num = 0
    array_out.cols_num = 0
    return array_out


cdef cr.CArray3DF64 _empty_array_3d_f64():
    cdef cr.CArray3DF64 array_out
    array_out.elems = <const double*>0
    array_out.dim0 = 0
    array_out.dim1 = 0
    array_out.dim2 = 0
    return array_out


cdef list _normalize_meshes(object meshes_in):
    if isinstance(meshes_in, (list, tuple)):
        return list(meshes_in)
    return [meshes_in]


cdef list _normalize_cameras(object cameras_in):
    if isinstance(cameras_in, (list, tuple)):
        return list(cameras_in)
    return [cameras_in]


cdef object _contig_f64_2d(object array_in, str label):
    array_np = np.ascontiguousarray(array_in, dtype=np.float64)
    rows_num, cols_num = _as_shape_2d(array_np)
    return array_np


cdef object _contig_u_size_2d(object array_in):
    array_np = np.ascontiguousarray(array_in, dtype=np.uintp)
    _as_shape_2d(array_np)
    return array_np


cdef object _contig_f64_3d(object array_in, str label):
    array_np = np.ascontiguousarray(array_in, dtype=np.float64)
    _as_shape_3d(array_np)
    return array_np


@cython.boundscheck(False)
@cython.wraparound(False)
def roi_cent_from_coords(coords_in) -> np.ndarray:
    coords_np = _contig_f64_2d(coords_in, "coords")
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
    coords_np = _contig_f64_2d(coords_in, "coords")
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
def roi_cent_over_meshes(meshes) -> np.ndarray:
    mesh_list = _normalize_meshes(meshes)
    cdef size_t meshes_len = len(mesh_list)
    cdef cr.CMeshInput* mesh_array = <cr.CMeshInput*>malloc(
        meshes_len * cython.sizeof(cr.CMeshInput)
    )
    cdef cr.CVec3F64 out_cent
    cdef list keepalive = []
    if mesh_array == NULL:
        raise MemoryError()
    try:
        _fill_mesh_array(mesh_list, mesh_array, keepalive)
        if cr.rileyRoiCentOverMeshes(mesh_array, meshes_len, &out_cent) != 0:
            _raise_last_error()
    finally:
        free(mesh_array)
    return np.array([out_cent.x, out_cent.y, out_cent.z], dtype=np.float64)


@cython.boundscheck(False)
@cython.wraparound(False)
def pos_fill_frame_from_rot_over_meshes(
    meshes,
    pixels_num,
    pixels_size,
    focal_length,
    rot_world,
    frame_fill=1.0,
) -> np.ndarray:
    mesh_list = _normalize_meshes(meshes)
    cdef size_t meshes_len = len(mesh_list)
    cdef cr.CMeshInput* mesh_array = <cr.CMeshInput*>malloc(
        meshes_len * cython.sizeof(cr.CMeshInput)
    )
    cdef cr.CVec3F64 out_pos
    cdef list keepalive = []
    if mesh_array == NULL:
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
            &out_pos,
        ) != 0:
            _raise_last_error()
    finally:
        free(mesh_array)
    return np.array([out_pos.x, out_pos.y, out_pos.z], dtype=np.float64)


cdef void _fill_mesh_array(
    list mesh_list,
    cr.CMeshInput* mesh_array,
    list keepalive,
) except *:
    cdef size_t nn
    cdef object mesh
    cdef object coords_np
    cdef object connect_np
    cdef object disp_np
    cdef object uvs_np
    cdef object texture_np
    cdef object nodal_field_np
    cdef tuple shape_2d
    cdef tuple shape_3d
    cdef cnp.float64_t[:, ::1] coords_view
    cdef size_t[:, ::1] connect_view
    cdef cnp.float64_t[:, :, ::1] disp_view
    cdef cnp.float64_t[:, ::1] uvs_view
    cdef cnp.float64_t[:, ::1] texture_view
    cdef cnp.float64_t[:, :, ::1] nodal_field_view

    for nn in range(len(mesh_list)):
        mesh = mesh_list[nn]
        coords_np = _contig_f64_2d(mesh.coords, "coords")
        connect_np = _contig_u_size_2d(mesh.connect)
        shape_2d = _as_shape_2d(coords_np)
        if int(shape_2d[1]) != 3:
            raise ValueError("coords must have shape (N, 3)")
        coords_view = coords_np
        connect_view = connect_np
        shape_2d = _as_shape_2d(connect_np)

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
            shape_3d = _as_shape_3d(disp_np)
            disp_view = disp_np
            mesh_array[nn].disp = _make_array_3d_f64(
                disp_view,
                shape_3d[0],
                shape_3d[1],
                shape_3d[2],
            )
            keepalive.append(disp_np)

        mesh_array[nn].shader_tag = int(mesh.shader_tag)
        mesh_array[nn].sample = int(mesh.sample)
        mesh_array[nn].sample_mode = int(mesh.sample_mode)
        mesh_array[nn].bits = int(mesh.bits)
        mesh_array[nn].scaling_tag = int(mesh.scaling_tag)
        mesh_array[nn].scaling_min = float(mesh.scaling_min)
        mesh_array[nn].scaling_max = float(mesh.scaling_max)
        mesh_array[nn].scale_over = int(mesh.scale_over)
        mesh_array[nn].tex_func_builtin = int(mesh.tex_func_builtin)
        mesh_array[nn].tex_func_params = _make_tex_func_params(
            mesh.tex_func_params,
        )
        mesh_array[nn].normal_type = int(mesh.normal_type)

        if mesh.uvs is None:
            mesh_array[nn].uvs = _empty_array_2d_f64()
        else:
            uvs_np = _contig_f64_2d(mesh.uvs, "uvs")
            shape_2d = _as_shape_2d(uvs_np)
            uvs_view = uvs_np
            mesh_array[nn].uvs = _make_array_2d_f64(
                uvs_view,
                shape_2d[0],
                shape_2d[1],
            )
            keepalive.append(uvs_np)

        if mesh.texture is None:
            mesh_array[nn].texture = _empty_array_2d_f64()
        else:
            texture_np = _contig_f64_2d(mesh.texture, "texture")
            shape_2d = _as_shape_2d(texture_np)
            texture_view = texture_np
            mesh_array[nn].texture = _make_array_2d_f64(
                texture_view,
                shape_2d[0],
                shape_2d[1],
            )
            keepalive.append(texture_np)

        if mesh.nodal_field is None:
            mesh_array[nn].nodal_field = _empty_array_3d_f64()
        else:
            nodal_field_np = _contig_f64_3d(mesh.nodal_field, "nodal_field")
            shape_3d = _as_shape_3d(nodal_field_np)
            nodal_field_view = nodal_field_np
            mesh_array[nn].nodal_field = _make_array_3d_f64(
                nodal_field_view,
                shape_3d[0],
                shape_3d[1],
                shape_3d[2],
            )
            keepalive.append(nodal_field_np)

        keepalive.append(coords_np)
        keepalive.append(connect_np)


def save_stereo_pair(
    out_dir: str,
    stereo_file_name: str,
    camera_0,
    camera_1,
) -> None:
    cdef cr.CCameraInput cam0_c = _make_camera_input(camera_0)
    cdef cr.CCameraInput cam1_c = _make_camera_input(camera_1)
    cdef bytes out_dir_bytes = out_dir.encode("utf-8")
    cdef bytes file_name_bytes = stereo_file_name.encode("utf-8")
    if cr.rileySaveStereoPair(
        out_dir_bytes,
        file_name_bytes,
        &cam0_c,
        &cam1_c,
    ) != 0:
        _raise_last_error()


def load_stereo_pair(
    dir_path: str,
    stereo_file_name: str,
) -> tuple[CameraInput, CameraInput]:
    cdef bytes dir_bytes = dir_path.encode("utf-8")
    cdef bytes file_bytes = stereo_file_name.encode("utf-8")
    cdef cr.CCameraInput cam0_c
    cdef cr.CCameraInput cam1_c
    if cr.rileyLoadStereoPair(
        dir_bytes,
        file_bytes,
        &cam0_c,
        &cam1_c,
    ) != 0:
        _raise_last_error()
    return (
        _camera_input_from_c(cam0_c),
        _camera_input_from_c(cam1_c),
    )


@cython.boundscheck(False)
@cython.wraparound(False)
def raster(
    meshes,
    cameras,
    config,
    out_dir: str | None = None,
) -> np.ndarray | None:
    mesh_list = _normalize_meshes(meshes)
    camera_list = _normalize_cameras(cameras)
    cdef size_t meshes_len = len(mesh_list)
    cdef size_t cameras_len = len(camera_list)
    cdef cr.CMeshInput* mesh_array = <cr.CMeshInput*>malloc(
        meshes_len * cython.sizeof(cr.CMeshInput)
    )
    cdef cr.CCameraInput* camera_array = <cr.CCameraInput*>malloc(
        cameras_len * cython.sizeof(cr.CCameraInput)
    )
    cdef cr.CRasterConfig config_c = _make_raster_config(config)
    cdef bytes out_dir_bytes
    cdef const char* out_dir_ptr = <const char*>0
    cdef cr.CDims5Usize dims_c
    cdef object image_np = None
    cdef cnp.float64_t[:, :, :, :, ::1] image_view
    cdef cr.CImageBufferF64 image_c
    cdef cr.CImageBufferF64* image_ptr = <cr.CImageBufferF64*>0
    cdef list keepalive = []
    cdef size_t nn

    if mesh_array == NULL or camera_array == NULL:
        if mesh_array != NULL:
            free(mesh_array)
        if camera_array != NULL:
            free(camera_array)
        raise MemoryError()

    try:
        _fill_mesh_array(mesh_list, mesh_array, keepalive)
        for nn in range(cameras_len):
            camera_array[nn] = _make_camera_input(camera_list[nn])

        if out_dir is not None:
            out_dir_bytes = out_dir.encode("utf-8")
            out_dir_ptr = out_dir_bytes

        if config.save_strategy in (SaveStrategy.memory, SaveStrategy.both):
            if cr.rileyCalcOutputDimsScene(
                mesh_array,
                meshes_len,
                camera_array,
                cameras_len,
                &dims_c,
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
            image_view = image_np
            image_c.elems = &image_view[0, 0, 0, 0, 0]
            image_c.dims = dims_c
            image_ptr = &image_c

        if cr.rileyRasterScene(
            mesh_array,
            meshes_len,
            camera_array,
            cameras_len,
            &config_c,
            out_dir_ptr,
            image_ptr,
        ) != 0:
            _raise_last_error()
    finally:
        free(mesh_array)
        free(camera_array)

    return image_np


__all__ = [
    "CameraCoordSys",
    "CameraInput",
    "MeshInput",
    "MeshInputTex",
    "MeshType",
    "NormalType",
    "RasterConfig",
    "RenderMode",
    "ReportMode",
    "SaveStrategy",
    "ScaleOver",
    "ScaleStrategy",
    "ShaderType",
    "SubPixelCenterMap",
    "TexFuncBuiltin",
    "TexFuncParams",
    "TextureSample",
    "TextureSampleMode",
    "load_stereo_pair",
    "pos_fill_frame_from_rot",
    "pos_fill_frame_from_rot_over_meshes",
    "raster",
    "roi_cent_from_coords",
    "roi_cent_over_meshes",
    "save_stereo_pair",
]
