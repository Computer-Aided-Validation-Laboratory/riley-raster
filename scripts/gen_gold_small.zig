const std = @import("std");
const gengold = @import("gengold.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    // Load original using C loader once, then save as simple TIFF
    // and reload using our simple loader to ensure compatibility.
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
        const MatSlice = @import("../src/zigraster/zig/matslice.zig").MatSlice;
        const temp_mat = MatSlice(f64).init(mat_mem, tex_orig.rows_n, tex_orig.cols_n);

        const out_dir = std.Io.Dir.cwd();
        try gengold.iio.saveTIFF(io, out_dir, "temp-test/speckle-simple.tiff", &temp_mat, 8);
        break :blk try gengold.iio.loadImage(
            allocator, io, "temp-test/speckle-simple.tiff", .tiff, u8, 1
        );
    };
    defer texture.deinit(allocator);

    const mesh_types = [_]gengold.MeshType{ 
        .tri3, .tri6, .quad4ibi, .quad4newton, .quad8, .quad9 
    };
    const interp_types = std.enums.values(gengold.texops.InterpType);

    const pixel_num = [_]u32{ 320, 200 };

    const gold_dir = "gold-small";
    const data_dir = "data-small";

    std.debug.print("Generating ALL Small Gold Data...\n", .{});

    std.debug.print("Single Element Cases...\n", .{});
    try gengold.runGenerationExt(
        allocator, io, "single", &mesh_types, 1.1, texture, pixel_num, interp_types, 
        gold_dir, data_dir
    );

    std.debug.print("Full Screen Cases...\n", .{});
    try gengold.runGenerationExt(
        allocator, io, "full", &mesh_types, 1.0, texture, pixel_num, interp_types, 
        gold_dir, data_dir
    );
    
    std.debug.print("Done.\n", .{});
}
