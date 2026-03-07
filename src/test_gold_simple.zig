const std = @import("std");
const common = @import("tests/common.zig");

// NOTE: should probably be 1e-9 to 1e-11
const REL_TOL: f64 = 1e-10;
const ABS_TOL: f64 = 1e-10;
const SHADER_FILTER: common.ShaderFilter = .flat; // .flat, .tex, or .both

test "Gold Simple Suite" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const texture = try common.texio.loadTIFF(allocator, io, "texture/speckle.tiff", u8, 1);
    defer texture.deinit(allocator);

    const mesh_types = [_]common.MeshType{ .tri3, .tri6 };
    const interp_types = [_]common.textureinterp.InterpType{ .cubic_lut_lerp };
    const pixel_num = [_]u32{ 320, 200 };

    const start_time = std.Io.Clock.Timestamp.now(io, .awake);

    for (mesh_types) |mt| {
        try common.runTestInternal(allocator, 
                                   io, 
                                   "single", 
                                   mt, 
                                   1.1, 
                                   texture, 
                                   pixel_num, 
                                   &interp_types, 
                                   "gold-simple", 
                                   "data-simple", 
                                   REL_TOL,
                                   ABS_TOL, 
                                   SHADER_FILTER);
                                   
        try common.runTestInternal(allocator, 
                                   io, 
                                   "full", 
                                   mt, 
                                   1.0, 
                                   texture, 
                                   pixel_num, 
                                   &interp_types, 
                                   "gold-simple", 
                                   "data-simple", 
                                   REL_TOL,
                                   ABS_TOL, 
                                   SHADER_FILTER);
    }

    const end_time = std.Io.Clock.Timestamp.now(io, .awake);
    const duration_ms = @as(f64, @floatFromInt(
        start_time.durationTo(end_time).raw.nanoseconds)) / 1e6;
    std.debug.print("\nGold Simple Suite (tri3, tri6) took {d:.3} ms\n", .{duration_ms});
}
