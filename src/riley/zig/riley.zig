// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const Timestamp = std.Io.Clock.Timestamp;
const matslice = @import("matslice.zig");
const ndarray = @import("ndarray.zig");
const buildconfig = @import("buildconfig.zig");

const sliceops = @import("sliceops.zig");

const cam = @import("camera.zig");
const cameraops = @import("cameraops.zig");
const rops = @import("rasterops.zig");
const mo = @import("meshops.zig");
const shaderops = @import("shaderops.zig");

const iio = @import("imageio.zig");
const imageops = @import("imageops.zig");
const pce = @import("parachunkexec.zig");
const saveoverlap = @import("saveoverlap.zig");
const scalingpolicy = @import("scalingpolicy.zig");

const geomkerns = @import("geometrykernels.zig");
const shadekerns = @import("shaderkernels.zig");
const rasterengine = @import("rasterengine.zig");

const rastcfg = @import("rasterconfig.zig");
pub const RasterConfig = rastcfg.RasterConfig;
pub const ImageMode = rastcfg.ImageMode;
pub const SaveStrategy = rastcfg.SaveStrategy;
pub const RenderMode = rastcfg.RenderMode;
pub const ReportMode = rastcfg.ReportMode;
pub const FullStatsOpts = rastcfg.FullStatsOpts;

const report = @import("report.zig");
const FrameReportStorage = report.FrameReportStorage;
const F = buildconfig.F;

// --------------------------------------------------------------------------
// 1. Threaded IO and Tiny Shared Helpers
// --------------------------------------------------------------------------
pub fn getThreadedIo(
    gpa: std.mem.Allocator,
    minimal: std.process.Init.Minimal,
    num_threads: u16,
) std.Io.Threaded {
    // User-facing thread counts in riley always include the caller thread.
    // Zig's std.Io.Threaded limits count only spawned worker threads, excluding
    // the caller. Translate here so:
    //   threads=1  -> caller only
    //   threads=N  -> caller + (N - 1) worker threads
    const limit: std.Io.Limit =
        if (num_threads <= 1) .nothing else .limited(num_threads - 1);

    return std.Io.Threaded.init(gpa, .{
        .argv0 = .init(minimal.args),
        .environ = minimal.environ,
        .async_limit = limit,
        .concurrent_limit = limit,
    });
}

fn FrameReportPtr(comptime report_mode: ReportMode) type {
    return *report.LogType(report_mode);
}

fn getFrameReportPtr(
    comptime report_mode: ReportMode,
    ctx: *FrameContext,
) FrameReportPtr(report_mode) {
    return switch (report_mode) {
        .off => &ctx.report_storage.off,
        .bench => &ctx.report_storage.bench,
        .full_stats => &ctx.report_storage.full_stats,
    };
}

// --------------------------------------------------------------------------
// 2. Output and Image Buffer Helpers
// --------------------------------------------------------------------------
fn initNodalGlobalScaling(
    outer_alloc: std.mem.Allocator,
    meshes: []const mo.MeshInput,
) ![]?imageops.ScalingParams {
    var nodal_global_scaling = try outer_alloc.alloc(?imageops.ScalingParams, meshes.len);

    for (meshes, 0..) |mesh, ii| {
        nodal_global_scaling[ii] = null;
        switch (mesh.shader) {
            .nodal => |s| {
                if (s.scale_over == .over_frames) {
                    nodal_global_scaling[ii] = imageops.getScalingParamsNDArray(
                        &s.field.array,
                        null,
                        s.scaling,
                    );
                }
            },
            else => {},
        }
    }

    return nodal_global_scaling;
}

fn initMeshStaticSlice(
    allocator: std.mem.Allocator,
    meshes: []const mo.MeshInput,
) ![]mo.MeshStatic {
    const mesh_static = try allocator.alloc(mo.MeshStatic, meshes.len);

    for (meshes, 0..) |mesh, ii| {
        mesh_static[ii] = try mo.initMeshStatic(allocator, &mesh);
    }

    return mesh_static;
}

fn calcAllFramesDimsFromPixels(
    camera_pixels_num: []const [2]u32,
    num_time: usize,
    num_fields: u8,
) [5]usize {
    std.debug.assert(camera_pixels_num.len > 0);

    var max_pixels_num = camera_pixels_num[0];
    for (camera_pixels_num[1..]) |pixels_num| {
        max_pixels_num[0] = @max(max_pixels_num[0], pixels_num[0]);
        max_pixels_num[1] = @max(max_pixels_num[1], pixels_num[1]);
    }

    return .{
        camera_pixels_num.len,
        num_time,
        @as(usize, num_fields),
        max_pixels_num[1],
        max_pixels_num[0],
    };
}

fn outputFieldsForImageMode(
    image_mode: ImageMode,
    raw_num_fields: u8,
) !u8 {
    return switch (image_mode) {
        .multifield => raw_num_fields,
        .grey => switch (raw_num_fields) {
            1, 3 => 1,
            else => error.UnsupportedImageModeFieldCount,
        },
        .rgb => switch (raw_num_fields) {
            1, 3 => 3,
            else => error.UnsupportedImageModeFieldCount,
        },
    };
}

fn needsOutputTransform(
    image_mode: ImageMode,
    raw_num_fields: u8,
) bool {
    return switch (image_mode) {
        .multifield => false,
        .grey => raw_num_fields != 1,
        .rgb => raw_num_fields != 3,
    };
}

fn validateAllFramesBuffer(
    images_arr: *const ndarray.NDArray(F),
    expected_dims: [5]usize,
) !void {
    if (images_arr.dims.len != expected_dims.len) {
        return error.InvalidOutputBuffer;
    }
    for (expected_dims, 0..) |expected_dim, dd| {
        if (images_arr.dims[dd] != expected_dim) {
            return error.InvalidOutputBuffer;
        }
    }
}

fn isFiniteSlice(values: []const F) bool {
    for (values) |value| {
        if (!std.math.isFinite(value)) {
            return false;
        }
    }
    return true;
}

fn isFiniteVec3(vec: anytype) bool {
    return isFiniteSlice(vec.slice[0..]);
}

fn isValidPolynomialMap(map: cam.PolynomialMap) bool {
    const term_count = map.order.termCount();
    return isFiniteSlice(map.coeffs_u[0..term_count]) and
        isFiniteSlice(map.coeffs_v[0..term_count]);
}

fn isValidBidirectionalPolynomial(poly: cam.BidirectionalPolynomial) bool {
    if (poly.forward_map == null and poly.inverse_map == null) {
        return false;
    }
    if (poly.forward_map) |forward_map| {
        if (!isValidPolynomialMap(forward_map)) return false;
    }
    if (poly.inverse_map) |inverse_map| {
        if (!isValidPolynomialMap(inverse_map)) return false;
    }
    return true;
}

fn isValidDistortion(distortion: cam.DistortionModel) bool {
    return switch (distortion) {
        .none => true,
        .brown_conrady => |bc| isFiniteSlice(&[_]F{
            bc.k1,
            bc.k2,
            bc.k3,
            bc.p1,
            bc.p2,
        }),
        .brown_conrady_ext => |bc| isFiniteSlice(&[_]F{
            bc.k1,
            bc.k2,
            bc.k3,
            bc.k4,
            bc.k5,
            bc.k6,
            bc.p1,
            bc.p2,
        }),
        .polynomial => |poly| isValidBidirectionalPolynomial(poly),
        .brown_conrady_polynomial => |chain| isFiniteSlice(&[_]F{
            chain.brown_conrady.k1,
            chain.brown_conrady.k2,
            chain.brown_conrady.k3,
            chain.brown_conrady.p1,
            chain.brown_conrady.p2,
        }) and isValidBidirectionalPolynomial(chain.polynomial),
        .brown_conrady_ext_polynomial => |chain| isFiniteSlice(&[_]F{
            chain.brown_conrady_ext.k1,
            chain.brown_conrady_ext.k2,
            chain.brown_conrady_ext.k3,
            chain.brown_conrady_ext.k4,
            chain.brown_conrady_ext.k5,
            chain.brown_conrady_ext.k6,
            chain.brown_conrady_ext.p1,
            chain.brown_conrady_ext.p2,
        }) and isValidBidirectionalPolynomial(chain.polynomial),
    };
}

