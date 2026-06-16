// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const orch = @import("orchestration.zig");
const riley = @import("../riley/zig/riley.zig");
const rastcfg = @import("../riley/zig/rasterconfig.zig");
const meshio = @import("../riley/zig/meshio.zig");
const iio = @import("../riley/zig/imageio.zig");
const csvio = @import("../riley/zig/csvio.zig");
const NDArray = @import("../riley/zig/ndarray.zig").NDArray;
const MeshInput = @import("../riley/zig/meshops.zig").MeshInput;
const cammod = @import("../riley/zig/camera.zig");
const cameraio_mod = @import("../riley/zig/cameraio.zig");
const cameraops_mod = @import("../riley/zig/cameraops.zig");
const Rotation = @import("../riley/zig/rotation.zig").Rotation;

pub const CameraInput = cammod.CameraInput;
pub const cameraio = cameraio_mod;
pub const cameraops = cameraops_mod;
pub const StereoPairInput = cammod.StereoPairInput;

pub const data_dir = "data/calplate/tri3_calplate/";
pub const out_dir_test0 = "./out/test0-stereo";
pub const out_dir_test1 = "./out/test1-stereo";
pub const out_dir_diff = "./out/test0-test1-stereo";

pub const pixel_num = [2]u32{ 2464, 2056 };
pub const pixel_size = [2]f64{ 3.45e-6, 3.45e-6 };
pub const focal_length: f64 = 50.0e-3;
pub const fov_scale: f64 = 1.5;
pub const sub_sample: u8 = 2;
pub const stereo_angle_deg: f64 = 45.0;

pub const sim_data_name = "stereoplate";

pub fn loadPlateSimData(
    allocator: std.mem.Allocator,
    io: std.Io,
) !meshio.SimData {
    return try meshio.loadSimData(
        allocator,
        io,
        data_dir ++ "coords.csv",
        data_dir ++ "connect.csv",
        null,
        null,
    );
}

pub fn buildConstantMeshInput(sim_data: meshio.SimData) MeshInput {
    return .{
        .mesh_type = .tri3,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = null,
        .shader = .{ .func = .{
            .uvs = null,
            .coord_mode = .parametric,
            .builtin = .constant,
            .params = .{
                .output_scale = 0.0,
                .output_offset = 1.0,
            },
            .bits = 8,
            .scaling = .auto,
            .normal_type = .none,
        } },
    };
}

pub fn buildAutoStereoPair(coords: *const meshio.Coords) StereoPairInput {
    const roi_pos = cameraops.roiCentFromCoords(coords);
    const cam0_rot = Rotation.init(0.0, 0.0, 0.0);
    const cam1_rot = Rotation.init(
        0.0,
        std.math.degreesToRadians(stereo_angle_deg),
        0.0,
    );

    const cam0_pos = cameraops.posFillFrameFromRot(
        coords,
        pixel_num,
        pixel_size,
        focal_length,
        cam0_rot,
        fov_scale,
    );
    const cam1_pos = cameraops.posFillFrameFromRot(
        coords,
        pixel_num,
        pixel_size,
        focal_length,
        cam1_rot,
        fov_scale,
    );

    return .{
        .cameras = .{
            .{
                .pixels_num = pixel_num,
                .pixels_size = pixel_size,
                .pos_world = cam0_pos,
                .rot_world = cam0_rot,
                .roi_cent_world = roi_pos,
                .focal_length = focal_length,
                .sub_sample = sub_sample,
            },
            .{
                .pixels_num = pixel_num,
                .pixels_size = pixel_size,
                .pos_world = cam1_pos,
                .rot_world = cam1_rot,
                .roi_cent_world = roi_pos,
                .focal_length = focal_length,
                .sub_sample = sub_sample,
            },
        },
    };
}

