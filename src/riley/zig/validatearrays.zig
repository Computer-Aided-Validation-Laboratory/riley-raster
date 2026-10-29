// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const geomkerns = @import("geometrykernels.zig");
const matslice = @import("matslice.zig");
const meshpipe = @import("meshpipeline.zig");
const ndarray = @import("ndarray.zig");
const shaderops = @import("shaderops_common.zig");
const texops = @import("textureops.zig");

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
pub fn checkRenderArrs(meshes: []const meshpipe.MeshInput) InputArrayError!void {
    for (meshes) |mesh| {
        try checkMeshConnectivity(mesh);
        try checkMeshCoordinates(mesh);
        try checkMeshDisplacements(mesh);
        try checkMeshShaderArrays(mesh);
    }
}

// --------------------------------------------------------------------------------------
// Connectivity Scans
// --------------------------------------------------------------------------------------

fn checkMeshConnectivity(mesh: meshpipe.MeshInput) InputArrayError!void {
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

fn checkMeshCoordinates(mesh: meshpipe.MeshInput) InputArrayError!void {
    if (!isFiniteSlice(mesh.coords.mem)) {
        return error.NonFiniteCoordinates;
    }
}

fn checkMeshDisplacements(mesh: meshpipe.MeshInput) InputArrayError!void {
    if (mesh.disp) |disp_field| {
        if (!isFiniteSlice(disp_field.array_mem)) {
            return error.NonFiniteDisplacements;
        }
    }
}

// --------------------------------------------------------------------------------------
// Shader Payload Scans (Nodal Fields, UVs, Floating Textures)
// --------------------------------------------------------------------------------------

fn checkMeshShaderArrays(mesh: meshpipe.MeshInput) InputArrayError!void {
    switch (mesh.shader) {
        .tex_u8 => |tex_shader| {
            if (!isFiniteSlice(tex_shader.uvs.slice)) {
                return error.NonFiniteUvs;
            }
        },
        .tex_u16 => |tex_shader| {
            if (!isFiniteSlice(tex_shader.uvs.slice)) {
                return error.NonFiniteUvs;
            }
        },
        .tex_f => |tex_shader| {
            if (!isFiniteSlice(tex_shader.uvs.slice)) {
                return error.NonFiniteUvs;
            }
            if (!isFiniteSlice(tex_shader.tex.array.slice)) {
                return error.NonFiniteTexels;
            }
        },
        .tex_rgb_u8 => |tex_shader| {
            if (!isFiniteSlice(tex_shader.uvs.slice)) {
                return error.NonFiniteUvs;
            }
        },
        .tex_rgb_u16 => |tex_shader| {
            if (!isFiniteSlice(tex_shader.uvs.slice)) {
                return error.NonFiniteUvs;
            }
        },
        .tex_rgb_f => |tex_shader| {
            if (!isFiniteSlice(tex_shader.uvs.slice)) {
                return error.NonFiniteUvs;
            }
            if (!isFiniteSlice(tex_shader.tex.array.slice)) {
                return error.NonFiniteTexels;
            }
        },
        .speckle => |speckle_shader| {
            if (!isFiniteSlice(speckle_shader.uvs.slice)) {
                return error.NonFiniteUvs;
            }
        },
        .nodal => |nodal_shader| {
            if (!isFiniteSlice(nodal_shader.field.array_mem)) {
                return error.NonFiniteNodalFields;
            }
        },
        .func => |func_shader| {
            if (func_shader.uvs) |uvs| {
                if (!isFiniteSlice(uvs.slice)) {
                    return error.NonFiniteUvs;
                }
            }
        },
        .func_rgb => |func_shader| {
            if (func_shader.uvs) |uvs| {
                if (!isFiniteSlice(uvs.slice)) {
                    return error.NonFiniteUvs;
                }
            }
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

test "full speckle array validation scans UVs and connectivity" {
    const meshio = @import("meshio.zig");
    const alloc = std.testing.allocator;
    var coords = [_]F{ 0, 0, 0, 1, 0, 0, 0, 1, 0 };
    var connect = [_]usize{ 0, 1, 2 };
    // Finite UVs outside [0,1] remain valid; sampling clamps them.
    var values = [_]F{ -0.5, 0, 1.5, 0, 0, 1 };
    const uvs = try ndarray.NDArray(F).init(alloc, &values, &.{ 3, 2 });
    defer uvs.deinit(alloc);
    const mesh = meshpipe.MeshInput{
        .mesh_type = .tri3,
        .coords = meshio.Coords.init(&coords, 3),
        .connect = meshio.Connect.init(&connect, 1, 3),
        .disp = null,
        .shader = .{ .speckle = .{ .uvs = uvs } },
    };
    try checkRenderArrs(&.{mesh});
    for ([_]F{ std.math.nan(F), std.math.inf(F), -std.math.inf(F) }) |invalid| {
        values[0] = invalid;
        try std.testing.expectError(error.NonFiniteUvs, checkRenderArrs(&.{mesh}));
    }
    values[0] = 0;
    connect[2] = 3;
    try std.testing.expectError(error.InvalidConnectivityIndex, checkRenderArrs(&.{mesh}));
    connect[2] = 1;
    try std.testing.expectError(error.DegenerateElementIndices, checkRenderArrs(&.{mesh}));
}