fn isValidPsf(psf: cam.PointSpreadFunc) bool {
    return switch (psf) {
        .pixel_box => |box| std.math.isFinite(box.support_rad_px) and
            box.support_rad_px >= 0.0,
        .gaussian => |gauss| isFiniteSlice(&[_]F{
            gauss.sigma_px,
            gauss.support_rad_px,
        }) and
            gauss.sigma_px > 0.0 and
            gauss.support_rad_px >= 0.0,
        .anisotropic_gaussian => |gauss| isFiniteSlice(&[_]F{
            gauss.sigma_x_px,
            gauss.sigma_y_px,
            gauss.theta_rad,
            gauss.support_rad_px,
        }) and
            gauss.sigma_x_px > 0.0 and
            gauss.sigma_y_px > 0.0 and
            gauss.support_rad_px >= 0.0,
    };
}

fn checkCameraInputError(camera_input: cam.CameraInput) !void {
    if (camera_input.pixels_num[0] == 0 or camera_input.pixels_num[1] == 0) {
        return error.InvalidCameraPixels;
    }
    if (!isFiniteSlice(&camera_input.pixels_size) or
        camera_input.pixels_size[0] <= 0.0 or
        camera_input.pixels_size[1] <= 0.0)
    {
        return error.InvalidCameraPixelSize;
    }
    if (!std.math.isFinite(camera_input.focal_length) or camera_input.focal_length <= 0.0) {
        return error.InvalidCameraFocalLength;
    }
    if (camera_input.sub_sample == 0) {
        return error.InvalidCameraSubSample;
    }
    if (!isFiniteVec3(camera_input.pos_world) or
        !isFiniteVec3(camera_input.roi_cent_world) or
        !isFiniteSlice(&[_]F{
            camera_input.rot_world.alpha_z,
            camera_input.rot_world.beta_y,
            camera_input.rot_world.gamma_x,
        }) or
        !isFiniteSlice(camera_input.rot_world.matrix.slice[0..]))
    {
        return error.NonFiniteCameraInput;
    }
    if (!isValidDistortion(camera_input.distortion)) {
        return error.InvalidCameraDistortion;
    }
    if (!isValidPsf(camera_input.psf)) {
        return error.InvalidCameraPsf;
    }
}

fn checkCameraInputAssert(camera_input: cam.CameraInput) void {
    std.debug.assert(camera_input.pixels_num[0] > 0);
    std.debug.assert(camera_input.pixels_num[1] > 0);
    std.debug.assert(isFiniteSlice(&camera_input.pixels_size));
    std.debug.assert(camera_input.pixels_size[0] > 0.0);
    std.debug.assert(camera_input.pixels_size[1] > 0.0);
    std.debug.assert(std.math.isFinite(camera_input.focal_length));
    std.debug.assert(camera_input.focal_length > 0.0);
    std.debug.assert(camera_input.sub_sample > 0);
    std.debug.assert(isFiniteVec3(camera_input.pos_world));
    std.debug.assert(isFiniteVec3(camera_input.roi_cent_world));
    std.debug.assert(isFiniteSlice(&[_]F{
        camera_input.rot_world.alpha_z,
        camera_input.rot_world.beta_y,
        camera_input.rot_world.gamma_x,
    }));
    std.debug.assert(isFiniteSlice(camera_input.rot_world.matrix.slice[0..]));
    std.debug.assert(isValidDistortion(camera_input.distortion));
    std.debug.assert(isValidPsf(camera_input.psf));
}

fn checkRenderConsistencyError(
    render_groups: []const RenderGroupSpec,
    camera_inputs: []const cam.CameraInput,
    meshes: []const mo.MeshInput,
    config: RasterConfig,
    images_arr: ?*ndarray.NDArray(F),
    bench_capture: ?[]report.FrameBenchCapture,
    validate_output_buffer: bool,
) !void {
    if (render_groups.len == 0) {
        return error.NoRenderGroups;
    }
    if (camera_inputs.len == 0) {
        return error.NoCameras;
    }
    if (meshes.len == 0) {
        return error.NoMeshes;
    }
    for (meshes) |mesh| {
        if (mesh.mesh_type == .tri3opt) {
            for (camera_inputs) |camera_input| {
                if (!cam.isNoDistortion(camera_input.distortion)) {
                    return error.DistortionNotSupportedWithTri3Opt;
                }
            }
        }
    }
    for (render_groups) |render_group| {
        if (render_group.workers == 0) {
            return error.InvalidRenderGroupWorkers;
        }
    }

    if (config.total_threads == 0) return error.InvalidTotalThreads;
    if (config.frame_batch_size_per_group == 0) return error.InvalidFrameBatchSize;
    if (config.max_geom_jobs_in_flight_per_group == 0) return error.InvalidGeomJobsInFlight;
    if (config.max_geom_workers_per_job == 0) return error.InvalidGeomWorkersPerJob;
    if (config.max_raster_workers_per_job == 0) return error.InvalidRasterWorkersPerJob;
    if (config.tile_size_min == 0) return error.InvalidTileSizeMin;
    if (config.tile_size_max == 0) return error.InvalidTileSizeMax;
    if (config.tile_size_min > config.tile_size_max) return error.InvalidTileSizeRange;
    if (config.tile_size_override) |tile_size_override| {
        if (tile_size_override < config.tile_size_min or
            tile_size_override > config.tile_size_max)
        {
            return error.InvalidTileSizeOverride;
        }
    }
    if (!std.math.isFinite(config.background_value)) {
        return error.InvalidBackgroundValue;
    }
    if ((config.save_strategy == .disk or config.save_strategy == .both) and
        config.image_save_opts.len == 0)
    {
        return error.InvalidImageSaveOpts;
    }
    if (config.report == .full_stats and config.full_stats_opts.formats.len == 0) {
        return error.InvalidFullStatsFormats;
    }

    for (camera_inputs) |camera_input| {
        try checkCameraInputError(camera_input);
    }

    const num_time = mo.countFrames(meshes);
    if (num_time == 0) {
        return error.NoMeshFrames;
    }

    const raw_num_fields = mo.countOutputFields(meshes);
    if (raw_num_fields == 0) {
        return error.NoOutputFields;
    }
    _ = try outputFieldsForImageMode(config.image_mode, raw_num_fields);

    if (bench_capture) |capture| {
        if (capture.len != camera_inputs.len * num_time) {
            return error.InvalidBenchCaptureBuffer;
        }
    }

    if (!validate_output_buffer) {
        return;
    }

    if (config.save_strategy == .memory or config.save_strategy == .both) {
        const expected_image_dims = try calcAllFramesImageDimsForConfig(
            camera_inputs,
            meshes,
            config,
        );
        const images_arr_req = images_arr orelse return error.InvalidOutputBuffer;
        try validateAllFramesBuffer(images_arr_req, expected_image_dims);
    } else if (images_arr != null) {
        return error.InvalidOutputBuffer;
    }
}

