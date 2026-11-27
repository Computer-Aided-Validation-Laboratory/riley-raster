// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
// --------------------------------------------------------------------------------------
const meshtypes = @import("meshtypes.zig");
const shadertypes = @import("shadertypes.zig");
const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const ndarray = @import("ndarray.zig");

const F = buildconfig.F;

// --------------------------------------------------------------------------------------
// Public Error Set
// --------------------------------------------------------------------------------------

pub const InputArrayError = error{
    InvalidConnectivityIndex,
    DegenerateElementIndices,
    NonFiniteCoordinates,
    NonFiniteDisplacements,
    NonFiniteNodalFields,
    NonFiniteUvs,
    NonFiniteTexels,
};

// --------------------------------------------------------------------------------------
// Public Entry-Point Function
// --------------------------------------------------------------------------------------

/// Scans full mesh array payloads (connectivity bounds and uniqueness, floating coordinates,
/// displacements, nodal fields, UVs, and floating textures for non-finite values).
/// Assumes structural and metadata validity checks from `checkRenderInps()` have passed.
pub fn checkRenderArrs(meshes: []const meshtypes.MeshInput) InputArrayError!void {
    for (meshes) |mesh| {
        try checkMeshConnectivity(mesh);
        try checkMeshCoordinates(mesh);
        try checkMeshDisplacements(mesh);
        try checkMeshShaderArrays(mesh);
    }
}

pub fn checkUvLayout(uvs: *const ndarray.NDArray(F), coords_num: usize) error{InvalidUvDimensions}!void {
    if (uvs.dims.len != 2 or uvs.strides.len != 2 or
        uvs.dims[0] != coords_num or uvs.dims[1] != 2)
        return error.InvalidUvDimensions;

    if (coords_num == 0) return;
    // Strides are nonnegative; (last node, V) is the maximum logical offset.
    const last_node = std.math.mul(usize, coords_num - 1, uvs.strides[0]) catch
        return error.InvalidUvDimensions;
    const last_uv = std.math.add(usize, last_node, uvs.strides[1]) catch
        return error.InvalidUvDimensions;
    if (last_uv >= uvs.slice.len) return error.InvalidUvDimensions;
}

pub fn checkTexMultiLayout(tex: anytype) error{InvalidTextureDimensions}!void {
    const dims = tex.array.dims;
    const strides = tex.array.strides;
    const rows = tex.rows_num;
    const cols = tex.cols_num;
    // Texture sampling assumes unit column stride but uses the supplied row and channel strides.
    if (dims.len != 3 or dims[0] < 2 or dims[0] > buildconfig.config.max_image_channels or
        rows == 0 or cols == 0 or rows != dims[1] or cols != dims[2] or
        strides.len != 3 or strides[2] != 1)
        return error.InvalidTextureDimensions;

    const last_ch = std.math.mul(usize, dims[0] - 1, strides[0]) catch
        return error.InvalidTextureDimensions;
    const last_row = std.math.mul(usize, rows - 1, strides[1]) catch
        return error.InvalidTextureDimensions;
    const last_start = std.math.add(usize, last_ch, last_row) catch
        return error.InvalidTextureDimensions;
    if (cols > tex.array.slice.len or last_start > tex.array.slice.len - cols)
        return error.InvalidTextureDimensions;
    const plane_size = std.math.mul(usize, rows, cols) catch return error.InvalidTextureDimensions;
    _ = std.math.mul(usize, dims[0], plane_size) catch return error.InvalidTextureDimensions;
}

// --------------------------------------------------------------------------------------
// Connectivity Scans
// --------------------------------------------------------------------------------------

fn checkMeshConnectivity(mesh: meshtypes.MeshInput) InputArrayError!void {
    const coords_num = mesh.coords.mat.rows_num;
    const elems_num = mesh.connect.table.rows_num;
    const nodes_per_elem = mesh.connect.table.cols_num;

    for (0..elems_num) |elem_index| {
        const elem_nodes = mesh.connect.table.getSlice(elem_index);

        // Check index range
        for (elem_nodes) |node_index| {
            if (node_index >= coords_num) {
                return error.InvalidConnectivityIndex;
            }
        }

        // Check for any duplicate vertex indices in this element
        for (0..nodes_per_elem) |ii| {
            for ((ii + 1)..nodes_per_elem) |jj| {
                if (elem_nodes[ii] == elem_nodes[jj]) {
                    return error.DegenerateElementIndices;
                }
            }
        }
    }
}

// --------------------------------------------------------------------------------------
// Coordinate and Displacement Scans
// --------------------------------------------------------------------------------------

