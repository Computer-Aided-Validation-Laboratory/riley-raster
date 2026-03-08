const std = @import("std");
const gengold = @import("gengold.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const texture = try gengold.texio.loadTIFF(allocator, io, "texture/speckle.tiff", u8, 1);
    defer texture.deinit(allocator);

    const mesh_types = [_]gengold.MeshType{ .tri3, .tri6, .quad4ibi, .quad4newton, .quad8, .quad9 };
    const interp_types = std.enums.values(gengold.textureinterp.InterpolationType);
    const pixel_num = [_]u32{ 160, 100 };
    const gold_dir = "gold-small";
    const data_dir = "data-small";

    std.debug.print("Generating ALL Small Gold Data (160x100)...\n", .{});
    
    std.debug.print("Single Element Cases...\n", .{});
    try gengold.runGenerationExt(allocator, io, "single", &mesh_types, 1.1, texture, pixel_num, interp_types, gold_dir, data_dir);
    
    std.debug.print("Full Screen Cases...\n", .{});
    try gengold.runGenerationExt(allocator, io, "full", &mesh_types, 1.0, texture, pixel_num, interp_types, gold_dir, data_dir);
    
    std.debug.print("Done.\n", .{});
}