fn checkRenderConsistencyAssert(
    render_groups: []const RenderGroupSpec,
    camera_inputs: []const cam.CameraInput,
    meshes: []const mo.MeshInput,
    config: RasterConfig,
    images_arr: ?*ndarray.NDArray(F),
    bench_capture: ?[]report.FrameBenchCapture,
    validate_output_buffer: bool,
) void {
    std.debug.assert(render_groups.len > 0);
    std.debug.assert(camera_inputs.len > 0);
    std.debug.assert(meshes.len > 0);
    for (render_groups) |render_group| {
        std.debug.assert(render_group.workers > 0);
    }

    std.debug.assert(config.total_threads > 0);
    std.debug.assert(config.frame_batch_size_per_group > 0);
    std.debug.assert(config.max_geom_jobs_in_flight_per_group > 0);
    std.debug.assert(config.max_geom_workers_per_job > 0);
    std.debug.assert(config.max_raster_workers_per_job > 0);
    std.debug.assert(config.tile_size_min > 0);
    std.debug.assert(config.tile_size_max > 0);
    std.debug.assert(config.tile_size_min <= config.tile_size_max);
    if (config.tile_size_override) |tile_size_override| {
        std.debug.assert(tile_size_override >= config.tile_size_min);
        std.debug.assert(tile_size_override <= config.tile_size_max);
    }
    std.debug.assert(std.math.isFinite(config.background_value));
    if (config.save_strategy == .disk or config.save_strategy == .both) {
        std.debug.assert(config.image_save_opts.len > 0);
    }
    if (config.report == .full_stats) {
        std.debug.assert(config.full_stats_opts.formats.len > 0);
    }

    for (camera_inputs) |camera_input| {
        checkCameraInputAssert(camera_input);
    }

    const num_time = mo.countFrames(meshes);
    const raw_num_fields = mo.countOutputFields(meshes);
    std.debug.assert(num_time > 0);
    std.debug.assert(raw_num_fields > 0);
    _ = outputFieldsForImageMode(config.image_mode, raw_num_fields) catch unreachable;

    if (bench_capture) |capture| {
        std.debug.assert(capture.len == camera_inputs.len * num_time);
    }

    if (!validate_output_buffer) {
        return;
    }

    if (config.save_strategy == .memory or config.save_strategy == .both) {
        const expected_image_dims = calcAllFramesImageDimsForConfig(
            camera_inputs,
            meshes,
            config,
        ) catch unreachable;
        const images_arr_req = images_arr orelse unreachable;
        validateAllFramesBuffer(images_arr_req, expected_image_dims) catch unreachable;
    } else {
        std.debug.assert(images_arr == null);
    }
}

pub fn calcAllFramesImageDims(
    camera_inputs: []const cam.CameraInput,
    meshes: []const mo.MeshInput,
) [5]usize {
    return calcAllFramesImageDimsForConfig(
        camera_inputs,
        meshes,
        .{},
    ) catch unreachable;
}

pub fn calcAllFramesImageDimsForConfig(
    camera_inputs: []const cam.CameraInput,
    meshes: []const mo.MeshInput,
    config: RasterConfig,
) ![5]usize {
    std.debug.assert(camera_inputs.len > 0);
    std.debug.assert(meshes.len > 0);

    const num_time = mo.countFrames(meshes);
    const raw_num_fields = mo.countOutputFields(meshes);
    const num_fields = try outputFieldsForImageMode(
        config.image_mode,
        raw_num_fields,
    );
    var max_pixels_num = camera_inputs[0].pixels_num;
    for (camera_inputs[1..]) |camera_input| {
        max_pixels_num[0] = @max(max_pixels_num[0], camera_input.pixels_num[0]);
        max_pixels_num[1] = @max(max_pixels_num[1], camera_input.pixels_num[1]);
    }

    return .{
        camera_inputs.len,
        num_time,
        @as(usize, num_fields),
        max_pixels_num[1],
        max_pixels_num[0],
    };
}

fn getFrameImageView(
    allocator: std.mem.Allocator,
    images_arr: *ndarray.NDArray(F),
    camera_idx: usize,
    frame_idx: usize,
) !ndarray.NDArray(F) {
    std.debug.assert(images_arr.dims.len == 5);
    return try images_arr.fixedPrefixView(
        allocator,
        &[_]usize{ camera_idx, frame_idx },
    );
}

fn initFrameReportStorage(
    outer_alloc: std.mem.Allocator,
    camera: *const cam.CameraPrepared,
    actual_tile_size: u16,
    config: RasterConfig,
) !report.FrameReportStorage {
    return switch (config.report) {
        .off => .{ .off = .{} },
        .bench => .{ .bench = .{} },
        .full_stats => .{ .full_stats = try report.initFullStatsLog(
            outer_alloc,
            camera.pixels_num,
            actual_tile_size,
            camera.sub_sample,
            config.full_stats_opts,
        ) },
    };
}

// --------------------------------------------------------------------------
// 4. Frame Assembly and Output Helpers
// --------------------------------------------------------------------------
const FrameJobDesc = struct {
    camera: *const cam.CameraPrepared,
    camera_idx: usize,
    frame_idx: usize,
    num_fields: u8,
    config: RasterConfig,
    out_dir: ?std.Io.Dir,
    mesh_static: []const mo.MeshStatic,
    nodal_global_scaling: []const ?imageops.ScalingParams,
    images_arr: ?*ndarray.NDArray(F),
    bench_capture: ?[]report.FrameBenchCapture,
    cameras_num: usize,
    can_write_result_direct: bool,
    save_slot: ?*saveoverlap.SaveSlot = null,
};

const FrameContext = struct {
    arena: std.heap.ArenaAllocator,

    frame_meshes: []mo.MeshFrame = &.{},
    prep_meshes: []mo.MeshPrepared = &.{},
    elem_bboxes_by_mesh: [][]rops.ElemBBox = &.{},
    elems_in_image_by_mesh: []usize = &.{},
    raster_hulls: []?ndarray.NDArray(F) = &.{},
    tiling: ?rops.TilingOverlaps = null,
    total_nodes_num: usize = 0,
    total_elems_num: usize = 0,
    total_elems_in_image: usize = 0,
    actual_tile_size: u16 = 1,

    frame_arr: ndarray.NDArray(F) = undefined,

    report_storage: report.FrameReportStorage = .{ .off = .{} },
    frame_times: report.FrameTimes = .{},

    fn init(
        outer_alloc: std.mem.Allocator,
    ) FrameContext {
        return .{
            .arena = std.heap.ArenaAllocator.init(outer_alloc),
        };
    }

    fn deinit(
        self: *FrameContext,
        outer_alloc: std.mem.Allocator,
        config: RasterConfig,
    ) void {
        report.deinitFrameReportStorage(
            outer_alloc,
            config,
            &self.report_storage,
        );
        self.arena.deinit();
    }
};

