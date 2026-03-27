const std = @import("std");
const common = @import("common/tests.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const texture = try common.iio.loadImage(
        allocator, io, "texture/speckle-simple.tiff", .tiff, u8, 1
    );
    defer texture.deinit(allocator);

    const mesh_types = [_]common.MeshType{ 
        .tri3, 
        .tri6, 
        .quad4ibi, 
        .quad8, 
        .quad9 
    };
    
    const pixel_num = [_]u32{ 160, 100 };
    const interp_types = [_]common.texops.InterpType{ .cubic_lut_lerp };

    std.debug.print("============================================================\n", .{});
    std.debug.print("RASTER PERFORMANCE BENCHMARK (Fullscreen, Dispon)\n", .{});
    std.debug.print("============================================================\n\n", .{});

    for (mesh_types) |mt| {
        std.debug.print("--- Mesh Type: {s} ---\n", .{@tagName(mt)});
        
        // Flat Shading
        std.debug.print("Flat Shading:\n", .{});
        try common.runTestInternal(
            allocator, io, "full", mt, 1.0, texture, pixel_num, 
            &interp_types, "gold-small", "data-small", 1.0, 1.0, .flat, true
        );

        // Texture Shading
        std.debug.print("Texture Shading (cubic_lut_lerp):\n", .{});
        try common.runTestInternal(
            allocator, io, "full", mt, 1.0, texture, pixel_num, 
            &interp_types, "gold-small", "data-small", 1.0, 1.0, .tex, true
        );
        std.debug.print("\n", .{});
    }
}
