// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;
const ndarray = @import("ndarray.zig");
const matslice = @import("matslice.zig");
const vecslice = @import("vecslice.zig");
const meshio = @import("meshio.zig");
const normals = @import("normals.zig");
const geomkerns = @import("geometrykernels.zig");
const shadertypes = @import("shadertypes.zig");
const frontend = @import("rasterfrontend.zig");
const distbounds = @import("distortbounds.zig");
const meshhit = @import("meshhit.zig");
const HullMultiRoot = @import("hullmultiroot.zig").HullMultiRoot;

// Input: Raw user data for all frames.
// meshio.Coords/Fields: Node-order [total_nodes, ...]
// meshio.Connect: Connectivity table links nodes to elems.
pub const MeshInput = struct {
    mesh_type: geomkerns.MeshType,
    normal_type: normals.NormalType = .exact,
    coords: meshio.Coords,
    connect: meshio.Connect,
    disp: ?meshio.Field,
    shaders: shadertypes.MeshShaderSetInput,
};

// Static: Persistent multi-frame resources in the engine's memory.
// meshio.Coords/Fields: Node-order [total_nodes, ...]
// Shader UVs: Elem-order (gathered during static init as they are usually static).
pub const MeshStatic = struct {
    scene_mesh_idx: usize = 0,
    mesh_type: geomkerns.MeshType,
    normal_type: normals.NormalType = .exact,
    coords_orig: meshio.Coords,
    connect: meshio.Connect,
    disp: ?meshio.Field,
    shaders: shadertypes.MeshShaderSetStatic,
};

pub const MultiRootHulls = struct {
    indices: matslice.MatSlice(u8),
    valid_depth: vecslice.VecSlice(u8),
    slot_by_visible_elem: vecslice.VecSlice(u32),
    leaves_pre_calc: []HullMultiRoot.BezierLeafPreCalc = &.{},
    leaves_on_the_fly: []HullMultiRoot.BezierLeafOnTheFly = &.{},
};

pub const MeshHulls = struct {
    // Dims: [mesh_idex][elems_in_image,2(x,y),NH(num_hull_pts)]
    hull_adaptive_by_mesh: []const ?ndarray.NDArray(F),
    // Dims: [mesh_idx][slot_by_visible_elem LUT]
    hull_multiroot_by_mesh: []const ?MultiRootHulls,
};

// Workspace: Temporary node-order working area for the geometry pipeline.
// meshio.Coords: Node-order [total_nodes, 3]. Holds coords for a single frame after
// displacement.
pub const MeshFrameWorkspace = struct {
    coords_nodes: meshio.Coords,
    coords_nodes_def_world: ?meshio.Coords,
    vis_orig_elem_inds: []usize,
    elem_bboxes: []frontend.ElemBBox,
    root_classes: []frontend.ElemRootClass,
    elem_float_bboxes: ?[]distbounds.DistortBounds = null,
    elems_in_image: usize,
    hull_adaptive: ?ndarray.NDArray(F),
    hull_multiroot: ?MultiRootHulls,
    vis_counts_by_chunk: []usize,
    vis_offsets_by_chunk: []usize,
};

// Frame: Wraps the Prep payload with per-frame spatial metadata.
// Prep means culled elem-order ndarray.NDArray data ready for the raster loop.
pub const MeshFrame = struct {
    mesh: MeshPrepared,
    elem_bboxes: []frontend.ElemBBox,
    root_classes: []frontend.ElemRootClass,
    elem_float_bboxes: ?[]distbounds.DistortBounds = null,
    elems_in_image: usize,
    total_elems_num: usize,
    hull_adaptive: ?ndarray.NDArray(F),
    hull_multiroot: ?MultiRootHulls,
    frame_workspace: MeshFrameWorkspace,
};

// Prep: Data culled and gathered for the raster loop for a SINGLE frame.
// Prep means culled elem-order ndarray.NDArray data ready for the raster loop.
// Elem-order [vis_elems, field, nodes_per_elem]
pub const MeshPrepared = struct {
    scene_mesh_idx: usize = 0,
    mesh_type: geomkerns.MeshType,
    coords: ndarray.NDArray(F),
    hit_geometry: meshhit.MeshHitGeomPrepared = .{},
    shaders: shadertypes.MeshShaderSetPrepared,
};

pub const GeomTimes = struct {
    coord_ops: u64 = 0,
    cull_ops: u64 = 0,
    prep_hulls_shaders: u64 = 0,
    remap_inds: u64 = 0,
};

pub const FrameGeomResult = struct {
    total_elems_num: usize,
    total_elems_in_image: usize,
};
