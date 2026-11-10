// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const riley = @import("riley/zig/api.zig");
const maths = riley.maths;
const datio = riley.dataio;
const ops = riley.ops;

pub fn main(init: std.process.Init) !void {
    const outer_alloc = init.gpa;
    const io = init.io;

    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const local_alloc = arena.allocator();

    // -------------------------------------------------------------------------
    // 1. Setup paths and load sphere simulation data and texture
    // -------------------------------------------------------------------------
    const data_dir = "data/min/tri6_sphere200/";
    const out_dir_root = "./out/demo10_sphere_lit";

    std.debug.print("Loading sphere simulation data from {s}...\n", .{data_dir});
    const coord_path = data_dir ++ "coords.csv";
    const conn_path = data_dir ++ "connect.csv";
    const sim_data = try datio.loadSimData(
        local_alloc,
        io,
        coord_path,
        conn_path,
        null,
        null,
    );

    std.debug.print("Loading UV map...\n", .{});
    const uv_path = data_dir ++ "uvs.csv";
    const uvs = try datio.loadUVMap(local_alloc, io, uv_path);

    std.debug.print("Loading speckle texture...\n", .{});
    const texture = try datio.loadImage(
        u8,
        1,
        local_alloc,
        io,
        "texture/speckle_mono.bmp",
        .bmp,
    );

    // -------------------------------------------------------------------------
    // 2. Define shaders: direct speckle, direct lambertian, and shader pipe
    // -------------------------------------------------------------------------
    const speckle_shader: riley.ShaderMonoInput = .{
        .tex_u8 = .{
            .uvs = uvs.array,
            .tex = texture,
            .samp_cfg = .{
                .sample = .cubic_catmull_rom,
                .mode = .direct,
            },

            .scaling = .none,
        },
    };

    const lambertian_shader: riley.ShaderMonoInput = .{
        .func = .{
            .builtin = .lambertian_normal_z,
            .params = .{
                .settings = .{
                    .lambertian_normal_z = .{
                        .coeffs = .{ 0.2, 0.8 },
                    },
                },
            },

            .scaling = .none,
        },
    };

    const channel_slot = riley.Register{ .kind = .channel, .index = 0 };
    const param_slot = riley.Register{ .kind = .parameter, .index = 0 };
    const channel_slots = [_]riley.Register{channel_slot};

    const lit_stages = [_]riley.ShaderPipeStageInput{
        .{
            .shader = .{
                .shader = ops.monoToPipeSource(speckle_shader),
                .register_dest = channel_slot,
            },
        },
        .{
            .shader = .{
                .shader = ops.monoToPipeSource(lambertian_shader),
                .register_dest = param_slot,
            },
        },
    };

    const lit_resolver: riley.ResolverInput = .{
        .modulate = .{
            .register_sources = &channel_slots,
            .factor = param_slot,
        },
    };

    const lit_shader: riley.ShaderPipeInput = .{
        .stages = &lit_stages,
        .resolver = lit_resolver,
    };

    // -------------------------------------------------------------------------
    // 3. Position and frame the camera
    // -------------------------------------------------------------------------
    std.debug.print("Setting up camera...\n", .{});
    const pixels_num = [_]u32{ 800, 500 };
    const pixels_size = [_]maths.F{
        5.3e-6,
        5.3e-6,
    };
    const focal_leng: maths.F = 50.0e-3;
    const rot = maths.Rotation.init(0, 0, 0);
    const fov_scale_factor: maths.F = 1.0;

    const roi_pos = ops.boundsCenter(&sim_data.coords);
    const cam_pos = ops.posFillFrameFromRot(
        &sim_data.coords,
        pixels_num,
        pixels_size,
        focal_leng,
        rot,
        fov_scale_factor,
    );

    var camera_input = riley.CameraInput{
        .pixels_num = pixels_num,
        .pixels_size = pixels_size,
        .pos_world = cam_pos,
        .rot_world = rot,
        .roi_cent_world = roi_pos,
        .focal_length = focal_leng,
        .sub_sample = 4,
        .render_format = .mono,
        .output_files = &.{.{ .format = .bmp, .file_bits = 8, .scaling = .auto }},
    };

    // -------------------------------------------------------------------------
    // 4. Configure raster engine
    // -------------------------------------------------------------------------
    var config = riley.RasterConfig{
        .save_strategy = .disk,
        .parallel = .{ .threads = 4 },
    };

    // -------------------------------------------------------------------------
    // 5. Render the three sphere images
    // -------------------------------------------------------------------------
    std.debug.print("Rendering sphere demo images to {s}/...\n", .{out_dir_root});

    var mesh = riley.MeshInput{
        .mesh_type = .tri6,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = null,
        .shaders = .{ .mono_direct = speckle_shader },
    };

    // 1) Direct speckle shader (like the normal sphere demo)
    std.debug.print("1/3: Rendering direct speckle sphere...\n", .{});
    camera_input.render_format = .mono;
    config.output_name_format = "demo10_1_direct_speckle";
    var images = try riley.raster(
        outer_alloc,
        io,
        &.{camera_input},
        &.{mesh},
        config,
        out_dir_root,
    );
    if (images) |image| {
        outer_alloc.free(image.slice);
        image.deinit(outer_alloc);
    }

    // 2) Direct lambertian function shader
    std.debug.print("2/3: Rendering direct lambertian sphere...\n", .{});
    mesh.shaders = .{ .mono_direct = lambertian_shader };
    camera_input.render_format = .mono;
    config.output_name_format = "demo10_2_direct_lambertian";
    images = try riley.raster(
        outer_alloc,
        io,
        &.{camera_input},
        &.{mesh},
        config,
        out_dir_root,
    );
    if (images) |image| {
        outer_alloc.free(image.slice);
        image.deinit(outer_alloc);
    }

    // 3) Combined speckle texture and lambertian shader via shader pipe
    std.debug.print("3/3: Rendering combined lit speckle sphere...\n", .{});
    mesh.shaders = .{ .mono_pipe = lit_shader };
    camera_input.render_format = .mono;
    config.output_name_format = "demo10_3_combined_lit";
    images = try riley.raster(
        outer_alloc,
        io,
        &.{camera_input},
        &.{mesh},
        config,
        out_dir_root,
    );
    if (images) |image| {
        outer_alloc.free(image.slice);
        image.deinit(outer_alloc);
    }
}
