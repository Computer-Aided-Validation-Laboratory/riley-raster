// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const print = std.debug.print;

const MatSlice = @import("zraster/zig/matslice.zig").MatSlice;
const meshio = @import("zraster/zig/meshio.zig");
const SimData = meshio.SimData;

const mr = @import("zraster/zig/meshraster.zig");
const MeshType = mr.MeshType;
const MeshInput = mr.MeshInput;
const MeshPrepared = mr.MeshPrepared;

const Camera = @import("zraster/zig/camera.zig").Camera;
const CameraOps = @import("zraster/zig/camera.zig").CameraOps;
const Rotation = @import("zraster/zig/rotation.zig").Rotation;

const zraster = @import("zraster/zig/zraster.zig");
const RasterConfig = zraster.RasterConfig;

const iio = @import("zraster/zig/imageio.zig");
const uvio = @import("zraster/zig/uvio.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const dir_paths = [_][]const u8{
        "data-simple/tri3_twoelems/",
        "data-simple/tri6_twoelems/",
        "data-simple/quad4_twoelems/",
        "data-simple/quad8_twoelems/",
        "data-simple/quad9_twoelems/",
    };

    const mesh_types = [_]MeshType{
        .tri3,
        .tri6,
        .quad4ibi,
        .quad8,
        .quad9,
    };

    print("Loading data...\n", .{});
    const sim_datas = try meshio.loadMultiSimData(aa, io, &dir_paths, .{});
    const texture = try iio.loadImage(
        u8,
        1,
        aa,
        io,
        "texture/speckle-simple.tiff",
        .tiff,
    );

    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, "out-bench-multimesh-debug", .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // --- Case 1: Just Texture (Bottom Row) ---
    {
        print("Rendering Just Texture Isolation...\n", .{});
        var mesh_inputs = try aa.alloc(MeshInput, 10);
        // Fill all with dummy or same data but only set bottom row to visible texture
        for (0..10) |ii| {
            const data_idx = ii % 5;
            var coords_dup = try MatSlice(f64).initAlloc(
                aa,
                sim_datas[data_idx].coords.mat.rows_num,
                sim_datas[data_idx].coords.mat.cols_num,
            );
            @memcpy(coords_dup.slice, sim_datas[data_idx].coords.mat.slice);

            if (ii >= 5) {
                const uv_path = try std.fmt.allocPrint(
                    aa,
                    "{s}uvs.csv",
                    .{dir_paths[data_idx]},
                );
                const uvs = try uvio.loadUVMap(aa, io, uv_path);
                mesh_inputs[ii] = MeshInput{
                    .mesh_type = mesh_types[data_idx],
                    .coords = meshio.Coords.init(coords_dup.slice, coords_dup.rows_num),
                    .connect = sim_datas[data_idx].connect,
                    .disp = null,
                    .shader = .{ .tex = .{
                        .uvs = uvs.array,
                        .texture = texture,
                        .sample_config = .{
                            .sample = .cubic_catmull_rom,
                            .mode = .lut_lerp,
                        },
                    } },
                };
            } else {
                // Top row empty (Nodal shader with no field or just skip)
                // We'll use a nodal shader with scaling .none and no field to keep it blank
                mesh_inputs[ii] = MeshInput{
                    .mesh_type = mesh_types[data_idx],
                    .coords = meshio.Coords.init(coords_dup.slice, coords_dup.rows_num),
                    .connect = sim_datas[data_idx].connect,
                    .disp = null,
                    .shader = .{ .nodal = .{
                        .field = sim_datas[data_idx].field.?,
                        .scaling = .none,
                        .bits = null,
                    } },
                };
                // Actually, let's just make it a very small triangle far away?
                // No, just render it but ensure field values are zero.
                @memset(mesh_inputs[ii].shader.nodal.field.array.slice, 0.0);
            }
        }

        mr.arrangeMeshSlice(mesh_inputs, .{ 0.15, 0.15, 0.0 }, .{ 5, 2, 1 });
        const camera = try setupCamera(aa, mesh_inputs);
        defer camera.deinit(aa);

        const config = RasterConfig{
            .save_opt = .disk,
            .save_opts = &[_]iio.ImageSaveOpts{
                .{ .format = .bmp, .bits = 8, .scaling = .auto },
            },
        };
        const camera_input = camera.toInput();
        _ = try zraster.rasterAllFrames(
            aa,
            io,
            &[_]@TypeOf(camera_input){camera_input},
            mesh_inputs,
            config,
            "out-bench-multimesh-debug",
            null,
        );
        // Rename frame_0_field_0.bmp to texture_only.bmp manually if needed,
        // but for now it's in debug dir.
    }

    _ = arena.reset(.free_all);
    // Reload sim_datas as we cleared arena and modified field in Test 1
    const sim_datas2 = try meshio.loadMultiSimData(aa, io, &dir_paths, .{});

    // --- Case 2: Just Nodal (Top Row) ---
    {
        print("Rendering Just Nodal Isolation...\n", .{});
        var mesh_inputs = try aa.alloc(MeshInput, 10);
        for (0..10) |ii| {
            const data_idx = ii % 5;
            var coords_dup = try MatSlice(f64).initAlloc(
                aa,
                sim_datas2[data_idx].coords.mat.rows_num,
                sim_datas2[data_idx].coords.mat.cols_num,
            );
            @memcpy(coords_dup.slice, sim_datas2[data_idx].coords.mat.slice);

            if (ii < 5) {
                mesh_inputs[ii] = MeshInput{
                    .mesh_type = mesh_types[data_idx],
                    .coords = meshio.Coords.init(coords_dup.slice, coords_dup.rows_num),
                    .connect = sim_datas2[data_idx].connect,
                    .disp = null,
                    .shader = .{ .nodal = .{
                        .field = sim_datas2[data_idx].field.?,
                        .bits = 8,
                        .scaling = .auto,
                        .scale_over = .within_frames,
                    } },
                };
            } else {
                mesh_inputs[ii] = MeshInput{
                    .mesh_type = mesh_types[data_idx],
                    .coords = meshio.Coords.init(coords_dup.slice, coords_dup.rows_num),
                    .connect = sim_datas2[data_idx].connect,
                    .disp = null,
                    .shader = .{ .nodal = .{
                        .field = sim_datas2[data_idx].field.?,
                        .scaling = .none,
                        .bits = null,
                    } },
                };
                @memset(mesh_inputs[ii].shader.nodal.field.array.slice, 0.0);
            }
        }

        mr.arrangeMeshSlice(mesh_inputs, .{ 0.15, 0.15, 0.0 }, .{ 5, 2, 1 });
        const camera = try setupCamera(aa, mesh_inputs);
        defer camera.deinit(aa);

        var out_dir = try cwd.openDir(io, "out-bench-multimesh-debug", .{});
        defer out_dir.close(io);

        const config = RasterConfig{
            .save_opt = .disk,
            .save_opts = &[_]iio.ImageSaveOpts{
                .{ .format = .bmp, .bits = 8, .scaling = .auto },
            },
        };
        // This will overwrite frame_0_field_0.bmp if we are not careful.
        // In this simple script it's fine, we'll see the second run results.
        const camera_input = camera.toInput();
        _ = try zraster.rasterAllFrames(
            aa,
            io,
            &[_]@TypeOf(camera_input){camera_input},
            mesh_inputs,
            config,
            out_dir,
            null,
        );
    }

    print("Done debug isolation.\n", .{});
}

fn setupCamera(allocator: std.mem.Allocator, meshes: []const MeshInput) !Camera {
    const pixel_num = [_]u32{ 1600, 800 };
    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);
    const fov_scale_factor: f64 = 1.2;
    const subsample: u8 = 2;

    const roi_pos = CameraOps.roiCentOverMeshes(meshes);
    const cam_pos = CameraOps.posFillFrameFromRotOverMeshes(
        meshes,
        pixel_num,
        pixel_size,
        focal_leng,
        rot,
        fov_scale_factor,
    );

    return try Camera.init(
        allocator,
        .{
            .pixels_num = pixel_num,
            .pixels_size = pixel_size,
            .pos_world = cam_pos,
            .rot_world = rot,
            .roi_cent_world = roi_pos,
            .focal_length = focal_leng,
            .sub_sample = subsample,
        },
    );
}