fn prepareFrameContext(
    outer_alloc: std.mem.Allocator,
    ctx: *FrameContext,
    input: *const FrameJobDesc,
) !void {
    const arena_alloc = ctx.arena.allocator();
    ctx.actual_tile_size = scalingpolicy.tileSize(
        input.config.tile_size_override,
        input.config.tile_size_min,
        input.config.tile_size_max,
        input.camera.pixels_num,
        input.camera.sub_sample,
        input.camera.prepared_psf.halo_px,
    );

    ctx.report_storage = try initFrameReportStorage(
        outer_alloc,
        input.camera,
        ctx.actual_tile_size,
        input.config,
    );

    const mesh_n = input.mesh_static.len;
    ctx.frame_meshes = try arena_alloc.alloc(mo.MeshFrame, mesh_n);
    ctx.prep_meshes = try arena_alloc.alloc(mo.MeshPrepared, mesh_n);
    ctx.elem_bboxes_by_mesh = try arena_alloc.alloc([]rops.ElemBBox, mesh_n);
    ctx.elems_in_image_by_mesh = try arena_alloc.alloc(usize, mesh_n);
    ctx.raster_hulls = try arena_alloc.alloc(?ndarray.NDArray(F), mesh_n);
}

fn prepareFrameBuffer(
    ctx: *FrameContext,
    input: *const FrameJobDesc,
) !void {
    const arena_alloc = ctx.arena.allocator();
    const dims = [_]usize{
        @as(usize, input.num_fields),
        input.camera.pixels_num[1],
        input.camera.pixels_num[0],
    };

    if (input.save_slot) |save_slot| {
        ctx.frame_arr = save_slot.frame_arr;
        std.debug.assert(ctx.frame_arr.dims.len == dims.len);
        for (dims, 0..) |dim, ii| {
            std.debug.assert(ctx.frame_arr.dims[ii] == dim);
        }
        @memset(ctx.frame_arr.slice, input.config.background_value);
        return;
    }

    if (input.can_write_result_direct) {
        const images_arr = input.images_arr orelse return error.NoResult;
        ctx.frame_arr = try getFrameImageView(
            arena_alloc,
            images_arr,
            input.camera_idx,
            input.frame_idx,
        );
    } else {
        ctx.frame_arr = try ndarray.NDArray(F).initFlat(
            arena_alloc,
            dims[0..],
        );
    }

    std.debug.assert(ctx.frame_arr.dims.len == dims.len);
    for (dims, 0..) |dim, ii| {
        std.debug.assert(ctx.frame_arr.dims[ii] == dim);
    }
    @memset(ctx.frame_arr.slice, input.config.background_value);
}

fn copyFrameToImageBatch(
    background_val: F,
    images_arr: *ndarray.NDArray(F),
    camera_idx: usize,
    frame_idx: usize,
    frame_arr: *const ndarray.NDArray(F),
) void {
    std.debug.assert(images_arr.dims.len == 5);
    std.debug.assert(frame_arr.dims.len == 3);
    std.debug.assert(frame_arr.dims[0] == images_arr.dims[2]);
    std.debug.assert(frame_arr.dims[1] <= images_arr.dims[3]);
    std.debug.assert(frame_arr.dims[2] <= images_arr.dims[4]);

    const dst_base = camera_idx * images_arr.strides[0] + frame_idx * images_arr.strides[1];
    const dst_field_stride = images_arr.strides[2];
    const dst_row_stride = images_arr.strides[3];
    const src_field_stride = frame_arr.strides[0];
    const src_row_stride = frame_arr.strides[1];
    const dst_rows = images_arr.dims[3];
    const dst_cols = images_arr.dims[4];
    const src_rows = frame_arr.dims[1];
    const src_cols = frame_arr.dims[2];
    for (0..frame_arr.dims[0]) |ff| {
        const dst_field_base = dst_base + ff * dst_field_stride;
        const src_field_base = ff * src_field_stride;

        for (0..dst_rows) |rr| {
            const dst_row_base = dst_field_base + rr * dst_row_stride;
            @memset(
                images_arr.slice[dst_row_base .. dst_row_base + dst_cols],
                background_val,
            );
        }

        for (0..src_rows) |rr| {
            const dst_row_base = dst_field_base + rr * dst_row_stride;
            const src_row_base = src_field_base + rr * src_row_stride;
            @memcpy(
                images_arr.slice[dst_row_base .. dst_row_base + src_cols],
                frame_arr.slice[src_row_base .. src_row_base + src_cols],
            );
        }
    }
}

fn rasterFrame(
    comptime report_mode: ReportMode,
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    input: *const FrameJobDesc,
    raster_workers: u16,
    ctx: *FrameContext,
) !void {
    const report_ptr = getFrameReportPtr(report_mode, ctx);
    const ctx_report = report.ReportContext(report_mode){ .log = report_ptr };
    const time_start_loop = Timestamp.now(io, .awake);

    const ctx_rast = rops.RasterContext{
        .camera = input.camera,
        .config = input.config,
        .frame_idx = input.frame_idx,
        .tile_size = ctx.actual_tile_size,
    };

    try rasterengine.rasterScene(
        report_mode,
        outer_alloc,
        io,
        ctx_rast,
        ctx_report,
        raster_workers,
        ctx.tiling.?,
        ctx.prep_meshes,
        ctx.raster_hulls,
        &ctx.frame_arr,
    );

    const time_end_loop = Timestamp.now(io, .awake);
    ctx.frame_times.raster_loop = @floatFromInt(
        time_start_loop.durationTo(time_end_loop).raw.nanoseconds,
    );
    if (report.getBenchLog(report_mode, report_ptr)) |bench_log| {
        ctx.frame_times.cam_invert = bench_log.cam_time_ns;
        ctx.frame_times.scratch_resolve = bench_log.resolve_time_ns;
    }
}

fn saveFrame(
    io: std.Io,
    input: *const FrameJobDesc,
    ctx: *FrameContext,
) !void {
    const arena_alloc = ctx.arena.allocator();
    const output_frame_arr = try saveoverlap.buildOutputFrameView(
        arena_alloc,
        input.config,
        &ctx.frame_arr,
    );
    if (input.config.save_strategy == .disk or input.config.save_strategy == .both) {
        std.debug.assert(output_frame_arr.dims[0] <= std.math.maxInt(u8));
        try iio.saveImages(
            io,
            input.out_dir,
            input.camera_idx,
            input.frame_idx,
            @intCast(output_frame_arr.dims[0]),
            input.camera.pixels_num,
            &output_frame_arr,
            saveoverlap.imageSaveChannelsOverride(input.config.image_mode),
            input.config.image_save_opts,
        );
    }
    if ((input.config.save_strategy == .memory or input.config.save_strategy == .both) and !input.can_write_result_direct) {
        const images_arr = input.images_arr orelse return error.NoResult;
        copyFrameToImageBatch(
            input.config.background_value,
            images_arr,
            input.camera_idx,
            input.frame_idx,
            &output_frame_arr,
        );
    }
}

// --------------------------------------------------------------------------
// 5. Raster Support and Save-Overlap Plumbing
// --------------------------------------------------------------------------
pub const RenderGroupSpec = struct {
    io: std.Io,
    save_frame_io: ?std.Io = null,
    workers: u16,
};

fn sceneTileOverlapBinning(
    io: std.Io,
    job: *const FrameJobDesc,
    chunk_exec: *pce.ParaChunkExecutor,
    geom_workers: u16,
    ctx: *FrameContext,
) !void {
    const arena_alloc = ctx.arena.allocator();

    const tiles_num_x: usize = try std.math.divCeil(
        usize,
        job.camera.pixels_num[0],
        ctx.actual_tile_size,
    );
    const tiles_num_y: usize = try std.math.divCeil(
        usize,
        job.camera.pixels_num[1],
        ctx.actual_tile_size,
    );

    const time_start_overlap = Timestamp.now(io, .awake);
    ctx.tiling = try rops.sceneTileElemOverlap(
        arena_alloc,
        chunk_exec,
        scalingpolicy.geometryWorkers(geom_workers),
        ctx.actual_tile_size,
        tiles_num_x,
        tiles_num_y,
        @intCast(job.camera.pixels_num[0]),
        @intCast(job.camera.pixels_num[1]),
        job.camera.prepared_psf.halo_px,
        ctx.elems_in_image_by_mesh,
        ctx.elem_bboxes_by_mesh,
    );
    const time_end_overlap = Timestamp.now(io, .awake);
    ctx.frame_times.tile_overlap = @floatFromInt(
        time_start_overlap.durationTo(time_end_overlap).raw.nanoseconds,
    );
}

