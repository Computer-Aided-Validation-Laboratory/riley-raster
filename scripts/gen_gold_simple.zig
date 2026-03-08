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
    
    std.debug.print("Generating Single Element Gold Data...\n", .{});
    try gengold.runGeneration(allocator, io, "single", &mesh_types, 1.1, texture);
    
    std.debug.print("Generating Full Screen Gold Data...\n", .{});
    try gengold.runGeneration(allocator, io, "full", &mesh_types, 1.0, texture);
    
    std.debug.print("Done.\n", .{});
}
