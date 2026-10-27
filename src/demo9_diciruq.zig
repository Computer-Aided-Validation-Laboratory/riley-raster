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
const riley = @import("riley/zig/riley.zig");
const meshio = @import("riley/zig/meshio.zig");
const uvio = @import("riley/zig/uvio.zig");
const imageio = @import("riley/zig/imageio.zig");
const meshpipe = @import("riley/zig/meshpipeline.zig");
const shaderops = @import("riley/zig/shaderops.zig");
const shaderpipe = @import("riley/zig/shaderpipe.zig");
const texops = @import("riley/zig/textureops.zig");
const camera = @import("riley/zig/camera.zig");
const cameraops = @import("riley/zig/cameraops.zig");
const cameraio = @import("riley/zig/cameraio.zig");
const sceneops = @import("riley/zig/sceneops.zig");
const Rotation = @import("riley/zig/rotation.zig").Rotation;
const buildconfig = @import("riley/zig/buildconfig.zig");
const F = buildconfig.F;

fn buildTemperatureField(
    allocator: std.mem.Allocator,
    coords: meshio.Coords,
    frames: usize,
) !meshio.Field {
    var min_y: F = std.math.inf(F);
    var max_y: F = -std.math.inf(F);
    for (0..coords.mat.rows_num) |node| {
        const y = coords.mat.get(node, 1); // FE plate vertical axis is world y.
        min_y = @min(min_y, y);
        max_y = @max(max_y, y);
    }
    if (max_y <= min_y) return error.DegenerateVerticalExtent;
    var field = try meshio.Field.initAlloc(allocator, frames, coords.mat.rows_num, 1);
    for (0..frames) |frame| {
        for (0..coords.mat.rows_num) |node| {
            const y = coords.mat.get(node, 1);
            const norm_y = (y - min_y) / (max_y - min_y);
            field.array.set(&.{ frame, node, 0 }, 323.15 + 150.0 * norm_y);
        }
    }
    return field;
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    const io = init.io;

    // -------------------------------------------------------------------------
    // 1. Setup paths and parameters
    // -------------------------------------------------------------------------
    const data_dir = "data/FE/platehole3d_2mr_7f/";
    const out_path = "./out/demo9_diciruq";

    // -------------------------------------------------------------------------
    // 2. Load simulation data, displacement, and temperature fields
    // -------------------------------------------------------------------------
    const disp_files = [_][]const u8{
        data_dir ++ "field_disp_x.csv",
        data_dir ++ "field_disp_y.csv",
        data_dir ++ "field_disp_z.csv",
    };
    const sim_data = try meshio.loadSimData(
        allocator,
        io,
        data_dir ++ "coords.csv",
        data_dir ++ "connect.csv",
        null,
        &disp_files,
    );
    const disp = sim_data.disp orelse return error.MissingDisplacement;
    const frame_indices = try sceneops.selectFirstLastFrameIndices(
        allocator,
        disp.getTimeN(),
    );
    const selected_disp = try sceneops.selectFieldFrames(
        allocator,
        &disp,
        frame_indices,
    );
    const temperature = try buildTemperatureField(
        allocator,
        sim_data.coords,
        selected_disp.getTimeN(),
    );

    // -------------------------------------------------------------------------
    // 3. Setup shaders, pipe stages, and radiance lookup
    // -------------------------------------------------------------------------
    const uvs = try uvio.loadUVMap(allocator, io, data_dir ++ "uvs.csv");
    const texture = try imageio.loadImage(
        u8,
        1,
        allocator,
        io,
        "texture/speckle_mono.bmp",
        .bmp,
    );
    const speckle_tex = shaderops.TexInput(texops.TexDataFix(u8, 1)){
        .uvs = uvs.array,
        .tex = texture,
        .samp_cfg = .{
            .sample = .cubic_catmull_rom,
            .mode = .direct,
        },

        .scaling = .none,
    };
    const speckle_source: shaderops.PipeSourceInput = .{ .tex_u8 = speckle_tex };
    const speckle_mono: shaderops.ShaderMonoInput = .{ .tex_u8 = speckle_tex };

    const channel = shaderpipe.Slot{ .kind = .channel, .index = 0 };
    const field = shaderpipe.Slot{ .kind = .field, .index = 0 };
    const parameter = shaderpipe.Slot{ .kind = .parameter, .index = 0 };

    const stages = [_]shaderops.ShaderPipeStageInput{
        .{
            .source = .{
                .shader = speckle_source,
                .destination = channel,
            },
        },
        .{
            .grey_to_emissivity = .{
                .source = channel,
                .destination = parameter,
                .black = 0.96,
                .white = 0.90,
                .grey_black = 0.0,
                .grey_white = 255.0,
            },
        },
        .{
            .source = .{
                .shader = .{
                    .nodal = .{
                        .field = temperature,

                        .scaling = .none,
                    },
                },
                .destination = field,
            },
        },
    };

    // Unit, flat 8–14 µm response; the lookup stores integrated spectral radiance.
    var wavelengths: [25]F = undefined;
    const response: [25]F = @splat(1.0);
    for (&wavelengths, 0..) |*lambda, ii| {
        lambda.* = (8.0 + 0.25 * @as(F, @floatFromInt(ii))) * 1e-6;
    }
    const band_resp = shaderpipe.BandResponse{
        .wavelengths_m = &wavelengths,
        .response = &response,
    };
    const radiance = try band_resp.prepareRadianceLookup(
        allocator,
        270.0,
        500.0,
        0.25,
    );

    const mesh = meshpipe.MeshInput{
        .mesh_type = .quad8,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = selected_disp,
        .shaders = .{
            .mono = .{ .direct = speckle_mono },
            .ir = .{ .pipe = .{
                .stages = &stages,
                .resolver = .{
                    .greybody_band_apparent_c = .{
                        .temperature = field,
                        .emissivity = parameter,
                        .radiance = radiance,
                        .ambient_k = 293.15,
                    },
                },
            } },
        },
    };

    // -------------------------------------------------------------------------
    // 4. Configure stereo DIC and IR cameras
    // -------------------------------------------------------------------------
    const target = sceneops.boundsCenter(&sim_data.coords);
    const dic_pixels = [2]u32{ 2464, 2056 };
    const dic_pitch = [2]F{ 3.45e-6, 3.45e-6 };
    const ir_pixels = [2]u32{ 640, 480 };
    const ir_pitch = [2]F{ 17e-6, 17e-6 };

    const left_rot = Rotation.init(
        0.0,
        std.math.degreesToRadians(@as(F, -10.0)),
        0.0,
    );
    const right_rot = Rotation.init(
        0.0,
        std.math.degreesToRadians(@as(F, 10.0)),
        0.0,
    );
    const ir_rot = Rotation.init(0.0, 0.0, 0.0);

    const distort: camera.DistortParams = .{
        .brown_con = camera.BrownCon.Params{
            .k1 = -0.2,
            .k2 = 0.1,
            .k3 = 0.0,
            .p1 = 0.0001,
            .p2 = -0.0001,
        },
    };

    const left_pos = cameraops.posFillFrameFromRotAndTarg(
        &sim_data.coords,
        target,
        dic_pixels,
        dic_pitch,
        0.05,
        left_rot,
        0.65,
    );
    const left = camera.CameraInput{
        .output_files = &.{.{ .format = .tiff, .bits = 16, .scaling = .none }},
        .pixels_num = dic_pixels,
        .pixels_size = dic_pitch,
        .pos_world = left_pos,
        .rot_world = left_rot,
        .roi_cent_world = target,
        .focal_length = 0.05,
        .sub_sample = 4,
        .distort = distort,
        .output_encoding = .{ .grid12_to_u16 = .{ 0.0, 255.0 } },
    };

    const ir_pos = cameraops.posFillFrameFromRotAndTarg(
        &sim_data.coords,
        target,
        ir_pixels,
        ir_pitch,
        0.035,
        ir_rot,
        0.65,
    );
    const ir = camera.CameraInput{
        .output_files = &.{.{ .format = .tiff, .bits = 16, .scaling = .none }},
        .pixels_num = ir_pixels,
        .pixels_size = ir_pitch,
        .pos_world = ir_pos,
        .rot_world = ir_rot,
        .roi_cent_world = target,
        .focal_length = 0.035,
        .sub_sample = 4,
        .render_format = .ir,
        .output_encoding = .{ .linear_u16 = .{ 0.0, 250.0 } },
    };

    var right = left;
    right.rot_world = right_rot;
    right.pos_world = cameraops.posFillFrameFromRotAndTarg(
        &sim_data.coords,
        target,
        dic_pixels,
        dic_pitch,
        0.05,
        right_rot,
        0.65,
    );

    // -------------------------------------------------------------------------
    // 5. Configure raster engine and render multimodal scene
    // -------------------------------------------------------------------------
    const config = riley.RasterConfig{
        .render_mode = .offline,
        .parallel = .{ .threads = 4 },
        .save_strategy = .disk,
        .background_value = 0.0,
    };

    var out_dir = try demo_common.resetOutputDir(io, out_path);
    defer out_dir.close(io);

    const images = try riley.raster(
        init.gpa,
        io,
        &.{ left, ir, right },
        &.{mesh},
        config,
        out_path,
    );
    if (images) |image| {
        init.gpa.free(image.slice);
        image.deinit(init.gpa);
    }

    // -------------------------------------------------------------------------
    // 6. Save calibration data and acquisition metadata
    // -------------------------------------------------------------------------
    try cameraio.saveStereoPair(
        io,
        out_dir,
        "stereo_data_opengl.csv",
        .{ .cameras = .{ left, right } },
    );

    const metadata = try out_dir.createFile(io, "acquisition_metadata.txt", .{});
    defer metadata.close(io);
    var buffer: [2048]u8 = undefined;
    var writer = metadata.writer(io, &buffer);
    try writer.interface.writeAll(
        "cam0=left DIC (-10 deg), cam1=IR (0 deg), cam2=right DIC (+10 deg)\n" ++
            "Frames: first and last FE displacement frames from demo3 dataset.\n" ++
            "DIC: source 0..255 -> round(source/255*4095)*16 in uint16 TIFF; " ++
            "4096 effective codes, range 0..65520.\n" ++
            "IR: flat 8-14 um band, ambient 293.15 K, black/white emissivity 0.96/0.90.\n" ++
            "IR pixel is blackbody-equivalent apparent temperature C, " ++
            "encoded round(clamp(C/250,0,1)*65535).\n" ++
            "Decode IR: C = code*250/65535. " ++
            "This is not emissivity-corrected true temperature.\n",
    );
    try writer.interface.flush();
}