fn renderGroupSaveIo(render_group: RenderGroupSpec) std.Io {
    return render_group.save_frame_io orelse render_group.io;
}

fn saveOverlapEnabled(config: RasterConfig) bool {
    return config.save_strategy == .disk and config.disk_save_overlap;
}

// --------------------------------------------------------------------------
// 6. Stage Runners
// --------------------------------------------------------------------------
const PreparedFrameJob = struct {
    desc: FrameJobDesc,
    ctx: FrameContext,
    time_start_frame: ?Timestamp = null,

    fn init(
        group_alloc: std.mem.Allocator,
        desc: FrameJobDesc,
    ) PreparedFrameJob {
        return .{
            .desc = desc,
            .ctx = FrameContext.init(group_alloc),
            .time_start_frame = null,
        };
    }

    fn deinit(
        self: *PreparedFrameJob,
        group_alloc: std.mem.Allocator,
    ) void {
        self.ctx.deinit(group_alloc, self.desc.config);
    }
};

fn runGeometryStage(
    group_alloc: std.mem.Allocator,
    io: std.Io,
    job: *PreparedFrameJob,
    geom_workers: u16,
) !void {
    if (job.time_start_frame == null) {
        job.time_start_frame = Timestamp.now(io, .awake);
    }

    const time_start_geo = Timestamp.now(io, .awake);
    const time_start_pfc = time_start_geo;
    try prepareFrameContext(
        group_alloc,
        &job.ctx,
        &job.desc,
    );
    const time_end_pfc = Timestamp.now(io, .awake);
    job.ctx.frame_times.prepare_frame_context = @floatFromInt(
        time_start_pfc.durationTo(time_end_pfc).raw.nanoseconds,
    );

    var chunk_exec = pce.ParaChunkExecutor.init(io, geom_workers);
    const arena_alloc = job.ctx.arena.allocator();

    var timing = mo.GeometryTiming{};
    const geo_res = try mo.prepareMeshFrames(
        arena_alloc,
        &chunk_exec,
        scalingpolicy.geometryWorkers(geom_workers),
        job.desc.camera,
        job.desc.config,
        job.desc.frame_idx,
        job.desc.mesh_static,
        job.desc.nodal_global_scaling,
        job.ctx.frame_meshes,
        &timing,
    );

    job.ctx.frame_times.geom_coord_ops = @floatFromInt(timing.coord_ops);
    job.ctx.frame_times.geom_cull_ops = @floatFromInt(timing.cull_ops);
    job.ctx.frame_times.geom_prep_hulls_shaders = @floatFromInt(
        timing.prep_hulls_shaders,
    );
    job.ctx.frame_times.geom_remap_inds = @floatFromInt(timing.remap_inds);

    for (job.ctx.frame_meshes, 0..) |*fm, ii| {
        job.ctx.prep_meshes[ii] = fm.mesh;
        job.ctx.elem_bboxes_by_mesh[ii] = fm.elem_bboxes;
        job.ctx.elems_in_image_by_mesh[ii] = fm.elems_in_image;
        job.ctx.raster_hulls[ii] = fm.raster_hull;
    }
    job.ctx.total_elems_num = geo_res.total_elems_num;
    job.ctx.total_elems_in_image = geo_res.total_elems_in_image;
    job.ctx.total_nodes_num = mo.countStaticMeshNodes(job.desc.mesh_static);

    const time_end_geo = Timestamp.now(io, .awake);
    job.ctx.frame_times.geometry_prep = @floatFromInt(
        time_start_geo.durationTo(time_end_geo).raw.nanoseconds,
    );

    try sceneTileOverlapBinning(
        io,
        &job.desc,
        &chunk_exec,
        geom_workers,
        &job.ctx,
    );
}

fn runRasterStage(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    job: *PreparedFrameJob,
    raster_workers: u16,
) !void {
    const time_start_fb = Timestamp.now(io, .awake);
    try prepareFrameBuffer(&job.ctx, &job.desc);
    const time_end_fb = Timestamp.now(io, .awake);
    job.ctx.frame_times.setup_frame_buffer = @floatFromInt(
        time_start_fb.durationTo(time_end_fb).raw.nanoseconds,
    );

    switch (job.desc.config.report) {
        .off => try rasterFrame(
            .off,
            outer_alloc,
            io,
            &job.desc,
            raster_workers,
            &job.ctx,
        ),
        .bench => try rasterFrame(
            .bench,
            outer_alloc,
            io,
            &job.desc,
            raster_workers,
            &job.ctx,
        ),
        .full_stats => try rasterFrame(
            .full_stats,
            outer_alloc,
            io,
            &job.desc,
            raster_workers,
            &job.ctx,
        ),
    }
}

fn runRasterAndSaveFrame(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    job: *PreparedFrameJob,
    raster_workers: u16,
) !void {
    try runRasterStage(
        outer_alloc,
        io,
        job,
        raster_workers,
    );

    const time_start_save = Timestamp.now(io, .awake);
    try saveFrame(io, &job.desc, &job.ctx);
    const time_end_save = Timestamp.now(io, .awake);

    job.ctx.frame_times.save_frame = @floatFromInt(
        time_start_save.durationTo(time_end_save).raw.nanoseconds,
    );
    job.ctx.frame_times.active_time =
        job.ctx.frame_times.setup_frame_buffer +
        job.ctx.frame_times.geometry_prep +
        job.ctx.frame_times.tile_overlap +
        job.ctx.frame_times.raster_loop +
        job.ctx.frame_times.save_frame;

    const time_end_frame = Timestamp.now(io, .awake);

    job.ctx.frame_times.latency_time = @floatFromInt(
        job.time_start_frame.?.durationTo(time_end_frame).raw.nanoseconds,
    );

    try report.publishFrameResults(
        outer_alloc,
        io,
        job.desc.config,
        job.ctx.actual_tile_size,
        job.desc.camera,
        job.desc.camera_idx,
        job.desc.frame_idx,
        job.desc.cameras_num,
        job.desc.out_dir,
        job.desc.bench_capture,
        &job.ctx.report_storage,
        job.ctx.frame_times,
        job.ctx.total_nodes_num,
        job.ctx.total_elems_num,
        job.ctx.total_elems_in_image,
        job.ctx.prep_meshes,
    );
}

