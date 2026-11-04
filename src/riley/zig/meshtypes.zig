// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const vecstack = @import("vecstack.zig");
const hullmultiroot = @import("hullmultiroot.zig");
const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;
const ndarray = @import("ndarray.zig");
const matslice = @import("matslice.zig");
const vecslice = @import("vecslice.zig");
const fieldtypes = @import("fieldtypes.zig");
const normals = @import("normals.zig");
const geometrykernels = @import("geometrykernels.zig");
const shadertypes = @import("shadertypes.zig");
const rasterfrontend = @import("rasterfrontend.zig");
const distortbounds = @import("distortbounds.zig");
const meshhit = @import("meshhit.zig");

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

pub const Coords = struct {
    mat: matslice.MatSlice(F),
    mem: []F,

    const Self: type = @This();

    pub fn init(mem: []F, coords_num: usize) Self {
        std.debug.assert(mem.len == coords_num * 3);
        const mat_coords = matslice.MatSlice(F).init(mem, coords_num, 3);

        return .{
            .mat = mat_coords,
            .mem = mem,
        };
    }

    pub fn initAlloc(outer_alloc: std.mem.Allocator, coords_num: usize) !Self {
        const mat_mem = try outer_alloc.alloc(F, coords_num * 3);

        return init(mat_mem, coords_num);
    }

    pub inline fn x(self: *const Self, ind: usize) F {
        return self.mat.get(ind, 0);
    }

    pub inline fn y(self: *const Self, ind: usize) F {
        return self.mat.get(ind, 1);
    }

    pub inline fn z(self: *const Self, ind: usize) F {
        return self.mat.get(ind, 2);
    }

    pub fn getVecSlice(self: *const Self, ind: usize) []F {
        return self.mat.getSlice(ind);
    }

    pub fn getVec3(self: *const Coords, ind: usize) vecstack.Vec3F {
        const vec_slice = self.mat.getSlice(ind);
        const vec = vecstack.Vec3F.initSlice(vec_slice);
        return vec;
    }
};

pub const Connect = struct {
    table: matslice.MatSlice(usize),
    table_mem: []usize,

    const Self: type = @This();

    pub fn init(mem: []usize, elems_num: usize, nodes_per_elem: usize) Self {
        std.debug.assert(mem.len == elems_num * nodes_per_elem);

        const mat_table = matslice.MatSlice(usize).init(mem, elems_num, nodes_per_elem);

        return .{
            .table = mat_table,
            .table_mem = mem,
        };
    }

    pub fn initAlloc(
        outer_alloc: std.mem.Allocator,
        elems_num: usize,
        nodes_per_elem: usize,
    ) !Self {
        const mat_mem = try outer_alloc.alloc(usize, elems_num * nodes_per_elem);

        return init(mat_mem, elems_num, nodes_per_elem);
    }

    pub inline fn getElemsNum(self: Self) usize {
        return self.table.rows_num;
    }

    pub inline fn getNodesPerElem(self: Self) usize {
        return self.table.cols_num;
    }

    pub fn deinit(self: *Self, outer_alloc: std.mem.Allocator) void {
        outer_alloc.free(self.table_mem);
    }

    pub fn getElem(self: *const Self, elem_num: usize) []usize {
        const ind_start: usize = elem_num * self.getNodesPerElem();
        const ind_end: usize = ind_start + self.getNodesPerElem();
        return self.table_mem[ind_start..ind_end];
    }
};

// Input: Raw user data for all frames.
// Coords/Fields: Node-order [total_nodes, ...]
// Connect: Connectivity table links nodes to elems.
pub const MeshInput = struct {
    mesh_type: geometrykernels.MeshType,
    normal_type: normals.NormalType = .exact,
    coords: Coords,
    connect: Connect,
    disp: ?fieldtypes.Field,
    shaders: shadertypes.MeshShaderSetInput,
};

// Static: Persistent multi-frame resources in the engine's memory.
// Coords/Fields: Node-order [total_nodes, ...]
// Shader UVs: Elem-order (gathered during static init as they are usually static).
pub const MeshStatic = struct {
    referenced_nodes_num: usize = 0,
    // Role order: mono, rgb, ir, multifield; independent of output channel count.
    hit_selections: [4]meshhit.MeshHitSelection = @splat(meshhit.MeshHitSelection.initEmpty()),
    scene_mesh_idx: usize = 0,
    mesh_type: geometrykernels.MeshType,
    normal_type: normals.NormalType = .exact,
    coords_orig: Coords,
    connect: Connect,
    disp: ?fieldtypes.Field,
    shaders: shadertypes.MeshShaderSetStatic,
};

pub const MultiRootHulls = struct {
    indices: matslice.MatSlice(u8),
    valid_depth: vecslice.VecSlice(u8),
    slot_by_visible_elem: vecslice.VecSlice(u32),
    leaves_pre_calc: []hullmultiroot.HullMultiRoot.BezierLeafPreCalc = &.{},
    leaves_on_the_fly: []hullmultiroot.HullMultiRoot.BezierLeafOnTheFly = &.{},
};

pub const MeshHulls = struct {
    // Dims: [mesh_idex][elems_in_image,2(x,y),NH(num_hull_pts)]
    hull_adaptive_by_mesh: []const ?ndarray.NDArray(F),
    // Dims: [mesh_idx][slot_by_visible_elem LUT]
    hull_multiroot_by_mesh: []const ?MultiRootHulls,
};

// Workspace: Temporary node-order working area for the geometry pipeline.
// Coords: Node-order [total_nodes, 3]. Holds coords for a single frame after
// displacement.
pub const MeshFrameWorkspace = struct {
    coords_nodes: Coords,
    coords_nodes_def_world: ?Coords,
    vis_orig_elem_inds: []usize,
    elem_bboxes: []rasterfrontend.ElemBBox,
    root_classes: []rasterfrontend.ElemRootClass,
    elem_float_bboxes: ?[]distortbounds.DistortBounds = null,
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
    elem_bboxes: []rasterfrontend.ElemBBox,
    root_classes: []rasterfrontend.ElemRootClass,
    elem_float_bboxes: ?[]distortbounds.DistortBounds = null,
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
    mesh_type: geometrykernels.MeshType,
    coords: ndarray.NDArray(F),
    hit_geometry: meshhit.MeshHitGeomPrepared = .{},
    shaders: shadertypes.MeshShaderSetPrepared,
};

pub const FrameGeomResult = struct {
    total_elems_num: usize,
    total_elems_in_image: usize,
};
