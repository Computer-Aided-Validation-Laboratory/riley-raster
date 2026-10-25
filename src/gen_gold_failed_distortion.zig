// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("riley/zig/buildconfig.zig");
const dist_gen = @import("gengold/gen_gold_full_dist_psf.zig");
const ssaa_gen = @import("gengold/gen_gold_full_ssaa_pxmap.zig");
const dist_case = @import("tests/fullcase_dist_psf.zig");
const ssaa_case = @import("tests/fullcase_ssaa_pxmap.zig");
const fullfixtures = @import("dev_support/fullfixtures.zig");
const iio = @import("riley/zig/imageio.zig");
const policy = @import("dev_support/testpolicy.zig");
const tcfg = @import("dev_support/testconfig.zig");

fn exists(io: std.Io, path: []const u8) !bool {
    std.Io.Dir.cwd().access(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return true;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const precision = if (buildconfig.F == f32) "f32" else "f64";
    const simd = if (buildconfig.config.simd == .on) "simdon" else "simdoff";
    var config = tcfg.getRasterConfig(.gold_gen);
    config.save_strategy = .disk;
    config.output.image_save_opts = &.{
        .{ .format = .fimg, .bits = null, .scaling = .none },
        .{ .format = .bmp, .bits = 8, .scaling = .auto },
    };

    var prep = try fullfixtures.prepareScene1(arena_alloc, io);
    defer prep.deinit(arena_alloc);
    var regenerated: usize = 0;

    for (dist_case.ssaa_levels) |ssaa| {
        for (dist_case.dist_cases) |dist| {
            for (dist_case.psf_cases) |psf| {
                const name = try dist_case.formatDistPsfCaseName(
                    arena_alloc,
                    ssaa,
                    dist.tag,
                    psf.tag,
                );
                var failed = false;
                for ([_][]const u8{ "tile_local", "global_subpx", "global_stripe" }) |mode| {
                    const path = try std.fmt.allocPrint(
                        arena_alloc,
                        "fails/{s}_{s}_full_dist_psf/{s}_{s}",
                        .{ precision, simd, name, mode },
                    );
                    if (try exists(io, path)) failed = true;
                }
                if (!failed) continue;
                try dist_gen.generateDistPsfCase(
                    arena_alloc,
                    io,
                    &prep,
                    ssaa,
                    dist,
                    psf,
                    policy.goldRoot(.full_dist_psf),
                    config,
                );
                regenerated += 1;
                std.debug.print("Regenerated full_dist_psf/{s}\n", .{name});
            }
        }
    }

    for (ssaa_case.ssaa_levels) |ssaa| {
        for (ssaa_case.dist_cases) |dist| {
            for (ssaa_case.psf_cases) |psf| {
                for (ssaa_case.pxmap_cases) |pxmap| {
                    const name = try ssaa_case.formatSsaaPxmapCaseName(
                        arena_alloc,
                        ssaa,
                        dist.tag,
                        psf.tag,
                        pxmap.tag,
                    );
                    const path = try std.fmt.allocPrint(
                        arena_alloc,
                        "fails/{s}_{s}_full_ssaa_pxmap/{s}",
                        .{ precision, simd, name },
                    );
                    if (!try exists(io, path)) continue;
                    try ssaa_gen.generateSsaaPxmapCase(
                        arena_alloc,
                        io,
                        &prep,
                        ssaa,
                        dist,
                        psf,
                        pxmap,
                        policy.goldRoot(.full_ssaa_pxmap),
                        config,
                    );
                    regenerated += 1;
                    std.debug.print("Regenerated full_ssaa_pxmap/{s}\n", .{name});
                }
            }
        }
    }
    std.debug.print("Regenerated {d} distinct gold cases.\n", .{regenerated});
}
