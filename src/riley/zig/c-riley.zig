// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const cam = @import("camera.zig");
const cameraio = @import("cameraio.zig");
const cameraops = @import("cameraops.zig");
const gk = @import("geometrykernels.zig");
const iio = @import("imageio.zig");
const imageops = @import("imageops.zig");
const meshio = @import("meshio.zig");
const mo = @import("meshops.zig");
const ndarray = @import("ndarray.zig");
const riley = @import("riley.zig");
const rotation = @import("rotation.zig");
const rastcfg = @import("rasterconfig.zig");
const shaderops = @import("shaderops.zig");
const texops = @import("textureops.zig");
const vector = @import("vecstack.zig");

const error_buf_len: usize = 512;
const default_image_save_opts = [_]iio.ImageSaveOpts{
    .{
        .format = .bmp,
        .bits = 8,
        .scaling = .auto,
    },
};

var last_error_buf: [error_buf_len]u8 = [_]u8{0} ** error_buf_len;

pub const CVec2U32 = extern struct {
    x: u32,
    y: u32,
};

pub const CVec2F64 = extern struct {
    x: f64,
    y: f64,
};

pub const CVec3F64 = extern struct {
    x: f64,
    y: f64,
    z: f64,
};

pub const CArray2DF64 = extern struct {
    elems: [*c]const f64,
    rows_num: usize,
    cols_num: usize,
};

pub const CArray2DUsize = extern struct {
    elems: [*c]const usize,
    rows_num: usize,
    cols_num: usize,
};

pub const CArray3DF64 = extern struct {
    elems: [*c]const f64,
    dim0: usize,
    dim1: usize,
    dim2: usize,
};

pub const CDims5Usize = extern struct {
    dim0: usize,
    dim1: usize,
    dim2: usize,
    dim3: usize,
    dim4: usize,
};

pub const CImageBufferF64 = extern struct {
    elems: [*c]f64,
    dims: CDims5Usize,
};

pub const CCameraInput = extern struct {
    pixels_num: CVec2U32,
    pixels_size: CVec2F64,
    pos_world: CVec3F64,
    rot_world: CVec3F64,
    roi_cent_world: CVec3F64,
    focal_length: f64,
    sub_sample: u8,
    distortion_model: u32,
    distortion_k1: f64,
    distortion_k2: f64,
    distortion_k3: f64,
    distortion_k4: f64,
    distortion_k5: f64,
    distortion_k6: f64,
    distortion_p1: f64,
    distortion_p2: f64,
    coord_sys: u32,
};

pub const CMeshInputTex = extern struct {
    mesh_type: u32,
    coords: CArray2DF64,
    connect: CArray2DUsize,
    uvs: CArray2DF64,
    texture: CArray2DF64,
    sample: u32,
    sample_mode: u32,
    bits: c_int,
    scaling_tag: u32,
    scaling_min: f64,
    scaling_max: f64,
};

pub const CFuncShaderParams = extern struct {
    coord_scale_0: f64,
    coord_scale_1: f64,
    coord_offset_0: f64,
    coord_offset_1: f64,
    output_scale: f64,
    output_offset: f64,
    wave_num_scalar_0: f64,
    wave_num_scalar_1: f64,
    wave_num_rgb_0: f64,
    wave_num_rgb_1: f64,
    wave_num_rgb_2: f64,
    extra_0: f64,
    extra_1: f64,
    extra_2: f64,
    extra_3: f64,
};


pub const CMeshInput = extern struct {
    mesh_type: u32,
    coords: CArray2DF64,
    connect: CArray2DUsize,
    disp: CArray3DF64,
    shader_tag: u32,
    uvs: CArray2DF64,
    texture: CArray3DF64,
    sample: u32,
    sample_mode: u32,
    bits: c_int,
    scaling_tag: u32,
    scaling_min: f64,
    scaling_max: f64,
    nodal_field: CArray3DF64,
    scale_over: u32,
    func_shader_builtin: u32,
    func_shader_params: CFuncShaderParams,
    normal_type: u32,
};

pub const CRasterConfig = extern struct {
    render_mode: u32,
    total_threads: u16,
    frame_batch_size_per_group: u16,
    max_geom_jobs_in_flight_per_group: u16,
    max_geom_workers_per_job: u16,
    geom_scheduling_mode: u32,
    max_raster_workers_per_job: u16,
    save_strategy: u32,
    image_mode: u32,
    subpixel_center_map: u32,
    report: u32,
    tile_size_min: u16,
    tile_size_max: u16,
    background_value: f64,
    disk_save_overlap: u8,
};

pub const CParallelConfig = extern struct {
    render_mode: u32,
    total_threads: u16,
    render_group_count: u16,
    workers_per_group_len: usize,
    workers_per_group: [*c]const u16,
    frame_batch_size_per_group: u16,
    max_geom_jobs_in_flight_per_group: u16,
    max_geom_workers_per_job: u16,
    geom_scheduling_mode: u32,
    max_raster_workers_per_job: u16,
};

const MeshInputBuilt = struct {
    mesh_input: mo.MeshInput,
    disp_array: ?ndarray.NDArray(f64) = null,
    uvs_array: ?ndarray.NDArray(f64) = null,
    texture_array: ?ndarray.NDArray(f64) = null,
    nodal_field_array: ?ndarray.NDArray(f64) = null,

    fn deinit(self: *MeshInputBuilt, allocator: std.mem.Allocator) void {
        if (self.disp_array) |*disp_array| {
            disp_array.deinit(allocator);
        }
        if (self.uvs_array) |*uvs_array| {
            uvs_array.deinit(allocator);
        }
        if (self.texture_array) |*texture_array| {
            texture_array.deinit(allocator);
        }
        if (self.nodal_field_array) |*nodal_field_array| {
            nodal_field_array.deinit(allocator);
        }
    }
};

fn clearLastError() void {
    @memset(last_error_buf[0..], 0);
}

fn setLastErrorSlice(msg: []const u8) void {
    clearLastError();
    const copy_len = @min(msg.len, error_buf_len - 1);
    @memcpy(last_error_buf[0..copy_len], msg[0..copy_len]);
}

fn setLastError(err: anyerror) void {
    var msg_buf: [error_buf_len]u8 = undefined;
    const msg = std.fmt.bufPrint(
        msg_buf[0..],
        "{s}",
        .{@errorName(err)},
    ) catch @errorName(err);
    setLastErrorSlice(msg);
}

