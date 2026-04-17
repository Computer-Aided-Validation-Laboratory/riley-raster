// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const rops = @import("zraster/zig/rasterops.zig");
const hull = @import("zraster/zig/hull.zig");
const Camera = @import("zraster/zig/camera.zig").Camera;
const CameraOps = @import("zraster/zig/camera.zig").CameraOps;
const NDArray = @import("zraster/zig/ndarray.zig").NDArray;
const meshio = @import("zraster/zig/meshio.zig");
const mr = @import("zraster/zig/meshraster.zig");
const Vec3f = @import("zraster/zig/vecstack.zig").Vec3f;
const Rotation = @import("zraster/zig/rotation.zig").Rotation;
const csvio = @import("zraster/zig/csvio.zig");

fn saveNDArrayToCSV(io: std.Io, arr: *const NDArray(f64), path: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    const parent_path = std.fs.path.dirname(path) orelse ".";
    const file_name = std.fs.path.basename(path);
    var out_dir = try cwd.openDir(io, parent_path, .{});
    defer out_dir.close(io);

    if (arr.dims.len == 3) {
        const d0 = arr.dims[0];
        const d1 = arr.dims[1];
        const d2 = arr.dims[2];

        const SaveCtx = struct {
            fn getVal(ctx: *const NDArray(f64), row: usize, col: usize) f64 {
                const d2 = ctx.dims[2];
                const elem = row / d2;
                const node = row % d2;
                return ctx.get(&[_]usize{ elem, col, node });
            }
        };

        try csvio.saveScalarGridCSV(
            io,
            out_dir,
            file_name,
            d0 * d2,
            d1,
            arr,
            SaveCtx.getVal,
        );
    }
}

fn processCase(
    allocator: std.mem.Allocator,
    io: std.Io,
    comptime N: usize,
    data_name: []const u8,
) !void {
    const aa = allocator;
    const data_path = try std.fmt.allocPrint(aa, "data-edge/{s}", .{data_name});
    const coord_path = try std.fmt.allocPrint(aa, "{s}/coords.csv", .{data_path});
    const connect_path = try std.fmt.allocPrint(aa, "{s}/connectivity.csv", .{data_path});
    const field_paths = [_][]const u8{
        try std.fmt.allocPrint(aa, "{s}/field_disp_x.csv", .{data_path}),
        try std.fmt.allocPrint(aa, "{s}/field_disp_y.csv", .{data_path}),
        try std.fmt.allocPrint(aa, "{s}/field_disp_z.csv", .{data_path}),
    };
    var sim_data = try meshio.loadSimData(
        aa,
        io,
        coord_path,
        connect_path,
        &field_paths,
        null,
    );

    var elem_coords = try mr.prepareCoords(aa, &sim_data.coords, &sim_data.connect);

    const pixel_num = [_]u32{ 800, 500 };
    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const fov_scale = 1.1;
    const rot = Rotation.init(0, 0, 0);

    const cam_pos = CameraOps.posFillFrameFromRot(
        &sim_data.coords,
        pixel_num,
        pixel_size,
        focal_leng,
        rot,
        fov_scale,
    );
    const camera = Camera.init(
        pixel_num,
        pixel_size,
        cam_pos,
        rot,
        Vec3f.initZeros(),
        focal_leng,
        2,
    );

    try rops.transformElemsClipPxLengSIMD(N, f64, &camera, 0, &elem_coords);

    const x_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[0]));
    const y_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[1]));
    var raster_coords = try NDArray(f64).initFlat(aa, &[_]usize{ 1, 2, N });
    for (0..N) |ii| {
        const lx = elem_coords.get(&[_]usize{ 0, 0, ii }) /
            elem_coords.get(&[_]usize{ 0, 2, ii }) + x_off;
        const ly = elem_coords.get(&[_]usize{ 0, 1, ii }) /
            elem_coords.get(&[_]usize{ 0, 2, ii }) + y_off;
        raster_coords.set(&[_]usize{ 0, 0, ii }, lx);
        raster_coords.set(&[_]usize{ 0, 1, ii }, ly);
    }

    const NH = if (N == 6) 6 else 8;
    var raster_hull = try NDArray(f64).initFlat(aa, &[_]usize{ 1, 2, NH });
    try hull.buildAdaptiveHulls(N, &camera, 0, &elem_coords, &raster_hull);

    const hull_csv_path = try std.fmt.allocPrint(
        aa,
        "scripts/hull-diags/{s}_hull.csv",
        .{data_name},
    );
    const coords_csv_path = try std.fmt.allocPrint(
        aa,
        "scripts/hull-diags/{s}_rastercoords.csv",
        .{data_name},
    );

    try saveNDArrayToCSV(io, &raster_hull, hull_csv_path);
    try saveNDArrayToCSV(io, &raster_coords, coords_csv_path);
}

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    try processCase(allocator, io, 6, "tri6_bulgein_rot");
    try processCase(allocator, io, 6, "tri6_bulgeout_rot");
    try processCase(allocator, io, 6, "tri6_vertbulge");

    try processCase(allocator, io, 8, "quad8_bulgein_rot");
    try processCase(allocator, io, 8, "quad8_bulgeout_rot");
    try processCase(allocator, io, 8, "quad8_vertbulge");

    try processCase(allocator, io, 9, "quad9_bulgein_rot");
    try processCase(allocator, io, 9, "quad9_bulgeout_rot");
    try processCase(allocator, io, 9, "quad9_vertbulge");

    std.debug.print("Wrote hull CSVs to scripts/hull-diags/\n", .{});
}
