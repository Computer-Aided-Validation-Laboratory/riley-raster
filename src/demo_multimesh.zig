// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

// Import zraster modules directly to show how the library is used
const zraster = @import("zraster/zig/zraster.zig");
const RasterConfig = zraster.RasterConfig;
const meshio = @import("zraster/zig/meshio.zig");
const uvio = @import("zraster/zig/uvio.zig");
const iio = @import("zraster/zig/imageio.zig");
const mo = @import("zraster/zig/meshops.zig");
const MeshInput = mo.MeshInput;
const gk = @import("zraster/zig/geometrykernels.zig");
const MeshType = gk.MeshType;
const camera_mod = @import("zraster/zig/camera.zig");
const CameraInput = camera_mod.CameraInput;
const CameraPrepared = camera_mod.CameraPrepared;
const Rotation = @import("zraster/zig/rotation.zig").Rotation;
const CameraOps = camera_mod.CameraOps;
const MatSlice = @import("zraster/zig/matslice.zig").MatSlice;

pub fn main(init: std.process.Init) !void {
    const outer_alloc = init.gpa;

    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const aa = arena.allocator();

    // 1. Setup Rasteriser Configuration
    // We want to save to disk as BMP files and also get a full report
    const config = RasterConfig{
        .save_strategy = .disk,
        .image_save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .bmp, .bits = 8, .scaling = .auto },
        },
        .report = .bench,
    };
    var threaded_io = zraster.getThreadedIo(
        aa,
        init.minimal,
        config.total_threads,
    );
    defer threaded_io.deinit();
    const io = threaded_io.io();

    // 2. Define Data Paths
    // These paths contain CSV files for coordinates, connectivity, and fields
    const dir_paths = [_][]const u8{
        "data/simple/tri3_twoelems/",
        "data/simple/tri6_twoelems/",
        "data/simple/quad4_twoelems/",
        "data/simple/quad8_twoelems/",
        "data/simple/quad9_twoelems/",
    };

    const out_dir_root = "out/demo-multimesh";
    const pixel_num = [_]u32{ 1600, 800 };

    const mesh_types = [_]MeshType{
        .tri3,
        .tri6,
        .quad4ibi,
        .quad8,
        .quad9,
    };

    // 3. Load Simulation Data
    std.debug.print("Loading simulation data...\n", .{});
    // SimDataFiles with default values will load coords.csv, connectivity.csv,
    // and field_disp_[x,y,z].csv into both field and disp.
    const sim_datas = try meshio.loadMultiSimData(aa, io, &dir_paths, .{});

    // 4. Load Texture for shading
    std.debug.print("Loading texture...\n", .{});
    const texture = try iio.loadImage(
        u8,
        1,
        aa,
        io,
        "texture/speckle-simple.tiff",
        .tiff,
    );

    // 5. Prepare Mesh Inputs
    // We create 10 meshes: 5 with nodal shading (top) and 5 with texture shading (bottom)
    std.debug.print("Preparing mesh inputs...\n", .{});
    var mesh_inputs = try aa.alloc(MeshInput, 10);

    // Top Row (0-4): Nodal Shading
    for (0..5) |ii| {
        // Duplicate coordinates as they are modified by the rasteriser (displacement)
        const coords_dup = try MatSlice(f64).initAlloc(
            aa,
            sim_datas[ii].coords.mat.rows_num,
            sim_datas[ii].coords.mat.cols_num,
        );
        @memcpy(coords_dup.slice, sim_datas[ii].coords.mat.slice);

        mesh_inputs[ii] = MeshInput{
            .mesh_type = mesh_types[ii],
            .coords = meshio.Coords.init(coords_dup.slice, coords_dup.rows_num),
            .connect = sim_datas[ii].connect,
            .disp = sim_datas[ii].field,
            .shader = .{ .nodal = .{
                .field = sim_datas[ii].field.?,
                .bits = 8,
                .scaling = .auto,
                .scale_over = .within_frames,
            } },
        };
    }

    // Bottom Row (5-9): Texture Shading
    for (0..5) |ii| {
        const uv_path = try std.fmt.allocPrint(aa, "{s}uvs.csv", .{dir_paths[ii]});
        const uvs = try uvio.loadUVMap(aa, io, uv_path);

        const coords_dup = try MatSlice(f64).initAlloc(
            aa,
            sim_datas[ii].coords.mat.rows_num,
            sim_datas[ii].coords.mat.cols_num,
        );
        @memcpy(coords_dup.slice, sim_datas[ii].coords.mat.slice);

        mesh_inputs[ii + 5] = MeshInput{
            .mesh_type = mesh_types[ii],
            .coords = meshio.Coords.init(coords_dup.slice, coords_dup.rows_num),
            .connect = sim_datas[ii].connect,
            .disp = sim_datas[ii].field,
            .shader = .{ .tex = .{
                .uvs = uvs.array,
                .texture = texture,
                .sample_config = .{
                    .sample = .cubic_catmull_rom,
                    .mode = .lut_lerp,
                },
                .bits = 8,
                .scaling = .none,
            } },
        };
    }

    // 6. Arrange Meshes in a Grid
    // We arrange them in a 5x2 grid with 0.15 spacing
    mo.arrangeMeshSlice(mesh_inputs, .{ 0.15, 0.15, 0.0 }, .{ 5, 2, 1 });

    // 7. Setup Camera
    // Automatically position camera to fill frame based on mesh layout
    std.debug.print("Setting up camera...\n", .{});
    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);
    const fov_scale_factor: f64 = 1.2;

    const roi_pos = CameraOps.roiCentOverMeshes(mesh_inputs);
    const cam_pos = CameraOps.posFillFrameFromRotOverMeshes(
        mesh_inputs,
        pixel_num,
        pixel_size,
        focal_leng,
        rot,
        fov_scale_factor,
    );
    const camera = try CameraPrepared.init(
        aa,
        .{
            .pixels_num = pixel_num,
            .pixels_size = pixel_size,
            .pos_world = cam_pos,
            .rot_world = rot,
            .roi_cent_world = roi_pos,
            .focal_length = focal_leng,
            .sub_sample = 2,
        },
    );
    defer camera.deinit(aa);

    // 8. Run the Rasteriser
    std.debug.print("Rendering to {s}/...\n", .{out_dir_root});
    const camera_input = CameraInput{
        .pixels_num = camera.pixels_num,
        .pixels_size = camera.pixels_size,
        .pos_world = camera.pos_world,
        .rot_world = camera.rot_world,
        .roi_cent_world = camera.roi_cent_world,
        .focal_length = camera.focal_length,
        .sub_sample = camera.sub_sample,
        .distortion = camera.distortion,
    };
    const render_groups = [_]zraster.RenderGroupSpec{
        .{ .io = io, .workers = @max(@as(u16, 1), config.total_threads) },
    };
    const images = try zraster.rasterAllFrames(
        f64,
        aa,
        &render_groups,
        &[_]@TypeOf(camera_input){camera_input},
        mesh_inputs,
        config,
        out_dir_root,
    );

    if (images) |img| {
        aa.free(img.slice);
        img.deinit(aa);
    }

    std.debug.print("Demo complete. Images saved to {s}/\n", .{out_dir_root});
}