pub export fn rileyGetLastError(
    out_buf: [*c]u8,
    out_buf_len: usize,
) usize {
    if (out_buf == null or out_buf_len == 0) {
        return 0;
    }

    const msg_len = std.mem.indexOfScalar(
        u8,
        last_error_buf[0..],
        0,
    ) orelse last_error_buf.len;
    const copy_len = @min(msg_len, out_buf_len - 1);
    @memcpy(out_buf[0..copy_len], last_error_buf[0..copy_len]);
    out_buf[copy_len] = 0;
    return copy_len;
}

fn cVec3ToVec3(in_vec: CVec3F64) vector.Vec3f {
    return vector.initVec3(
        f64,
        in_vec.x,
        in_vec.y,
        in_vec.z,
    );
}

fn vec3ToCVec3(in_vec: vector.Vec3f) CVec3F64 {
    return .{
        .x = in_vec.get(0),
        .y = in_vec.get(1),
        .z = in_vec.get(2),
    };
}

fn dimsToArray(in_dims: CDims5Usize) [5]usize {
    return .{
        in_dims.dim0,
        in_dims.dim1,
        in_dims.dim2,
        in_dims.dim3,
        in_dims.dim4,
    };
}

fn dimsFromArray(in_dims: [5]usize) CDims5Usize {
    return .{
        .dim0 = in_dims[0],
        .dim1 = in_dims[1],
        .dim2 = in_dims[2],
        .dim3 = in_dims[3],
        .dim4 = in_dims[4],
    };
}

fn array3ToDims(in_array: CArray3DF64) [3]usize {
    return .{
        in_array.dim0,
        in_array.dim1,
        in_array.dim2,
    };
}

fn cConstSlice(
    comptime T: type,
    ptr: [*c]const T,
    len: usize,
) ![]const T {
    if (ptr == null and len > 0) {
        return error.NullPointer;
    }
    return ptr[0..len];
}

fn cMutSlice(
    comptime T: type,
    ptr: [*c]T,
    len: usize,
) ![]T {
    if (ptr == null and len > 0) {
        return error.NullPointer;
    }
    return ptr[0..len];
}

fn meshTypeFromC(mesh_type: u32) !gk.MeshType {
    return switch (mesh_type) {
        @intFromEnum(gk.MeshType.tri3) => .tri3,
        @intFromEnum(gk.MeshType.tri6) => .tri6,
        @intFromEnum(gk.MeshType.quad4ibi) => .quad4ibi,
        @intFromEnum(gk.MeshType.quad4newton) => .quad4newton,
        @intFromEnum(gk.MeshType.quad8) => .quad8,
        @intFromEnum(gk.MeshType.quad9) => .quad9,
        else => error.InvalidMeshType,
    };
}

fn renderModeFromC(render_mode: u32) !riley.RenderMode {
    return switch (render_mode) {
        @intFromEnum(riley.RenderMode.in_order) => .in_order,
        @intFromEnum(riley.RenderMode.offline) => .offline,
        else => error.InvalidRenderMode,
    };
}

fn geometrySchedulingModeFromC(
    geom_scheduling_mode: u32,
) !rastcfg.GeometrySchedulingMode {
    return switch (geom_scheduling_mode) {
        @intFromEnum(rastcfg.GeometrySchedulingMode.spread) => .spread,
        @intFromEnum(rastcfg.GeometrySchedulingMode.pack) => .pack,
        @intFromEnum(rastcfg.GeometrySchedulingMode.auto) => .auto,
        else => error.InvalidGeometrySchedulingMode,
    };
}

fn saveStrategyFromC(save_strategy: u32) !riley.SaveStrategy {
    return switch (save_strategy) {
        @intFromEnum(riley.SaveStrategy.disk) => .disk,
        @intFromEnum(riley.SaveStrategy.memory) => .memory,
        @intFromEnum(riley.SaveStrategy.both) => .both,
        @intFromEnum(riley.SaveStrategy.none) => .none,
        else => error.InvalidSaveStrategy,
    };
}

fn imageModeFromC(image_mode: u32) !riley.ImageMode {
    return switch (image_mode) {
        @intFromEnum(riley.ImageMode.grey) => .grey,
        @intFromEnum(riley.ImageMode.rgb) => .rgb,
        @intFromEnum(riley.ImageMode.multifield) => .multifield,
        else => error.InvalidImageMode,
    };
}

fn reportModeFromC(report_mode: u32) !riley.ReportMode {
    return switch (report_mode) {
        @intFromEnum(riley.ReportMode.off) => .off,
        @intFromEnum(riley.ReportMode.bench) => .bench,
        @intFromEnum(riley.ReportMode.full_stats) => .full_stats,
        else => error.InvalidReportMode,
    };
}

fn subPixelCenterMapFromC(
    subpx_map: u32,
) !cam.SubPixelCenterMap {
    return switch (subpx_map) {
        @intFromEnum(cam.SubPixelCenterMap.full_in_mem) => .full_in_mem,
        @intFromEnum(cam.SubPixelCenterMap.per_tile) => .per_tile,
        @intFromEnum(cam.SubPixelCenterMap.affine_jac) => .affine_jac,
        else => error.InvalidSubPixelCenterMap,
    };
}

fn coordSysFromC(coord_sys: u32) !cam.CameraCoordSys {
    return switch (coord_sys) {
        @intFromEnum(cam.CameraCoordSys.opengl) => .opengl,
        @intFromEnum(cam.CameraCoordSys.opencv) => .opencv,
        else => error.InvalidCoordSys,
    };
}

fn distortionFromC(in_camera: *const CCameraInput) !cam.DistortionModel {
    return switch (in_camera.distortion_model) {
        0 => .none,
        1 => .{ .brown_conrady = .{
            .k1 = in_camera.distortion_k1,
            .k2 = in_camera.distortion_k2,
            .k3 = in_camera.distortion_k3,
            .p1 = in_camera.distortion_p1,
            .p2 = in_camera.distortion_p2,
        } },
        2 => .{ .brown_conrady_ext = .{
            .k1 = in_camera.distortion_k1,
            .k2 = in_camera.distortion_k2,
            .k3 = in_camera.distortion_k3,
            .k4 = in_camera.distortion_k4,
            .k5 = in_camera.distortion_k5,
            .k6 = in_camera.distortion_k6,
            .p1 = in_camera.distortion_p1,
            .p2 = in_camera.distortion_p2,
        } },
        else => error.InvalidDistortionModel,
    };
}

fn textureSampleFromC(sample: u32) !texops.TextureSample {
    return switch (sample) {
        @intFromEnum(texops.TextureSample.nearest) => .nearest,
        @intFromEnum(texops.TextureSample.linear) => .linear,
        @intFromEnum(texops.TextureSample.cubic_catmull_rom) => .cubic_catmull_rom,
        @intFromEnum(texops.TextureSample.cubic_mitchell_netravali) => .cubic_mitchell_netravali,
        @intFromEnum(texops.TextureSample.lanczos3) => .lanczos3,
        @intFromEnum(texops.TextureSample.cubic_bspline) => .cubic_bspline,
        @intFromEnum(texops.TextureSample.quintic_bspline) => .quintic_bspline,
        else => error.InvalidTextureSample,
    };
}

