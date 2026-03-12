const std = @import("std");
const gengold = @import("common/gengold.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const texture = blk: {
        const tex_orig = try gengold.iio.CLoadTIFF(
            allocator, io, "texture/speckle.tiff", u8, 1
        );
        defer tex_orig.deinit(allocator);

        const mat_size = tex_orig.rows_n * tex_orig.cols_n;
        const mat_mem = try allocator.alloc(f64, mat_size);
        defer allocator.free(mat_mem);
        for (0..mat_size) |i| {
            mat_mem[i] = @as(f64, @floatFromInt(tex_orig.pixels[i].channels[0]));
        }
        const MatSlice = @import("zigraster/zig/matslice.zig").MatSlice;
        const temp_mat = MatSlice(f64).init(mat_mem, tex_orig.rows_n, tex_orig.cols_n);

        const out_dir = std.Io.Dir.cwd();
        try gengold.iio.saveTIFF(io, out_dir, "temp-test/speckle-simple.tiff", &temp_mat, 8);
        break :blk try gengold.iio.loadImage(
            allocator, io, "temp-test/speckle-simple.tiff", .tiff, u8, 1
        );
    };
    defer texture.deinit(allocator);

    const interp_types = [_]gengold.texops.InterpType{ .cubic_lut_lerp };
    const pixel_num = [_]u32{ 800, 500 };
    const gold_dir = "out-edge-bulgein";
    const data_dir = "data-edge";

    const config = gengold.specraster.RasterConfig{
        .save_opt = .disk,
        .save_formats = &[_]gengold.iio.ImageFormat{ .bmp },
        .tile_size = 16,
        .report = .perf,
        .perf_opts = .{
            .formats = &[_]gengold.iio.ImageFormat{ .bmp, .csv },
            .save_iteration_map = true,
            .save_tile_timing_map = false,
            .save_tile_density_map = false,
            .save_tile_occupancy_map = false,
            .save_depth_map = false,
            .save_earlyout_map = true,
            .save_pixel_occupancy_map = true,
        },
    };

    const mt_tri6 = [_]gengold.MeshType{ .tri6 };
    const mt_quad8 = [_]gengold.MeshType{ .quad8 };
    const mt_quad9 = [_]gengold.MeshType{ .quad9 };

    try gengold.runGenerationExt(allocator, io, "bulgein_rot", &mt_tri6, 1.1, texture, pixel_num, &interp_types, gold_dir, data_dir, config);
    try gengold.runGenerationExt(allocator, io, "bulgein_rot", &mt_quad8, 1.1, texture, pixel_num, &interp_types, gold_dir, data_dir, config);
    try gengold.runGenerationExt(allocator, io, "bulgein_rot", &mt_quad9, 1.1, texture, pixel_num, &interp_types, gold_dir, data_dir, config);
}
