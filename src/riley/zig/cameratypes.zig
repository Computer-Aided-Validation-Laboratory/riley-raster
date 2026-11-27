// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const shadertypes = @import("shadertypes.zig");
const std = @import("std");
const vecstack = @import("vecstack.zig");
const matstack = @import("matstack.zig");
const rotation = @import("rotation.zig");
const ndarray = @import("ndarray.zig");
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;
const cameramodels = @import("cameramodels.zig");
const distortbounds = @import("distortbounds.zig");
const imageio = @import("imageio.zig");

/// Camera geometry, sampling, optics, and output options for rendering.
pub const CameraInput = struct {
    /// Sensor width and height, in pixels.
    pixels_num: [2]u32,
    /// Physical pixel pitch in the horizontal and vertical directions.
    pixels_size: [2]F,
    /// Camera centre in world space, regardless of `coord_sys`.
    pos_world: vecstack.Vec3F,
    /// OpenGL-style camera-to-world rotation, regardless of `coord_sys`.
    rot_world: rotation.Rotation,
    /// World-space point defining the region-of-interest projection distance.
    roi_cent_world: vecstack.Vec3F,
    /// Focal length in the same length units as `pixels_size`.
    focal_length: F,
    /// Samples per pixel axis; render input validation rejects zero.
    sub_sample: u32,
    background_value: F = 0.0,
    distort: cameramodels.DistortParams = .none,
    psf: cameramodels.PointSpreadFunc = .{ .pixel_box = .{} },
    /// Camera CSV convention; does not change the in-memory pose used for rendering.
    coord_sys: CameraCoordSys = .opengl,
    subpixel_center_map: SubPixelCenterMap = .per_tile,
    render_format: shadertypes.RenderFormat = .mono,
    /// Per-file encoding options used when disk output is requested.
    output_files: []const imageio.ImageSaveOpts = &.{
        .{ .format = .bmp, .file_bits = 8, .scaling = .none },
    },
};

/// Two independently configured cameras in stereo-pair order.
pub const StereoPairInput = struct {
    cameras: [2]CameraInput,
};

/// Camera CSV pose convention. Rendering uses an OpenGL-style in-memory pose for either tag.
pub const CameraCoordSys = enum {
    /// CSV stores the camera centre and camera-to-world rotation (+x right, +y up, −z forward).
    opengl,
    /// CSV stores world-to-camera extrinsics (+x right, +y down, +z forward).
    /// Loading converts to the in-memory pose while retaining this tag; saving converts back.
    opencv,
};

/// Storage policy for undistorted subpixel centres: cache the whole image or compute
/// centres per tile.
pub const SubPixelCenterMap = enum {
    full_in_mem,
    per_tile,
};

/// Field-of-view size and per-axis pixel/length conversion at a reference plane.
/// The two-element quantities are ordered horizontal, then vertical.
pub const FOVScaling = struct {
    plane_dist: F,
    plane_size: [2]F,
    leng_per_pixel: [2]F,
    pixel_per_leng: [2]F,
};

pub inline fn isNoDistort(distort: anytype) bool {
    return switch (distort) {
        .none => true,
        .poly => false,
        .brown_con_poly, .brown_con_ext_poly => false,
        else => false,
    };
}