fn textureSampleModeFromC(
    sample_mode: u32,
) !texops.TextureSampleMode {
    return switch (sample_mode) {
        @intFromEnum(texops.TextureSampleMode.direct) => .direct,
        @intFromEnum(texops.TextureSampleMode.lut) => .lut,
        @intFromEnum(texops.TextureSampleMode.lut_lerp) => .lut_lerp,
        else => error.InvalidTextureSampleMode,
    };
}

fn scaleOverFromC(scale_over: u32) !shaderops.ScaleOver {
    return switch (scale_over) {
        @intFromEnum(shaderops.ScaleOver.within_frames) => .within_frames,
        @intFromEnum(shaderops.ScaleOver.over_frames) => .over_frames,
        else => error.InvalidScaleOver,
    };
}

fn funcShaderBuiltinFromC(
    func_shader_builtin: u32,
) !shaderops.FuncShaderBuiltin {
    return switch (func_shader_builtin) {
        @intFromEnum(shaderops.FuncShaderBuiltin.constant) => .constant,
        @intFromEnum(shaderops.FuncShaderBuiltin.linear) => .linear,
        @intFromEnum(shaderops.FuncShaderBuiltin.quadratic) => .quadratic,
        @intFromEnum(shaderops.FuncShaderBuiltin.sinusoidal) => .sinusoidal,
        @intFromEnum(shaderops.FuncShaderBuiltin.checker) => .checker,
        @intFromEnum(shaderops.FuncShaderBuiltin.checker_smooth) => .checker_smooth,
        @intFromEnum(shaderops.FuncShaderBuiltin.lambertian_normal_z) => .lambertian_normal_z,
        else => error.InvalidFuncShaderBuiltin,
    };
}


fn normalTypeFromC(normal_type: u32) !shaderops.NormalType {
    return switch (normal_type) {
        @intFromEnum(shaderops.NormalType.none) => .none,
        @intFromEnum(shaderops.NormalType.exact) => .exact,
        @intFromEnum(shaderops.NormalType.averaged) => .averaged,
        else => error.InvalidNormalType,
    };
}

fn funcShaderParamsFromC(
    in_params: CFuncShaderParams,
) shaderops.FuncShaderParams {
    return .{
        .coord_scale = .{
            in_params.coord_scale_0,
            in_params.coord_scale_1,
        },
        .coord_offset = .{
            in_params.coord_offset_0,
            in_params.coord_offset_1,
        },
        .output_scale = in_params.output_scale,
        .output_offset = in_params.output_offset,
        .wave_num_scalar = .{
            in_params.wave_num_scalar_0,
            in_params.wave_num_scalar_1,
        },
        .wave_num_rgb = .{
            in_params.wave_num_rgb_0,
            in_params.wave_num_rgb_1,
            in_params.wave_num_rgb_2,
        },
        .extra = .{
            in_params.extra_0,
            in_params.extra_1,
            in_params.extra_2,
            in_params.extra_3,
        },
    };
}


fn bitsFromC(bits: c_int) !?u8 {
    if (bits < 0) {
        return null;
    }
    if (bits > std.math.maxInt(u8)) {
        return error.InvalidBits;
    }
    return @intCast(bits);
}

fn scaleStrategyFromC(
    scaling_tag: u32,
    scaling_min: f64,
    scaling_max: f64,
) !imageops.ScaleStrategy {
    return switch (scaling_tag) {
        0 => .none,
        1 => .auto,
        2 => .{ .fixed = .{ scaling_min, scaling_max } },
        3 => .{ .frac = .{ scaling_min, scaling_max } },
        else => error.InvalidScaleStrategy,
    };
}

fn buildCoordsFromC(in_coords: *const CArray2DF64) !meshio.Coords {
    if (in_coords.cols_num != 3) {
        return error.InvalidCoordsShape;
    }
    const coords_slice = try cConstSlice(
        f64,
        in_coords.elems,
        in_coords.rows_num * in_coords.cols_num,
    );
    return meshio.Coords.init(
        @constCast(coords_slice),
        in_coords.rows_num,
    );
}

fn buildConnectFromC(
    in_connect: *const CArray2DUsize,
) !meshio.Connect {
    const connect_slice = try cConstSlice(
        usize,
        in_connect.elems,
        in_connect.rows_num * in_connect.cols_num,
    );
    return meshio.Connect.init(
        @constCast(connect_slice),
        in_connect.rows_num,
        in_connect.cols_num,
    );
}

fn buildArray2DF64(
    allocator: std.mem.Allocator,
    in_array: *const CArray2DF64,
    cols_num_expected: ?usize,
) !ndarray.NDArray(f64) {
    if (cols_num_expected) |expected_cols_num| {
        if (in_array.cols_num != expected_cols_num) {
            return error.InvalidArray2DShape;
        }
    }
    const slice_in = try cConstSlice(
        f64,
        in_array.elems,
        in_array.rows_num * in_array.cols_num,
    );
    var dims = [_]usize{
        in_array.rows_num,
        in_array.cols_num,
    };
    return try ndarray.NDArray(f64).init(
        allocator,
        @constCast(slice_in),
        dims[0..],
    );
}

fn buildArray3DF64(
    allocator: std.mem.Allocator,
    in_array: *const CArray3DF64,
) !ndarray.NDArray(f64) {
    const dims = array3ToDims(in_array.*);
    const elems_num = dims[0] * dims[1] * dims[2];
    const slice_in = try cConstSlice(
        f64,
        in_array.elems,
        elems_num,
    );
    var dims_mut = dims;
    return try ndarray.NDArray(f64).init(
        allocator,
        @constCast(slice_in),
        dims_mut[0..],
    );
}

fn buildTextureArray(
    allocator: std.mem.Allocator,
    in_array: *const CArray3DF64,
    channels_num: usize,
) !ndarray.NDArray(f64) {
    const dims = array3ToDims(in_array.*);
    if (dims[0] != channels_num or dims[1] == 0 or dims[2] == 0) {
        return error.InvalidTextureShape;
    }
    return try buildArray3DF64(allocator, in_array);
}

