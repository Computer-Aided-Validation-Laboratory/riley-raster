// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const MatSlice = @import("../zraster/zig/matslice.zig").MatSlice;
const NDArray = @import("../zraster/zig/ndarray.zig").NDArray;
const iio = @import("../zraster/zig/imageio.zig");
const meshio = @import("../zraster/zig/meshio.zig");
const mr = @import("../zraster/zig/meshraster.zig");
const uvio = @import("../zraster/zig/uvio.zig");
const Camera = @import("../zraster/zig/camera.zig").Camera;
const CameraOps = @import("../zraster/zig/camera.zig").CameraOps;
const Rotation = @import("../zraster/zig/camera.zig").Rotation;

pub const default_multimesh_mesh_types = [_]mr.MeshType{
    .tri3,
    .tri6,
    .quad4ibi,
    .quad8,
    .quad9,
};

pub const default_multimesh_dir_paths = [_][]const u8{
    "data-simple/tri3_twoelems/",
    "data-simple/tri6_twoelems/",
    "data-simple/quad4_twoelems/",
    "data-simple/quad8_twoelems/",
    "data-simple/quad9_twoelems/",
};

pub const default_pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
pub const default_focal_length: f64 = 50.0e-3;

pub fn defaultRotation() Rotation {
    return Rotation.init(0, 0, 0);
}

pub fn loadData(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
) !meshio.SimData {
    const coords_path = try std.fmt.allocPrint(
        outer_alloc,
        "{s}/coords.csv",
        .{path},
    );
    const connect_path = try std.fmt.allocPrint(
        outer_alloc,
        "{s}/connectivity.csv",
        .{path},
    );
    const field_paths = [_][]const u8{
        try std.fmt.allocPrint(outer_alloc, "{s}/field_disp_x.csv", .{path}),
        try std.fmt.allocPrint(outer_alloc, "{s}/field_disp_y.csv", .{path}),
        try std.fmt.allocPrint(outer_alloc, "{s}/field_disp_z.csv", .{path}),
    };
    return try meshio.loadSimData(
        outer_alloc,
        io,
        coords_path,
        connect_path,
        field_paths[0..],
        null,
    );
}

pub fn meshDataName(mesh_type: mr.MeshType) []const u8 {
    return switch (mesh_type) {
        .quad4ibi, .quad4newton => "quad4",
        else => @tagName(mesh_type),
    };
}

pub fn testTypeSuffix(test_type: []const u8) []const u8 {
    if (std.mem.eql(u8, test_type, "full")) return "fullscreen";
    if (std.mem.eql(u8, test_type, "twoelems")) return "twoelems";
    if (std.mem.eql(u8, test_type, "single")) return "single";
    return test_type;
}

pub fn initCameraForCoords(
    coords: *const meshio.Coords,
    pixel_num: [2]u32,
    fov_scale: f64,
) Camera {
    const rot = defaultRotation();
    const cam_pos = CameraOps.posFillFrameFromRot(
        coords,
        pixel_num,
        default_pixel_size,
        default_focal_length,
        rot,
        fov_scale,
    );
    return Camera.init(
        pixel_num,
        default_pixel_size,
        cam_pos,
        rot,
        CameraOps.roiCentFromCoords(coords),
        default_focal_length,
        2,
    );
}

pub fn initCameraForMeshes(
    mesh_inputs: []mr.MeshInput,
    pixel_num: [2]u32,
    fov_scale: f64,
) Camera {
    const rot = defaultRotation();
    const roi_pos = CameraOps.roiCentOverMeshes(mesh_inputs);
    const cam_pos = CameraOps.posFillFrameFromRotOverMeshes(
        mesh_inputs,
        pixel_num,
        default_pixel_size,
        default_focal_length,
        rot,
        fov_scale,
    );
    return Camera.init(
        pixel_num,
        default_pixel_size,
        cam_pos,
        rot,
        roi_pos,
        default_focal_length,
        2,
    );
}

pub const MultimeshShaderMode = enum { nodal, texture };

pub fn buildMultimeshInputs(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir_paths: []const []const u8,
    shader_mode: MultimeshShaderMode,
) ![]mr.MeshInput {
    const sim_datas = try meshio.loadMultiSimData(allocator, io, dir_paths, .{});
    const mesh_inputs = switch (shader_mode) {
        .nodal => try mr.meshInputFromSimDataSlice(
            allocator,
            io,
            sim_datas,
            &default_multimesh_mesh_types,
            .nodal,
            null,
            null,
            null,
        ),
        .texture => try mr.meshInputFromSimDataSlice(
            allocator,
            io,
            sim_datas,
            &default_multimesh_mesh_types,
            .texture,
            dir_paths,
            "texture/speckle-simple.tiff",
            null,
        ),
    };
    mr.arrangeMeshSlice(mesh_inputs, .{ 0.1, 0.1, 0.0 }, .{ 3, 2, 1 });
    return mesh_inputs;
}

fn copyCoords(
    allocator: std.mem.Allocator,
    coords: meshio.Coords,
) !meshio.Coords {
    var coords_dup = try MatSlice(f64).initAlloc(
        allocator,
        coords.mat.rows_num,
        coords.mat.cols_num,
    );
    @memcpy(coords_dup.slice, coords.mat.slice);
    return meshio.Coords.init(coords_dup.slice, coords_dup.rows_num);
}

