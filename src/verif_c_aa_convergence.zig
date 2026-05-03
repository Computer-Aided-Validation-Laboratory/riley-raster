// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const orch = @import("common/orchestration.zig");
const zraster = @import("zraster/zig/zraster.zig");
const rastcfg = @import("zraster/zig/rasterconfig.zig");
const meshio = @import("zraster/zig/meshio.zig");
const uvio = @import("zraster/zig/uvio.zig");
const mo = @import("zraster/zig/meshops.zig");
const gk = @import("zraster/zig/geometrykernels.zig");
const iio = @import("zraster/zig/imageio.zig");
const imageops = @import("zraster/zig/imageops.zig");
const matslice = @import("zraster/zig/matslice.zig");
const ndarray = @import("zraster/zig/ndarray.zig");
const camera_mod = @import("zraster/zig/camera.zig");
const Rotation = @import("zraster/zig/rotation.zig").Rotation;

const MeshInput = mo.MeshInput;
const CameraPrepared = camera_mod.CameraPrepared;
const CameraOps = camera_mod.CameraOps;
const NDArrayOps = ndarray.NDArrayOps(f64);
const MatSlice = matslice.MatSlice(f64);

const rabbit_mesh_types = [_]gk.MeshType{
    .tri3,
    .tri6,
    .quad4ibi,
    .quad8,
    .quad9,
};

const rabbit_names = [_][]const u8{
    "tri3",
    "tri6",
    "quad4",
    "quad8",
    "quad9",
};

const rabbit_dir_paths = [_][]const u8{
    "data-rabbits/rabbit_tri3/",
    "data-rabbits/rabbit_tri6/",
    "data-rabbits/rabbit_quad4/",
    "data-rabbits/rabbit_quad8/",
    "data-rabbits/rabbit_quad9/",
};

// const ssaa_levels = [_]u8{ 64, 32, 16, 4, 2 };
const ssaa_levels = [_]u8{ 32, 16, 4, 2 };

