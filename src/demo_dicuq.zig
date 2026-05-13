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

    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const aa = arena.allocator();

    // 1. Setup Rasteriser Configuration
    const config = RasterConfig{
        .render_mode = .in_order,
        .total_threads = 4,
        .max_frames_in_flight = 2,
        .max_geom_workers_per_frame = 1,
        .max_raster_workers_per_frame = 4,
        .save_strategy = .disk,
        .tile_size_min = 8,
        .tile_size_max = 128,
        .background_value = 128.0,
        .image_save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .bmp, .bits = 8, .scaling = .auto },
        },
        .report = .bench,
    };
    var threaded_io = zraster.getThreadedIo(
        outer_alloc,
        init.minimal,
        config.total_threads,
    );
    defer threaded_io.deinit();
    const io = threaded_io.io();

    const data_dir = "data/FE/platehole3d_4mr_2f/";
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
    const sim_data = try meshio.loadSimData(aa, 
                                            io, 
                                            coord_path, 
                                            conn_path, 
                                            null, 
                                            field_files,);

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
    const mesh_input = MeshInput{
        .mesh_type = .quad8,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = sim_data.disp,
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

    // 6. Setup Camera
    std.debug.print("Setting up camera...\n", .{});
    // Common camera parameters: typical 5MPx 
    const pixel_num = [_]u32{ 2464, 2056 };
    const pixel_size = [_]f64{ 3.45e-6, 3.45e-6 };
    const focal_leng: f64 = 50.0e-3;
    const fov_scale_factor: f64 = 0.9;
    const sub_samp: u8 = 2; 

    const roi_pos = CameraOps.roiCentFromCoords(&sim_data.coords);
        
    // Camera 0: face on
    const cam0_rot = Rotation.init(
        std.math.degreesToRadians(0.0), //alpha_z_deg
        std.math.degreesToRadians(0.0),  //beta_y_deg - stereo axis
        std.math.degreesToRadians(0.0), //gamma_x_deg
    );
    
    const cam0_pos = CameraOps.posFillFrameFromRot(
        &sim_data.coords,
        pixel_num,
        pixel_size,
        focal_leng,
        cam0_rot,
        fov_scale_factor,
    );

    const cam0_in = CameraInput{
        .pixels_num = pixel_num,
        .pixels_size = pixel_size,
        .pos_world = cam0_pos,
        .rot_world = cam0_rot,
        .roi_cent_world = roi_pos,
        .focal_length = focal_leng,
        .sub_sample = sub_samp,     
    };

    // Camera 1: stereo angle
    const cam1_rot = Rotation.init(
        std.math.degreesToRadians(0.0), //alpha_z_deg
        std.math.degreesToRadians(20.0),  //beta_y_deg - stereo axis
        std.math.degreesToRadians(0.0), //gamma_x_deg
    );
    
    const cam1_pos = CameraOps.posFillFrameFromRot(
        &sim_data.coords,
        pixel_num,
        pixel_size,
        focal_leng,
        cam1_rot,
        fov_scale_factor,
    );

    const cam1_in = CameraInput{
        .pixels_num = pixel_num,
        .pixels_size = pixel_size,
        .pos_world = cam1_pos,
        .rot_world = cam1_rot,
        .roi_cent_world = roi_pos,
        .focal_length = focal_leng,
        .sub_sample = sub_samp,     
    };
        
    // 7. Run the Rasteriser
    std.debug.print("Rendering simulation to {s}/...\n", .{out_dir_root});
    const meshes = [_]MeshInput{mesh_input};
    const cams_in = [_]CameraInput{cam0_in,cam1_in};
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

    const print_break = [_]u8{'='} ** 80;
    print("\n{s}\n",.{print_break});

    print("ROI center:\n",.{});
    roi_pos.vecPrint();
    
    print("Camera 0:\n",.{});
    cam0_pos.vecPrint();

    print("Camera 1:\n",.{});
    cam1_pos.vecPrint();

    print("{s}\n",.{print_break});

}