// --------------------------------------------------------------------------
// 7. Batch Preparation and Wave Scheduling
// --------------------------------------------------------------------------
fn prepareJobBatch(
    group_alloc: std.mem.Allocator,
    cameras: []const cam.CameraPrepared,
    config: RasterConfig,
    out_dir: ?std.Io.Dir,
    num_fields: u8,
    mesh_static: []const mo.MeshStatic,
    nodal_global_scaling: []const ?imageops.ScalingParams,
    images_arr: ?*ndarray.NDArray(F),
    bench_capture: ?[]report.FrameBenchCapture,
    job_indices: []const usize,
) ![]PreparedFrameJob {
    const jobs = try group_alloc.alloc(PreparedFrameJob, job_indices.len);

    const can_write_result_direct = images_arr != null and
        cam.allCamerasSharePixels(cameras) and
        !needsOutputTransform(config.image_mode, num_fields);

    for (job_indices, 0..) |job_idx, ii| {
        const frame_idx = @divFloor(job_idx, cameras.len);
        const camera_idx = @mod(job_idx, cameras.len);
        jobs[ii] = PreparedFrameJob.init(
            group_alloc,
            .{
                .camera = &cameras[camera_idx],
                .camera_idx = camera_idx,
                .frame_idx = frame_idx,
                .num_fields = num_fields,
                .config = config,
                .out_dir = out_dir,
                .mesh_static = mesh_static,
                .nodal_global_scaling = nodal_global_scaling,
                .images_arr = images_arr,
                .bench_capture = bench_capture,
                .cameras_num = cameras.len,
                .can_write_result_direct = can_write_result_direct,
            },
        );
    }

    return jobs;
}

fn assignSpreadGeometryWorkers(
    allocator: std.mem.Allocator,
    group_workers: u16,
    jobs_in_wave: usize,
    max_geom_workers_per_job: u16,
) ![]u16 {
    const assigned = try allocator.alloc(u16, jobs_in_wave);
    @memset(assigned, 0);

    const max_jobs = @min(jobs_in_wave, @as(usize, @max(@as(u16, 1), group_workers)));
    for (0..max_jobs) |ii| {
        assigned[ii] = 1;
    }

    var remaining_workers = @as(usize, @max(@as(u16, 1), group_workers)) - max_jobs;
    while (remaining_workers > 0) {
        var added_any = false;
        for (assigned) |*workers| {
            if (remaining_workers == 0) break;
            if (workers.* < @max(@as(u16, 1), max_geom_workers_per_job)) {
                workers.* += 1;
                remaining_workers -= 1;
                added_any = true;
            }
        }
        if (!added_any) break;
    }

    for (assigned) |*workers| {
        if (workers.* == 0) workers.* = 1;
    }
    return assigned;
}

fn geometryJobsPerWave(
    config: RasterConfig,
    group_workers: u16,
    jobs_remaining: usize,
) usize {
    const requested_jobs = @max(@as(u16, 1), config.max_geom_jobs_in_flight_per_group);
    const worker_cap = @max(@as(u16, 1), group_workers);
    return @min(
        jobs_remaining,
        @as(usize, @intCast(@min(requested_jobs, worker_cap))),
    );
}

const FrameJobErrorState = struct {
    mutex: std.atomic.Mutex = .unlocked,
    first_err: ?anyerror = null,

    fn setFirst(
        self: *FrameJobErrorState,
        err: anyerror,
    ) void {
        while (!self.mutex.tryLock()) {
            std.atomic.spinLoopHint();
        }
        defer self.mutex.unlock();
        if (self.first_err == null) {
            self.first_err = err;
        }
    }
};

fn processGeometryWave(
    group_alloc: std.mem.Allocator,
    io: std.Io,
    jobs: []PreparedFrameJob,
    workers_per_job: []const u16,
) !void {
    const AsyncGeometryJob = struct {
        fn run(
            local_group_alloc: std.mem.Allocator,
            local_io: std.Io,
            job: *PreparedFrameJob,
            geom_workers: u16,
            err_state: *FrameJobErrorState,
        ) std.Io.Cancelable!void {
            runGeometryStage(
                local_group_alloc,
                local_io,
                job,
                geom_workers,
            ) catch |err| {
                err_state.setFirst(err);
            };
        }
    };

    var err_state = FrameJobErrorState{};
    var group: std.Io.Group = .init;
    errdefer group.cancel(io);

    const caller_idx = jobs.len - 1;
    for (jobs[0..caller_idx], workers_per_job[0..caller_idx]) |*job, geom_workers| {
        group.async(
            io,
            AsyncGeometryJob.run,
            .{ group_alloc, io, job, geom_workers, &err_state },
        );
    }

    try runGeometryStage(
        group_alloc,
        io,
        &jobs[caller_idx],
        workers_per_job[caller_idx],
    );
    try group.await(io);
    if (err_state.first_err) |err| return err;
}

fn processGeometryBatch(
    group_alloc: std.mem.Allocator,
    io: std.Io,
    group_workers: u16,
    config: RasterConfig,
    total_scene_elems: usize,
    jobs: []PreparedFrameJob,
) !void {
    const geom_mode = scalingpolicy.resolveGeometrySchedulingMode(
        config.geom_scheduling_mode,
        total_scene_elems,
    );
    var wave_start: usize = 0;

    while (wave_start < jobs.len) {
        const jobs_remaining = jobs.len - wave_start;

        const wave_jobs = switch (geom_mode) {
            .spread => geometryJobsPerWave(config, group_workers, jobs_remaining),
            .pack => @min(@as(usize, 1), jobs_remaining),
            .auto => unreachable,
        };

        const wave_end = wave_start + wave_jobs;
        const wave = jobs[wave_start..wave_end];

        const workers_per_job = switch (geom_mode) {
            .spread => try assignSpreadGeometryWorkers(
                group_alloc,
                group_workers,
                wave.len,
                config.max_geom_workers_per_job,
            ),
            .pack => blk: {
                const assigned = try group_alloc.alloc(u16, 1);
                assigned[0] = @min(
                    @max(@as(u16, 1), group_workers),
                    @max(@as(u16, 1), config.max_geom_workers_per_job),
                );
                break :blk assigned;
            },
            .auto => unreachable,
        };
        defer group_alloc.free(workers_per_job);

        try processGeometryWave(group_alloc, io, wave, workers_per_job);

        wave_start = wave_end;
    }
}

fn processRasterBatch(
    outer_alloc: std.mem.Allocator,
    group_io: std.Io,
    group_alloc: std.mem.Allocator,
    group_workers: u16,
    config: RasterConfig,
    save_overlap: ?*saveoverlap.SaveOverlap,
    jobs: []PreparedFrameJob,
) !void {
    const raster_workers = @min(
        @max(@as(u16, 1), group_workers),
        @max(@as(u16, 1), config.max_raster_workers_per_job),
    );
    for (jobs) |*job| {
        defer job.deinit(group_alloc);
        if (save_overlap) |so| {
            try so.runRasterStageAndQueue(
                outer_alloc,
                group_io,
                job,
                raster_workers,
                runRasterStage,
            );
            continue;
        }
        try runRasterAndSaveFrame(
            outer_alloc,
            group_io,
            job,
            raster_workers,
        );
    }
}

// --------------------------------------------------------------------------
// 8. Offline Dispatch Path
// --------------------------------------------------------------------------
const OfflineDispatchShared = struct {
    outer_alloc: std.mem.Allocator,
    cameras: []const cam.CameraPrepared,
    config: RasterConfig,
    out_dir: ?std.Io.Dir,
    num_time: usize,
    num_fields: u8,
    mesh_static: []const mo.MeshStatic,
    nodal_global_scaling: []const ?imageops.ScalingParams,
    images_arr: ?*ndarray.NDArray(F),
    bench_capture: ?[]report.FrameBenchCapture,
    total_scene_elems: usize,
    batch_size: usize,
    next_job: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    err_state: *FrameJobErrorState,
};

