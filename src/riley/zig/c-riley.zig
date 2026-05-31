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

pub const CRasterConfig = extern struct {
    render_mode: u32,
    total_threads: u16,
    save_strategy: u32,
    subpixel_center_map: u32,
    report: u32,
    tile_size_min: u16,
    tile_size_max: u16,
    background_value: f64,
    disk_save_overlap: u8,
};

const MeshInputTexBuilt = struct {
    mesh_input: mo.MeshInput,
    uvs_array: ndarray.NDArray(f64),
    texture_array: ndarray.NDArray(f64),

    fn deinit(self: *MeshInputTexBuilt, allocator: std.mem.Allocator) void {
        self.uvs_array.deinit(allocator);
        self.texture_array.deinit(allocator);
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

fn saveStrategyFromC(save_strategy: u32) !riley.SaveStrategy {
    return switch (save_strategy) {
        @intFromEnum(riley.SaveStrategy.disk) => .disk,
        @intFromEnum(riley.SaveStrategy.memory) => .memory,
        @intFromEnum(riley.SaveStrategy.both) => .both,
        @intFromEnum(riley.SaveStrategy.none) => .none,
        else => error.InvalidSaveStrategy,
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
) !rastcfg.SubPixelCenterMap {
    return switch (subpx_map) {
        @intFromEnum(rastcfg.SubPixelCenterMap.full_in_mem) => .full_in_mem,
        @intFromEnum(rastcfg.SubPixelCenterMap.per_tile) => .per_tile,
        @intFromEnum(rastcfg.SubPixelCenterMap.affine_jac) => .affine_jac,
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
) !MeshInputTexBuilt {
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
    const connect_slice = try cConstSlice(
        usize,
        in_mesh.connect.elems,
        in_mesh.connect.rows_num * in_mesh.connect.cols_num,
    );
    const uvs_slice = try cConstSlice(
        f64,
        in_mesh.uvs.elems,
        in_mesh.uvs.rows_num * in_mesh.uvs.cols_num,
    );
    const texture_slice = try cConstSlice(
        f64,
        in_mesh.texture.elems,
        in_mesh.texture.rows_num * in_mesh.texture.cols_num,
    );

    const coords = meshio.Coords.init(
        @constCast(coords_slice),
        in_mesh.coords.rows_num,
    );
    const connect = meshio.Connect.init(
        @constCast(connect_slice),
        in_mesh.connect.rows_num,
        in_mesh.connect.cols_num,
    );

    var uvs_dims = [_]usize{
        in_mesh.uvs.rows_num,
        in_mesh.uvs.cols_num,
    };
    var uvs_array = try ndarray.NDArray(f64).init(
        allocator,
        @constCast(uvs_slice),
        uvs_dims[0..],
    );
    errdefer uvs_array.deinit(allocator);

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

fn buildRasterConfig(
    in_config: *const CRasterConfig,
) !riley.RasterConfig {
    var config = riley.RasterConfig{};
    config.render_mode = try renderModeFromC(in_config.render_mode);
    config.total_threads = @max(@as(u16, 1), in_config.total_threads);
    config.save_strategy = try saveStrategyFromC(in_config.save_strategy);
    config.subpixel_center_map = try subPixelCenterMapFromC(
        in_config.subpixel_center_map,
    );
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

pub export fn rileyRoiCentFromCoords(
    in_coords: *const CArray2DF64,
    out_cent: *CVec3F64,
) c_int {
    clearLastError();

    const coords = buildCoordsFromC(in_coords) catch |err| {
        setLastError(err);
        return 1;
    };
    const roi_cent = cam.CameraOps.roiCentFromCoords(&coords);
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
    const cam_pos = cam.CameraOps.posFillFrameFromRot(
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

pub export fn rileyCalcOutputDimsTex(
    in_mesh: *const CMeshInputTex,
    in_camera: *const CCameraInput,
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
    const dims = riley.calcAllFramesImageDims(
        &[_]cam.CameraInput{camera_input},
        &[_]mo.MeshInput{built_mesh.mesh_input},
    );
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
