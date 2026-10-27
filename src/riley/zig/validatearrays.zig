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
const shaderops = @import("shaderops.zig");
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
    if (mesh.shaders.mono) |execution| try checkMonoExecutionArrays(execution);
    if (mesh.shaders.ir) |execution| try checkMonoExecutionArrays(execution);
    if (mesh.shaders.rgb) |pipe| try checkPipeArrays(pipe);
    if (mesh.shaders.multifield) |pipe| try checkPipeArrays(pipe);
}

fn checkMonoExecutionArrays(
    execution: shaderops.ShaderMonoExecutionInput,
) InputArrayError!void {
    switch (execution) {
        .direct => |shader| try checkShaderMonoArrays(shader),
        .pipe => |pipe| try checkPipeArrays(pipe),
    }
}

fn checkPipeArrays(pipe: shaderops.ShaderPipeInput) InputArrayError!void {
    for (pipe.stages) |stage| {
        switch (stage) {
            .source => |src| try checkPipeSourceArrays(src.shader),
            else => {},
        }
    }
}

fn checkTexUvArrays(slice: []const f64) InputArrayError!void {
    for (slice) |val| {
        if (!std.math.isFinite(val)) return error.NonFiniteUvs;
    }
}

fn checkShaderMonoArrays(shader: shaderops.ShaderMonoInput) InputArrayError!void {
    switch (shader) {
        .tex_u8 => |t| try checkTexUvArrays(t.uvs.slice),
        .tex_u16 => |t| try checkTexUvArrays(t.uvs.slice),
        .tex_f => |t| {
            try checkTexUvArrays(t.uvs.slice);
            if (!isFiniteSlice(t.tex.array.slice)) return error.NonFiniteTexels;
        },
        .nodal => |n| {
            if (!isFiniteSlice(n.field.array_mem)) return error.NonFiniteNodalFields;
        },
        .func => |f| {
            if (f.uvs) |uvs| try checkTexUvArrays(uvs.slice);
        },
    }
}

fn checkPipeSourceArrays(source: shaderops.PipeSourceInput) InputArrayError!void {
    switch (source) {
        .tex_u8 => |t| try checkTexUvArrays(t.uvs.slice),
        .tex_u16 => |t| try checkTexUvArrays(t.uvs.slice),
        .tex_f => |t| {
            try checkTexUvArrays(t.uvs.slice);
            if (!isFiniteSlice(t.tex.array.slice)) return error.NonFiniteTexels;
        },
        .tex_rgb_u8 => |t| try checkTexUvArrays(t.uvs.slice),
        .tex_rgb_u16 => |t| try checkTexUvArrays(t.uvs.slice),
        .tex_rgb_f => |t| {
            try checkTexUvArrays(t.uvs.slice);
            if (!isFiniteSlice(t.tex.array.slice)) return error.NonFiniteTexels;
        },
        .tex_multi_u8 => |t| try checkTexUvArrays(t.uvs.slice),
        .tex_multi_u16 => |t| try checkTexUvArrays(t.uvs.slice),
        .tex_multi_f => |t| {
            try checkTexUvArrays(t.uvs.slice);
            if (!isFiniteSlice(t.tex.array.slice)) return error.NonFiniteTexels;
        },
        .nodal => |n| {
            if (!isFiniteSlice(n.field.array_mem)) return error.NonFiniteNodalFields;
        },
        .func => |f| switch (f) {
            .mono => |m| if (m.uvs) |uvs| try checkTexUvArrays(uvs.slice),
            .rgb => |r| if (r.uvs) |uvs| try checkTexUvArrays(uvs.slice),
            .multi => |m| if (m.uvs) |uvs| try checkTexUvArrays(uvs.slice),
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