fn processOfflineRenderGroupLoop(
    render_group: RenderGroupSpec,
    shared: *OfflineDispatchShared,
) !void {
    var group_arena = std.heap.ArenaAllocator.init(shared.outer_alloc);
    defer group_arena.deinit();
    const group_alloc = group_arena.allocator();
    const jobs_num = shared.cameras.len * shared.num_time;

    var save_overlap = try saveoverlap.SaveOverlap.initMaybe(
        shared.outer_alloc,
        renderGroupSaveIo(render_group),
        shared.cameras,
        shared.num_fields,
        shared.config,
        saveOverlapEnabled(shared.config),
    );
    defer save_overlap.deinit();

    while (true) {
        const batch_start = shared.next_job.fetchAdd(shared.batch_size, .monotonic);
        if (batch_start >= jobs_num) break;

        const batch_end = @min(jobs_num, batch_start + shared.batch_size);
        const batch_len = batch_end - batch_start;
        const job_indices = try group_alloc.alloc(usize, batch_len);
        for (0..batch_len) |ii| {
            job_indices[ii] = batch_start + ii;
        }

        const jobs = try prepareJobBatch(
            group_alloc,
            shared.cameras,
            shared.config,
            shared.out_dir,
            shared.num_fields,
            shared.mesh_static,
            shared.nodal_global_scaling,
            shared.images_arr,
            shared.bench_capture,
            job_indices,
        );

        try processGeometryBatch(
            group_alloc,
            render_group.io,
            render_group.workers,
            shared.config,
            shared.total_scene_elems,
            jobs,
        );

        try processRasterBatch(
            shared.outer_alloc,
            render_group.io,
            group_alloc,
            render_group.workers,
            shared.config,
            if (save_overlap.enabled()) &save_overlap else null,
            jobs,
        );
        _ = group_arena.reset(.retain_capacity);
    }

    try save_overlap.checkError();
}

fn processOfflineRenderGroupThread(
    render_group: RenderGroupSpec,
    shared: *OfflineDispatchShared,
) void {
    // Required for threads to submit error to the mutex
    processOfflineRenderGroupLoop(render_group, shared) catch |err| {
        shared.err_state.setFirst(err);
    };
}

fn dispatchFrameJobsOffline(
    outer_alloc: std.mem.Allocator,
    render_groups: []const RenderGroupSpec,
    cameras: []const cam.CameraPrepared,
    config: RasterConfig,
    out_dir: ?std.Io.Dir,
    num_time: usize,
    num_fields: u8,
    mesh_static: []const mo.MeshStatic,
    nodal_global_scaling: []const ?imageops.ScalingParams,
    images_arr: ?*ndarray.NDArray(F),
    bench_capture: ?[]report.FrameBenchCapture,
) !void {
    var err_state = FrameJobErrorState{};
    var shared = OfflineDispatchShared{
        .outer_alloc = outer_alloc,
        .cameras = cameras,
        .config = config,
        .out_dir = out_dir,
        .num_time = num_time,
        .num_fields = num_fields,
        .mesh_static = mesh_static,
        .nodal_global_scaling = nodal_global_scaling,
        .images_arr = images_arr,
        .bench_capture = bench_capture,
        .total_scene_elems = mo.countStaticMeshElements(mesh_static),
        .batch_size = @max(@as(usize, 1), config.frame_batch_size_per_group),
        .err_state = &err_state,
    };

    var threads = try outer_alloc.alloc(std.Thread, render_groups.len -| 1);
    defer outer_alloc.free(threads);

    // Submit to worker threads but not the main thread
    for (render_groups[1..], 0..) |render_group, ii| {
        threads[ii] = try std.Thread.spawn(
            .{},
            processOfflineRenderGroupThread,
            .{ render_group, &shared },
        );
    }

    // Submit to the main thread
    processOfflineRenderGroupLoop(render_groups[0], &shared) catch |err| {
        err_state.setFirst(err);
    };

    for (threads) |thread| {
        thread.join();
    }
    if (err_state.first_err) |err| return err;
}

// --------------------------------------------------------------------------
// 9. In-Order Dispatch Path
// --------------------------------------------------------------------------
const InOrderDispatchShared = struct {
    outer_alloc: std.mem.Allocator,
    cameras: []const cam.CameraPrepared,
    config: RasterConfig,
    out_dir: ?std.Io.Dir,
    frame_idx: usize,
    num_fields: u8,
    mesh_static: []const mo.MeshStatic,
    nodal_global_scaling: []const ?imageops.ScalingParams,
    images_arr: ?*ndarray.NDArray(F),
    bench_capture: ?[]report.FrameBenchCapture,
    total_scene_elems: usize,
    batch_size: usize,
    next_camera: std.atomic.Value(usize) =
        std.atomic.Value(usize).init(0),
    err_state: *FrameJobErrorState,
};

fn processInOrderRenderGroupLoop(
    render_group: RenderGroupSpec,
    shared: *InOrderDispatchShared,
) !void {
    var group_arena = std.heap.ArenaAllocator.init(shared.outer_alloc);
    defer group_arena.deinit();
    const group_alloc = group_arena.allocator();

    var save_overlap = try saveoverlap.SaveOverlap.initMaybe(
        shared.outer_alloc,
        renderGroupSaveIo(render_group),
        shared.cameras,
        shared.num_fields,
        shared.config,
        saveOverlapEnabled(shared.config),
    );
    defer save_overlap.deinit();

    while (true) {
        const batch_start_camera = shared.next_camera.fetchAdd(
            shared.batch_size,
            .monotonic,
        );
        if (batch_start_camera >= shared.cameras.len) break;

        const batch_end_camera = @min(
            shared.cameras.len,
            batch_start_camera + shared.batch_size,
        );

        const batch_len = batch_end_camera - batch_start_camera;
        const job_indices = try group_alloc.alloc(usize, batch_len);
        for (0..batch_len) |ii| {
            job_indices[ii] =
                shared.frame_idx * shared.cameras.len + batch_start_camera + ii;
        }

        const jobs = try prepareJobBatch(
            group_alloc,
            shared.cameras,
            shared.config,
            shared.out_dir,
            shared.num_fields,
            shared.mesh_static,
            shared.nodal_global_scaling,
            shared.images_arr,
            shared.bench_capture,
            job_indices,
        );

        try processGeometryBatch(
            group_alloc,
            render_group.io,
            render_group.workers,
            shared.config,
            shared.total_scene_elems,
            jobs,
        );

        try processRasterBatch(
            shared.outer_alloc,
            render_group.io,
            group_alloc,
            render_group.workers,
            shared.config,
            if (save_overlap.enabled()) &save_overlap else null,
            jobs,
        );

        _ = group_arena.reset(.retain_capacity);
    }
    try save_overlap.checkError();
}

fn processInOrderRenderGroupThread(
    render_group: RenderGroupSpec,
    shared: *InOrderDispatchShared,
) void {
    // Required to submit the error from thread through a mutex
    processInOrderRenderGroupLoop(render_group, shared) catch |err| {
        shared.err_state.setFirst(err);
    };
}

