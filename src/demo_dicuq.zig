// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

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
const Rotation = @import("zraster/zig/rotation.zig").Rotation;
const CameraInput = camera_mod.CameraInput;
const CameraOps = camera_mod.CameraOps;
const MatSlice = @import("zraster/zig/matslice.zig").MatSlice;

pub fn main(init: std.process.Init) !void {
    const outer_alloc = init.gpa;
    const io = init.io;

    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const aa = arena.allocator();

    // 1. Setup Rasteriser Configuration
    const config = RasterConfig{
        .render_mode = .in_order,
        .total_threads = 4,
        .max_frames_in_flight = 1,
        .max_geom_threads_per_frame = 1,
        .max_raster_threads_per_frame = 4,
        .save_strategy = .disk,
        .image_save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .bmp, .bits = 8, .scaling = .auto },
        },
        .report = .bench,
    };

    const data_dir = "data/FE/platewithhole3d_1/";
    const out_dir_root = "out/demo-dicuq";
    
    // 2. Load Simulation Data
    std.debug.print("Loading simulation data from {s}...\n", .{data_dir});
    const coord_path = data_dir ++ "coords.csv";
    const conn_path = data_dir ++ "connect.csv";
    
    const field_files = &[_][]const u8{
        data_dir ++ "field_disp_x.csv",
        data_dir ++ "field_disp_y.csv",
        data_dir ++ "field_disp_z.csv",
    };

    // For this demo, we don't need the field data as we are using texture shading
    const sim_data = try meshio.loadSimData(aa, io, coord_path, conn_path, field_files, field_files,);

    // 3. Load UV map for the texture
    std.debug.print("Loading UV map...\n", .{});
    const uv_path = data_dir ++ "uvs.csv";
    const uvs = try uvio.loadUVMap(aa, io, uv_path);

    // 4. Load Texture for shading
    std.debug.print("Loading speckle texture...\n", .{});
    const texture = try iio.loadImage(
        u8,
        1,
        aa,
        io,
        "texture/speckle.bmp",
        .bmp,
    );

    // 5. Prepare Mesh Input
    std.debug.print("Preparing mesh input...\n", .{});
    const use_tex: bool = true;
    var mesh_input: MeshInput = undefined;

    if (use_tex){
        mesh_input = MeshInput{
            .mesh_type = .quad8,
            .coords = sim_data.coords,
            .connect = sim_data.connect,
            .disp = null,
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
    } else {
        mesh_input = MeshInput{
            .mesh_type = .quad8,
            .coords = sim_data.coords,
            .connect = sim_data.connect,
            .disp = null,
            .shader = .{ .tex_func = .{
                .uvs = null,
                .builtin = .checker_smooth,
            } },
        };
    }

    // 6. Setup Camera
    // Position camera to frame the sphere
    std.debug.print("Setting up camera...\n", .{});
    // Typical 5MPx 
    const pixel_num = [_]u32{ 2464, 2056 };
    const pixel_size = [_]f64{ 3.45e-6, 3.45e-6 };
    const focal_leng: f64 = 50.0e-3;

    const alpha_z_deg = 0.0;
    const beta_y_deg = 0.0; // Use this to get the stereo angle
    const gamma_x_deg = 0.0;
    const cam_rot = Rotation.init(
        std.math.degreesToRadians(alpha_z_deg),
        std.math.degreesToRadians(beta_y_deg),
        std.math.degreesToRadians(gamma_x_deg),
    );
    
    const fov_scale_factor: f64 = 0.9;

    const roi_pos = CameraOps.roiCentFromCoords(&sim_data.coords);
    const cam_pos = CameraOps.posFillFrameFromRot(
        &sim_data.coords,
        pixel_num,
        pixel_size,
        focal_leng,
        cam_rot,
        fov_scale_factor,
    );

    const cam_in = CameraInput{
        .pixels_num = pixel_num,
        .pixels_size = pixel_size,
        .pos_world = cam_pos,
        .rot_world = cam_rot,
        .roi_cent_world = roi_pos,
        .focal_length = focal_leng,
        .sub_sample = 2,     
    };
    
    // 7. Run the Rasteriser
    std.debug.print("Rendering simulation to {s}/...\n", .{out_dir_root});
    const meshes = [_]MeshInput{mesh_input};
    const cams_in = [_]CameraInput{cam_in};
    const images = try zraster.rasterAllFrames(
        aa,
        io,
        &cams_in,
        &meshes,
        config,
        out_dir_root,
        null,
    );

    if (images) |img| {
        aa.free(img.slice);
        img.deinit(aa);
    }

    std.debug.print("Demo complete. Images saved to {s}/\n", .{out_dir_root});
}
