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

    ctypedef struct CRasterConfig:
        uint32_t render_mode
        uint16_t total_threads
        uint32_t save_strategy
        uint32_t subpixel_center_map
        uint32_t report
        uint16_t tile_size_min
        uint16_t tile_size_max
        double background_value
        uint8_t disk_save_overlap

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

    int rileyCalcOutputDimsTex(
        const CMeshInputTex* in_mesh,
        const CCameraInput* in_camera,
        CDims5Usize* out_dims,
    )

    int rileyRasterTex(
        const CMeshInputTex* in_mesh,
        const CCameraInput* in_camera,
        const CRasterConfig* in_config,
        const char* out_dir_path,
        CImageBufferF64* out_image,
    )