pub fn CameraPreparedType(comptime CameraBackend: type) type {
    return struct {
        const Self = @This();

        pixels_num: [2]u32,
        pixels_size: [2]F,
        pos_world: vecstack.Vec3F,
        rot_world: rotation.Rotation,
        roi_cent_world: vecstack.Vec3F,
        focal_length: F,
        sub_sample: u32,
        background_value: F,
        sensor_size: [2]F,
        image_dims: [2]F,
        image_dist: F,
        cam_to_world_mat: matstack.Mat44F,
        world_to_cam_mat: matstack.Mat44F,
        distort: cameramodels.DistortModel,
        psf: cameramodels.PointSpreadFunc,
        prep_psf: cameramodels.PreparedPSF,
        coord_sys: CameraCoordSys,
        /// Undistorted centers in raster pixels, indexed
        /// `[subpixel_row][subpixel_column][2]` with `x` then `y`.
        /// Empty (shape `[0][0][2]`) in `.per_tile` mode.
        ideal_pixel_centers: ndarray.NDArray(F),
        subpixel_center_map: SubPixelCenterMap,
        render_format: shadertypes.RenderFormat = .mono,
        output_files: []const imageio.ImageSaveOpts = &.{
            .{ .format = .bmp, .file_bits = 8, .scaling = .none },
        },
        ideal_sensor_bounds: ?distortbounds.DistortBounds = null,

        pub fn init(
            allocator: std.mem.Allocator,
            input: CameraInput,
        ) !Self {
            const distort = try cameramodels.DistortModel.init(input.distort);
            const subpixel_center_map = input.subpixel_center_map;
            const actual_sub_sample = if (input.sub_sample == 0)
                @as(u32, 2)
            else
                input.sub_sample;
            const sensor_size = calcSensorSize(
                input.pixels_num,
                input.pixels_size,
            );

            const pos_w = input.pos_world;
            const rot_matrix = input.rot_world.matrix;
            const image_dist: F = pos_w.sub(input.roi_cent_world).vecLen();

            const image_dims = [2]F{
                (image_dist / input.focal_length) * sensor_size[0],
                (image_dist / input.focal_length) * sensor_size[1],
            };

            var cam_to_world_mat = matstack.Mat44F.initIdentity();
            cam_to_world_mat.insertColVec(3, 0, 3, pos_w);
            cam_to_world_mat.insertSubMat(0, 0, 3, 3, rot_matrix);

            const world_to_cam_mat = matstack.Mat44Ops.inv(F, cam_to_world_mat);

            const ideal_pixel_centers = switch (subpixel_center_map) {
                .full_in_mem => blk: {
                    const sub_samp_u: usize = @intCast(actual_sub_sample);
                    const dims = [_]usize{
                        input.pixels_num[1] * sub_samp_u,
                        input.pixels_num[0] * sub_samp_u,
                        2,
                    };
                    break :blk try ndarray.NDArray(F).initFlat(
                        allocator,
                        dims[0..],
                    );
                },
                else => blk: {
                    const dims = [_]usize{ 0, 0, 2 };
                    break :blk try ndarray.NDArray(F).initFlat(
                        allocator,
                        dims[0..],
                    );
                },
            };
            var self = Self{
                .pixels_num = input.pixels_num,
                .render_format = input.render_format,
                .output_files = input.output_files,
                .pixels_size = input.pixels_size,
                .pos_world = input.pos_world,
                .rot_world = input.rot_world,
                .roi_cent_world = input.roi_cent_world,
                .focal_length = input.focal_length,
                .sub_sample = actual_sub_sample,
                .background_value = input.background_value,
                .sensor_size = sensor_size,
                .image_dims = image_dims,
                .image_dist = image_dist,
                .cam_to_world_mat = cam_to_world_mat,
                .world_to_cam_mat = world_to_cam_mat,
                .distort = distort,
                .psf = input.psf,
                .prep_psf = try cameramodels.PreparedPSF.init(
                    allocator,
                    input.psf,
                    actual_sub_sample,
                ),
                .coord_sys = input.coord_sys,
                .ideal_pixel_centers = ideal_pixel_centers,
                .subpixel_center_map = subpixel_center_map,
                .ideal_sensor_bounds = null,
            };
            errdefer self.deinit(allocator);

            switch (subpixel_center_map) {
                .full_in_mem => try self.initFullIdealPixelCenters(),
                .per_tile => {},
            }

            self.ideal_sensor_bounds = if (isNoDistort(self.distort))
                null
            else
                try distortbounds.idealSensorBounds(&self, self.prep_psf.halo_px);

            return self;
        }

        pub fn deinit(
            self: *const Self,
            allocator: std.mem.Allocator,
        ) void {
            var prep_psf = self.prep_psf;
            prep_psf.deinit(allocator);
            allocator.free(self.ideal_pixel_centers.slice);
            self.ideal_pixel_centers.deinit(allocator);
        }

        pub inline fn calcPinholeRasterPoint(
            self: *const Self,
            observed_x_px: F,
            observed_y_px: F,
        ) ![2]F {
            return CameraBackend.calcPinholeRasterPoint(
                self,
                observed_x_px,
                observed_y_px,
            );
        }

        pub inline fn calcPinholeRasterPointSIMD(
            self: *const Self,
            v_observed_x_px: buildconfig.VecSF,
            v_observed_y_px: buildconfig.VecSF,
            v_lane_active: buildconfig.VecSB,
        ) !struct { x: buildconfig.VecSF, y: buildconfig.VecSF } {
            return CameraBackend.calcPinholeRasterPointSIMD(
                self,
                v_observed_x_px,
                v_observed_y_px,
                v_lane_active,
            );
        }

        /// Fill tile-local subpixel rows in two planes (`x` then `y`),
        /// each spanning half the scratch slice with row stride `subpx_tile_size`.
        pub inline fn fillTileIdealCentersPerTile(
            self: *const Self,
            scratch_x_px_min: i32,
            scratch_x_px_max: i32,
            scratch_y_px_min: i32,
            scratch_y_px_max: i32,
            subpx_tile_size: usize,
            ideal_pixel_centers: []F,
        ) !void {
            return CameraBackend.fillTileIdealCentersPerTile(
                self,
                scratch_x_px_min,
                scratch_x_px_max,
                scratch_y_px_min,
                scratch_y_px_max,
                subpx_tile_size,
                ideal_pixel_centers,
            );
        }

        fn initFullIdealPixelCenters(self: *Self) !void {
            const sub_samp_u: usize = @intCast(self.sub_sample);
            const sub_samp_f = @as(F, @floatFromInt(self.sub_sample));
            const subpx_step = 1.0 / sub_samp_f;
            const subpx_off = 0.5 / sub_samp_f;

            const slice = self.ideal_pixel_centers.slice;
            const stride_y = self.ideal_pixel_centers.strides[0];
            const stride_x = self.ideal_pixel_centers.strides[1];

            for (0..self.pixels_num[1] * sub_samp_u) |jj| {
                const subpx_y_f = @as(F, @floatFromInt(jj)) *
                    subpx_step + subpx_off;
                const row_off = jj * stride_y;

                for (0..self.pixels_num[0] * sub_samp_u) |ii| {
                    const subpx_x_f = @as(F, @floatFromInt(ii)) *
                        subpx_step + subpx_off;
                    const ideal = try self.calcPinholeRasterPoint(
                        subpx_x_f,
                        subpx_y_f,
                    );
                    const col_off = ii * stride_x;
                    slice[row_off + col_off + 0] = ideal[0];
                    slice[row_off + col_off + 1] = ideal[1];
                }
            }
        }

        pub fn calcFocalPx(self: *const Self) struct { fx: F, fy: F } {
            return .{
                .fx = self.focal_length / self.pixels_size[0],
                .fy = self.focal_length / self.pixels_size[1],
            };
        }

        pub fn calcRasterOffsets(self: *const Self) struct { x_off: F, y_off: F } {
            return .{
                .x_off = 0.5 * @as(F, @floatFromInt(self.pixels_num[0])),
                .y_off = 0.5 * @as(F, @floatFromInt(self.pixels_num[1])),
            };
        }
    };
}

