// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const demo_common = @import("demo_common.zig");

const buildconfig = @import("riley/zig/buildconfig.zig");
const riley = @import("riley/zig/riley.zig");
const meshio = @import("riley/zig/meshio.zig");
const uvio = @import("riley/zig/uvio.zig");
const iio = @import("riley/zig/imageio.zig");
const meshpipe = @import("riley/zig/meshpipeline.zig");
const camera = @import("riley/zig/camera.zig");
const cameraops = @import("riley/zig/cameraops.zig");
const sceneops = @import("riley/zig/sceneops.zig");
const Rotation = @import("riley/zig/rotation.zig").Rotation;

const F = buildconfig.F;

pub fn main(init: std.process.Init) !void {
    const outer_alloc = init.gpa;

    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const local_alloc = arena.allocator();

    // -------------------------------------------------------------------------
    // 1. Setup paths and parameters
    // -------------------------------------------------------------------------
    const raster_threads: u16 = 4;

    const config_base = riley.RasterConfig{
        .save_strategy = .disk,
        .parallel = .{ .threads = raster_threads },
        .output = .{
            .image_save_opts = &[_]iio.ImageSaveOpts{
                .{ .format = .bmp, .bits = 8, .scaling = .auto },
            },
        },
        .report = .{ .mode = .bench },
    };

    const io = init.io;

    const data_dir = "data/min/tri6_sphere200/";
    const out_dir_root = "./out/demo5_cameramodels";

    const pixels_num = [_]u32{ 800, 500 };

    // -------------------------------------------------------------------------
    // 2. Load mesh data and texture shader
    // -------------------------------------------------------------------------
    std.debug.print(
        "Loading sphere simulation data from {s}...\n",
        .{data_dir},
    );
    const sim_data = try meshio.loadSimData(
        local_alloc,
        io,
        data_dir ++ "coords.csv",
        data_dir ++ "connect.csv",
        null,
        null,
    );
    const uvs = try uvio.loadUVMap(local_alloc, io, data_dir ++ "uvs.csv");
    const texture = try iio.loadImage(
        u8,
        1,
        local_alloc,
        io,
        "texture/speckle_mono.bmp",
        .bmp,
    );
    const mesh = meshpipe.MeshInput{
        .mesh_type = .tri6,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = null,
        .shader = .{ .tex_u8 = .{
            .uvs = uvs.array,
            .tex = texture,
            .samp_cfg = .{
                .sample = .cubic_catmull_rom,
                .mode = .lut_lerp,
            },
            .bits = 8,
            .scaling = .none,
        } },
    };

    // -------------------------------------------------------------------------
    // 3. Position the base camera
    // -------------------------------------------------------------------------
    const pixel_size = [_]F{ 5.3e-6, 5.3e-6 };
    const focal_length: F = 50.0e-3;
    const rotation = Rotation.init(0, 0, 0);
    const roi_cent_world = sceneops.boundsCenter(&sim_data.coords);

    const pos_world = cameraops.posFillFrameFromRot(
        &sim_data.coords,
        pixels_num,
        pixel_size,
        focal_length,
        rotation,
        1.0,
    );

    const camera_input = camera.CameraInput{
        .pixels_num = pixels_num,
        .pixels_size = pixel_size,
        .pos_world = pos_world,
        .rot_world = rotation,
        .roi_cent_world = roi_cent_world,
        .focal_length = focal_length,
        .sub_sample = 2,
    };

    // -------------------------------------------------------------------------
    // 4. Compare every distortion family and PSF path across buffer modes
    // -------------------------------------------------------------------------
    const poly = camera.PolyMap{
        .degree = 2,
        .mode = .displacement,
        .coeffs = &.{
            0,    0,     0.02,  -0.01,  0.01,   -0.015,
            0.01, 0.005, 0.005, -0.005, -0.005, 0.01,
        },
    };

    const brown = camera.BrownCon.Params{
        .k1 = -0.12,
        .k2 = 0.035,
        .p1 = 0.0002,
        .p2 = -0.0001,
    };

    const brown_ext = camera.BrownConExt.Params{
        .k1 = brown.k1,
        .k2 = brown.k2,
        .k4 = -0.04,
        .k5 = 0.018,
        .p1 = brown.p1,
        .p2 = brown.p2,
        .s1 = 0.00001,
        .s2 = -0.000002,
        .tau_x = 0.005,
        .tau_y = -0.003,
    };

    const distorts = [_]camera.DistortParams{
        .none,
        .{ .brown_con = brown },
        .{ .brown_con_ext = brown_ext },
        .{ .poly = poly },
        .{ .brown_con_poly = .{
            .brown_con = brown,
            .poly = poly,
        } },
        .{ .brown_con_ext_poly = .{
            .brown_con_ext = brown_ext,
            .poly = poly,
        } },
    };

    const distort_names = [_][]const u8{
        "none",
        "brown_conrady",
        "brown_conrady_ext",
        "polynomial",
        "brown_conrady_polynomial",
        "brown_conrady_ext_polynomial",
    };

    const psf_names = [_][]const u8{
        "pixel_box",
        "gaussian_separable",
        "gaussian_nonseparable",
        "anisotropic_separable",
        "anisotropic_rotated",
    };

    const psfs = [_]camera.PointSpreadFunc{
        .{ .pixel_box = .{} },
        .{ .gaussian = .{ .sigma_px = 1.0, .supp_rad_px = 3.0, .separable = .yes } },
        .{ .gaussian = .{ .sigma_px = 1.0, .supp_rad_px = 3.0, .separable = .no } },
        .{ .anisotropic_gaussian = .{
            .sigma_x_px = 1.2,
            .sigma_y_px = 0.4,
            .supp_rad_px = 3.0,
            .separable = .yes,
        } },
        .{ .anisotropic_gaussian = .{
            .sigma_x_px = 1.2,
            .sigma_y_px = 0.4,
            .theta_rad = 0.35,
            .supp_rad_px = 3.0,
            .separable = .no,
        } },
    };

    const modes = [_]riley.BufferMode{
        .tile_local,
        .global_subpx_full,
        .global_subpx_stripe,
    };

    var output_root = try demo_common.resetOutputDir(io, out_dir_root);
    defer output_root.close(io);

    for (distorts, distort_names) |distort, distort_name| {
        for (psfs, psf_names) |psf, psf_name| {
            for (modes) |mode| {
                var config = config_base;
                config.advanced.raster.buffer_mode = mode;
                var cam = camera_input;
                cam.distort = distort;
                cam.psf = psf;

                const out_dir = try std.fs.path.join(local_alloc, &.{
                    out_dir_root, distort_name, psf_name, @tagName(mode),
                });

                std.debug.print("Rendering {s}/{s}/{s}...\n", .{
                    distort_name, psf_name, @tagName(mode),
                });

                if (try riley.raster(
                    outer_alloc,
                    io,
                    &.{cam},
                    &.{mesh},
                    config,
                    out_dir,
                )) |image| {
                    outer_alloc.free(image.slice);
                    var image_mut = image;
                    image_mut.deinit(outer_alloc);
                }
            }
        }
    }

    std.debug.print("Demo complete. Images saved to {s}/\n", .{out_dir_root});
}
