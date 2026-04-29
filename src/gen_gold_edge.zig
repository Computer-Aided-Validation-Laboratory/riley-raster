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
const zraster = @import("zraster/zig/zraster.zig");
const meshio = @import("zraster/zig/meshio.zig");
const mo = @import("zraster/zig/meshops.zig");
const gk = @import("zraster/zig/geometrykernels.zig");
const iio = @import("zraster/zig/imageio.zig");
const texops = @import("zraster/zig/textureops.zig");

fn buildUvField(
    allocator: std.mem.Allocator,
    uvs: @import("zraster/zig/ndarray.zig").NDArray(f64),
    time_steps: usize,
) !meshio.Field {
    const node_num = uvs.dims[0];
    var field = try meshio.Field.initAlloc(allocator, time_steps, node_num, 2);

    for (0..time_steps) |tt| {
        for (0..node_num) |nn| {
            field.array.set(&[_]usize{ tt, nn, 0 }, uvs.get(&[_]usize{ nn, 0 }));
            field.array.set(&[_]usize{ tt, nn, 1 }, uvs.get(&[_]usize{ nn, 1 }));
        }
    }

    return field;
}

fn generateDistortMidsideGold(
    allocator: std.mem.Allocator,
    io: std.Io,
    gold_dir_root: []const u8,
    data_dir_root: []const u8,
    pixel_num: [2]u32,
    texture: iio.Texture(1),
    config: zraster.RasterConfig,
) !void {
    const mesh_types = [_]gk.MeshType{ .tri6, .quad8, .quad9 };
    const tex_sample_config = texops.TextureSampleConfig{
        .sample = .cubic_catmull_rom,
        .mode = .lut_lerp,
    };

    for (mesh_types) |mesh_type| {
        const prepared = try orch.prepareSingleMeshCase(
            allocator,
            io,
            "distort-midside",
            mesh_type,
            pixel_num,
            1.1,
            data_dir_root,
        );
        const time_steps = prepared.sim_data.field.?.getTimeN();
        const uv_field = try buildUvField(allocator, prepared.uvs.array, time_steps);

        const gold_dir = try std.fmt.allocPrint(
            allocator,
            "{s}/distort-midside_{s}_texfunc_constant",
            .{ gold_dir_root, @tagName(mesh_type) },
        );
        try gengold.renderAndSave(
            allocator,
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
            config,
        );

        const nodal_uv_dir = try std.fmt.allocPrint(
            allocator,
            "{s}/distort-midside_{s}_nodal_uv",
            .{ gold_dir_root, @tagName(mesh_type) },
        );
        try gengold.renderAndSave(
            allocator,
            io,
            &prepared.camera,
            mesh_type,
            prepared.sim_data.coords,
            prepared.sim_data.connect,
            prepared.sim_data.field,
            .{
                .nodal = .{
                    .field = uv_field,
                    .bits = null,
                    .scaling = .none,
                },
            },
            nodal_uv_dir,
            true,
            config,
        );

        const tex_dir = try std.fmt.allocPrint(
            allocator,
            "{s}/distort-midside_{s}_tex_{s}_{s}",
            .{
                gold_dir_root,
                @tagName(mesh_type),
                @tagName(tex_sample_config.sample),
                @tagName(tex_sample_config.mode),
            },
        );
        try gengold.renderAndSave(
            allocator,
            io,
            &prepared.camera,
            mesh_type,
            prepared.sim_data.coords,
            prepared.sim_data.connect,
            prepared.sim_data.field,
            .{
                .tex = .{
                    .uvs = prepared.uvs.array,
                    .texture = texture,
                    .sample_config = tex_sample_config,
                },
            },
            tex_dir,
            true,
            config,
        );
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const aa = arena.allocator();

    const texture = try iio.loadImage(
        u8,
        1,
        aa,
        io,
        "texture/speckle-simple.tiff",
        .tiff,
    );

    const mesh_types = [_]gk.MeshType{
        .tri6,
        .quad8,
        .quad9,
    };

    const sample_configs = [_]texops.TextureSampleConfig{
        .{ .sample = .nearest, .mode = .direct },
        .{ .sample = .linear, .mode = .direct },
        .{ .sample = .cubic_catmull_rom, .mode = .lut_lerp },
        .{ .sample = .cubic_mitchell_netravali, .mode = .lut_lerp },
        .{ .sample = .lanczos3, .mode = .lut_lerp },
        .{ .sample = .cubic_bspline, .mode = .lut_lerp },
        .{ .sample = .quintic_bspline, .mode = .lut_lerp },
    };
    const pixel_num = [_]u32{ 320, 200 };
    const pixel_num_distort_midside = [_]u32{ 800, 500 };
    const config = zraster.RasterConfig{
        .save_strategy = .disk,
        .image_save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .fimg, .bits = null, .scaling = .none },
            .{ .format = .bmp, .bits = 8, .scaling = .auto },
        },
        .report = .off,
    };

    std.debug.print("Generating Edge Cases to gold-edge/...\n", .{});

    try gengold.runGenerationExt(
        aa,
        io,
        "vertbulge",
        &mesh_types,
        1.1,
        texture,
        pixel_num,
        &sample_configs,
        "gold-edge",
        "data-edge",
        config,
    );
    try gengold.runGenerationExt(
        aa,
        io,
        "bulgein_rot",
        &mesh_types,
        1.1,
        texture,
        pixel_num,
        &sample_configs,
        "gold-edge",
        "data-edge",
        config,
    );
    try gengold.runGenerationExt(
        aa,
        io,
        "bulgeout_rot",
        &mesh_types,
        1.1,
        texture,
        pixel_num,
        &sample_configs,
        "gold-edge",
        "data-edge",
        config,
    );
    try generateDistortMidsideGold(
        aa,
        io,
        "gold-edge",
        "data-edge",
        pixel_num_distort_midside,
        texture,
        config,
    );

    std.debug.print("Done.\n", .{});
}
