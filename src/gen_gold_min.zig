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
const zraster = @import("zraster/zig/zraster.zig");
const mr = @import("zraster/zig/meshraster.zig");
const iio = @import("zraster/zig/imageio.zig");
const texops = @import("zraster/zig/textureops.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const texture_grey = try iio.loadImage(
        u8,
        1,
        allocator,
        io,
        "texture/speckle.bmp",
        .bmp,
    );
    defer texture_grey.deinit(allocator);

    const texture_rgb = try iio.loadImage(
        u8,
        3,
        allocator,
        io,
        "texture/speckle_rgb.bmp",
        .bmp,
    );
    defer texture_rgb.deinit(allocator);

    const out_dir = "gold-min";
    const pixel_num_sphere = [_]u32{ 160, 100 };
    const pixel_num_multi = [_]u32{ 640, 400 };

    const mesh_types = comptime std.enums.values(mr.MeshType);
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

    const config = zraster.RasterConfig{
        .save_strategy = .disk,
        .image_save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .fimg, .bits = null, .scaling = .none },
        },
        .report = .off,
    };

    std.debug.print("Generating MIN Gold Data (sphere200)...\n", .{});
    for (mesh_types) |mt| {
        for (shader_types) |st| {
            for (sample_configs) |sc| {
                const data_dir = try std.fmt.allocPrint(
                    allocator,
                    "data-min/{s}_sphere200",
                    .{@tagName(mt)},
                );
                defer allocator.free(data_dir);

                // Filter for Min Suite:
                // - Greyscale: All cases
                // - RGB: Only nodal and one texture case
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
                    const num_ch: u8 = if (is_rgb) 3 else 1;
                    var result = try common.runBenchmarkQuiet(
                        allocator,
                        io,
                        mt,
                        st,
                        sc,
                        data_dir,
                        pixel_num_sphere,
                        texture_grey,
                        texture_rgb,
                        .{
                            .out_dir_base = out_dir,
                            .save_opts = &[_]iio.ImageSaveOpts{
                                .{ .format = .fimg, .bits = null, .scaling = .none, .channels = num_ch },
                            },
                        },
                    );
                    result.deinit(allocator);
                }
            }
        }
    }

    std.debug.print("Generating MIN Gold Data (multimesh)...\n", .{});
    const multi_dir_paths = [_][]const u8{
        "data-min/tri3_twoelems/",
        "data-min/tri6_twoelems/",
        "data-min/quad4_twoelems/",
        "data-min/quad8_twoelems/",
        "data-min/quad9_twoelems/",
    };

    try gengold.runMultimeshGenerationExt(
        allocator,
        io,
        config,
        out_dir,
        &multi_dir_paths,
        pixel_num_multi,
    );
    try gengold.runMultimeshMixedGenerationExt(
        allocator,
        io,
        config,
        out_dir ++ "/allelem_allshade",
        &multi_dir_paths,
        pixel_num_multi,
    );
    try gengold.runMultimeshMixedRGBGenerationExt(
        allocator,
        io,
        config,
        out_dir ++ "/allelem_allshade_rgb",
        &multi_dir_paths,
        pixel_num_multi,
    );

    std.debug.print("Done. MIN gold references established.\n", .{});
}
