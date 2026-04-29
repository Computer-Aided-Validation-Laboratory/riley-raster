// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const common = @import("common/benchcommon.zig");
const gengold = @import("common/gengold.zig");
const minsuite = @import("common/minsuite.zig");
const tcfg = @import("common/testconfig.zig");
const zraster = @import("zraster/zig/zraster.zig");
const mo = @import("zraster/zig/meshops.zig");
const gk = @import("zraster/zig/geometrykernels.zig");
const iio = @import("zraster/zig/imageio.zig");
const texops = @import("zraster/zig/textureops.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const aa = arena.allocator();

    const texture_grey = try iio.loadImage(
        u8,
        1,
        aa,
        io,
        "texture/speckle.bmp",
        .bmp,
    );
    const texture_rgb = try iio.loadImage(
        u8,
        3,
        aa,
        io,
        "texture/speckle_rgb.bmp",
        .bmp,
    );

    const out_dir = "out-min";
    const pixel_num_sphere = [_]u32{ 160, 100 };
    const pixel_num_multi = [_]u32{ 640, 400 };

    const mesh_types = comptime std.enums.values(gk.MeshType);
    const shader_types = comptime std.enums.values(common.ShaderType);
    const sample_configs = [_]texops.TextureSampleConfig{
        .{ .sample = .nearest, .mode = .direct },
        .{ .sample = .linear, .mode = .direct },
        .{ .sample = .cubic_catmull_rom, .mode = .direct },
        .{ .sample = .cubic_catmull_rom, .mode = .lut_lerp },
        .{ .sample = .cubic_mitchell_netravali, .mode = .lut_lerp },
        .{ .sample = .lanczos3, .mode = .lut_lerp },
        .{ .sample = .cubic_bspline, .mode = .lut_lerp },
        .{ .sample = .quintic_bspline, .mode = .direct },
        .{ .sample = .quintic_bspline, .mode = .lut_lerp },
    };

    var config = tcfg.rasterConfig(.preview);
    config.save_strategy = .disk;
    config.image_save_opts = &[_]iio.ImageSaveOpts{
        .{ .format = .fimg, .bits = null, .scaling = .none },
        .{ .format = .bmp, .bits = 8, .scaling = .auto },
    };

    std.debug.print("Rendering MIN Suite (sphere200/base) to {s}...\n", .{out_dir});
    for (mesh_types) |mt| {
        for (shader_types) |st| {
            for (sample_configs) |sc| {
                const data_dir = try std.fmt.allocPrint(
                    aa,
                    "data-min/{s}_sphere200",
                    .{@tagName(mt)},
                );

                const is_rgb = (st == .tex8_rgb or st == .nodal_rgb);
                const is_allowed_rgb = (st == .nodal_rgb) or
                    (st == .tex8_rgb and sc.sample == .cubic_catmull_rom and sc.mode == .lut_lerp);

                if (is_rgb and !is_allowed_rgb) continue;

                if (common.shouldRun(
                    .{ .run = .all, .skip_quad4ibi_sphere = true },
                    mt,
                    st,
                    sc,
                    data_dir,
                )) {
                    _ = try common.runBenchmarkQuiet(
                        aa,
                        io,
                        mt,
                        st,
                        sc,
                        data_dir,
                        pixel_num_sphere,
                        texture_grey,
                        texture_rgb,
                        .{
                            .out_dir_base = out_dir ++ "/sphere200/base",
                            .fov_scale = 1.0,
                        },
                    );
                }
            }
        }
    }

    std.debug.print("Rendering MIN Suite (sphere200multicull) to {s}...\n", .{out_dir});
    for (mesh_types) |mt| {
        for (shader_types) |st| {
            for (sample_configs) |sc| {
                const data_dir = try std.fmt.allocPrint(
                    aa,
                    "data-min/{s}_sphere200",
                    .{@tagName(mt)},
                );

                const is_rgb = (st == .tex8_rgb or st == .nodal_rgb);
                const is_allowed_rgb = (st == .nodal_rgb) or
                    (st == .tex8_rgb and sc.sample == .cubic_catmull_rom and sc.mode == .lut_lerp);

                if (is_rgb and !is_allowed_rgb) continue;

                if (common.shouldRun(
                    .{ .run = .all, .skip_quad4ibi_sphere = true },
                    mt,
                    st,
                    sc,
                    data_dir,
                )) {
                    _ = try minsuite.runSphere200MultiCullQuiet(
                        aa,
                        io,
                        mt,
                        st,
                        sc,
                        data_dir,
                        pixel_num_sphere,
                        texture_grey,
                        texture_rgb,
                        .{
                            .out_dir_base = out_dir ++ "/sphere200multicull",
                            .fov_scale = 0.75,
                        },
                    );
                }
            }
        }
    }

    std.debug.print("Rendering MIN Suite (multimesh) to {s}...\n", .{out_dir});
    const multi_dir_paths = [_][]const u8{
        "data-min/tri3_twoelems/",
        "data-min/tri6_twoelems/",
        "data-min/quad4_twoelems/",
        "data-min/quad8_twoelems/",
        "data-min/quad9_twoelems/",
    };

    try gengold.runMultimeshGenerationExt(
        aa,
        io,
        config,
        out_dir ++ "/multimesh/base",
        &multi_dir_paths,
        pixel_num_multi,
    );
    try gengold.runMultimeshMixedGenerationExt(
        aa,
        io,
        config,
        out_dir ++ "/multimesh/allelem_allshade",
        &multi_dir_paths,
        pixel_num_multi,
    );
    try gengold.runMultimeshMixedRGBGenerationExt(
        aa,
        io,
        config,
        out_dir ++ "/multimesh/allelem_allshade_rgb",
        &multi_dir_paths,
        pixel_num_multi,
    );

    std.debug.print("Done. MIN Suite rendering complete.\n", .{});
}