fn checkMeshCoordinates(mesh: meshtypes.MeshInput) InputArrayError!void {
    if (!isFiniteSlice(mesh.coords.mem)) {
        return error.NonFiniteCoordinates;
    }
}

fn checkMeshDisplacements(mesh: meshtypes.MeshInput) InputArrayError!void {
    if (mesh.disp) |disp_field| {
        if (!isFiniteSlice(disp_field.array_mem)) {
            return error.NonFiniteDisplacements;
        }
    }
}

// --------------------------------------------------------------------------------------
// Shader Payload Scans (Nodal Fields, UVs, Floating Textures)
// --------------------------------------------------------------------------------------

fn checkMeshShaderArrays(mesh: meshtypes.MeshInput) InputArrayError!void {
    if (mesh.shaders.mono_direct) |shader| try checkShaderMonoArrays(shader);
    if (mesh.shaders.mono_pipe) |pipe| try checkPipeArrays(pipe);
    if (mesh.shaders.ir_direct) |shader| try checkShaderMonoArrays(shader);
    if (mesh.shaders.ir_pipe) |pipe| try checkPipeArrays(pipe);
    if (mesh.shaders.rgb_pipe) |pipe| try checkPipeArrays(pipe);
    if (mesh.shaders.multifield_pipe) |pipe| try checkPipeArrays(pipe);
}

fn checkPipeArrays(pipe: shadertypes.ShaderPipeInput) InputArrayError!void {
    for (pipe.stages) |stage| {
        switch (stage) {
            .shader => |src| try checkPipeSourceArrays(src.shader),
            else => {},
        }
    }
}

fn checkUvArrays(uvs: *const ndarray.NDArray(F)) InputArrayError!void {
    // The layout is already checked. Scan only logical entries, not padding.
    const nodes = uvs.dims[0];
    const node_stride = uvs.strides[0];
    const uv_stride = uvs.strides[1];
    if (node_stride == 2 and uv_stride == 1) {
        if (!isFiniteSlice(uvs.slice[0 .. nodes * 2])) return error.NonFiniteUvs;
    } else {
        for (0..nodes) |node| {
            const start = node * node_stride;
            if (!std.math.isFinite(uvs.slice[start]) or
                !std.math.isFinite(uvs.slice[start + uv_stride])) return error.NonFiniteUvs;
        }
    }
}

fn checkShaderMonoArrays(shader: shadertypes.ShaderMonoInput) InputArrayError!void {
    switch (shader) {
        .tex_u8 => |t| try checkUvArrays(&t.uvs),
        .speckle => |speckle| try checkUvArrays(&speckle.uvs),
        .speckle3d => {},
        .tex_u16 => |t| try checkUvArrays(&t.uvs),
        .tex_f => |t| {
            try checkUvArrays(&t.uvs);
            if (!isFiniteSlice(t.tex.array.slice)) return error.NonFiniteTexels;
        },
        .nodal => |n| {
            if (!isFiniteSlice(n.field.array_mem)) return error.NonFiniteNodalFields;
        },
        .func => |f| {
            if (f.uvs) |uvs| try checkUvArrays(&uvs);
        },
    }
}

fn checkPipeSourceArrays(source: shadertypes.PipeSourceInput) InputArrayError!void {
    switch (source) {
        .tex_u8 => |t| try checkUvArrays(&t.uvs),
        .speckle => |speckle| try checkUvArrays(&speckle.uvs),
        .speckle3d => {},
        .tex_u16 => |t| try checkUvArrays(&t.uvs),
        .tex_f => |t| {
            try checkUvArrays(&t.uvs);
            if (!isFiniteSlice(t.tex.array.slice)) return error.NonFiniteTexels;
        },
        .tex_rgb_u8 => |t| try checkUvArrays(&t.uvs),
        .tex_rgb_u16 => |t| try checkUvArrays(&t.uvs),
        .tex_rgb_f => |t| {
            try checkUvArrays(&t.uvs);
            if (!isFiniteSlice(t.tex.array.slice)) return error.NonFiniteTexels;
        },
        .tex_multi_u8 => |t| try checkUvArrays(&t.uvs),
        .tex_multi_u16 => |t| try checkUvArrays(&t.uvs),
        .tex_multi_f => |t| {
            try checkUvArrays(&t.uvs);
            const array = &t.tex.array;
            const cols = t.tex.cols_num;
            const plane_size = t.tex.rows_num * cols;
            if (array.strides[0] == plane_size and array.strides[1] == cols) {
                if (!isFiniteSlice(array.slice[0 .. array.dims[0] * plane_size]))
                    return error.NonFiniteTexels;
            } else {
                for (0..array.dims[0]) |ch| {
                    for (0..t.tex.rows_num) |row| {
                        const start = array.subBase2(ch, row);
                        if (!isFiniteSlice(array.slice[start..][0..cols]))
                            return error.NonFiniteTexels;
                    }
                }
            }
        },
        .nodal => |n| {
            if (!isFiniteSlice(n.field.array_mem)) return error.NonFiniteNodalFields;
        },
        .func, .func_rgb => |f| {
            if (f.uvs) |uvs| try checkUvArrays(&uvs);
        },
        .func_multi => |f| {
            if (f.uvs) |uvs| try checkUvArrays(&uvs);
        },
    }
}

