// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const print = std.debug.print;

const riley = @import("riley/zig/riley.zig");
const RasterConfig = riley.RasterConfig;
const meshio = @import("riley/zig/meshio.zig");
const uvio = @import("riley/zig/uvio.zig");
const iio = @import("riley/zig/imageio.zig");
const mo = @import("riley/zig/meshops.zig");
const MeshInput = mo.MeshInput;
const gk = @import("riley/zig/geometrykernels.zig");
const MeshType = gk.MeshType;
const camera_mod = @import("riley/zig/camera.zig");
const Rotation = @import("riley/zig/rotation.zig").Rotation;
const CameraInput = camera_mod.CameraInput;
const CameraOps = camera_mod.CameraOps;
const DistortionModel = camera_mod.DistortionModel;
const BrownConrady = camera_mod.BrownConrady;
const MatSlice = @import("riley/zig/matslice.zig").MatSlice;

const DATA_DIR = "data/FE/platehole3d_2mr_63f/";
const TEXTURE_PATH = "texture/speckle.bmp";
const OUT_DIR_ROOT = "./out/demo-dicuq";

const PIXELS_NUM = [2]u32{ 2464, 2056 };
const PIXELS_SIZE = [2]f64{ 3.45e-6, 3.45e-6 };
const FOCAL_LENGTH: f64 = 50.0e-3;
const FOV_SCALE_FACTOR: f64 = 0.65;
const SUB_SAMPLE: u8 = 2;
const STEREO_ANGLE_DEG: f64 = 20.0;

const TOTAL_THREADS: u16 = 8;
const MAX_FRAMES_IN_FLIGHT: u16 = 1;
const FRAME_BATCH_SIZE_PER_GROUP: u16 = 1;
const MAX_GEOM_JOBS_IN_FLIGHT_PER_GROUP: u16 = 1;
const RENDER_GROUP_COUNT: usize = 8;
const WORKERS_PER_GROUP: u16 = 1;

const DISTORTION = true; 