fn buildOptionalFieldFromC(
    allocator: std.mem.Allocator,
    in_array: *const CArray3DF64,
) !struct {
    field: ?meshio.Field,
    array: ?ndarray.NDArray(f64),
} {
    const dims = array3ToDims(in_array.*);
    if (dims[0] == 0 or dims[1] == 0 or dims[2] == 0) {
        return .{
            .field = null,
            .array = null,
        };
    }
    const array = try buildArray3DF64(allocator, in_array);
    return .{
        .field = .{
            .array = array,
            .array_mem = array.slice,
        },
        .array = array,
    };
}

fn buildCameraInput(
    in_camera: *const CCameraInput,
) !cam.CameraInput {
    return .{
        .pixels_num = .{
            in_camera.pixels_num.x,
            in_camera.pixels_num.y,
        },
        .pixels_size = .{
            in_camera.pixels_size.x,
            in_camera.pixels_size.y,
        },
        .pos_world = cVec3ToVec3(in_camera.pos_world),
        .rot_world = rotation.Rotation.init(
            in_camera.rot_world.x,
            in_camera.rot_world.y,
            in_camera.rot_world.z,
        ),
        .roi_cent_world = cVec3ToVec3(in_camera.roi_cent_world),
        .focal_length = in_camera.focal_length,
        .sub_sample = in_camera.sub_sample,
        .distortion = try distortionFromC(in_camera),
        .coord_sys = try coordSysFromC(in_camera.coord_sys),
    };
}

fn buildMeshInputTex(
    allocator: std.mem.Allocator,
    in_mesh: *const CMeshInputTex,
) !MeshInputBuilt {
    const mesh_type = try meshTypeFromC(in_mesh.mesh_type);
    const nodes_per_elem = mesh_type.getNodesNum();

    if (in_mesh.connect.cols_num != nodes_per_elem) {
        return error.InvalidConnectShape;
    }
    if (in_mesh.uvs.cols_num != 2) {
        return error.InvalidUVShape;
    }

    const coords_slice = try cConstSlice(
        f64,
        in_mesh.coords.elems,
        in_mesh.coords.rows_num * in_mesh.coords.cols_num,
    );
    const coords = meshio.Coords.init(
        @constCast(coords_slice),
        in_mesh.coords.rows_num,
    );
    const connect = try buildConnectFromC(&in_mesh.connect);

    var uvs_array = try buildArray2DF64(
        allocator,
        &in_mesh.uvs,
        2,
    );
    errdefer uvs_array.deinit(allocator);

    const texture_slice = try cConstSlice(
        f64,
        in_mesh.texture.elems,
        in_mesh.texture.rows_num * in_mesh.texture.cols_num,
    );
    var texture_dims = [_]usize{
        1,
        in_mesh.texture.rows_num,
        in_mesh.texture.cols_num,
    };
    var texture_array = try ndarray.NDArray(f64).init(
        allocator,
        @constCast(texture_slice),
        texture_dims[0..],
    );
    errdefer texture_array.deinit(allocator);

    const texture = texops.Texture(1){
        .array = texture_array,
        .rows_num = in_mesh.texture.rows_num,
        .cols_num = in_mesh.texture.cols_num,
    };
    const sample_config = texops.TextureSampleConfig{
        .sample = try textureSampleFromC(in_mesh.sample),
        .mode = try textureSampleModeFromC(in_mesh.sample_mode),
    };
    if (!sample_config.isValid()) {
        return error.InvalidTextureSampleConfig;
    }

    return .{
        .mesh_input = .{
            .mesh_type = mesh_type,
            .coords = coords,
            .connect = connect,
            .disp = null,
            .shader = .{ .tex = .{
                .uvs = uvs_array,
                .texture = texture,
                .sample_config = sample_config,
                .bits = try bitsFromC(in_mesh.bits),
                .scaling = try scaleStrategyFromC(
                    in_mesh.scaling_tag,
                    in_mesh.scaling_min,
                    in_mesh.scaling_max,
                ),
                .normal_type = .none,
            } },
        },
        .uvs_array = uvs_array,
        .texture_array = texture_array,
    };
}