fn calcSensorSize(pixels_num: [2]u32, pixels_size: [2]F) [2]F {
    return .{
        @as(F, @floatFromInt(pixels_num[0])) * pixels_size[0],
        @as(F, @floatFromInt(pixels_num[1])) * pixels_size[1],
    };
}

/// Selects the limiting axis when positioning a camera to fit projected bounds.
pub const FrameFitMode = enum(u32) {
    /// Fit both axes, using the farther of the two fit distances.
    contain = 0,
    /// Fill both axes, allowing one axis to extend beyond the frame.
    cover = 1,
    /// Fit the width only.
    horizontal = 2,
    /// Fit the height only.
    vertical = 3,
};

/// World-space position and camera-to-world rotation of a camera on an orbit.
pub const OrbitCam = struct {
    pos: vecstack.Vec3F,
    rot: rotation.Rotation,
};

/// World-space positions and camera-to-world rotations of the two cameras in a stereo pair.
pub const StereoPairPosRot = struct {
    cam0_pos: vecstack.Vec3F,
    cam0_rot: rotation.Rotation,
    cam1_pos: vecstack.Vec3F,
    cam1_rot: rotation.Rotation,
};

/// Sensor and projection measurements at the camera's region-of-interest plane.
pub const CameraPlaneMetrics = struct {
    sensor_size: [2]F,
    focal_px: [2]F,
    principal_point_px: [2]F,
    roi_plane_dist: F,
    roi_plane_size: [2]F,
    avg_leng_per_pixel: F,
    avg_pixel_per_leng: F,
};
