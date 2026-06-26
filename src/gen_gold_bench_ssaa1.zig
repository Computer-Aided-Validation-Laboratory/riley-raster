// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const common = @import("common/benchcommon.zig");
const goldpaths = @import("common/goldpaths.zig");
const policy = @import("common/testpolicy.zig");
const tcfg = @import("common/testconfig.zig");
const gk = @import("riley/zig/geometrykernels.zig");
const iio = @import("riley/zig/imageio.zig");
const texops = @import("riley/zig/textureops.zig");
const buildconfig = @import("riley/zig/buildconfig.zig");
const Rotation = @import("riley/zig/rotation.zig").Rotation;

const F = buildconfig.F;

pub fn main(init: std.process.Init) !void {
    @setEvalBranchQuota(buildconfig.comptime_eval_branch_quota);
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

    const pixel_num = [_]u32{ 800, 500 };
    const render_defaults_base = common.BenchRenderDefaults{
        .pixels_num = pixel_num,
        .sub_sample = 1,
        .focal_leng = 50.0e-3,
        .pixels_size = .{ 5.3e-6, 5.3e-6 },
        .fov_scale = 1.0,
        .rot = Rotation.init(0, 0, 0),
    };

    const mesh_types = comptime std.enums.values(gk.MeshType);
    const shader_types = [_]common.ShaderType{
        .nodal_grey,
        .nodal_rgb,
        .tex8_grey,
        .tex8_rgb,
    };
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

    const cases = [_]struct {
        name: []const u8,
        data_name: []const u8,
        gold_root: []const u8,
        fov_scale: F = 1.0,
        skip_quad4ibi_sphere: bool = false,
    }{
        .{
            .name = "fullraster_ssaa1",
            .data_name = "fullraster",
            .gold_root = goldpaths.sharedRoot("fullscreen_ssaa1"),
        },
        .{
            .name = "sphere2000_ssaa1",
            .data_name = "sphere2000",
            .gold_root = goldpaths.sphereRoot("sphere2000_ssaa1"),
            .skip_quad4ibi_sphere = true,
        },
    };

    std.debug.print(
        "Generating SSAA=1 benchmark gold data...\n",
        .{},
    );

    for (cases) |case| {
        inline for (mesh_types) |mt| {
            inline for (shader_types) |st| {
                inline for (sample_configs) |sc| {
                    const mesh_name = comptime policy.meshName(
                        .benchmark_data,
                        mt,
                    );
                    const data_dir = try std.fmt.allocPrint(
                        aa,
                        "data/bench/{s}_{s}",
                        .{ mesh_name, case.data_name },
                    );
                    const run_config = if (case.skip_quad4ibi_sphere)
                        common.BenchConfig{
                            .run = .all,
                            .skip_quad4ibi_sphere = true,
                        }
                    else
                        common.BenchConfig{ .run = .all };

                    if (common.shouldRun(run_config, mt, st, sc, data_dir)) {
                        const case_name = try common.calcCaseName(
                            aa,
                            mt,
                            st,
                            sc,
                            null,
                            case.fov_scale,
                        );

                        std.debug.print(
                            "Rendering reference: {s}/{s}\n",
                            .{ case.gold_root, case_name },
                        );

                        var r_config = tcfg.getRasterConfig(.bench);
                        r_config.save_strategy = .disk;
                        const is_rgb = st == .nodal_rgb or st == .tex8_rgb;
                        r_config.image_save_opts = if (is_rgb)
                            &[_]iio.ImageSaveOpts{
                                .{
                                    .format = .fimg,
                                    .bits = null,
                                    .scaling = .none,
                                    .channels = 3,
                                },
                                .{
                                    .format = .bmp,
                                    .bits = 8,
                                    .scaling = .auto,
                                    .channels = 3,
                                },
                            }
                        else
                            &[_]iio.ImageSaveOpts{
                                .{
                                    .format = .fimg,
                                    .bits = null,
                                    .scaling = .none,
                                },
                                .{
                                    .format = .bmp,
                                    .bits = 8,
                                    .scaling = .auto,
                                },
                            };
                        const case_out_dir = try std.fs.path.join(
                            aa,
                            &[_][]const u8{ case.gold_root, case_name },
                        );
                        _ = try common.runBenchmarkQuietWithImageOut(
                            u8,
                            aa,
                            io,
                            mt,
                            st,
                            sc,
                            null,
                            data_dir,
                            .{
                                .pixels_num = render_defaults_base.pixels_num,
                                .sub_sample = render_defaults_base.sub_sample,
                                .focal_leng = render_defaults_base.focal_leng,
                                .pixels_size = render_defaults_base.pixels_size,
                                .fov_scale = case.fov_scale,
                                .rot = render_defaults_base.rot,
                            },
                            texture_grey,
                            texture_rgb,
                            r_config,
                            "",
                            case_out_dir,
                        );
                    }
                }
            }
        }
    }

    std.debug.print(
        "\nDone. SSAA=1 benchmark gold references established.\n",
        .{},
    );
}
