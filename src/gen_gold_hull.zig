// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const gengold = @import("common/gengold.zig");
const orch = @import("common/orchestration.zig");
const tcfg = @import("common/testconfig.zig");
const gk = @import("zraster/zig/geometrykernels.zig");
const rastcfg = @import("zraster/zig/rasterconfig.zig");
const iio = @import("zraster/zig/imageio.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const aa = arena.allocator();

    const pixel_num = [_]u32{ 800, 500 };
    const hull_modes = [_]rastcfg.HullMode{
        .off,
        .on_no_fallback,
        .on_convex_fallback,
    };
    const midside_mesh_types = [_]gk.MeshType{ .tri6, .quad8, .quad9 };

    var config = tcfg.getRasterConfig(.gold);
    config.save_strategy = .disk;
    config.image_save_opts = &[_]iio.ImageSaveOpts{
        .{ .format = .fimg, .bits = null, .scaling = .none },
        .{ .format = .bmp, .bits = 8, .scaling = .auto },
    };

    std.debug.print("Generating Hull Cases to gold/hull/...\n", .{});

    for (hull_modes) |hull_mode| {
        try gengold.generateDistortEdgeGoldForHullMode(
            aa,
            io,
            "gold/hull",
            "data/edge",
            pixel_num,
            config,
            hull_mode,
        );

        for (midside_mesh_types) |mesh_type| {
            const prepared = try orch.prepareSingleMeshCase(
                aa,
                io,
                "vertbulge",
                mesh_type,
                pixel_num,
                1.1,
                "data/edge",
            );

            var hull_config = config;
            hull_config.hull_mode = hull_mode;

            const gold_dir = try std.fmt.allocPrint(
                aa,
                "gold/hull/vertbulge_{s}_texfunc_constant_{s}",
                .{ @tagName(mesh_type), @tagName(hull_mode) },
            );
            try gengold.renderAndSave(
                aa,
                io,
                &prepared.camera,
                mesh_type,
                prepared.sim_data.coords,
                prepared.sim_data.connect,
                prepared.sim_data.field,
                .{
                    .tex_func = .{
                        .uvs = null,
                        .builtin = .constant,
                        .normal_type = .none,
                    },
                },
                gold_dir,
                true,
                hull_config,
            );
        }
    }

    std.debug.print("Done.\n", .{});
}
