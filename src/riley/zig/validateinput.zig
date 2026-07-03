// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const ndarray = @import("ndarray.zig");
const buildconfig = @import("buildconfig.zig");
const cam = @import("camera.zig");
const mo = @import("meshpipeline.zig");
const rastcfg = @import("rasterconfig.zig");
const report = @import("report.zig");

const F = buildconfig.F;

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

pub const ValidationSummary = struct {
    num_time: usize,
    raw_num_fields: u8,
};

// --------------------------------------------------------------------------------------
// Public Entry-Point Func
// --------------------------------------------------------------------------------------

pub fn checkRenderInputsError(
    render_groups: anytype,
    camera_inputs: []const cam.CameraInput,
    meshes: []const mo.MeshInput,
    config: rastcfg.RasterConfig,
    bench_capture: ?[]report.FrameBenchCapture,
) !ValidationSummary {
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
                    return error.DistortionNotSuppedWithTri3Opt;
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

    if (bench_capture) |capture| {
        if (capture.len != camera_inputs.len * num_time) {
            return error.InvalidBenchCaptureBuff;
        }
    }

    return .{
        .num_time = num_time,
        .raw_num_fields = raw_num_fields,
    };
}

pub fn checkRenderInputsAssert(
    render_groups: anytype,
    camera_inputs: []const cam.CameraInput,
    meshes: []const mo.MeshInput,
    config: rastcfg.RasterConfig,
    bench_capture: ?[]report.FrameBenchCapture,
) ValidationSummary {
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

    if (bench_capture) |capture| {
        std.debug.assert(capture.len == camera_inputs.len * num_time);
    }

    return .{
        .num_time = num_time,
        .raw_num_fields = raw_num_fields,
    };
}

pub fn validateOutputBuffError(
    config: rastcfg.RasterConfig,
    images_arr: ?*ndarray.NDArray(F),
    expected_dims: [5]usize,
) !void {
    if (config.save_strategy == .memory or config.save_strategy == .both) {
        const images_arr_req = images_arr orelse return error.InvalidOutputBuff;
        try validateAllFramesBuff(images_arr_req, expected_dims);
    } else if (images_arr != null) {
        return error.InvalidOutputBuff;
    }
}

pub fn validateOutputBuffAssert(
    config: rastcfg.RasterConfig,
    images_arr: ?*ndarray.NDArray(F),
    expected_dims: [5]usize,
) void {
    if (config.save_strategy == .memory or config.save_strategy == .both) {
        const images_arr_req = images_arr orelse unreachable;
        validateAllFramesBuff(images_arr_req, expected_dims) catch unreachable;
    } else {
        std.debug.assert(images_arr == null);
    }
}

// --------------------------------------------------------------------------------------
// Generic Low-Level Helpers
// --------------------------------------------------------------------------------------

fn validateAllFramesBuff(
    images_arr: *const ndarray.NDArray(F),
    expected_dims: [5]usize,
) !void {
    if (images_arr.dims.len != expected_dims.len) {
        return error.InvalidOutputBuff;
    }
    for (expected_dims, 0..) |expected_dim, dd| {
        if (images_arr.dims[dd] != expected_dim) {
            return error.InvalidOutputBuff;
        }
    }
}

fn isFiniteSlice(vals: []const F) bool {
    for (vals) |value| {
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
    if (poly.forward_map == null and poly.inv_map == null) {
        return false;
    }
    if (poly.forward_map) |forward_map| {
        if (!isValidPolynomialMap(forward_map)) return false;
    }
    if (poly.inv_map) |inv_map| {
        if (!isValidPolynomialMap(inv_map)) return false;
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
        .pixel_box => |box| std.math.isFinite(box.supp_rad_px) and
            box.supp_rad_px >= 0.0,
        .gaussian => |gauss| isFiniteSlice(&[_]F{
            gauss.sigma_px,
            gauss.supp_rad_px,
        }) and
            gauss.sigma_px > 0.0 and
            gauss.supp_rad_px >= 0.0,
        .anisotropic_gaussian => |gauss| isFiniteSlice(&[_]F{
            gauss.sigma_x_px,
            gauss.sigma_y_px,
            gauss.theta_rad,
            gauss.supp_rad_px,
        }) and
            gauss.sigma_x_px > 0.0 and
            gauss.sigma_y_px > 0.0 and
            gauss.supp_rad_px >= 0.0,
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
    if (!std.math.isFinite(camera_input.focal_length) or
        camera_input.focal_length <= 0.0)
    {
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