const shader_names = [_][]const u8{ "funcsin", "tex" };

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const aa = arena.allocator();

    const out_verif_root = "out-verif";
    const pixel_num = [_]u32{ 640, 400 };
    const fov_scale: f64 = 1.01;

    std.debug.print("Loading speckle texture...\n", .{});
    const texture = try iio.loadImage(
        u8,
        1,
        aa,
        io,
        "texture/speckle-simple.tiff",
        .tiff,
    );

    for (rabbit_mesh_types, 0..) |mesh_type, ii| {
        const rabbit_name = rabbit_names[ii];
        const dir_path = rabbit_dir_paths[ii];

        std.debug.print("Processing rabbit: {s}\n", .{rabbit_name});

        const sim_datas = try meshio.loadMultiSimData(
            aa,
            io,
            &[_][]const u8{dir_path},
            .{
                .field_files = null,
                .disp_files = null,
            },
        );
        const sim_data = sim_datas[0];

        const uv_path = try std.fmt.allocPrint(aa, "{s}uvs.csv", .{dir_path});
        const uv_map = try uvio.loadUVMap(aa, io, uv_path);

        for (shader_names) |shader_name| {
            const out_dir_path = try std.fmt.allocPrint(
                aa,
                "{s}/c_{s}_{s}",
                .{ out_verif_root, rabbit_name, shader_name },
            );
            const out_dir = try orch.openDirEnsured(io, out_dir_path);

            var ref_mat = try MatSlice.initAlloc(aa, pixel_num[1], pixel_num[0]);
            var ssaa_mat = try MatSlice.initAlloc(aa, pixel_num[1], pixel_num[0]);
            var diff_mat = try MatSlice.initAlloc(aa, pixel_num[1], pixel_num[0]);

            for (ssaa_levels, 0..) |ssaa, jj| {
                var render_arena = std.heap.ArenaAllocator.init(aa);
                defer render_arena.deinit();
                const ra = render_arena.allocator();

                const rot = Rotation.init(0.0, std.math.pi, 0.0);

                var mesh_input = MeshInput{
                    .mesh_type = mesh_type,
                    .coords = try orch.copyCoords(ra, sim_data.coords),
                    .connect = sim_data.connect,
                    .disp = null,
                    .shader = undefined,
                };

                if (std.mem.eql(u8, shader_name, "funcsin")) {
                    mesh_input.shader = .{ .tex_func = .{
                        .uvs = uv_map.array,
                        .builtin = .sinusoidal,
                        .params = .{
                            .wave_num_scalar = .{
                                2.0*8.0 * std.math.pi,
                                2.0*8.0 * std.math.pi,
                            },
                        },
                        .bits = 8,
                        .scaling = .auto,
                        .normal_type = .none,
                    } };
                } else {
                    mesh_input.shader = .{ .tex = .{
                        .uvs = uv_map.array,
                        .texture = texture,
                        .sample_config = .{
                            .sample = .cubic_catmull_rom,
                            .mode = .lut_lerp,
                        },
                        .bits = 8,
                        .scaling = .none,
                        .normal_type = .none,
                    } };
                }

                const mesh_inputs = &[_]MeshInput{mesh_input};
                const roi_pos = CameraOps.roiCentOverMeshes(mesh_inputs);
                const cam_pos = CameraOps.posFillFrameFromRotOverMeshes(
                    mesh_inputs,
                    pixel_num,
                    orch.default_pixel_size,
                    orch.default_focal_length,
                    rot,
                    fov_scale,
                );

                std.debug.print("  Shader: {s}, SSAA: {d}\n", .{ shader_name, ssaa });

                const camera = try CameraPrepared.init(
                    ra,
                    .{
                        .pixels_num = pixel_num,
                        .pixels_size = orch.default_pixel_size,
                        .pos_world = cam_pos,
                        .rot_world = rot,
                        .roi_cent_world = roi_pos,
                        .focal_length = orch.default_focal_length,
                        .sub_sample = ssaa,
                    },
                );

                const camera_input = camera.toInput();
                const config = rastcfg.RasterConfig{
                    .save_strategy = .memory,
                    .report = .off,
                    .subpixel_center_map= .per_tile,
                };

                const images = try zraster.rasterAllFrames(
                    ra,
                    io,
                    &[_]@TypeOf(camera_input){camera_input},
                    mesh_inputs,
                    config,
                    null,
                    null,
                );

                if (images) |img| {
                    const fixed_idxs = [_]usize{ 0, 0, 0, 0, 0 };
                    try NDArrayOps.extractMat(ra, &img, &fixed_idxs, 3, 4, &ssaa_mat);

                    if (jj == 0) {
                        @memcpy(ref_mat.slice, ssaa_mat.slice);
                    }

                    for (0..pixel_num[1]) |rr| {
                        for (0..pixel_num[0]) |cc| {
                            const val_ref = ref_mat.get(rr, cc);
                            const val_ssaa = ssaa_mat.get(rr, cc);
                            diff_mat.set(rr, cc, val_ref - val_ssaa);
                        }
                    }

                    var name_buf: [64]u8 = undefined;
                    const ssaa_base = try std.fmt.bufPrint(
                        name_buf[0..],
                        "ssaa{d}",
                        .{ssaa},
                    );
                    try iio.saveMatAsImage(io, out_dir, ssaa_base, &ssaa_mat, .{
                        .format = .bmp,
                        .bits = 8,
                        .scaling = .auto,
                    });
                    const ssaa_csv_name = try std.fmt.allocPrint(
                        ra,
                        "ssaa{d}.csv",
                        .{ssaa},
                    );
                    try ssaa_mat.saveCSV(io, out_dir, ssaa_csv_name);

                    const diff_base = try std.fmt.bufPrint(
                        name_buf[0..],
                        "diff_ssaa{d}",
                        .{ssaa},
                    );
                    try iio.saveMatAsImage(io, out_dir, diff_base, &diff_mat, .{
                        .format = .bmp,
                        .bits = 8,
                        .scaling = .auto,
                    });
                    const diff_csv_name = try std.fmt.allocPrint(
                        ra,
                        "diff_ssaa{d}.csv",
                        .{ssaa},
                    );
                    try diff_mat.saveCSV(io, out_dir, diff_csv_name);
                }
            }
        }
    }

    std.debug.print("Convergence study complete.\n", .{});
}