fn buildMeshInput(
    allocator: std.mem.Allocator,
    in_mesh: *const CMeshInput,
) !MeshInputBuilt {
    const mesh_type = try meshTypeFromC(in_mesh.mesh_type);
    const nodes_per_elem = mesh_type.getNodesNum();

    if (in_mesh.coords.cols_num != 3) {
        return error.InvalidCoordsShape;
    }
    if (in_mesh.connect.cols_num != nodes_per_elem) {
        return error.InvalidConnectShape;
    }

    const coords = try buildCoordsFromC(&in_mesh.coords);
    const connect = try buildConnectFromC(&in_mesh.connect);

    var built = MeshInputBuilt{
        .mesh_input = .{
            .mesh_type = mesh_type,
            .coords = coords,
            .connect = connect,
            .disp = null,
            .shader = undefined,
        },
    };

    const disp_built = try buildOptionalFieldFromC(
        allocator,
        &in_mesh.disp,
    );
    built.mesh_input.disp = disp_built.field;
    built.disp_array = disp_built.array;

    const bits = try bitsFromC(in_mesh.bits);
    const scaling = try scaleStrategyFromC(
        in_mesh.scaling_tag,
        in_mesh.scaling_min,
        in_mesh.scaling_max,
    );
    const normal_type = try normalTypeFromC(in_mesh.normal_type);

    switch (in_mesh.shader_tag) {
        0 => {
            if (in_mesh.uvs.cols_num != 2) {
                return error.InvalidUVShape;
            }

            var uvs_array = try buildArray2DF64(
                allocator,
                &in_mesh.uvs,
                2,
            );
            errdefer uvs_array.deinit(allocator);

            var texture_array = try buildTextureArray(
                allocator,
                &in_mesh.texture,
                1,
            );
            errdefer texture_array.deinit(allocator);

            const sample_config = texops.TextureSampleConfig{
                .sample = try textureSampleFromC(in_mesh.sample),
                .mode = try textureSampleModeFromC(in_mesh.sample_mode),
            };
            if (!sample_config.isValid()) {
                return error.InvalidTextureSampleConfig;
            }

            built.mesh_input.shader = .{ .tex = .{
                .uvs = uvs_array,
                .texture = texops.Texture(1){
                    .array = texture_array,
                    .rows_num = in_mesh.texture.dim1,
                    .cols_num = in_mesh.texture.dim2,
                },
                .sample_config = sample_config,
                .bits = bits,
                .scaling = scaling,
                .normal_type = normal_type,
            } };
            built.uvs_array = uvs_array;
            built.texture_array = texture_array;
        },
        1 => {
            if (in_mesh.uvs.cols_num != 2) {
                return error.InvalidUVShape;
            }

            var uvs_array = try buildArray2DF64(
                allocator,
                &in_mesh.uvs,
                2,
            );
            errdefer uvs_array.deinit(allocator);

            var texture_array = try buildTextureArray(
                allocator,
                &in_mesh.texture,
                3,
            );
            errdefer texture_array.deinit(allocator);

            const sample_config = texops.TextureSampleConfig{
                .sample = try textureSampleFromC(in_mesh.sample),
                .mode = try textureSampleModeFromC(in_mesh.sample_mode),
            };
            if (!sample_config.isValid()) {
                return error.InvalidTextureSampleConfig;
            }

            built.mesh_input.shader = .{ .tex_rgb = .{
                .uvs = uvs_array,
                .texture = texops.Texture(3){
                    .array = texture_array,
                    .rows_num = in_mesh.texture.dim1,
                    .cols_num = in_mesh.texture.dim2,
                },
                .sample_config = sample_config,
                .bits = bits,
                .scaling = scaling,
                .normal_type = normal_type,
            } };
            built.uvs_array = uvs_array;
            built.texture_array = texture_array;
        },
        2 => {
            const nodal_built = try buildOptionalFieldFromC(
                allocator,
                &in_mesh.nodal_field,
            );
            if (nodal_built.field == null or nodal_built.array == null) {
                return error.MissingNodalField;
            }
            built.mesh_input.shader = .{ .nodal = .{
                .field = nodal_built.field.?,
                .bits = bits,
                .scaling = scaling,
                .scale_over = try scaleOverFromC(in_mesh.scale_over),
                .normal_type = normal_type,
            } };
            built.nodal_field_array = nodal_built.array;
        },
        5 => {
            const nodal_built = try buildOptionalFieldFromC(
                allocator,
                &in_mesh.nodal_field,
            );
            if (nodal_built.field == null or nodal_built.array == null) {
                return error.MissingNodalField;
            }
            if (nodal_built.field.?.getFieldsN() != 3) {
                return error.InvalidNodalRgbFieldCount;
            }
            built.mesh_input.shader = .{ .nodal = .{
                .field = nodal_built.field.?,
                .bits = bits,
                .scaling = scaling,
                .scale_over = try scaleOverFromC(in_mesh.scale_over),
                .normal_type = normal_type,
            } };
            built.nodal_field_array = nodal_built.array;
        },
        3 => {
            var uvs_array_opt: ?ndarray.NDArray(f64) = null;
            if (in_mesh.uvs.rows_num > 0 and in_mesh.uvs.cols_num > 0) {
                uvs_array_opt = try buildArray2DF64(
                    allocator,
                    &in_mesh.uvs,
                    2,
                );
            }
            errdefer if (uvs_array_opt) |*uvs_array| {
                uvs_array.deinit(allocator);
            };

            built.mesh_input.shader = .{ .func = .{
                .uvs = uvs_array_opt,
                .builtin = try funcShaderBuiltinFromC(in_mesh.func_shader_builtin),
                .params = funcShaderParamsFromC(in_mesh.func_shader_params),
                .bits = bits,
                .scaling = scaling,
                .normal_type = normal_type,
            } };
            built.uvs_array = uvs_array_opt;
        },
        4 => {
            var uvs_array_opt: ?ndarray.NDArray(f64) = null;
            if (in_mesh.uvs.rows_num > 0 and in_mesh.uvs.cols_num > 0) {
                uvs_array_opt = try buildArray2DF64(
                    allocator,
                    &in_mesh.uvs,
                    2,
                );
            }
            errdefer if (uvs_array_opt) |*uvs_array| {
                uvs_array.deinit(allocator);
            };

            built.mesh_input.shader = .{ .func_rgb = .{
                .uvs = uvs_array_opt,
                .builtin = try funcShaderBuiltinFromC(in_mesh.func_shader_builtin),
                .params = funcShaderParamsFromC(in_mesh.func_shader_params),
                .bits = bits,
                .scaling = scaling,
                .normal_type = normal_type,
            } };
            built.uvs_array = uvs_array_opt;
        },
        else => return error.InvalidShaderTag,
    }

    return built;
}

fn buildCameraInputSlice(
    allocator: std.mem.Allocator,
    in_cameras: [*c]const CCameraInput,
    cameras_len: usize,
) ![]cam.CameraInput {
    const cameras_slice = try cConstSlice(
        CCameraInput,
        in_cameras,
        cameras_len,
    );
    const cameras_out = try allocator.alloc(cam.CameraInput, cameras_len);
    for (cameras_slice, 0..) |camera_in, nn| {
        cameras_out[nn] = try buildCameraInput(&camera_in);
    }
    return cameras_out;
}

fn buildMeshInputSlice(
    allocator: std.mem.Allocator,
    in_meshes: [*c]const CMeshInput,
    meshes_len: usize,
) ![]MeshInputBuilt {
    const meshes_in = try cConstSlice(
        CMeshInput,
        in_meshes,
        meshes_len,
    );
    const meshes_out = try allocator.alloc(MeshInputBuilt, meshes_len);
    errdefer allocator.free(meshes_out);

    for (meshes_in, 0..) |mesh_in, nn| {
        meshes_out[nn] = buildMeshInput(allocator, &mesh_in) catch |err| {
            for (0..nn) |mm| {
                meshes_out[mm].deinit(allocator);
            }
            return err;
        };
    }
    return meshes_out;
}

fn extractMeshInputs(
    allocator: std.mem.Allocator,
    built_meshes: []const MeshInputBuilt,
) ![]mo.MeshInput {
    const mesh_inputs = try allocator.alloc(mo.MeshInput, built_meshes.len);
    for (built_meshes, 0..) |built_mesh, nn| {
        mesh_inputs[nn] = built_mesh.mesh_input;
    }
    return mesh_inputs;
}

fn deinitMeshInputSlice(
    allocator: std.mem.Allocator,
    built_meshes: []MeshInputBuilt,
) void {
    for (built_meshes) |*built_mesh| {
        built_mesh.deinit(allocator);
    }
    allocator.free(built_meshes);
}

