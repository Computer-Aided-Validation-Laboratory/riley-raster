const std = @import("std");
const rops = @import("zigraster/zig/rasterops.zig");
const hull = @import("zigraster/zig/hull.zig");
const Camera = @import("zigraster/zig/camera.zig").Camera;
const CameraOps = @import("zigraster/zig/camera.zig").CameraOps;
const NDArray = @import("zigraster/zig/ndarray.zig").NDArray;
const meshio = @import("zigraster/zig/meshio.zig");
const mr = @import("zigraster/zig/meshraster.zig");
const Vec3f = @import("zigraster/zig/vecstack.zig").Vec3f;
const Rotation = @import("zigraster/zig/rotation.zig").Rotation;

fn saveNDArrayToCSV(io: std.Io, arr: *const NDArray(f64), path: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    var file = try cwd.createFile(io, path, .{});
    defer file.close(io);
    
    var write_buf: [4096]u8 = undefined;
    var file_writer = file.writer(io, &write_buf);
    const writer = &file_writer.interface;

    if (arr.dims.len == 3) {
        const d0 = arr.dims[0];
        const d1 = arr.dims[1];
        const d2 = arr.dims[2];
        for (0..d0) |ee| {
            for (0..d2) |nn| {
                for (0..d1) |ff| {
                    try writer.print("{d}", .{arr.get(&[_]usize{ ee, ff, nn })});
                    if (ff < d1 - 1) try writer.print(",", .{});
                }
                try writer.print("\n", .{});
            }
        }
    }
    try file_writer.flush();
}

fn processCase(allocator: std.mem.Allocator, io: std.Io, comptime N: usize, data_name: []const u8) !void {
    const aa = allocator;
    const data_path = try std.fmt.allocPrint(aa, "data-edge/{s}", .{data_name});
    const coord_path = try std.fmt.allocPrint(aa, "{s}/coords.csv", .{data_path});
    const connect_path = try std.fmt.allocPrint(aa, "{s}/connectivity.csv", .{data_path});
    const field_paths = [_][]const u8{
        try std.fmt.allocPrint(aa, "{s}/field_disp_x.csv", .{data_path}),
        try std.fmt.allocPrint(aa, "{s}/field_disp_y.csv", .{data_path}),
        try std.fmt.allocPrint(aa, "{s}/field_disp_z.csv", .{data_path}),
    };
    var sim_data = try meshio.loadSimData(aa, io, coord_path, connect_path, &field_paths, null);

    var elem_coords = try mr.prepareCoords(aa, &sim_data.coords, &sim_data.connect);

    const pixel_num = [_]u32{ 800, 500 };
    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const fov_scale = 1.1;
    const rot = Rotation.init(0, 0, 0);

    const cam_pos = CameraOps.posFillFrameFromRot(
        &sim_data.coords, pixel_num, pixel_size, focal_leng, rot, fov_scale,
    );
    const camera = Camera.init(pixel_num, pixel_size, cam_pos, rot, Vec3f.initZeros(), focal_leng, 2);

    try rops.transformElemsClipPxLengSIMD(N, f64, &camera, 0, &elem_coords);

    const x_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[0]));
    const y_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[1]));
    var raster_coords = try NDArray(f64).initFlat(aa, &[_]usize{ 1, 2, N });
    for (0..N) |ii| {
        const lx = elem_coords.get(&[_]usize{ 0, 0, ii }) / elem_coords.get(&[_]usize{ 0, 2, ii }) + x_off;
        const ly = elem_coords.get(&[_]usize{ 0, 1, ii }) / elem_coords.get(&[_]usize{ 0, 2, ii }) + y_off;
        raster_coords.set(&[_]usize{ 0, 0, ii }, lx);
        raster_coords.set(&[_]usize{ 0, 1, ii }, ly);
    }

    const NH = if (N == 6) 6 else 8;
    var raster_hull = try NDArray(f64).initFlat(aa, &[_]usize{ 1, 2, NH });
    try hull.buildAdaptiveHulls(N, &camera, 0, &elem_coords, &raster_hull);

    const hull_csv_path = try std.fmt.allocPrint(aa, "scripts/hull-diags/{s}_hull.csv", .{data_name});
    const coords_csv_path = try std.fmt.allocPrint(aa, "scripts/hull-diags/{s}_rastercoords.csv", .{data_name});

    try saveNDArrayToCSV(io, &raster_hull, hull_csv_path);
    try saveNDArrayToCSV(io, &raster_coords, coords_csv_path);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
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