pub fn renderStereoPlate(
    allocator: std.mem.Allocator,
    io: std.Io,
    stereo_pair: StereoPairInput,
    out_dir_root: []const u8,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    var sim_data = try loadPlateSimData(aa, io);
    defer sim_data.deinit(aa);

    const mesh_input = buildConstantMeshInput(sim_data);
    var out_dir = try orch.openDirEnsured(io, out_dir_root);
    defer out_dir.close(io);
    try cameraio.saveStereoPair(io, out_dir, "stereo_data.csv", stereo_pair);

    const config = rastcfg.RasterConfig{
        .render_mode = .offline,
        .total_threads = 1,
        .frame_batch_size_per_group = 1,
        .max_geom_jobs_in_flight_per_group = 1,
        .max_geom_workers_per_job = 1,
        .geom_scheduling_mode = .spread,
        .max_raster_workers_per_job = 1,
        .save_strategy = .disk,
        .background_value = 0.0,
        .image_save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .bmp, .bits = 8, .scaling = .auto },
            .{ .format = .csv, .bits = null, .scaling = .none },
        },
        .report = .bench,
    };
    const render_groups = [_]riley.RenderGroupSpec{
        .{ .io = io, .workers = 1 },
    };
    _ = try riley.raster(
        aa,
        &render_groups,
        &stereo_pair.cameras,
        &[_]MeshInput{mesh_input},
        config,
        out_dir_root,
    );
}

fn loadScalarImageCsv(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
) !NDArray(f64) {
    var csv = try csvio.loadScalarCsv2D(allocator, io, path);
    defer {
        allocator.free(csv.slice);
        csv.deinit(allocator);
    }

    var image = try NDArray(f64).initFlat(
        allocator,
        &[_]usize{ 1, csv.dims[0], csv.dims[1] },
    );
    for (0..csv.dims[0]) |rr| {
        for (0..csv.dims[1]) |cc| {
            image.set(&[_]usize{ 0, rr, cc }, csv.get(&[_]usize{ rr, cc }));
        }
    }
    return image;
}

pub fn compareStereoOutputs(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir_a_path: []const u8,
    dir_b_path: []const u8,
    diff_dir_path: []const u8,
) !f64 {
    var diff_dir = try orch.openDirEnsured(io, diff_dir_path);
    defer diff_dir.close(io);

    var max_abs_all: f64 = 0.0;
    for (0..2) |cam_idx| {
        const path_a = try std.fmt.allocPrint(
            allocator,
            "{s}/cam{d}_frame0_field0.csv",
            .{ dir_a_path, cam_idx },
        );
        const path_b = try std.fmt.allocPrint(
            allocator,
            "{s}/cam{d}_frame0_field0.csv",
            .{ dir_b_path, cam_idx },
        );
        var img_a = try loadScalarImageCsv(allocator, io, path_a);
        defer {
            allocator.free(img_a.slice);
            img_a.deinit(allocator);
        }
        var img_b = try loadScalarImageCsv(allocator, io, path_b);
        defer {
            allocator.free(img_b.slice);
            img_b.deinit(allocator);
        }

        if (!std.mem.eql(usize, img_a.dims, img_b.dims)) {
            return error.ImageDimsMismatch;
        }

        var diff = try NDArray(f64).initFlat(allocator, img_a.dims);
        defer {
            allocator.free(diff.slice);
            diff.deinit(allocator);
        }
        var absdiff = try NDArray(f64).initFlat(allocator, img_a.dims);
        defer {
            allocator.free(absdiff.slice);
            absdiff.deinit(allocator);
        }

        var max_abs_cam: f64 = 0.0;
        for (0..img_a.slice.len) |ii| {
            const d = img_b.slice[ii] - img_a.slice[ii];
            diff.slice[ii] = d;
            absdiff.slice[ii] = @abs(d);
            max_abs_cam = @max(max_abs_cam, absdiff.slice[ii]);
        }
        max_abs_all = @max(max_abs_all, max_abs_cam);

        const diff_base = try std.fmt.allocPrint(
            allocator,
            "cam{d}_diff",
            .{cam_idx},
        );
        const absdiff_base = try std.fmt.allocPrint(
            allocator,
            "cam{d}_absdiff",
            .{cam_idx},
        );
        try iio.saveImage(
            io,
            diff_dir,
            diff_base,
            &diff,
            0,
            .{
                .format = .csv,
                .bits = null,
                .scaling = .none,
            },
        );
        try iio.saveImage(
            io,
            diff_dir,
            absdiff_base,
            &absdiff,
            0,
            .{
                .format = .csv,
                .bits = null,
                .scaling = .none,
            },
        );
        try iio.saveImage(
            io,
            diff_dir,
            absdiff_base,
            &absdiff,
            0,
            .{
                .format = .bmp,
                .bits = 8,
                .scaling = .{ .fixed = .{ 0.0, @max(max_abs_cam, 1e-15) } },
            },
        );
    }

    return max_abs_all;
}