fn buildRasterConfig(
    in_config: *const CRasterConfig,
) !riley.RasterConfig {
    var config = riley.RasterConfig{};
    config.render_mode = try renderModeFromC(in_config.render_mode);
    config.total_threads = @max(@as(u16, 1), in_config.total_threads);
    config.frame_batch_size_per_group =
        @max(@as(u16, 1), in_config.frame_batch_size_per_group);
    config.max_geom_jobs_in_flight_per_group =
        @max(@as(u16, 1), in_config.max_geom_jobs_in_flight_per_group);
    config.max_geom_workers_per_job =
        @max(@as(u16, 1), in_config.max_geom_workers_per_job);
    config.geom_scheduling_mode = try geometrySchedulingModeFromC(
        in_config.geom_scheduling_mode,
    );
    config.max_raster_workers_per_job =
        @max(@as(u16, 1), in_config.max_raster_workers_per_job);
    config.save_strategy = try saveStrategyFromC(in_config.save_strategy);
    config.image_mode = try imageModeFromC(in_config.image_mode);
    config.report = try reportModeFromC(in_config.report);
    config.tile_size_min = if (in_config.tile_size_min == 0)
        config.tile_size_min
    else
        in_config.tile_size_min;
    config.tile_size_max = if (in_config.tile_size_max == 0)
        config.tile_size_max
    else
        in_config.tile_size_max;
    config.background_value = in_config.background_value;
    config.disk_save_overlap = in_config.disk_save_overlap != 0;
    config.image_save_opts = &default_image_save_opts;
    return config;
}

fn applyParallelConfig(
    config: *riley.RasterConfig,
    in_parallel_config: *const CParallelConfig,
) !void {
    config.render_mode = try renderModeFromC(in_parallel_config.render_mode);
    config.total_threads = @max(@as(u16, 1), in_parallel_config.total_threads);
    config.frame_batch_size_per_group =
        @max(@as(u16, 1), in_parallel_config.frame_batch_size_per_group);
    config.max_geom_jobs_in_flight_per_group =
        @max(@as(u16, 1), in_parallel_config.max_geom_jobs_in_flight_per_group);
    config.max_geom_workers_per_job =
        @max(@as(u16, 1), in_parallel_config.max_geom_workers_per_job);
    config.geom_scheduling_mode = try geometrySchedulingModeFromC(
        in_parallel_config.geom_scheduling_mode,
    );
    config.max_raster_workers_per_job =
        @max(@as(u16, 1), in_parallel_config.max_raster_workers_per_job);
}

const RenderGroupRuntime = struct {
    managed_ios: []std.Io.Threaded,
    render_groups: []riley.RenderGroupSpec,

    fn deinit(
        self: *RenderGroupRuntime,
        allocator: std.mem.Allocator,
    ) void {
        for (self.managed_ios) |*managed_io| {
            managed_io.deinit();
        }
        allocator.free(self.managed_ios);
        allocator.free(self.render_groups);
    }
};

fn initRenderGroups(
    allocator: std.mem.Allocator,
    in_parallel_config: *const CParallelConfig,
) !RenderGroupRuntime {
    const render_group_count = @max(@as(u16, 1), in_parallel_config.render_group_count);
    const workers_per_group = try cConstSlice(
        u16,
        in_parallel_config.workers_per_group,
        in_parallel_config.workers_per_group_len,
    );
    if (workers_per_group.len != 0 and workers_per_group.len != render_group_count) {
        return error.InvalidWorkersPerGroupLen;
    }

    const managed_ios = try allocator.alloc(std.Io.Threaded, render_group_count);
    errdefer allocator.free(managed_ios);
    const render_groups = try allocator.alloc(riley.RenderGroupSpec, render_group_count);
    errdefer allocator.free(render_groups);

    var total_threads: u32 = 0;
    for (0..render_group_count) |gg| {
        const workers = if (workers_per_group.len == 0)
            1
        else
            @max(@as(u16, 1), workers_per_group[gg]);
        total_threads += workers;
        managed_ios[gg] = initThreadedIo(
            allocator,
            workers,
        );
        render_groups[gg] = .{
            .io = managed_ios[gg].io(),
            .workers = workers,
        };
    }

    if (in_parallel_config.total_threads != 0 and
        total_threads != in_parallel_config.total_threads)
    {
        return error.InvalidTotalThreads;
    }

    return .{
        .managed_ios = managed_ios,
        .render_groups = render_groups,
    };
}

fn buildImageBuffer(
    allocator: std.mem.Allocator,
    in_buffer: *const CImageBufferF64,
) !ndarray.NDArray(f64) {
    const dims = dimsToArray(in_buffer.dims);
    var elems_num: usize = 1;
    for (dims) |dim| {
        elems_num *= dim;
    }
    const image_slice = try cMutSlice(
        f64,
        in_buffer.elems,
        elems_num,
    );
    return try ndarray.NDArray(f64).init(
        allocator,
        image_slice,
        dims[0..],
    );
}

fn initThreadedIo(
    gpa: std.mem.Allocator,
    total_threads: u16,
) std.Io.Threaded {
    const threads = @max(@as(u16, 1), total_threads);
    const limit: std.Io.Limit = if (threads <= 1)
        .nothing
    else
        .limited(threads - 1);

    return std.Io.Threaded.init(gpa, .{
        .argv0 = .empty,
        .environ = .empty,
        .async_limit = limit,
        .concurrent_limit = limit,
    });
}

fn cameraInputToC(in_camera: cam.CameraInput) CCameraInput {
    var out_camera = CCameraInput{
        .pixels_num = .{
            .x = in_camera.pixels_num[0],
            .y = in_camera.pixels_num[1],
        },
        .pixels_size = .{
            .x = in_camera.pixels_size[0],
            .y = in_camera.pixels_size[1],
        },
        .pos_world = vec3ToCVec3(in_camera.pos_world),
        .rot_world = .{
            .x = in_camera.rot_world.alpha_z,
            .y = in_camera.rot_world.beta_y,
            .z = in_camera.rot_world.gamma_x,
        },
        .roi_cent_world = vec3ToCVec3(in_camera.roi_cent_world),
        .focal_length = in_camera.focal_length,
        .sub_sample = in_camera.sub_sample,
        .distortion_model = 0,
        .distortion_k1 = 0.0,
        .distortion_k2 = 0.0,
        .distortion_k3 = 0.0,
        .distortion_k4 = 0.0,
        .distortion_k5 = 0.0,
        .distortion_k6 = 0.0,
        .distortion_p1 = 0.0,
        .distortion_p2 = 0.0,
        .coord_sys = @intFromEnum(in_camera.coord_sys),
    };

    switch (in_camera.distortion) {
        .none => {},
        .brown_conrady => |model| {
            out_camera.distortion_model = 1;
            out_camera.distortion_k1 = model.k1;
            out_camera.distortion_k2 = model.k2;
            out_camera.distortion_k3 = model.k3;
            out_camera.distortion_p1 = model.p1;
            out_camera.distortion_p2 = model.p2;
        },
        .brown_conrady_ext => |model| {
            out_camera.distortion_model = 2;
            out_camera.distortion_k1 = model.k1;
            out_camera.distortion_k2 = model.k2;
            out_camera.distortion_k3 = model.k3;
            out_camera.distortion_k4 = model.k4;
            out_camera.distortion_k5 = model.k5;
            out_camera.distortion_k6 = model.k6;
            out_camera.distortion_p1 = model.p1;
            out_camera.distortion_p2 = model.p2;
        },
    }
    return out_camera;
}

