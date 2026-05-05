// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const cam = @import("zraster/zig/camera.zig");
const iio = @import("zraster/zig/imageio.zig");
const meshio = @import("zraster/zig/meshio.zig");
const mo = @import("zraster/zig/meshops.zig");
const orch = @import("common/orchestration.zig");
const tcfg = @import("common/testconfig.zig");
const vconst = @import("common/verifconstants.zig");
const verif = @import("common/verif.zig");
const zraster = @import("zraster/zig/zraster.zig");

const pixel_num = [_]u32{ 640, 400 };
const fov_scale: f64 = 1.01;

const CentroidStats = struct {
    ideal_x: f64,
    ideal_y: f64,
    calc_x: f64,
    calc_y: f64,
    diff_x: f64,
    diff_y: f64,
    dist: f64,
};

const ScalarMap = struct {
    rows_num: usize,
    cols_num: usize,
    vals: []f64,
};

fn buildFrameCoords(
    allocator: std.mem.Allocator,
    sim_data: *const meshio.SimData,
    frame_idx: usize,
) !meshio.Coords {
    var coords = try meshio.Coords.initAlloc(allocator, sim_data.coords.mat.rows_num);

    for (0..sim_data.coords.mat.rows_num) |nn| {
        coords.mat.set(nn, 0, sim_data.coords.x(nn));
        coords.mat.set(nn, 1, sim_data.coords.y(nn));
        coords.mat.set(nn, 2, sim_data.coords.z(nn));

        if (sim_data.field) |field| {
            coords.mat.set(nn, 0, coords.mat.get(nn, 0) + field.array.get(&[_]usize{ frame_idx, nn, 0 }));
            coords.mat.set(nn, 1, coords.mat.get(nn, 1) + field.array.get(&[_]usize{ frame_idx, nn, 1 }));
            coords.mat.set(nn, 2, coords.mat.get(nn, 2) + field.array.get(&[_]usize{ frame_idx, nn, 2 }));
        }
    }

    return coords;
}

fn extractScalarMap(
    allocator: std.mem.Allocator,
    image_arr: *const @import("zraster/zig/ndarray.zig").NDArray(f64),
) !ScalarMap {
    const rows_num = if (image_arr.dims.len == 5) image_arr.dims[3] else image_arr.dims[2];
    const cols_num = if (image_arr.dims.len == 5) image_arr.dims[4] else image_arr.dims[3];

    const vals = try allocator.alloc(f64, rows_num * cols_num);
    for (0..rows_num) |rr| {
        for (0..cols_num) |cc| {
            vals[rr * cols_num + cc] = if (image_arr.dims.len == 5)
                image_arr.get(&[_]usize{ 0, 0, 0, rr, cc })
            else
                image_arr.get(&[_]usize{ 0, 0, rr, cc });
        }
    }

    return .{
        .rows_num = rows_num,
        .cols_num = cols_num,
        .vals = vals,
    };
}

fn calcCentroidStats(
    camera_input: cam.CameraInput,
    rows_num: usize,
    cols_num: usize,
    vals: []const f64,
) !CentroidStats {
    const ideal_x = 0.5 * @as(f64, @floatFromInt(camera_input.pixels_num[0]));
    const ideal_y = 0.5 * @as(f64, @floatFromInt(camera_input.pixels_num[1]));

    var sum_w: f64 = 0.0;
    var sum_x: f64 = 0.0;
    var sum_y: f64 = 0.0;

    for (0..rows_num) |rr| {
        for (0..cols_num) |cc| {
            const weight = vals[rr * cols_num + cc];
            if (!(weight > 0.0)) continue;

            const x = @as(f64, @floatFromInt(cc)) + 0.5;
            const y = @as(f64, @floatFromInt(rr)) + 0.5;
            sum_w += weight;
            sum_x += x * weight;
            sum_y += y * weight;
        }
    }

    if (sum_w == 0.0) return error.EmptySilhouette;

    const calc_x = sum_x / sum_w;
    const calc_y = sum_y / sum_w;
    const diff_x = calc_x - ideal_x;
    const diff_y = calc_y - ideal_y;

    return .{
        .ideal_x = ideal_x,
        .ideal_y = ideal_y,
        .calc_x = calc_x,
        .calc_y = calc_y,
        .diff_x = diff_x,
        .diff_y = diff_y,
        .dist = @sqrt(diff_x * diff_x + diff_y * diff_y),
    };
}

fn writeStatsCsv(
    io: std.Io,
    out_dir: std.Io.Dir,
    file_name: []const u8,
    stats: CentroidStats,
) !void {
    const file = try out_dir.createFile(io, file_name, .{});
    defer file.close(io);

    var write_buf: [1024]u8 = undefined;
    var writer_buf = file.writer(io, &write_buf);
    const writer = &writer_buf.interface;

    try writer.writeAll("cent_ideal_x,cent_ideal_y,cent_calc_x,cent_calc_y,diff_x,diff_y,dist\n");
    try writer.print(
        "{d:.17},{d:.17},{d:.17},{d:.17},{d:.17},{d:.17},{d:.17}\n",
        .{
            stats.ideal_x,
            stats.ideal_y,
            stats.calc_x,
            stats.calc_y,
            stats.diff_x,
            stats.diff_y,
            stats.dist,
        },
    );
    try writer.flush();
}

