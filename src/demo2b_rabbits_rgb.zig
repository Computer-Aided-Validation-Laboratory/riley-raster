// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const cam = @import("riley/zig/camera.zig");
const cameraops = @import("riley/zig/cameraops.zig");
const gk = @import("riley/zig/geometrykernels.zig");
const iio = @import("riley/zig/imageio.zig");
const meshio = @import("riley/zig/meshio.zig");
const meshpipe = @import("riley/zig/meshpipeline.zig");
const riley = @import("riley/zig/riley.zig");
const Rotation = @import("riley/zig/rotation.zig").Rotation;
const sceneops = @import("riley/zig/sceneops.zig");
const shaderops = @import("riley/zig/shaderops.zig");
const uvio = @import("riley/zig/uvio.zig");

const buildconfig = @import("riley/zig/buildconfig.zig");

const F = buildconfig.F;

pub fn main(init: std.process.Init) !void {
    // Keep the mesh arrays and shared texture alive through the render.
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const local_alloc = arena.allocator();

    const io = init.io;

    // -------------------------------------------------------------------------
    // 1. Pick the rabbit meshes, shaders, and shared texture
    // -------------------------------------------------------------------------
    const rabbit_names = [_][]const u8{ "riley", "feebs" };
    const ShaderMode = enum { texture, nodal, checker };
    const pairs = [_]struct { mesh_type: gk.MeshType, shaders: [2]ShaderMode }{
        // Shaders are listed in rabbit_names order: Riley first, Feebs second.
        .{ .mesh_type = .tri3, .shaders = .{ .texture, .nodal } },
        .{ .mesh_type = .tri6, .shaders = .{ .checker, .texture } },
        .{ .mesh_type = .quad4, .shaders = .{ .nodal, .checker } },
        .{ .mesh_type = .quad8, .shaders = .{ .texture, .nodal } },
        .{ .mesh_type = .quad9, .shaders = .{ .checker, .texture } },
    };
    const texture = try iio.loadImage(
        u8,
        3,
        local_alloc,
        io,
        "texture/speckle_rgb.bmp",
        .bmp,
    );

    // -------------------------------------------------------------------------
    // 2. Load each mesh and attach its shader
    // -------------------------------------------------------------------------
    var mesh_inputs: [pairs.len * rabbit_names.len]meshpipe.MeshInput = undefined;
    for (pairs, 0..) |pair, pair_idx| {
        const asset_type = if (pair.mesh_type == .tri3opt) .tri3 else pair.mesh_type;
        for (rabbit_names, pair.shaders, 0..) |name, shader_mode, rabbit_idx| {
            const data_dir = try std.fmt.allocPrint(
                local_alloc,
                "data/rabbits/{s}_{s}",
                .{ name, @tagName(asset_type) },
            );
            const coords_path = try std.fmt.allocPrint(local_alloc, "{s}/coords.csv", .{data_dir});
            const connect_path = try std.fmt.allocPrint(
                local_alloc,
                "{s}/connectivity.csv",
                .{data_dir},
            );
            const uvs_path = try std.fmt.allocPrint(local_alloc, "{s}/uvs.csv", .{data_dir});
            const sim_data = try meshio.loadSimData(
                local_alloc,
                io,
                coords_path,
                connect_path,
                null,
                null,
            );
            const uvs = try uvio.loadUVMap(local_alloc, io, uvs_path);

            const shader: shaderops.ShaderInput = switch (shader_mode) {
                .texture => .{ .tex_rgb_u8 = .{
                    .uvs = uvs.array,
                    .tex = texture,
                    .samp_cfg = .{ .sample = .cubic_catmull_rom, .mode = .direct },
                } },
                .nodal => blk: {
                    // Use the UVs to make a synthetic field for one static frame.
                    const node_num = uvs.array.dims[0];
                    var field = try meshio.Field.initAlloc(local_alloc, 1, node_num, 3);
                    for (0..node_num) |nn| {
                        const uu = uvs.array.get(&.{ nn, 0 });
                        const vv = uvs.array.get(&.{ nn, 1 });
                        field.array.set(&.{ 0, nn, 0 }, uu);
                        field.array.set(&.{ 0, nn, 1 }, vv);
                        field.array.set(&.{ 0, nn, 2 }, 0.5 * (uu + vv));
                    }
                    break :blk .{ .nodal = .{ .field = field, .scaling = .auto } };
                },
                .checker => .{ .func_rgb = .{
                    .uvs = uvs.array,
                    .coord_mode = .uv,
                    .builtin = .checker,
                    .params = .{
                        .coord_scale = .{ 36.0, 36.0 },
                        .settings = .{ .checker = .{} },
                    },
                    .scaling = .auto,
                } },
            };

            mesh_inputs[pair_idx * rabbit_names.len + rabbit_idx] = .{
                .mesh_type = pair.mesh_type,
                .coords = sim_data.coords,
                .connect = sim_data.connect,
                .disp = null,
                .shader = shader,
            };
        }
    }

    // -------------------------------------------------------------------------
    // 3. Overlap each pair in XY, then arrange the pairs in a grid
    // -------------------------------------------------------------------------
    var groups: [pairs.len]sceneops.MeshGroup = undefined;
    for (&groups, 0..) |*group, pair_idx| {
        const first = pair_idx * rabbit_names.len;
        sceneops.overlapMeshGroupBounds(
            &mesh_inputs,
            sceneops.meshGroupSingle(first),
            sceneops.meshGroupSingle(first + 1),
            .{
                .overlap_frac = .{ 0.85, 0.8, 0.0 },
                .enabled_axes = .{ true, true, false },
                .direction = .{ .positive, .negative, .current },
            },
        );
        group.* = sceneops.meshGroupSpan(first, rabbit_names.len);
    }
    sceneops.arrangeMeshGroupsGrid(&mesh_inputs, &groups, .{
        .gap = .{ 0.18, 0.28, 0.0 },
        .max_divs = .{ 3, 2, 1 },
    });

    // -------------------------------------------------------------------------
    // 4. Frame the whole grid with one camera
    // -------------------------------------------------------------------------
    const pixels_num = [2]u32{ 1600, 800 };
    const pixels_size = [2]F{ 5.3e-6, 5.3e-6 };
    const focal_length: F = 50.0e-3;
    const fov_scale: F = 1.01;
    const rot = Rotation.init(0.0, 0.0, 0.0);

    const roi_pos = sceneops.boundsCenterOverMeshes(&mesh_inputs);
    const cam_pos = cameraops.posFillFrameFromRotOverMeshes(
        &mesh_inputs,
        pixels_num,
        pixels_size,
        focal_length,
        rot,
        fov_scale,
    );

    const camera_input = cam.CameraInput{
        .pixels_num = pixels_num,
        .pixels_size = pixels_size,
        .pos_world = cam_pos,
        .rot_world = rot,
        .roi_cent_world = roi_pos,
        .focal_length = focal_length,
        .sub_sample = 4,
    };

    // -------------------------------------------------------------------------
    // 5. Configure rasterisation and image output
    // -------------------------------------------------------------------------
    // Pack the three channels into one RGB BMP per camera and frame.
    const config = riley.RasterConfig{
        .parallel = .{ .threads = 4 },
        .save_strategy = .disk,
        .background_value = 127.5,
        .output = .{
            .image_save_mode = .rgb,
            .image_save_opts = &.{
                .{ .format = .bmp, .bits = 8, .scaling = .none },
            },
        },
    };

    // -------------------------------------------------------------------------
    // 6. Render the scene
    // -------------------------------------------------------------------------
    const out_dir_root = "./out/demo2b_rabbits_rgb";

    // Disk-only output writes files without returning an image buffer.
    _ = try riley.raster(
        init.gpa,
        io,
        &.{camera_input},
        &mesh_inputs,
        config,
        out_dir_root,
    );
}