fn rasterSceneInternal(
    allocator: std.mem.Allocator,
    in_meshes: [*c]const CMeshInput,
    meshes_len: usize,
    in_cameras: [*c]const CCameraInput,
    cameras_len: usize,
    in_config: *const CRasterConfig,
    in_parallel_config: ?*const CParallelConfig,
    out_dir_path: ?[*:0]const u8,
    out_image: ?*CImageBufferF64,
) !void {
    const built_meshes = try buildMeshInputSlice(
        allocator,
        in_meshes,
        meshes_len,
    );
    defer deinitMeshInputSlice(allocator, built_meshes);

    const mesh_inputs = try extractMeshInputs(allocator, built_meshes);
    defer allocator.free(mesh_inputs);

    const camera_inputs = try buildCameraInputSlice(
        allocator,
        in_cameras,
        cameras_len,
    );
    defer allocator.free(camera_inputs);

    var raster_config = try buildRasterConfig(in_config);
    if (in_parallel_config) |parallel_config| {
        try applyParallelConfig(&raster_config, parallel_config);
    }

    var image_arr_opt: ?ndarray.NDArray(f64) = null;
    if (out_image) |image_buffer| {
        image_arr_opt = try buildImageBuffer(allocator, image_buffer);
    }
    defer if (image_arr_opt) |*image_arr| {
        image_arr.deinit(allocator);
    };

    var render_group_runtime = if (in_parallel_config) |parallel_config|
        try initRenderGroups(std.heap.smp_allocator, parallel_config)
    else blk: {
        const threaded_io = initThreadedIo(
            std.heap.smp_allocator,
            raster_config.total_threads,
        );
        const managed_ios = try std.heap.smp_allocator.alloc(std.Io.Threaded, 1);
        errdefer std.heap.smp_allocator.free(managed_ios);
        managed_ios[0] = threaded_io;
        const render_groups = try std.heap.smp_allocator.alloc(riley.RenderGroupSpec, 1);
        errdefer std.heap.smp_allocator.free(render_groups);
        render_groups[0] = .{
            .io = managed_ios[0].io(),
            .workers = @max(@as(u16, 1), raster_config.total_threads),
        };
        break :blk RenderGroupRuntime{
            .managed_ios = managed_ios,
            .render_groups = render_groups,
        };
    };
    defer render_group_runtime.deinit(std.heap.smp_allocator);

    const out_dir_path_slice = if (out_dir_path) |path|
        std.mem.span(path)
    else
        null;

    try riley.rasterAllFramesInto(
        std.heap.smp_allocator,
        render_group_runtime.render_groups,
        camera_inputs,
        mesh_inputs,
        raster_config,
        out_dir_path_slice,
        if (image_arr_opt) |*image_arr| image_arr else null,
    );
}

pub export fn rileyRoiCentFromCoords(
    in_coords: *const CArray2DF64,
    out_cent: *CVec3F64,
) c_int {
    clearLastError();

    const coords = buildCoordsFromC(in_coords) catch |err| {
        setLastError(err);
        return 1;
    };
    const roi_cent = cameraops.roiCentFromCoords(&coords);
    out_cent.* = vec3ToCVec3(roi_cent);
    return 0;
}

pub export fn rileyPosFillFrameFromRot(
    in_coords: *const CArray2DF64,
    pixels_num: CVec2U32,
    pixels_size: CVec2F64,
    focal_length: f64,
    rot_world: CVec3F64,
    frame_fill: f64,
    out_pos: *CVec3F64,
) c_int {
    clearLastError();

    const coords = buildCoordsFromC(in_coords) catch |err| {
        setLastError(err);
        return 1;
    };
    const rot = rotation.Rotation.init(
        rot_world.x,
        rot_world.y,
        rot_world.z,
    );
    const cam_pos = cameraops.posFillFrameFromRot(
        &coords,
        .{ pixels_num.x, pixels_num.y },
        .{ pixels_size.x, pixels_size.y },
        focal_length,
        rot,
        frame_fill,
    );
    out_pos.* = vec3ToCVec3(cam_pos);
    return 0;
}

pub export fn rileyRoiCentOverMeshes(
    in_meshes: [*c]const CMeshInput,
    meshes_len: usize,
    out_cent: *CVec3F64,
) c_int {
    clearLastError();

    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const built_meshes = buildMeshInputSlice(
        aa,
        in_meshes,
        meshes_len,
    ) catch |err| {
        setLastError(err);
        return 1;
    };
    defer deinitMeshInputSlice(aa, built_meshes);

    const mesh_inputs = extractMeshInputs(aa, built_meshes) catch |err| {
        setLastError(err);
        return 1;
    };

    const roi_cent = cameraops.roiCentOverMeshes(mesh_inputs);
    out_cent.* = vec3ToCVec3(roi_cent);
    return 0;
}

pub export fn rileyPosFillFrameFromRotOverMeshes(
    in_meshes: [*c]const CMeshInput,
    meshes_len: usize,
    pixels_num: CVec2U32,
    pixels_size: CVec2F64,
    focal_length: f64,
    rot_world: CVec3F64,
    frame_fill: f64,
    out_pos: *CVec3F64,
) c_int {
    clearLastError();

    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const built_meshes = buildMeshInputSlice(
        aa,
        in_meshes,
        meshes_len,
    ) catch |err| {
        setLastError(err);
        return 1;
    };
    defer deinitMeshInputSlice(aa, built_meshes);

    const mesh_inputs = extractMeshInputs(aa, built_meshes) catch |err| {
        setLastError(err);
        return 1;
    };

    const rot = rotation.Rotation.init(
        rot_world.x,
        rot_world.y,
        rot_world.z,
    );
    const cam_pos = cameraops.posFillFrameFromRotOverMeshes(
        mesh_inputs,
        .{ pixels_num.x, pixels_num.y },
        .{ pixels_size.x, pixels_size.y },
        focal_length,
        rot,
        frame_fill,
    );
    out_pos.* = vec3ToCVec3(cam_pos);
    return 0;
}