pub fn main(init: std.process.Init) !void {
    const outer_alloc = init.gpa;

    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const aa = arena.allocator();

    // 1. Setup Rasteriser Configuration
    const config = RasterConfig{
        .render_mode = .offline,
        .total_threads = TOTAL_THREADS,
        .max_frames_in_flight = MAX_FRAMES_IN_FLIGHT,
        .max_geom_workers_per_frame = 1,
        .max_raster_workers_per_frame = 1,
        .frame_batch_size_per_group = FRAME_BATCH_SIZE_PER_GROUP,
        .max_geom_jobs_in_flight_per_group = MAX_GEOM_JOBS_IN_FLIGHT_PER_GROUP,
        .max_geom_workers_per_job = 1,
        .geom_scheduling_mode = .spread,
        .max_raster_workers_per_job = 1,
        .save_strategy = .disk,
        .tile_size_min = 8,
        .tile_size_max = 128,
        .background_value = 128.0,
        .image_save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .bmp, .bits = 8, .scaling = .auto },
        },
        .report = .bench,
    };
    const managed_ios = try outer_alloc.alloc(std.Io.Threaded, RENDER_GROUP_COUNT);
    defer {
        for (managed_ios) |*managed_io| {
            managed_io.deinit();
        }
        outer_alloc.free(managed_ios);
    }
    const render_groups = try outer_alloc.alloc(riley.RenderGroupSpec, RENDER_GROUP_COUNT);
    defer outer_alloc.free(render_groups);
    for (0..RENDER_GROUP_COUNT) |gg| {
        managed_ios[gg] = riley.getThreadedIo(
            aa,
            init.minimal,
            WORKERS_PER_GROUP,
        );
        render_groups[gg] = .{
            .io = managed_ios[gg].io(),
            .workers = WORKERS_PER_GROUP,
        };
    }
    const io = render_groups[0].io;

    // 2. Load Simulation Data
    std.debug.print("Loading simulation data from {s}...\n", .{DATA_DIR});
    const coord_path = DATA_DIR ++ "coords.csv";
    const conn_path = DATA_DIR ++ "connect.csv";

    const field_files = &[_][]const u8{
        DATA_DIR ++ "field_disp_x.csv",
        DATA_DIR ++ "field_disp_y.csv",
        DATA_DIR ++ "field_disp_z.csv",
    };

    // For this demo, we don't need the field data as we are using texture shading
    const sim_data = try meshio.loadSimData(
        aa,
        io,
        coord_path,
        conn_path,
        null,
        field_files,
    );

    // 3. Load UV map for the texture
    std.debug.print("Loading UV map...\n", .{});
    const uv_path = DATA_DIR ++ "uvs.csv";
    const uvs = try uvio.loadUVMap(aa, io, uv_path);

    // 4. Load Texture for shading
    std.debug.print("Loading speckle texture...\n", .{});
    const texture = try iio.loadImage(
        u8,
        1,
        aa,
        io,
        TEXTURE_PATH,
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
    const roi_pos = CameraOps.roiCentFromCoords(&sim_data.coords);

    const distortion: DistortionModel = if (!DISTORTION)
        .none
    else
        .{ .brown_conrady = BrownConrady{
            .k1 = -0.19,
            .k2 = -1.17,
            .k3 = 25.0,
            .p1 = 0.0004,
            .p2 = -0.0007,
        } };

    // Camera 0: face on
    const cam0_rot = Rotation.init(
        std.math.degreesToRadians(0.0), //alpha_z_deg
        std.math.degreesToRadians(0.0), //beta_y_deg - stereo axis
        std.math.degreesToRadians(0.0), //gamma_x_deg
    );

    const cam0_pos = CameraOps.posFillFrameFromRot(
        &sim_data.coords,
        PIXELS_NUM,
        PIXELS_SIZE,
        FOCAL_LENGTH,
        cam0_rot,
        FOV_SCALE_FACTOR,
    );

    const cam0_in = CameraInput{
        .pixels_num = PIXELS_NUM,
        .pixels_size = PIXELS_SIZE,
        .pos_world = cam0_pos,
        .rot_world = cam0_rot,
        .roi_cent_world = roi_pos,
        .focal_length = FOCAL_LENGTH,
        .sub_sample = SUB_SAMPLE,
        .distortion = distortion,
    };

    // Camera 1: stereo angle
    const cam1_rot = Rotation.init(
        std.math.degreesToRadians(0.0), //alpha_z_deg
        std.math.degreesToRadians(STEREO_ANGLE_DEG), //beta_y_deg - stereo axis
        std.math.degreesToRadians(0.0), //gamma_x_deg
    );

    const cam1_pos = CameraOps.posFillFrameFromRot(
        &sim_data.coords,
        PIXELS_NUM,
        PIXELS_SIZE,
        FOCAL_LENGTH,
        cam1_rot,
        FOV_SCALE_FACTOR,
    );

    const cam1_in = CameraInput{
        .pixels_num = PIXELS_NUM,
        .pixels_size = PIXELS_SIZE,
        .pos_world = cam1_pos,
        .rot_world = cam1_rot,
        .roi_cent_world = roi_pos,
        .focal_length = FOCAL_LENGTH,
        .sub_sample = SUB_SAMPLE,
        .distortion = distortion,
    };

    // 7. Run the Rasteriser
    std.debug.print("Rendering simulation to {s}/...\n", .{OUT_DIR_ROOT});
    const meshes = [_]MeshInput{mesh_input};
    const cams_in = [_]CameraInput{ cam0_in, cam1_in };
    const images = try riley.rasterAllFrames(
        aa,
        render_groups,
        &cams_in,
        &meshes,
        config,
        OUT_DIR_ROOT,
    );

    if (images) |img| {
        aa.free(img.slice);
        img.deinit(aa);
    }

    std.debug.print("Demo complete. Images saved to {s}/\n", .{OUT_DIR_ROOT});

    const print_break = [_]u8{'='} ** 80;
    print("\n{s}\n", .{print_break});

    print("ROI center:\n", .{});
    roi_pos.vecPrint();

    print("Camera 0:\n", .{});
    cam0_pos.vecPrint();

    print("Camera 1:\n", .{});
    cam1_pos.vecPrint();

    var out_dir = try std.Io.Dir.cwd().openDir(io, OUT_DIR_ROOT, .{});
    defer out_dir.close(io);
    try CameraOps.saveStereoPair(
        io,
        out_dir,
        .{
            .cameras = .{ cam0_in, cam1_in },
        },
    );

    print("{s}\n", .{print_break});
}
