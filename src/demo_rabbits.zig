// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const orch = @import("common/orchestration.zig");
const riley = @import("riley/zig/riley.zig");
const rastcfg = @import("riley/zig/rasterconfig.zig");
const meshio = @import("riley/zig/meshio.zig");
const uvio = @import("riley/zig/uvio.zig");
const mo = @import("riley/zig/meshops.zig");
const gk = @import("riley/zig/geometrykernels.zig");
const iio = @import("riley/zig/imageio.zig");
const so = @import("riley/zig/shaderops_common.zig");
const cammod = @import("riley/zig/camera.zig");
const cameraops = @import("riley/zig/cameraops.zig");
const Rotation = @import("riley/zig/rotation.zig").Rotation;

const CameraInput = cammod.CameraInput;
const CameraPrepared = cammod.CameraPrepared;
const MeshInput = mo.MeshInput;
const TexFuncBuiltin = so.TexFuncBuiltin;

const OVERLAP_X: f64 = 0.85;
const OVERLAP_Y: f64 = 0.8;
const BEHIND_FACT: f64 = 1.05;

const pixel_num = [_]u32{ 1600, 800 };
const fov_scale: f64 = 1.01;
const out_dir_root = "./out/demo-rabbits";
const pair_gap_factor: f64 = 0.18;
const row_gap_factor: f64 = 0.28;
const feebs_front_riley_shift_factor: f64 = 0.1;

const rabbit_mesh_types = [_]gk.MeshType{
    .tri3,
    .tri6,
    .quad4ibi,
    .quad8,
    .quad9,
};

const Bounds2D = struct {
    min_x: f64,
    max_x: f64,
    min_y: f64,
    max_y: f64,

    fn width(self: Bounds2D) f64 {
        return self.max_x - self.min_x;
    }

    fn height(self: Bounds2D) f64 {
        return self.max_y - self.min_y;
    }

    fn centerX(self: Bounds2D) f64 {
        return 0.5 * (self.min_x + self.max_x);
    }

    fn centerY(self: Bounds2D) f64 {
        return 0.5 * (self.min_y + self.max_y);
    }
};

fn translateCoords(coords: *meshio.Coords, translation: [3]f64) void {
    for (0..coords.mat.rows_num) |nn| {
        coords.mat.set(nn, 0, coords.mat.get(nn, 0) + translation[0]);
        coords.mat.set(nn, 1, coords.mat.get(nn, 1) + translation[1]);
        coords.mat.set(nn, 2, coords.mat.get(nn, 2) + translation[2]);
    }
}

fn boundsForCoords(coords_a: *const meshio.Coords, coords_b: *const meshio.Coords) Bounds2D {
    var min_x = std.math.inf(f64);
    var max_x = -std.math.inf(f64);
    var min_y = std.math.inf(f64);
    var max_y = -std.math.inf(f64);

    const coords_list = [_]*const meshio.Coords{ coords_a, coords_b };
    for (coords_list) |coords| {
        for (0..coords.mat.rows_num) |nn| {
            const xx = coords.mat.get(nn, 0);
            const yy = coords.mat.get(nn, 1);
            min_x = @min(min_x, xx);
            max_x = @max(max_x, xx);
            min_y = @min(min_y, yy);
            max_y = @max(max_y, yy);
        }
    }

    return .{
        .min_x = min_x,
        .max_x = max_x,
        .min_y = min_y,
        .max_y = max_y,
    };
}

fn buildRabbitDir(
    allocator: std.mem.Allocator,
    rabbit_name: []const u8,
    mesh_type: gk.MeshType,
) ![]const u8 {
    return try std.fmt.allocPrint(
        allocator,
        "data/rabbits/{s}_{s}",
        .{ rabbit_name, orch.meshDataName(mesh_type) },
    );
}

fn loadStaticMesh(
    allocator: std.mem.Allocator,
    io: std.Io,
    data_dir: []const u8,
) !meshio.SimData {
    const coords_path = try std.fmt.allocPrint(allocator, "{s}/coords.csv", .{data_dir});
    const connect_path = try std.fmt.allocPrint(allocator, "{s}/connectivity.csv", .{data_dir});
    return try meshio.loadSimData(
        allocator,
        io,
        coords_path,
        connect_path,
        null,
        null,
    );
}