pub export fn rileyCalcOutputDimsScene(
    in_meshes: [*c]const CMeshInput,
    meshes_len: usize,
    in_cameras: [*c]const CCameraInput,
    cameras_len: usize,
    in_config: *const CRasterConfig,
    out_dims: *CDims5Usize,
) c_int {
    clearLastError();

    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const built_meshes = buildMeshInputSlice(
        aa,
        in_meshes,
        meshes_len,
    ) catch |err| {
        setLastError(err);
        return 1;
    };
    defer deinitMeshInputSlice(aa, built_meshes);

    const mesh_inputs = extractMeshInputs(aa, built_meshes) catch |err| {
        setLastError(err);
        return 1;
    };
    const camera_inputs = buildCameraInputSlice(
        aa,
        in_cameras,
        cameras_len,
    ) catch |err| {
        setLastError(err);
        return 1;
    };

    const dims = riley.calcAllFramesImageDimsForConfig(
        camera_inputs,
        mesh_inputs,
        buildRasterConfig(in_config) catch |err| {
            setLastError(err);
            return 1;
        },
    ) catch |err| {
        setLastError(err);
        return 1;
    };
    out_dims.* = dimsFromArray(dims);
    return 0;
}

pub export fn rileyRasterScene(
    in_meshes: [*c]const CMeshInput,
    meshes_len: usize,
    in_cameras: [*c]const CCameraInput,
    cameras_len: usize,
    in_config: *const CRasterConfig,
    in_parallel_config: ?*const CParallelConfig,
    out_dir_path: ?[*:0]const u8,
    out_image: ?*CImageBufferF64,
) c_int {
    clearLastError();

    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();

    rasterSceneInternal(
        arena.allocator(),
        in_meshes,
        meshes_len,
        in_cameras,
        cameras_len,
        in_config,
        in_parallel_config,
        out_dir_path,
        out_image,
    ) catch |err| {
        setLastError(err);
        return 1;
    };

    return 0;
}

pub export fn rileySaveStereoPair(
    out_dir_path: [*:0]const u8,
    stereo_file_name: [*:0]const u8,
    cam0_in: *const CCameraInput,
    cam1_in: *const CCameraInput,
) c_int {
    clearLastError();

    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const cam0 = buildCameraInput(cam0_in) catch |err| {
        setLastError(err);
        return 1;
    };
    const cam1 = buildCameraInput(cam1_in) catch |err| {
        setLastError(err);
        return 1;
    };

    var threaded_io = initThreadedIo(std.heap.smp_allocator, 1);
    defer threaded_io.deinit();
    const io = threaded_io.io();
    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, std.mem.span(out_dir_path), .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            setLastError(err);
            return 1;
        }
    };

    var out_dir = cwd.openDir(
        io,
        std.mem.span(out_dir_path),
        .{},
    ) catch |err| {
        setLastError(err);
        return 1;
    };
    defer out_dir.close(io);

    cameraio.saveStereoPair(
        io,
        out_dir,
        std.mem.span(stereo_file_name),
        .{ .cameras = .{ cam0, cam1 } },
    ) catch |err| {
        _ = aa;
        setLastError(err);
        return 1;
    };
    return 0;
}

pub export fn rileyLoadStereoPair(
    dir_path: [*:0]const u8,
    stereo_file_name: [*:0]const u8,
    cam0_out: *CCameraInput,
    cam1_out: *CCameraInput,
) c_int {
    clearLastError();

    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    var threaded_io = initThreadedIo(std.heap.smp_allocator, 1);
    defer threaded_io.deinit();
    const io = threaded_io.io();
    const cwd = std.Io.Dir.cwd();

    var dir = cwd.openDir(
        io,
        std.mem.span(dir_path),
        .{},
    ) catch |err| {
        setLastError(err);
        return 1;
    };
    defer dir.close(io);

    const stereo_pair = cameraio.loadStereoPair(
        aa,
        io,
        dir,
        std.mem.span(stereo_file_name),
    ) catch |err| {
        setLastError(err);
        return 1;
    };
    cam0_out.* = cameraInputToC(stereo_pair.cameras[0]);
    cam1_out.* = cameraInputToC(stereo_pair.cameras[1]);
    return 0;
}

pub export fn rileyCalcOutputDimsTex(
    in_mesh: *const CMeshInputTex,
    in_camera: *const CCameraInput,
    in_config: *const CRasterConfig,
    out_dims: *CDims5Usize,
) c_int {
    clearLastError();

    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    var built_mesh = buildMeshInputTex(aa, in_mesh) catch |err| {
        setLastError(err);
        return 1;
    };
    defer built_mesh.deinit(aa);

    const camera_input = buildCameraInput(in_camera) catch |err| {
        setLastError(err);
        return 1;
    };
    const dims = riley.calcAllFramesImageDimsForConfig(
        &[_]cam.CameraInput{camera_input},
        &[_]mo.MeshInput{built_mesh.mesh_input},
        buildRasterConfig(in_config) catch |err| {
            setLastError(err);
            return 1;
        },
    ) catch |err| {
        setLastError(err);
        return 1;
    };
    out_dims.* = dimsFromArray(dims);
    return 0;
}

pub export fn rileyRasterTex(
    in_mesh: *const CMeshInputTex,
    in_camera: *const CCameraInput,
    in_config: *const CRasterConfig,
    out_dir_path: ?[*:0]const u8,
    out_image: ?*CImageBufferF64,
) c_int {
    clearLastError();

    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    var built_mesh = buildMeshInputTex(aa, in_mesh) catch |err| {
        setLastError(err);
        return 1;
    };
    defer built_mesh.deinit(aa);

    const camera_input = buildCameraInput(in_camera) catch |err| {
        setLastError(err);
        return 1;
    };
    const raster_config = buildRasterConfig(in_config) catch |err| {
        setLastError(err);
        return 1;
    };

    var image_arr_opt: ?ndarray.NDArray(f64) = null;
    if (out_image) |image_buffer| {
        image_arr_opt = buildImageBuffer(aa, image_buffer) catch |err| {
            setLastError(err);
            return 1;
        };
    }
    defer if (image_arr_opt) |*image_arr| {
        image_arr.deinit(aa);
    };

    var threaded_io = initThreadedIo(
        std.heap.smp_allocator,
        raster_config.total_threads,
    );
    defer threaded_io.deinit();
    const io = threaded_io.io();

    const render_groups = [_]riley.RenderGroupSpec{
        .{
            .io = io,
            .workers = @max(@as(u16, 1), raster_config.total_threads),
        },
    };
    const out_dir_path_slice = if (out_dir_path) |path|
        std.mem.span(path)
    else
        null;

    riley.rasterAllFramesInto(
        std.heap.smp_allocator,
        &render_groups,
        &[_]cam.CameraInput{camera_input},
        &[_]mo.MeshInput{built_mesh.mesh_input},
        raster_config,
        out_dir_path_slice,
        if (image_arr_opt) |*image_arr| image_arr else null,
    ) catch |err| {
        setLastError(err);
        return 1;
    };

    return 0;
}
