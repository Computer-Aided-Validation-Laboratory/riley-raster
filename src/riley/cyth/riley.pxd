# --------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher)
# --------------------------------------------------------------------------
from libc.stddef cimport size_t
from libc.stdint cimport uint8_t, uint16_t, uint32_t

cdef extern from "riley.h":

    ctypedef struct CVec2U32:
        uint32_t x
        uint32_t y

    ctypedef struct CVec2F64:
        double x
        double y

    ctypedef struct CVec3F64:
        double x
        double y
        double z

    ctypedef struct CArray2DF64:
        const double* elems
        size_t rows_num
        size_t cols_num

    ctypedef struct CArray2DUsize:
        const size_t* elems
        size_t rows_num
        size_t cols_num

    ctypedef struct CArray3DF64:
        const double* elems
        size_t dim0
        size_t dim1
        size_t dim2

    ctypedef struct CDims5Usize:
        size_t dim0
        size_t dim1
        size_t dim2
        size_t dim3
        size_t dim4

    ctypedef struct CImageBufferF64:
        double* elems
        CDims5Usize dims

    ctypedef struct CCameraInput:
        CVec2U32 pixels_num
        CVec2F64 pixels_size
        CVec3F64 pos_world
        CVec3F64 rot_world
        CVec3F64 roi_cent_world
        double focal_length
        uint8_t sub_sample
        uint32_t distortion_model
        double distortion_k1
        double distortion_k2
        double distortion_k3
        double distortion_k4
        double distortion_k5
        double distortion_k6
        double distortion_p1
        double distortion_p2
        uint32_t coord_sys

    ctypedef struct CMeshInputTex:
        uint32_t mesh_type
        CArray2DF64 coords
        CArray2DUsize connect
        CArray2DF64 uvs
        CArray2DF64 texture
        uint32_t sample
        uint32_t sample_mode
        int bits
        uint32_t scaling_tag
        double scaling_min
        double scaling_max

    ctypedef struct CTexFuncParams:
        double coord_scale_0
        double coord_scale_1
        double coord_offset_0
        double coord_offset_1
        double output_scale
        double output_offset
        double wave_num_scalar_0
        double wave_num_scalar_1
        double wave_num_rgb_0
        double wave_num_rgb_1
        double wave_num_rgb_2
        double extra_0
        double extra_1
        double extra_2
        double extra_3

    ctypedef struct CMeshInput:
        uint32_t mesh_type
        CArray2DF64 coords
        CArray2DUsize connect
        CArray3DF64 disp
        uint32_t shader_tag
        CArray2DF64 uvs
        CArray3DF64 texture
        uint32_t sample
        uint32_t sample_mode
        int bits
        uint32_t scaling_tag
        double scaling_min
        double scaling_max
        CArray3DF64 nodal_field
        uint32_t scale_over
        uint32_t tex_func_builtin
        CTexFuncParams tex_func_params
        uint32_t normal_type

    ctypedef struct CRasterConfig:
        uint32_t render_mode
        uint16_t total_threads
        uint16_t max_frames_in_flight
        uint16_t max_geom_workers_per_frame
        uint16_t max_raster_workers_per_frame
        uint16_t frame_batch_size_per_group
        uint16_t max_geom_jobs_in_flight_per_group
        uint16_t max_geom_workers_per_job
        uint32_t geom_scheduling_mode
        uint16_t max_raster_workers_per_job
        uint32_t save_strategy
        uint32_t image_mode
        uint32_t subpixel_center_map
        uint32_t report
        uint16_t tile_size_min
        uint16_t tile_size_max
        double background_value
        uint8_t disk_save_overlap

    ctypedef struct CParallelConfig:
        uint32_t render_mode
        uint16_t total_threads
        uint16_t render_group_count
        size_t workers_per_group_len
        const uint16_t* workers_per_group
        uint16_t max_frames_in_flight
        uint16_t max_geom_workers_per_frame
        uint16_t max_raster_workers_per_frame
        uint16_t frame_batch_size_per_group
        uint16_t max_geom_jobs_in_flight_per_group
        uint16_t max_geom_workers_per_job
        uint32_t geom_scheduling_mode
        uint16_t max_raster_workers_per_job

    size_t rileyGetLastError(uint8_t* out_buf, size_t out_buf_len)

    int rileyRoiCentFromCoords(
        const CArray2DF64* in_coords,
        CVec3F64* out_cent,
    )

    int rileyPosFillFrameFromRot(
        const CArray2DF64* in_coords,
        CVec2U32 pixels_num,
        CVec2F64 pixels_size,
        double focal_length,
        CVec3F64 rot_world,
        double frame_fill,
        CVec3F64* out_pos,
    )

    int rileyRoiCentOverMeshes(
        const CMeshInput* in_meshes,
        size_t meshes_len,
        CVec3F64* out_cent,
    )

    int rileyPosFillFrameFromRotOverMeshes(
        const CMeshInput* in_meshes,
        size_t meshes_len,
        CVec2U32 pixels_num,
        CVec2F64 pixels_size,
        double focal_length,
        CVec3F64 rot_world,
        double frame_fill,
        CVec3F64* out_pos,
    )

    int rileyCalcOutputDimsScene(
        const CMeshInput* in_meshes,
        size_t meshes_len,
        const CCameraInput* in_cameras,
        size_t cameras_len,
        const CRasterConfig* in_config,
        CDims5Usize* out_dims,
    )

    int rileyRasterScene(
        const CMeshInput* in_meshes,
        size_t meshes_len,
        const CCameraInput* in_cameras,
        size_t cameras_len,
        const CRasterConfig* in_config,
        const CParallelConfig* in_parallel_config,
        const char* out_dir_path,
        CImageBufferF64* out_image,
    )

    int rileySaveStereoPair(
        const char* out_dir_path,
        const char* stereo_file_name,
        const CCameraInput* cam0_in,
        const CCameraInput* cam1_in,
    )

    int rileyLoadStereoPair(
        const char* dir_path,
        const char* stereo_file_name,
        CCameraInput* cam0_out,
        CCameraInput* cam1_out,
    )

    int rileyCalcOutputDimsTex(
        const CMeshInputTex* in_mesh,
        const CCameraInput* in_camera,
        const CRasterConfig* in_config,
        CDims5Usize* out_dims,
    )

    int rileyRasterTex(
        const CMeshInputTex* in_mesh,
        const CCameraInput* in_camera,
        const CRasterConfig* in_config,
        const char* out_dir_path,
        CImageBufferF64* out_image,
    )
