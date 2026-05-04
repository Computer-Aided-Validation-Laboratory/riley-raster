// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const benchcommon = @import("common/benchcommon.zig");
const orch = @import("common/orchestration.zig");
const tcfg = @import("common/testconfig.zig");
const buildconfig = @import("zraster/zig/buildconfig.zig");
const cfg = buildconfig.config;
const CameraPrepared = @import("zraster/zig/camera.zig").CameraPrepared;
const iio = @import("zraster/zig/imageio.zig");
const mo = @import("zraster/zig/meshops.zig");
const gk = @import("zraster/zig/geometrykernels.zig");
const meshio = @import("zraster/zig/meshio.zig");
const texops = @import("zraster/zig/textureops.zig");
const uvio = @import("zraster/zig/uvio.zig");
const zraster = @import("zraster/zig/zraster.zig");

const simd_on = cfg.simd == .on;

const RenderCase = struct {
    case_name: []const u8,
    data_dir: []const u8,
    mesh_type: gk.MeshType,
    channels: usize,
    shader: union(enum) {
        nodal_grey,
        tex8_rgb: texops.TextureSampleConfig,
    },
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    const out_root = if (simd_on)
        "gold/sphere200multicam-simd"
    else
        "gold/sphere200multicam";
    const pixel_num = [_]u32{ 800, 500 };

    const texture_rgb = try iio.loadImage(
        u8,
        3,
        allocator,
        io,
        "texture/speckle_rgb.bmp",
        .bmp,
    );
    defer texture_rgb.deinit(allocator);

    const render_cases = [_]RenderCase{
        .{
            .case_name = "tri3_nodal_grey",
            .data_dir = "data/bench/tri3_sphere200",
            .mesh_type = .tri3,
            .channels = 1,
            .shader = .nodal_grey,
        },
        .{
            .case_name = "tri6_tex8_rgb_cubic_catmull_rom_lut_lerp",
            .data_dir = "data/bench/tri6_sphere200",
            .mesh_type = .tri6,
            .channels = 3,
            .shader = .{
                .tex8_rgb = .{
                    .sample = .cubic_catmull_rom,
                    .mode = .lut_lerp,
                },
            },
        },
    };

    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, out_root, .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    for (render_cases) |render_case| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const aa = arena.allocator();

        const coord_path = try std.fs.path.join(
            aa,
            &[_][]const u8{ render_case.data_dir, "coords.csv" },
        );
        const connect_path = try std.fs.path.join(
            aa,
            &[_][]const u8{ render_case.data_dir, "connect.csv" },
        );
        const field_path = try std.fs.path.join(
            aa,
            &[_][]const u8{ render_case.data_dir, "field.csv" },
        );
        const sim_data = try meshio.loadSimData(
            aa,
            io,
            coord_path,
            connect_path,
            null,
            null,
        );
        const field_raw = try benchcommon.loadNDArrayFromCSV(
            aa,
            io,
            field_path,
            if (render_case.channels == 3) 3 else 1,
            true,
        );
        const cameras = try orch.initStereoCamerasForCoords(
            aa,
            &sim_data.coords,
            pixel_num,
            1.0,
            10.0,
        );
        defer for (cameras) |cam| cam.deinit(aa);
        const camera_inputs = [_]@TypeOf(cameras[0].toInput()){
            cameras[0].toInput(),
            cameras[1].toInput(),
        };

        const mesh_input = switch (render_case.shader) {
            .nodal_grey => mo.MeshInput{
                .mesh_type = render_case.mesh_type,
                .coords = sim_data.coords,
                .connect = sim_data.connect,
                .disp = null,
                .shader = .{
                    .nodal = .{
                        .field = .{
                            .array = field_raw,
                            .array_mem = field_raw.slice,
                        },
                        .scaling = .auto,
                    },
                },
            },
            .tex8_rgb => |sample_config| blk: {
                const uv_path = try std.fmt.allocPrint(
                    aa,
                    "{s}/uvs.csv",
                    .{render_case.data_dir},
                );
                const uv_map = try uvio.loadUVMap(aa, io, uv_path);
                break :blk mo.MeshInput{
                    .mesh_type = render_case.mesh_type,
                    .coords = sim_data.coords,
                    .connect = sim_data.connect,
                    .disp = null,
                    .shader = .{
                        .tex_rgb = .{
                            .uvs = uv_map.array,
                            .texture = texture_rgb,
                            .sample_config = sample_config,
                        },
                    },
                };
            },
        };

        var config = tcfg.rasterConfig(.gold);
        config.save_strategy = .disk;
        config.image_save_opts = &[_]iio.ImageSaveOpts{
            .{
                .format = .fimg,
                .bits = null,
                .scaling = .none,
                .channels = render_case.channels,
            },
        };

        const out_dir_path = try std.fs.path.join(
            aa,
            &[_][]const u8{ out_root, render_case.case_name },
        );
        std.debug.print(
            "Rendering multicamera gold: {s}/{s}\n",
            .{ out_root, render_case.case_name },
        );

        _ = try zraster.rasterAllFrames(
            aa,
            io,
            &camera_inputs,
            &[_]mo.MeshInput{mesh_input},
            config,
            out_dir_path,
            null,
        );
    }

    std.debug.print(
        "Done. Multicamera gold references established for .simd = .{s}.\n",
        .{if (simd_on) "on" else "off"},
    );
}