fn buildGradientRgbField(
    allocator: std.mem.Allocator,
    coords: meshio.Coords,
    field: meshio.Field,
) !meshio.Field {
    const num_coords = coords.mat.rows_num;
    var rgb_field_arr = try NDArray(f64).initFlat(
        allocator,
        &[_]usize{ field.array.dims[0], num_coords, 3 },
    );

    var min_x: f64 = std.math.inf(f64);
    var max_x: f64 = -std.math.inf(f64);
    for (0..num_coords) |nn| {
        const x_val = coords.x(nn);
        if (x_val < min_x) min_x = x_val;
        if (x_val > max_x) max_x = x_val;
    }
    const range_x = max_x - min_x;

    for (0..field.array.dims[0]) |tt| {
        for (0..num_coords) |nn| {
            const x_val = coords.x(nn);
            const t = if (range_x > 0) (x_val - min_x) / range_x else 0.5;

            var rr: f64 = 0;
            var gg: f64 = 0;
            var bb: f64 = 0;

            if (t < 0.5) {
                const t_scaled = t * 2.0;
                rr = 1.0 - t_scaled;
                gg = t_scaled;
            } else {
                const t_scaled = (t - 0.5) * 2.0;
                gg = 1.0 - t_scaled;
                bb = t_scaled;
            }

            rgb_field_arr.set(&[_]usize{ tt, nn, 0 }, rr);
            rgb_field_arr.set(&[_]usize{ tt, nn, 1 }, gg);
            rgb_field_arr.set(&[_]usize{ tt, nn, 2 }, bb);
        }
    }

    return .{
        .array = rgb_field_arr,
        .array_mem = rgb_field_arr.slice,
    };
}

pub fn buildMixedMeshInputs(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir_paths: []const []const u8,
    texture: iio.Texture(1),
) ![]mr.MeshInput {
    const sim_datas = try meshio.loadMultiSimData(allocator, io, dir_paths, .{});
    var mesh_inputs = try allocator.alloc(mr.MeshInput, 10);

    for (0..default_multimesh_mesh_types.len) |ii| {
        mesh_inputs[ii] = .{
            .mesh_type = default_multimesh_mesh_types[ii],
            .coords = try copyCoords(allocator, sim_datas[ii].coords),
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

    for (0..default_multimesh_mesh_types.len) |ii| {
        const uv_path = try std.fmt.allocPrint(
            allocator,
            "{s}uvs.csv",
            .{dir_paths[ii]},
        );
        const uvs = try uvio.loadUVMap(allocator, io, uv_path);

        mesh_inputs[ii + default_multimesh_mesh_types.len] = .{
            .mesh_type = default_multimesh_mesh_types[ii],
            .coords = try copyCoords(allocator, sim_datas[ii].coords),
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

    mr.arrangeMeshSlice(mesh_inputs, .{ 0.15, 0.15, 0.0 }, .{ 5, 2, 1 });
    return mesh_inputs;
}

pub fn buildMixedRgbMeshInputs(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir_paths: []const []const u8,
    texture: iio.Texture(3),
) ![]mr.MeshInput {
    const sim_datas = try meshio.loadMultiSimData(allocator, io, dir_paths, .{});
    var mesh_inputs = try allocator.alloc(mr.MeshInput, 10);

    for (0..default_multimesh_mesh_types.len) |ii| {
        const uv_path = try std.fmt.allocPrint(
            allocator,
            "{s}uvs.csv",
            .{dir_paths[ii]},
        );
        const uvs = try uvio.loadUVMap(allocator, io, uv_path);

        mesh_inputs[ii] = .{
            .mesh_type = default_multimesh_mesh_types[ii],
            .coords = try copyCoords(allocator, sim_datas[ii].coords),
            .connect = sim_datas[ii].connect,
            .disp = sim_datas[ii].field,
            .shader = .{ .tex_rgb = .{
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

    for (0..default_multimesh_mesh_types.len) |ii| {
        const rgb_field = try buildGradientRgbField(
            allocator,
            sim_datas[ii].coords,
            sim_datas[ii].field.?,
        );

        mesh_inputs[ii + default_multimesh_mesh_types.len] = .{
            .mesh_type = default_multimesh_mesh_types[ii],
            .coords = try copyCoords(allocator, sim_datas[ii].coords),
            .connect = sim_datas[ii].connect,
            .disp = sim_datas[ii].field,
            .shader = .{ .nodal = .{
                .field = rgb_field,
                .bits = 8,
                .scaling = .auto,
                .scale_over = .within_frames,
            } },
        };
    }

    mr.arrangeMeshSlice(mesh_inputs, .{ 0.15, 0.15, 0.0 }, .{ 5, 2, 1 });
    return mesh_inputs;
}

pub fn openDirEnsured(io: std.Io, dir_path: []const u8) !std.Io.Dir {
    const cwd = std.Io.Dir.cwd();
    var parts_iter = std.mem.splitScalar(u8, dir_path, '/');
    var path_buf: [256]u8 = undefined;
    var path_len: usize = 0;

    while (parts_iter.next()) |part| {
        if (path_len > 0) {
            path_buf[path_len] = '/';
            path_len += 1;
        }
        std.mem.copyForwards(u8, path_buf[path_len..], part);
        path_len += part.len;
        cwd.createDir(io, path_buf[0..path_len], .default_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }

    return try cwd.openDir(io, dir_path, .{});
}