// --------------------------------------------------------------------------------------
// Generic Finite Scanning Helpers
// --------------------------------------------------------------------------------------

fn isFiniteSlice(values: []const F) bool {
    for (values) |val| {
        if (!std.math.isFinite(val)) {
            return false;
        }
    }
    return true;
}

test "full multifield payload validation ignores texture padding but rejects non-finite texels" {
    var uv_mem = [_]F{ 0, 0, 1, 0, 0, 1 };
    var uv_dims = [_]usize{ 3, 2 };
    var uv_strides = [_]usize{ 2, 1 };
    var tex_dims = [_]usize{ 2, 2, 2 };
    var tex_strides = [_]usize{ 7, 3, 1 };
    const pad = std.math.nan(F);
    var texels = [_]F{ 2, 4, pad, 3, 6, pad, pad, 5, 8, pad, 9, 10, pad };
    var input: shadertypes.PipeSourceInput = .{ .tex_multi_f = .{
        .uvs = .{ .slice = &uv_mem, .dims = &uv_dims, .strides = &uv_strides },
        .tex = .{
            .array = .{ .slice = &texels, .dims = &tex_dims, .strides = &tex_strides },
            .rows_num = 2,
            .cols_num = 2,
        },
    } };
    try checkTexMultiLayout(input.tex_multi_f.tex);
    try checkPipeSourceArrays(input);
    texels[11] = std.math.inf(F);
    try checkTexMultiLayout(input.tex_multi_f.tex);
    try std.testing.expectError(error.NonFiniteTexels, checkPipeSourceArrays(input));

    // The flat scan must also ignore unused trailing storage.
    @memset(texels[0..8], 1);
    tex_strides = .{ 4, 2, 1 };
    try checkTexMultiLayout(input.tex_multi_f.tex);
    try checkPipeSourceArrays(input);
    input.tex_multi_f.tex.array.slice = texels[0..7];
    try std.testing.expectError(error.InvalidTextureDimensions, checkTexMultiLayout(input.tex_multi_f.tex));
}

test "full speckle array validation scans UVs and connectivity" {
    const alloc = std.testing.allocator;
    var coords = [_]F{ 0, 0, 0, 1, 0, 0, 0, 1, 0 };
    var connect = [_]usize{ 0, 1, 2 };
    // This pass checks finiteness; mesh preparation checks the interpolated UV domain.
    var values = [_]F{ -0.5, 0, 1.5, 0, 0, 1 };
    const uvs = try ndarray.NDArray(F).init(alloc, &values, &.{ 3, 2 });
    defer uvs.deinit(alloc);
    const mesh = meshtypes.MeshInput{
        .mesh_type = .tri3,
        .coords = meshtypes.Coords.init(&coords, 3),
        .connect = meshtypes.Connect.init(&connect, 1, 3),
        .disp = null,
        .shaders = .{ .mono_direct = .{ .speckle = .{
            .uvs = uvs,
            .params = .{ .disk = .{ .coverage = 0.5, .radius = 0.1 } },
        } } },
    };
    try checkRenderArrs(&.{mesh});
    for ([_]F{ std.math.nan(F), std.math.inf(F), -std.math.inf(F) }) |invalid| {
        values[0] = invalid;
        try std.testing.expectError(error.NonFiniteUvs, checkRenderArrs(&.{mesh}));
        try std.testing.expectError(error.NonFiniteUvs, checkPipeSourceArrays(.{ .speckle = mesh.shaders.mono_direct.?.speckle }));
    }
    values[0] = 0;
    connect[2] = 3;
    try std.testing.expectError(error.InvalidConnectivityIndex, checkRenderArrs(&.{mesh}));
    connect[2] = 1;
    try std.testing.expectError(error.DegenerateElementIndices, checkRenderArrs(&.{mesh}));
}