fn dispatchFrameJobsInOrder(
    outer_alloc: std.mem.Allocator,
    render_groups: []const RenderGroupSpec,
    cameras: []const cam.CameraPrepared,
    config: RasterConfig,
    out_dir: ?std.Io.Dir,
    num_time: usize,
    num_fields: u8,
    mesh_static: []const mo.MeshStatic,
    nodal_global_scaling: []const ?imageops.ScalingParams,
    images_arr: ?*ndarray.NDArray(F),
    bench_capture: ?[]report.FrameBenchCapture,
) !void {
    const total_scene_elems = mo.countStaticMeshElements(mesh_static);
    const batch_size = @max(@as(usize, 1), config.frame_batch_size_per_group);

    for (0..num_time) |frame_idx| {
        var err_state = FrameJobErrorState{};
        var shared = InOrderDispatchShared{
            .outer_alloc = outer_alloc,
            .cameras = cameras,
            .config = config,
            .out_dir = out_dir,
            .frame_idx = frame_idx,
            .num_fields = num_fields,
            .mesh_static = mesh_static,
            .nodal_global_scaling = nodal_global_scaling,
            .images_arr = images_arr,
            .bench_capture = bench_capture,
            .total_scene_elems = total_scene_elems,
            .batch_size = batch_size,
            .err_state = &err_state,
        };

        var threads = try outer_alloc.alloc(
            std.Thread,
            render_groups.len -| 1,
        );
        defer outer_alloc.free(threads);

        // Submit to all worker threads but not the main thread
        for (render_groups[1..], 0..) |render_group, ii| {
            threads[ii] = try std.Thread.spawn(
                .{},
                processInOrderRenderGroupThread,
                .{ render_group, &shared },
            );
        }

        // Submit to the main thread
        processInOrderRenderGroupLoop(render_groups[0], &shared) catch |err| {
            err_state.setFirst(err);
        };

        for (threads) |thread| {
            thread.join();
        }
        if (err_state.first_err) |err| return err;
    }
}

// --------------------------------------------------------------------------
// 10. Public API
// --------------------------------------------------------------------------
pub fn raster(
    outer_alloc: std.mem.Allocator,
    render_groups: []const RenderGroupSpec,
    camera_inputs: []const cam.CameraInput,
    meshes: []const mo.MeshInput,
    config: RasterConfig,
    out_dir_path: ?[]const u8,
) !?ndarray.NDArray(F) {
    return rasterReport(
        outer_alloc,
        render_groups,
        camera_inputs,
        meshes,
        config,
        out_dir_path,
        null,
    );
}

pub fn rasterInto(
    outer_alloc: std.mem.Allocator,
    render_groups: []const RenderGroupSpec,
    camera_inputs: []const cam.CameraInput,
    meshes: []const mo.MeshInput,
    config: RasterConfig,
    out_dir_path: ?[]const u8,
    images_arr: ?*ndarray.NDArray(F),
) !void {
    try rasterReportInto(
        outer_alloc,
        render_groups,
        camera_inputs,
        meshes,
        config,
        out_dir_path,
        images_arr,
        null,
    );
}

pub fn rasterReport(
    outer_alloc: std.mem.Allocator,
    render_groups: []const RenderGroupSpec,
    camera_inputs: []const cam.CameraInput,
    meshes: []const mo.MeshInput,
    config: RasterConfig,
    out_dir_path: ?[]const u8,
    bench_capture: ?[]report.FrameBenchCapture,
) !?ndarray.NDArray(F) {
    try checkRenderConsistencyError(
        render_groups,
        camera_inputs,
        meshes,
        config,
        null,
        bench_capture,
        false,
    );

    const needs_images_arr = config.save_strategy == .memory or
        config.save_strategy == .both;
    var images_arr_opt: ?ndarray.NDArray(F) = null;
    if (needs_images_arr) {
        const dims = try calcAllFramesImageDimsForConfig(
            camera_inputs,
            meshes,
            config,
        );
        images_arr_opt = try ndarray.NDArray(F).initFlat(
            outer_alloc,
            dims[0..],
        );
    }
    errdefer if (images_arr_opt) |*images_arr| {
        outer_alloc.free(images_arr.slice);
        images_arr.deinit(outer_alloc);
    };

    try rasterReportInto(
        outer_alloc,
        render_groups,
        camera_inputs,
        meshes,
        config,
        out_dir_path,
        if (images_arr_opt) |*images_arr| images_arr else null,
        bench_capture,
    );
    return images_arr_opt;
}

pub fn rasterReportInto(
    outer_alloc: std.mem.Allocator,
    render_groups: []const RenderGroupSpec,
    camera_inputs: []const cam.CameraInput,
    meshes: []const mo.MeshInput,
    config: RasterConfig,
    out_dir_path: ?[]const u8,
    images_arr: ?*ndarray.NDArray(F),
    bench_capture: ?[]report.FrameBenchCapture,
) !void {
    try checkRenderConsistencyError(
        render_groups,
        camera_inputs,
        meshes,
        config,
        images_arr,
        bench_capture,
        true,
    );

    const summary_io = render_groups[0].io;
    const time_start_render = Timestamp.now(summary_io, .awake);

    var out_dir: ?std.Io.Dir = null;
    if (out_dir_path) |path| {
        const cwd = std.Io.Dir.cwd();
        cwd.createDirPath(summary_io, path) catch |err| {
            if (err != error.PathAlreadyExists) {
                return err;
            }
        };
        out_dir = try cwd.openDir(summary_io, path, .{});
    }
    defer if (out_dir) |*od| od.close(summary_io);

    var static_arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer static_arena.deinit();
    const static_alloc = static_arena.allocator();

    const cameras = try cameraops.prepareCameraSlice(
        outer_alloc,
        camera_inputs,
    );
    defer {
        for (cameras) |camera| camera.deinit(outer_alloc);
        outer_alloc.free(cameras);
    }

    const num_time = mo.countFrames(meshes);
    const num_fields = mo.countOutputFields(meshes);

    // Init. static data across all frames - here we reshape uv's once if we have them so
    // we don't need to do this every frames
    const mesh_static = try initMeshStaticSlice(static_alloc, meshes);
    const nodal_global_scaling = try initNodalGlobalScaling(outer_alloc, meshes);
    defer outer_alloc.free(nodal_global_scaling);

    const time_start_frame_buffer = Timestamp.now(summary_io, .awake);
    const time_end_setup = Timestamp.now(summary_io, .awake);
    var end_to_end_times = report.EndToEndTimes{
        .setup_time = @floatFromInt(
            time_start_render.durationTo(time_end_setup).raw.nanoseconds,
        ),
        .setup_other_time = @floatFromInt(
            time_start_render.durationTo(
                time_start_frame_buffer,
            ).raw.nanoseconds,
        ),
        .setup_frame_buffer_time = @floatFromInt(
            time_start_frame_buffer.durationTo(
                time_end_setup,
            ).raw.nanoseconds,
        ),
    };
    const time_start_dispatch = Timestamp.now(summary_io, .awake);

    if (config.render_mode == .in_order) {
        try dispatchFrameJobsInOrder(
            outer_alloc,
            render_groups,
            cameras,
            config,
            out_dir,
            num_time,
            num_fields,
            mesh_static,
            nodal_global_scaling,
            images_arr,
            bench_capture,
        );
    } else {
        try dispatchFrameJobsOffline(
            outer_alloc,
            render_groups,
            cameras,
            config,
            out_dir,
            num_time,
            num_fields,
            mesh_static,
            nodal_global_scaling,
            images_arr,
            bench_capture,
        );
    }

    const time_end_render = Timestamp.now(summary_io, .awake);
    end_to_end_times.dispatch_time = @floatFromInt(
        time_start_dispatch.durationTo(time_end_render).raw.nanoseconds,
    );
    end_to_end_times.total_time = @floatFromInt(
        time_start_render.durationTo(time_end_render).raw.nanoseconds,
    );
    const actual_tile_size = scalingpolicy.tileSize(
        config.tile_size_override,
        config.tile_size_min,
        config.tile_size_max,
        cameras[0].pixels_num,
        cameras[0].sub_sample,
        cameras[0].prepared_psf.halo_px,
    );
    try report.printRenderSummary(
        summary_io,
        cameras,
        actual_tile_size,
        num_time,
        config.report,
        end_to_end_times,
        if (bench_capture) |capture| capture else null,
    );
}
