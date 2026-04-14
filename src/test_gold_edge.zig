const std = @import("std");
const common = @import("common/tests.zig");
const tcfg = @import("common/testconfig.zig");

const SHADER_FILTER: common.ShaderFilter = .both; // .flat, .tex, or .both

test "Gold Edge Suite" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const texture = blk: {
        break :blk try common.iio.loadImage(
            allocator,
            io,
            "texture/speckle-simple.tiff",
            .tiff,
            u8,
            1,
        );
    };
    defer texture.deinit(allocator);

    const mesh_types = [_]common.MeshType{ .tri6, .quad8, .quad9 };
    const sample_configs = [_]common.texops.TextureSampleConfig{
        .{ .sample = .nearest, .mode = .direct },
        .{ .sample = .linear, .mode = .direct },
        .{ .sample = .cubic_catmull_rom, .mode = .lut_lerp },
        .{ .sample = .cubic_mitchell_netravali, .mode = .lut_lerp },
        .{ .sample = .lanczos3, .mode = .lut_lerp },
        .{ .sample = .cubic_bspline, .mode = .lut_lerp },
        .{ .sample = .quintic_bspline, .mode = .lut_lerp },
    };
    const pixel_num = [_]u32{ 320, 200 };

    const start_time = std.Io.Clock.Timestamp.now(io, .awake);

    for (mesh_types) |mt| {
        try common.runTestInternal(
            allocator,
            io,
            "bulgein_rot",
            mt,
            1.1,
            texture,
            pixel_num,
            &sample_configs,
            "gold-edge",
            "data-edge",
            tcfg.REL_TOL,
            tcfg.ABS_TOL,
            SHADER_FILTER,
            false,
        );

        try common.runTestInternal(
            allocator,
            io,
            "bulgeout_rot",
            mt,
            1.1,
            texture,
            pixel_num,
            &sample_configs,
            "gold-edge",
            "data-edge",
            tcfg.REL_TOL,
            tcfg.ABS_TOL,
            SHADER_FILTER,
            false,
        );

        try common.runTestInternal(
            allocator,
            io,
            "vertbulge",
            mt,
            1.1,
            texture,
            pixel_num,
            &sample_configs,
            "gold-edge",
            "data-edge",
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
    std.debug.print("Gold Edge Test Suite took {d:.3} ms\n", .{duration_ms});
}
