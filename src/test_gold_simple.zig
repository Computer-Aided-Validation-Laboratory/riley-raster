const std = @import("std");
const common = @import("common/tests.zig");
const tcfg = @import("common/testconfig.zig");

const SHADER_FILTER: common.ShaderFilter = .both; // .flat, .tex, or .both

test "Gold Simple Suite" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const texture = blk: {
        break :blk try common.iio.loadImage(
            u8,
            1,
            allocator,
            io,
            "texture/speckle-simple.tiff",
            .tiff,
        );
    };
    defer texture.deinit(allocator);

    const mesh_types = [_]common.MeshType{
        .tri3,
        .tri6,
        .quad4ibi,
        .quad4newton,
        .quad8,
        .quad9,
    };
    const interp_types = [_]common.texops.InterpType{.cubic_lut_lerp};
    const pixel_num = [_]u32{ 640, 400 };

    const start_time = std.Io.Clock.Timestamp.now(io, .awake);

    for (mesh_types) |mt| {
        try common.runTestInternal(
            allocator,
            io,
            "twoelems",
            mt,
            1.1,
            texture,
            pixel_num,
            &interp_types,
            "gold-simple",
            "data-simple",
            tcfg.REL_TOL,
            tcfg.ABS_TOL,
            SHADER_FILTER,
            false,
        );
    }

    const end_time = std.Io.Clock.Timestamp.now(io, .awake);
    const duration_ms = @as(
        f64,
        @floatFromInt(start_time.durationTo(end_time).raw.nanoseconds),
    ) / 1e6;
    std.debug.print("Gold Simple Test Suite took {d:.3} ms\n", .{duration_ms});
}
