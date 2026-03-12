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

    // Only generate Tri6 as requested
    const mesh_types = [_]gengold.MeshType{ .tri6 };
    const interp_types = [_]gengold.texops.InterpType{ .cubic_lut_lerp };
    const pixel_num = [_]u32{ 800, 500 };

    const gold_dir = "out-edge";
    const data_dir = "data-edge";

    std.debug.print("Rendering Rotated Tri6 Edge Cases to out-edge/...\n", .{});
    
    // Render tri6_bulgein_rot (All edges bulge in)
    // Render tri6_bulgeout_rot (All edges bulge out)
    try gengold.runGenerationExt(
        allocator, io, "bulgein_rot", &mesh_types, 1.1, texture, pixel_num, &interp_types, 
        gold_dir, data_dir
    );

    try gengold.runGenerationExt(
        allocator, io, "bulgeout_rot", &mesh_types, 1.1, texture, pixel_num, &interp_types, 
        gold_dir, data_dir
    );
    
    std.debug.print("Done.\n", .{});
}
