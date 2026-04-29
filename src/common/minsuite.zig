// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const common = @import("benchcommon.zig");
const orch = @import("orchestration.zig");
const zraster = @import("../zraster/zig/zraster.zig");
const iio = @import("../zraster/zig/imageio.zig");
const meshio = @import("../zraster/zig/meshio.zig");
const mo = @import("../zraster/zig/meshops.zig");
const gk = @import("../zraster/zig/geometrykernels.zig");
const texops = @import("../zraster/zig/textureops.zig");
const CameraInput = @import("../zraster/zig/camera.zig").CameraInput;
const tcfg = @import("testconfig.zig");

fn translateCoords(coords: *meshio.Coords, translation: [3]f64) void {
    for (0..coords.mat.rows_num) |nn| {
        coords.mat.set(nn, 0, coords.mat.get(nn, 0) + translation[0]);
        coords.mat.set(nn, 1, coords.mat.get(nn, 1) + translation[1]);
        coords.mat.set(nn, 2, coords.mat.get(nn, 2) + translation[2]);
    }
}

pub fn calcMinCaseName(
    allocator: std.mem.Allocator,
    etype: gk.MeshType,
    shader_type: common.ShaderType,
    sample_config: texops.TextureSampleConfig,
) ![]const u8 {
    return common.calcCaseName(
        allocator,
        etype,
        shader_type,
        sample_config,
        .{ .fov_scale = 1.0 },
    );
}

fn buildSphere200MultiCullMeshInputs(
    allocator: std.mem.Allocator,
    io: std.Io,
    etype: gk.MeshType,
    shader_type: common.ShaderType,
    sample_config: texops.TextureSampleConfig,
    data_dir: []const u8,
    texture_grey: iio.Texture(1),
    texture_rgb: iio.Texture(3),
) ![]mo.MeshInput {
    const base_mesh_input = try common.loadBenchmarkMeshInput(
        allocator,
        io,
        etype,
        shader_type,
        sample_config,
        data_dir,
        texture_grey,
        texture_rgb,
    );
    const mesh_inputs = try allocator.alloc(mo.MeshInput, 2);

    const left_coords = try orch.copyCoords(allocator, base_mesh_input.coords);
    const right_coords = try orch.copyCoords(allocator, base_mesh_input.coords);

    const bounds = mo.findAlignedCentroid(&left_coords);
    const diameter = bounds.extent[0];
    const overlap_x = 0.7 * diameter;
    var right_coords_mut = right_coords;
    translateCoords(&right_coords_mut, .{ overlap_x, 0.0, -20.0 * diameter });

    mesh_inputs[0] = base_mesh_input;
    mesh_inputs[0].coords = left_coords;
    mesh_inputs[1] = base_mesh_input;
    mesh_inputs[1].coords = right_coords_mut;
    return mesh_inputs;
}

pub fn runSphere200MultiCullQuiet(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    etype: gk.MeshType,
    shader_type: common.ShaderType,
    sample_config: texops.TextureSampleConfig,
    data_dir: []const u8,
    pixel_num: [2]u32,
    texture_grey: iio.Texture(1),
    texture_rgb: iio.Texture(3),
    options: common.BenchOptions,
) !common.BenchResult {
    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const aa = arena.allocator();

    const mesh_inputs = try buildSphere200MultiCullMeshInputs(
        aa,
        io,
        etype,
        shader_type,
        sample_config,
        data_dir,
        texture_grey,
        texture_rgb,
    );
    const camera = try orch.initCameraForMeshes(
        aa,
        mesh_inputs,
        pixel_num,
        options.fov_scale,
    );
    defer camera.deinit(aa);

    const num_out_fields = common.calcOutputChannels(shader_type);
    var config = tcfg.rasterConfig(.testing);
    config.save_strategy = if (options.out_dir_base.len > 0)
        .disk
    else if (options.return_image)
        .memory
    else
        .none;
    config.image_save_opts = options.save_opts orelse &[_]iio.ImageSaveOpts{
        .{
            .format = .bmp,
            .bits = 8,
            .scaling = .auto,
            .channels = num_out_fields,
        },
        .{
            .format = .fimg,
            .bits = null,
            .scaling = .none,
            .channels = num_out_fields,
        },
    };

    if (options.out_dir_base.len > 0) {
        var out_dir = try orch.openDirEnsured(io, options.out_dir_base);
        out_dir.close(io);
    }

    const case_name = try calcMinCaseName(
        aa,
        etype,
        shader_type,
        sample_config,
    );
    const out_path = if (options.out_dir_base.len > 0)
        try std.fs.path.join(aa, &[_][]const u8{
            options.out_dir_base,
            case_name,
        })
    else
        null;

    const camera_input = camera.toInput();
    var image_arr = try zraster.rasterAllFrames(
        outer_alloc,
        io,
        &[_]CameraInput{camera_input},
        mesh_inputs,
        config,
        out_path,
        null,
    );

    const image_final = if (options.return_image) blk: {
        var images = image_arr orelse return error.NoResult;
        image_arr = null;
        defer {
            outer_alloc.free(images.slice);
            images.deinit(outer_alloc);
        }
        break :blk try common.extractFirstFrameImage(outer_alloc, &images);
    } else null;

    if (image_arr) |images| {
        outer_alloc.free(images.slice);
        var images_mut = images;
        images_mut.deinit(outer_alloc);
    }

    return .{
        .e2e_ms = 0.0,
        .geom_ms = 0.0,
        .raster_ms = 0.0,
        .fps = 0.0,
        .metrics = .{
            .mpx_sec = 0.0,
            .msubpx_sec = 0.0,
            .mshades_sec = 0.0,
            .msubshades_sec = 0.0,
            .melems_sec = 0.0,
            .mnodes_sec = 0.0,
            .mops_sec = 0.0,
        },
        .pipeline_times = .{},
        .image = image_final,
    };
}