fn buildUvRgbField(
    allocator: std.mem.Allocator,
    uvs: uvio.UVMap,
) !meshio.Field {
    const node_num = uvs.array.dims[0];
    var field = try meshio.Field.initAlloc(allocator, 1, node_num, 3);

    for (0..node_num) |nn| {
        const uu = uvs.array.get(&[_]usize{ nn, 0 });
        const vv = uvs.array.get(&[_]usize{ nn, 1 });
        field.array.set(&[_]usize{ 0, nn, 0 }, uu);
        field.array.set(&[_]usize{ 0, nn, 1 }, vv);
        field.array.set(&[_]usize{ 0, nn, 2 }, 0.5 * (uu + vv));
    }

    return field;
}

fn sinusoidalUvParams() so.TexFuncParams {
    const wave_num = 2.0 * std.math.pi * 6.0;
    return .{
        .wave_num_scalar = .{ wave_num, wave_num },
    };
}

fn makeMeshInput(
    allocator: std.mem.Allocator,
    mesh_type: gk.MeshType,
    sim_data: meshio.SimData,
    coords: meshio.Coords,
    uvs: uvio.UVMap,
    texture: iio.Texture(1),
    texture_rgb: iio.Texture(3),
    shader_index: usize,
) !MeshInput {
    return switch (shader_index % 5) {
        0 => .{
            .mesh_type = mesh_type,
            .coords = coords,
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
                .normal_type = .none,
            } },
        },
        1 => .{
            .mesh_type = mesh_type,
            .coords = coords,
            .connect = sim_data.connect,
            .disp = null,
            .shader = .{ .tex_rgb = .{
                .uvs = uvs.array,
                .texture = texture_rgb,
                .sample_config = .{
                    .sample = .cubic_catmull_rom,
                    .mode = .lut_lerp,
                },
                .bits = 8,
                .scaling = .none,
                .normal_type = .none,
            } },
        },
        2 => .{
            .mesh_type = mesh_type,
            .coords = coords,
            .connect = sim_data.connect,
            .disp = null,
            .shader = .{ .nodal = .{
                .field = try buildUvRgbField(allocator, uvs),
                .bits = 8,
                .scaling = .auto,
                .scale_over = .over_frames,
                .normal_type = .none,
            } },
        },
        3 => .{
            .mesh_type = mesh_type,
            .coords = coords,
            .connect = sim_data.connect,
            .disp = null,
            .shader = .{ .func = .{
                .uvs = uvs.array,
                .builtin = .sinusoidal,
                .params = sinusoidalUvParams(),
                .bits = 8,
                .scaling = .auto,
                .normal_type = .none,
            } },
        },
        else => .{
            .mesh_type = mesh_type,
            .coords = coords,
            .connect = sim_data.connect,
            .disp = null,
            .shader = .{ .func_rgb = .{
                .uvs = uvs.array,
                .builtin = TexFuncBuiltin.sinusoidal,
                .params = sinusoidalUvParams(),
                .bits = 8,
                .scaling = .auto,
                .normal_type = .none,
            } },
        },
    };
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const aa = arena.allocator();

    const rot = Rotation.init(0.0, std.math.pi, 0.0);

    std.debug.print("Loading texture...\n", .{});
    const texture = try iio.loadImage(
        u8,
        1,
        aa,
        io,
        "texture/speckle.bmp",
        .bmp,
    );
    const texture_rgb = try iio.loadImage(
        u8,
        3,
        aa,
        io,
        "texture/speckle.bmp",
        .bmp,
    );

    std.debug.print("Preparing rabbit pairs...\n", .{});
    var mesh_inputs = try aa.alloc(MeshInput, rabbit_mesh_types.len * 2);
    var pair_widths: [rabbit_mesh_types.len]f64 = undefined;
    var pair_heights: [rabbit_mesh_types.len]f64 = undefined;
    var pair_center_xs: [rabbit_mesh_types.len]f64 = undefined;
    var pair_center_ys: [rabbit_mesh_types.len]f64 = undefined;
    var max_pair_width: f64 = 0.0;
    var max_pair_height: f64 = 0.0;

    for (rabbit_mesh_types, 0..) |mesh_type, ii| {
        const riley_dir = try buildRabbitDir(aa, "riley", mesh_type);
        const feebs_dir = try buildRabbitDir(aa, "feebs", mesh_type);

        const riley_sim_data = try loadStaticMesh(aa, io, riley_dir);
        const feebs_sim_data = try loadStaticMesh(aa, io, feebs_dir);

        const riley_uv_path = try std.fmt.allocPrint(aa, "{s}/uvs.csv", .{riley_dir});
        const feebs_uv_path = try std.fmt.allocPrint(aa, "{s}/uvs.csv", .{feebs_dir});
        const riley_uvs = try uvio.loadUVMap(aa, io, riley_uv_path);
        const feebs_uvs = try uvio.loadUVMap(aa, io, feebs_uv_path);

        const riley_coords = try orch.copyCoords(aa, riley_sim_data.coords);
        const feebs_coords = try orch.copyCoords(aa, feebs_sim_data.coords);

        const base_bounds = mo.findAlignedCentroid(&riley_coords);
        const x_sep = base_bounds.extent[0] * (1.0 - OVERLAP_X);
        const y_sep = base_bounds.extent[1] * (1.0 - OVERLAP_Y);
        const feebs_front_riley_shift = [3]f64{
            feebs_front_riley_shift_factor * base_bounds.extent[0],
            feebs_front_riley_shift_factor * base_bounds.extent[1],
            0.0,
        };

        const riley_front = (ii % 2) == 0;
        const front_idx = ii * 2;
        const back_idx = front_idx + 1;

        var front_mesh = if (riley_front)
            try makeMeshInput(
                aa,
                mesh_type,
                riley_sim_data,
                riley_coords,
                riley_uvs,
                texture,
                texture_rgb,
                front_idx,
            )
        else
            try makeMeshInput(
                aa,
                mesh_type,
                feebs_sim_data,
                feebs_coords,
                feebs_uvs,
                texture,
                texture_rgb,
                front_idx,
            );

        var back_mesh = if (riley_front)
            try makeMeshInput(
                aa,
                mesh_type,
                feebs_sim_data,
                feebs_coords,
                feebs_uvs,
                texture,
                texture_rgb,
                back_idx,
            )
        else
            try makeMeshInput(
                aa,
                mesh_type,
                riley_sim_data,
                riley_coords,
                riley_uvs,
                texture,
                texture_rgb,
                back_idx,
            );

        translateCoords(&front_mesh.coords, .{ 0.5 * x_sep, -0.5 * y_sep, 0.0 });
        translateCoords(&back_mesh.coords, .{ -0.5 * x_sep, 0.5 * y_sep, 0.0 });
        if (!riley_front) {
            translateCoords(&back_mesh.coords, feebs_front_riley_shift);
        }

        const temp_meshes = [_]MeshInput{ front_mesh, back_mesh };
        const roi_pos = cameraops.roiCentOverMeshes(&temp_meshes);
        const cam_pos = cameraops.posFillFrameFromRotOverMeshes(
            &temp_meshes,
            pixel_num,
            orch.default_pixel_size,
            orch.default_focal_length,
            rot,
            fov_scale,
        );

        const front_centroid = mo.findAlignedCentroid(&front_mesh.coords).centroid;
        const cam_axis = [3]f64{
            cam_pos.slice[0] - roi_pos.slice[0],
            cam_pos.slice[1] - roi_pos.slice[1],
            cam_pos.slice[2] - roi_pos.slice[2],
        };
        const cam_axis_norm = @sqrt(
            cam_axis[0] * cam_axis[0] +
                cam_axis[1] * cam_axis[1] +
                cam_axis[2] * cam_axis[2],
        );
        const cam_axis_unit = [3]f64{
            cam_axis[0] / cam_axis_norm,
            cam_axis[1] / cam_axis_norm,
            cam_axis[2] / cam_axis_norm,
        };
        const front_dist =
            (cam_pos.slice[0] - front_centroid[0]) * cam_axis_unit[0] +
            (cam_pos.slice[1] - front_centroid[1]) * cam_axis_unit[1] +
            (cam_pos.slice[2] - front_centroid[2]) * cam_axis_unit[2];
        const behind_extra = (BEHIND_FACT - 1.0) * front_dist;
        translateCoords(&back_mesh.coords, .{
            -cam_axis_unit[0] * behind_extra,
            -cam_axis_unit[1] * behind_extra,
            -cam_axis_unit[2] * behind_extra,
        });

        const pair_bounds = boundsForCoords(&front_mesh.coords, &back_mesh.coords);
        pair_widths[ii] = pair_bounds.width();
        pair_heights[ii] = pair_bounds.height();
        pair_center_xs[ii] = pair_bounds.centerX();
        pair_center_ys[ii] = pair_bounds.centerY();
        max_pair_width = @max(max_pair_width, pair_widths[ii]);
        max_pair_height = @max(max_pair_height, pair_heights[ii]);

        mesh_inputs[front_idx] = front_mesh;
        mesh_inputs[back_idx] = back_mesh;
    }

    const pair_gap_x = pair_gap_factor * max_pair_width;
    const row_gap_y = row_gap_factor * max_pair_height;
    const top_row_total_width = blk: {
        var accum: f64 = 0.0;
        for (0..2) |ii| accum += pair_widths[ii];
        accum += pair_gap_x;
        break :blk accum;
    };
    const bottom_row_total_width = blk: {
        var accum: f64 = 0.0;
        for (2..rabbit_mesh_types.len) |ii| accum += pair_widths[ii];
        accum += pair_gap_x * 2.0;
        break :blk accum;
    };
    const top_row_max_height = @max(pair_heights[0], pair_heights[1]);
    const bottom_row_max_height = blk: {
        var max_height: f64 = 0.0;
        for (2..rabbit_mesh_types.len) |ii| {
            max_height = @max(max_height, pair_heights[ii]);
        }
        break :blk max_height;
    };
    const top_row_center_y = 0.5 * (bottom_row_max_height + row_gap_y);
    const bottom_row_center_y = -0.5 * (top_row_max_height + row_gap_y);

    var top_cursor = -0.5 * top_row_total_width;
    for (0..2) |ii| {
        const desired_center_x = top_cursor + 0.5 * pair_widths[ii];
        const delta_x = desired_center_x - pair_center_xs[ii];
        const delta_y = top_row_center_y - pair_center_ys[ii];

        translateCoords(&mesh_inputs[ii * 2].coords, .{ delta_x, delta_y, 0.0 });
        translateCoords(&mesh_inputs[ii * 2 + 1].coords, .{ delta_x, delta_y, 0.0 });

        top_cursor += pair_widths[ii] + pair_gap_x;
    }

    var bottom_cursor = -0.5 * bottom_row_total_width;
    for (2..rabbit_mesh_types.len) |ii| {
        const desired_center_x = bottom_cursor + 0.5 * pair_widths[ii];
        const delta_x = desired_center_x - pair_center_xs[ii];
        const delta_y = bottom_row_center_y - pair_center_ys[ii];

        translateCoords(&mesh_inputs[ii * 2].coords, .{ delta_x, delta_y, 0.0 });
        translateCoords(&mesh_inputs[ii * 2 + 1].coords, .{ delta_x, delta_y, 0.0 });

        bottom_cursor += pair_widths[ii] + pair_gap_x;
    }

    std.debug.print("Setting up camera...\n", .{});
    const roi_pos = cameraops.roiCentOverMeshes(mesh_inputs);
    const cam_pos = cameraops.posFillFrameFromRotOverMeshes(
        mesh_inputs,
        pixel_num,
        orch.default_pixel_size,
        orch.default_focal_length,
        rot,
        fov_scale,
    );
    const camera = try CameraPrepared.init(
        aa,
        .{
            .pixels_num = pixel_num,
            .pixels_size = orch.default_pixel_size,
            .pos_world = cam_pos,
            .rot_world = rot,
            .roi_cent_world = roi_pos,
            .focal_length = orch.default_focal_length,
            .sub_sample = 2,
        },
    );
    defer camera.deinit(aa);

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

    std.debug.print("Rendering rabbits to {s}/...\n", .{out_dir_root});
    const image_modes = [_]rastcfg.ImageMode{
        .multifield,
        .grey,
        .rgb,
    };
    for (image_modes) |image_mode| {
        const mode_out_dir = try std.fmt.allocPrint(
            aa,
            "{s}/{s}",
            .{ out_dir_root, @tagName(image_mode) },
        );
        const config = rastcfg.RasterConfig{
            .save_strategy = .disk,
            .image_mode = image_mode,
            .background_value = 0.0,
            .image_save_opts = &[_]iio.ImageSaveOpts{
                .{ .format = .bmp, .bits = 8, .scaling = .auto },
            },
        };
        const render_groups_mode = [_]riley.RenderGroupSpec{
            .{
                .io = io,
                .workers = @max(@as(u16, 1), config.total_threads),
            },
        };
        const images = try riley.rasterAllFrames(
            aa,
            &render_groups_mode,
            &[_]CameraInput{camera_input},
            mesh_inputs,
            config,
            mode_out_dir,
        );
        if (images) |img| {
            aa.free(img.slice);
            img.deinit(aa);
        }
    }

    std.debug.print("Done.\n", .{});
}