fn referenceFrameIndex(
    case_name: []const u8,
    time_steps: usize,
) usize {
    if (std.mem.eql(u8, case_name, "bulge") or std.mem.eql(u8, case_name, "tan")) {
        return time_steps / 2;
    }
    if (std.mem.eql(u8, case_name, "stretch") or std.mem.eql(u8, case_name, "shear")) {
        return time_steps - 1;
    }
    return 0;
}

fn renderScalarMap(
    render_allocator: std.mem.Allocator,
    out_allocator: std.mem.Allocator,
    io: std.Io,
    case_spec: vconst.DistortCase,
    connect: meshio.Connect,
    frame_coords: meshio.Coords,
    camera_input: cam.CameraInput,
    config: @TypeOf(tcfg.getRasterConfig(.preview)),
) !ScalarMap {
    const mesh_input = mo.MeshInput{
        .mesh_type = case_spec.mesh_type,
        .coords = frame_coords,
        .connect = connect,
        .disp = null,
        .shader = .{
            .tex_func = .{
                .uvs = null,
                .builtin = .constant,
                .normal_type = .none,
            },
        },
    };

    const result = (try zraster.rasterAllFrames(
        render_allocator,
        io,
        &[_]cam.CameraInput{camera_input},
        &[_]mo.MeshInput{mesh_input},
        config,
        null,
        null,
    )) orelse return error.NoResult;

    return try extractScalarMap(out_allocator, &result);
}

fn runDistortCase(
    allocator: std.mem.Allocator,
    io: std.Io,
    case_spec: vconst.DistortCase,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const sim_data = try orch.loadData(aa, io, case_spec.data_dir);
    const time_steps = if (sim_data.field) |field| field.getTimeN() else 1;
    const ref_frame_idx = referenceFrameIndex(case_spec.case_name, time_steps);
    const ref_coords = try buildFrameCoords(aa, &sim_data, ref_frame_idx);
    const base_camera = try orch.initCameraForCoords(
        aa,
        &ref_coords,
        pixel_num,
        fov_scale,
    );
    const base_camera_input = base_camera.toInput();

    const out_dir_path = try std.fmt.allocPrint(
        aa,
        "{s}/b_{s}_{s}",
        .{
            vconst.output_dir_name,
            orch.meshDataName(case_spec.mesh_type),
            case_spec.case_name,
        },
    );
    var out_dir = try orch.openDirEnsured(io, out_dir_path);
    defer out_dir.close(io);

    var config = tcfg.getRasterConfig(.preview);
    config.save_strategy = .memory;

    for (0..time_steps) |frame_idx| {
        var frame_arena = std.heap.ArenaAllocator.init(allocator);
        defer frame_arena.deinit();
        const fa = frame_arena.allocator();

        const frame_coords = try buildFrameCoords(fa, &sim_data, frame_idx);
        const scalar_map = try renderScalarMap(
            fa,
            allocator,
            io,
            case_spec,
            sim_data.connect,
            frame_coords,
            base_camera_input,
            config,
        );
        defer allocator.free(scalar_map.vals);

        var base_name_buf: [128]u8 = undefined;
        const base_name = try iio.formatFrameFieldBaseName(
            &base_name_buf,
            0,
            frame_idx,
            0,
            1,
        );

        const csv_name = try std.fmt.allocPrint(aa, "{s}.csv", .{base_name});
        try verif.writeScalarMapCsv(
            io,
            out_dir,
            csv_name,
            scalar_map.rows_num,
            scalar_map.cols_num,
            scalar_map.vals,
        );
        try verif.writeScalarMapBmp(
            allocator,
            io,
            out_dir,
            base_name,
            scalar_map.rows_num,
            scalar_map.cols_num,
            scalar_map.vals,
        );
        const stats = calcCentroidStats(
            base_camera_input,
            scalar_map.rows_num,
            scalar_map.cols_num,
            scalar_map.vals,
        ) catch CentroidStats{
            .ideal_x = 0.5 * @as(f64, @floatFromInt(base_camera_input.pixels_num[0])),
            .ideal_y = 0.5 * @as(f64, @floatFromInt(base_camera_input.pixels_num[1])),
            .calc_x = std.math.nan(f64),
            .calc_y = std.math.nan(f64),
            .diff_x = std.math.nan(f64),
            .diff_y = std.math.nan(f64),
            .dist = std.math.nan(f64),
        };
        const stats_name = try std.fmt.allocPrint(aa, "{s}_stats.csv", .{base_name});
        try writeStatsCsv(io, out_dir, stats_name, stats);

        std.debug.print(
            "b_{s}_{s} frame {d}: centroid dist={e:.6}\n",
            .{
                orch.meshDataName(case_spec.mesh_type),
                case_spec.case_name,
                frame_idx,
                stats.dist,
            },
        );
    }
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var root_dir = try orch.openDirEnsured(io, vconst.output_dir_name);
    defer root_dir.close(io);

    for (vconst.distort_cases) |case_spec| {
        try runDistortCase(allocator, io, case_spec);
    }

    std.debug.print("Done.\n", .{});
}
