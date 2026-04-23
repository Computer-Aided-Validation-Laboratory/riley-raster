// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const ndarray = @import("ndarray.zig");
const matslice = @import("matslice.zig");

const meshio = @import("meshio.zig");

const uvio = @import("uvio.zig");

const imageio = @import("imageio.zig");

const imageops = @import("imageops.zig");
const cam = @import("camera.zig");
const pce = @import("parachunkexec.zig");
const rops = @import("rasterops.zig");
const texops = @import("textureops.zig");

const shaderops = @import("shaderops.zig");

//------------------------------------------------------------------------------------------
// External Helper Functions: General geometry and mesh utilities
//------------------------------------------------------------------------------------------

pub const MeshType = enum {
    tri3,
    tri6,
    quad4ibi,
    quad4newton,
    quad8,
    quad9,

    pub fn getNodesNum(self: MeshType) usize {
        return switch (self) {
            .tri3 => 3,
            .tri6 => 6,
            .quad4ibi, .quad4newton => 4,
            .quad8 => 8,
            .quad9 => 9,
        };
    }
};

// Input: Raw user data for all frames.
// meshio.Coords/Fields: Node-order [total_nodes, ...]
// meshio.Connect: Connectivity table links nodes to elements.
pub const MeshInput = struct {
    mesh_type: MeshType,
    coords: meshio.Coords,
    connect: meshio.Connect,
    disp: ?meshio.Field,
    shader: shaderops.ShaderInput,
};

// Static: Persistent multi-frame resources in the engine's memory.
// meshio.Coords/Fields: Node-order [total_nodes, ...]
// UVs: Element-order (expanded during static init as they are usually static).
pub const MeshStatic = struct {
    mesh_type: MeshType,
    coords_orig: meshio.Coords,
    connect: meshio.Connect,
    disp: ?meshio.Field,
    shader: shaderops.ShaderStatic,
};

// Workspace: Temporary node-order working area for the geometry pipeline.
// meshio.Coords: Node-order [total_nodes, 3]. Holds coords for a single frame after displacement.
pub const MeshFrameWorkspace = struct {
    coords_nodes: meshio.Coords,
    visible_orig_elem_indices: []usize,
    elem_bboxes: []rops.ElemBBox,
    elems_in_image: usize,
    raster_hull: ?ndarray.NDArray(f64),
};

// Frame: Wraps the Prepared payload with per-frame spatial metadata.
// Prepared means culled element-order ndarray.NDArray data ready for the raster loop.
pub const MeshFrame = struct {
    mesh: MeshPrepared,
    elem_bboxes: []rops.ElemBBox,
    elems_in_image: usize,
    total_elems_num: usize,
    raster_hull: ?ndarray.NDArray(f64),
};

// Prepared: Data culled and expanded for the raster loop for a SINGLE frame.
// Prepared means culled element-order ndarray.NDArray data ready for the raster loop.
// meshio.Coords/Fields: Element-order [visible_elems, ..., nodes_per_elem]
pub const MeshPrepared = struct {
    mesh_type: MeshType,
    coords: ndarray.NDArray(f64),
    shader: shaderops.ShaderPrepared,
};

// External helper function for finding mesh centroids
pub fn findAlignedCentroid(coords: *const meshio.Coords) struct {
    centroid: [3]f64,
    extent: [3]f64,
} {
    var min = [3]f64{
        std.math.inf(f64),
        std.math.inf(f64),
        std.math.inf(f64),
    };
    var max = [3]f64{
        -std.math.inf(f64),
        -std.math.inf(f64),
        -std.math.inf(f64),
    };

    for (0..coords.mat.rows_num) |ii| {
        const x = coords.mat.get(ii, 0);
        const y = coords.mat.get(ii, 1);
        const z = coords.mat.get(ii, 2);

        if (x < min[0]) min[0] = x;
        if (x > max[0]) max[0] = x;
        if (y < min[1]) min[1] = y;
        if (y > max[1]) max[1] = y;
        if (z < min[2]) min[2] = z;
        if (z > max[2]) max[2] = z;
    }

    return .{
        .centroid = .{
            (min[0] + max[0]) * 0.5,
            (min[1] + max[1]) * 0.5,
            (min[2] + max[2]) * 0.5,
        },
        .extent = .{
            max[0] - min[0],
            max[1] - min[1],
            max[2] - min[2],
        },
    };
}

// Used to arrange multiple meshes in a scene on a regular grid
pub fn arrangeMeshSlice(
    meshes: []MeshInput,
    gap: [3]f64,
    max_divs: [3]usize,
) void {
    var max_extent = [3]f64{ 0, 0, 0 };

    // First pass: find the maximum extent among all individual meshes
    for (meshes) |mesh| {
        const bounds = findAlignedCentroid(&mesh.coords);
        for (0..3) |ii| {
            if (bounds.extent[ii] > max_extent[ii]) {
                max_extent[ii] = bounds.extent[ii];
            }
        }
    }

    const stride = [3]f64{
        max_extent[0] + gap[0],
        max_extent[1] + gap[1],
        max_extent[2] + gap[2],
    };

    // Second pass: arrange meshes in a regular grid
    for (meshes, 0..) |mesh, nn| {
        // Calculate grid indices based on max divisions per axis
        const ix = nn % max_divs[0];
        const iy = (nn / max_divs[0]) % max_divs[1];
        const iz = nn / (max_divs[0] * max_divs[1]);

        const target_center = [3]f64{
            @as(f64, @floatFromInt(ix)) * stride[0],
            @as(f64, @floatFromInt(iy)) * stride[1],
            @as(f64, @floatFromInt(iz)) * stride[2],
        };

        const bounds = findAlignedCentroid(&mesh.coords);

        const translation = [3]f64{
            target_center[0] - bounds.centroid[0],
            target_center[1] - bounds.centroid[1],
            target_center[2] - bounds.centroid[2],
        };

        var mat = mesh.coords.mat;

        // Apply translation in-place to the coordinate matrix
        for (0..mesh.coords.mat.rows_num) |ii| {
            const x = mat.get(ii, 0);
            const y = mat.get(ii, 1);
            const z = mat.get(ii, 2);

            mat.set(ii, 0, x + translation[0]);
            mat.set(ii, 1, y + translation[1]);
            mat.set(ii, 2, z + translation[2]);
        }
    }
}

// External helper to turn a SimData struct into a MeshInput with associted shader data for
// rendering
pub fn meshInputFromSimDataSlice(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    sim_datas: []const meshio.SimData,
    mesh_types: []const MeshType,
    shader_mode: enum { nodal, texture },
    uv_paths: ?[]const []const u8,
    texture_path: ?[]const u8,
    uv_file: ?[]const u8,
) ![]MeshInput {
    var mesh_inputs = try outer_alloc.alloc(MeshInput, sim_datas.len);
    var initialized_count: usize = 0;
    errdefer {
        for (0..initialized_count) |ii| {
            switch (mesh_inputs[ii].shader) {
                .tex => |tex| {
                    outer_alloc.free(tex.uvs.slice);
                },
                .tex_rgb => |tex| {
                    outer_alloc.free(tex.uvs.slice);
                },
                else => {},
            }
        }
        outer_alloc.free(mesh_inputs);
    }

    const uv_file_name = uv_file orelse "uvs.csv";

    for (sim_datas, 0..) |sim_data, ii| {
        mesh_inputs[ii] = MeshInput{
            .mesh_type = mesh_types[ii],
            .coords = sim_data.coords,
            .connect = sim_data.connect,
            .disp = sim_data.disp,
            .shader = undefined,
        };

        if (shader_mode == .nodal) {
            if (sim_data.field) |field| {
                mesh_inputs[ii].shader = .{ .nodal = .{
                    .field = field,
                    .bits = 8,
                    .normal_type = .none,
                } };
            } else {
                return error.MissingFieldData;
            }
        } else {
            const paths = uv_paths orelse return error.MissingUVPaths;
            const path_uvs = try std.fmt.allocPrint(
                outer_alloc,
                "{s}{s}",
                .{ paths[ii], uv_file_name },
            );
            defer outer_alloc.free(path_uvs);

            const uvmap = try uvio.loadUVMap(outer_alloc, io, path_uvs);

            const format: imageio.ImageFormat = if (std.mem.endsWith(u8, texture_path.?, ".bmp"))
                .bmp
            else
                .tiff;

            const texture = try imageio.loadImage(
                u8,
                1,
                outer_alloc,
                io,
                texture_path.?,
                format,
            );

            mesh_inputs[ii].shader = .{ .tex = .{
                .uvs = uvmap.array,
                .texture = texture,
                .sample_config = .{ .sample = .cubic_catmull_rom, .mode = .lut_lerp },
                .normal_type = .none,
            } };
        }
        initialized_count += 1;
    }
    return mesh_inputs;
}

//------------------------------------------------------------------------------------------
// Mesh Initialization: Initial mesh and coordinate preparation
//------------------------------------------------------------------------------------------

pub fn initStatic(
    allocator: std.mem.Allocator,
    mesh_input: *const MeshInput,
) !MeshStatic {
    const coords_orig = try copyCoordsAlloc(allocator, &mesh_input.coords);

    var shader_static: shaderops.ShaderStatic = undefined;
    switch (mesh_input.shader) {
        .nodal => |nodal_in| {
            shader_static = .{ .nodal = .{
                .field = nodal_in.field,
                .bits = nodal_in.bits,
                .scaling = nodal_in.scaling,
                .scale_over = nodal_in.scale_over,
                .normal_type = nodal_in.normal_type,
            } };
        },
        .tex => |tex_in| {
            const elem_uvs = try prepareUVs(
                allocator,
                &tex_in.uvs,
                &mesh_input.connect,
            );
            shader_static = .{ .tex = .{
                .elem_uvs = elem_uvs,
                .texture = tex_in.texture,
                .sample_config = tex_in.sample_config,
                .bits = tex_in.bits,
                .scaling = tex_in.scaling,
                .normal_type = tex_in.normal_type,
            } };
        },
        .tex_rgb => |tex_in| {
            const elem_uvs = try prepareUVs(
                allocator,
                &tex_in.uvs,
                &mesh_input.connect,
            );
            shader_static = .{ .tex_rgb = .{
                .elem_uvs = elem_uvs,
                .texture = tex_in.texture,
                .sample_config = tex_in.sample_config,
                .bits = tex_in.bits,
                .scaling = tex_in.scaling,
                .normal_type = tex_in.normal_type,
            } };
        },
    }

    return .{
        .mesh_type = mesh_input.mesh_type,
        .coords_orig = coords_orig,
        .connect = mesh_input.connect,
        .disp = mesh_input.disp,
        .shader = shader_static,
    };
}

fn prepareUVs(
    outer_alloc: std.mem.Allocator,
    uvs: *const ndarray.NDArray(f64),
    connect: *const meshio.Connect,
) !ndarray.NDArray(f64) {
    const elems_num = connect.getElemsNum();
    const nodes_per_elem = connect.getNodesPerElem();
    var elem_uv_arr = try ndarray.NDArray(f64).initFlat(
        outer_alloc,
        &[_]usize{ elems_num, 2, nodes_per_elem },
    );
    @memset(elem_uv_arr.slice, 0.0);

    for (0..elems_num) |ee| {
        const coord_inds = connect.getElem(ee);
        for (0..nodes_per_elem) |nn| {
            for (0..2) |uu| {
                const val = uvs.get(&[_]usize{ coord_inds[nn], uu });
                elem_uv_arr.set(&[_]usize{ ee, uu, nn }, val);
            }
        }
    }

    return elem_uv_arr;
}

fn copyCoordsAlloc(
    allocator: std.mem.Allocator,
    coords: *const meshio.Coords,
) !meshio.Coords {
    const coords_copy = try meshio.Coords.initAlloc(allocator, coords.mat.rows_num);
    @memcpy(coords_copy.mem, coords.mem);
    return coords_copy;
}

//------------------------------------------------------------------------------------------
// Geometry Workspace and Chunks: Pipeline workspace and chunking utilities
//------------------------------------------------------------------------------------------

const MeshFrameContext = struct {
    frame_workspace: MeshFrameWorkspace,
    visible_counts_by_chunk: []usize,
    visible_offsets_by_chunk: []usize,
    visible_elems_num: usize,
};

fn initMeshFrameWorkspace(
    allocator: std.mem.Allocator,
    mesh_static: *const MeshStatic,
) !MeshFrameWorkspace {
    return .{
        .coords_nodes = try meshio.Coords.initAlloc(
            allocator,
            mesh_static.coords_orig.mat.rows_num,
        ),
        .visible_orig_elem_indices = &.{},
        .elem_bboxes = &.{},
        .elems_in_image = 0,
        .raster_hull = null,
    };
}

//------------------------------------------------------------------------------------------
// Geometry Pipeline Stages: meshio.Coords, Transform, Culling and Compaction
//------------------------------------------------------------------------------------------

const PrepareCoordsStage = struct {
    frame_workspace: *MeshFrameWorkspace,
    mesh_static: *const MeshStatic,
    frame_idx: usize,
};

fn runPrepareCoordsStage(
    ctx_ptr: *anyopaque,
    chunk_idx: usize,
    range_start: usize,
    range_end: usize,
) void {
    _ = chunk_idx;
    const stage: *PrepareCoordsStage = @ptrCast(@alignCast(ctx_ptr));

    const actual_frame_idx = if (stage.mesh_static.disp) |disp|
        @min(stage.frame_idx, disp.array.dims[0] - 1)
    else
        0;

    for (range_start..range_end) |nn| {
        const coord_off = nn * 3;
        stage.frame_workspace.coords_nodes.mem[coord_off + 0] =
            stage.mesh_static.coords_orig.mem[coord_off + 0];
        stage.frame_workspace.coords_nodes.mem[coord_off + 1] =
            stage.mesh_static.coords_orig.mem[coord_off + 1];
        stage.frame_workspace.coords_nodes.mem[coord_off + 2] =
            stage.mesh_static.coords_orig.mem[coord_off + 2];

        if (stage.mesh_static.disp) |disp| {
            for (0..3) |cc| {
                stage.frame_workspace.coords_nodes.mem[coord_off + cc] += disp.array.get(
                    &[_]usize{ actual_frame_idx, nn, cc },
                );
            }
        }
    }
}

fn runPrepareCoordsDynamicStage(
    ctx_ptr: *anyopaque,
    range_start: usize,
    range_end: usize,
) void {
    runPrepareCoordsStage(ctx_ptr, 0, range_start, range_end);
}

const TransformCoordsStage = struct {
    camera: *const cam.CameraPrepared,
    mesh_type: MeshType,
    frame_workspace: *MeshFrameWorkspace,
};

fn runTransformCoordsStage(
    ctx_ptr: *anyopaque,
    chunk_idx: usize,
    range_start: usize,
    range_end: usize,
) void {
    _ = chunk_idx;
    const stage: *TransformCoordsStage = @ptrCast(@alignCast(ctx_ptr));
    switch (stage.mesh_type) {
        .tri3 => rops.nodesToRasterRangeInPlace(
            stage.camera,
            &stage.frame_workspace.coords_nodes,
            range_start,
            range_end,
        ),
        .quad4ibi => rops.nodesToClipPxLengRangeInPlace(
            stage.camera,
            &stage.frame_workspace.coords_nodes,
            range_start,
            range_end,
        ),
        .tri6,
        .quad4newton,
        .quad8,
        .quad9,
        => rops.nodesToClipPxLengRangeInPlace(
            stage.camera,
            &stage.frame_workspace.coords_nodes,
            range_start,
            range_end,
        ),
    }
}

fn runTransformCoordsDynamicStage(
    ctx_ptr: *anyopaque,
    range_start: usize,
    range_end: usize,
) void {
    runTransformCoordsStage(ctx_ptr, 0, range_start, range_end);
}

const CullVisibleCountStage = struct {
    camera: *const cam.CameraPrepared,
    mesh_type: MeshType,
    connect: *const meshio.Connect,
    coords_nodes: *const meshio.Coords,
    visible_counts_by_chunk: []usize,
};

fn runCullVisibleCountStage(
    ctx_ptr: *anyopaque,
    chunk_idx: usize,
    range_start: usize,
    range_end: usize,
) void {
    const stage: *CullVisibleCountStage = @ptrCast(@alignCast(ctx_ptr));
    stage.visible_counts_by_chunk[chunk_idx] = rops.countVisibleElemsRange(
        stage.camera,
        stage.mesh_type,
        stage.connect,
        stage.coords_nodes,
        range_start,
        range_end,
    );
}

fn prefixVisibleCounts(mesh_frame: *MeshFrameContext) void {
    var running_total: usize = 0;
    for (mesh_frame.visible_counts_by_chunk, 0..) |visible_count, cc| {
        mesh_frame.visible_offsets_by_chunk[cc] = running_total;
        running_total += visible_count;
    }
    mesh_frame.visible_elems_num = running_total;
    mesh_frame.frame_workspace.elems_in_image = running_total;
}

const CullVisibleFillStage = struct {
    camera: *const cam.CameraPrepared,
    mesh_type: MeshType,
    connect: *const meshio.Connect,
    coords_nodes: *const meshio.Coords,
    visible_orig_elem_indices: []usize,
    elem_bboxes: []rops.ElemBBox,
    visible_offsets_by_chunk: []const usize,
};

fn runCullVisibleFillStage(
    ctx_ptr: *anyopaque,
    chunk_idx: usize,
    range_start: usize,
    range_end: usize,
) void {
    const stage: *CullVisibleFillStage = @ptrCast(@alignCast(ctx_ptr));
    rops.fillVisibleElemsRange(
        stage.camera,
        stage.mesh_type,
        stage.connect,
        stage.coords_nodes,
        stage.visible_orig_elem_indices,
        stage.elem_bboxes,
        range_start,
        range_end,
        stage.visible_offsets_by_chunk[chunk_idx],
    );
}

const CompactVisibleCoordsStage = struct {
    mesh_static: *const MeshStatic,
    frame_workspace: *const MeshFrameWorkspace,
    elem_coords: *ndarray.NDArray(f64),
};

fn runCompactVisibleCoordsStage(
    ctx_ptr: *anyopaque,
    chunk_idx: usize,
    range_start: usize,
    range_end: usize,
) void {
    _ = chunk_idx;
    const stage: *CompactVisibleCoordsStage = @ptrCast(@alignCast(ctx_ptr));
    const nodes_num = stage.mesh_static.mesh_type.getNodesNum();

    for (range_start..range_end) |pp| {
        const orig_ee = stage.frame_workspace.visible_orig_elem_indices[pp];
        const coord_inds = stage.mesh_static.connect.getElem(orig_ee);
        for (0..nodes_num) |nn| {
            const node_idx = coord_inds[nn];
            stage.elem_coords.set(
                &[_]usize{ pp, 0, nn },
                stage.frame_workspace.coords_nodes.x(node_idx),
            );
            stage.elem_coords.set(
                &[_]usize{ pp, 1, nn },
                stage.frame_workspace.coords_nodes.y(node_idx),
            );
            stage.elem_coords.set(
                &[_]usize{ pp, 2, nn },
                stage.frame_workspace.coords_nodes.z(node_idx),
            );
        }
    }
}

fn runCompactVisibleCoordsDynamicStage(
    ctx_ptr: *anyopaque,
    range_start: usize,
    range_end: usize,
) void {
    runCompactVisibleCoordsStage(ctx_ptr, 0, range_start, range_end);
}

const CompactVisibleFieldStage = struct {
    connect: *const meshio.Connect,
    field: *const meshio.Field,
    frame_idx: usize,
    visible_orig_elem_indices: []const usize,
    elem_field: *ndarray.NDArray(f64),
};

fn runCompactVisibleFieldStage(
    ctx_ptr: *anyopaque,
    chunk_idx: usize,
    range_start: usize,
    range_end: usize,
) void {
    _ = chunk_idx;
    const stage: *CompactVisibleFieldStage = @ptrCast(@alignCast(ctx_ptr));
    const actual_frame_idx = @min(stage.frame_idx, stage.field.array.dims[0] - 1);
    const fields_num = stage.field.getFieldsN();
    const nodes_num = stage.connect.getNodesPerElem();

    for (range_start..range_end) |pp| {
        const orig_ee = stage.visible_orig_elem_indices[pp];
        const coord_inds = stage.connect.getElem(orig_ee);
        for (0..nodes_num) |nn| {
            for (0..@as(usize, fields_num)) |ff| {
                const field_val = stage.field.array.get(
                    &[_]usize{ actual_frame_idx, coord_inds[nn], ff },
                );
                stage.elem_field.set(&[_]usize{ pp, ff, nn }, field_val);
            }
        }
    }
}

const CompactVisibleUVStage = struct {
    elem_uvs_full: ndarray.NDArray(f64),
    visible_orig_elem_indices: []const usize,
    elem_uvs: *ndarray.NDArray(f64),
};

fn runCompactVisibleUVStage(
    ctx_ptr: *anyopaque,
    chunk_idx: usize,
    range_start: usize,
    range_end: usize,
) void {
    _ = chunk_idx;
    const stage: *CompactVisibleUVStage = @ptrCast(@alignCast(ctx_ptr));
    const nodes_num = stage.elem_uvs_full.dims[2];

    for (range_start..range_end) |pp| {
        const orig_ee = stage.visible_orig_elem_indices[pp];
        const src_start = stage.elem_uvs_full.getFlatIdx(&[_]usize{ orig_ee, 0, 0 });
        const dst_start = stage.elem_uvs.getFlatIdx(&[_]usize{ pp, 0, 0 });
        @memcpy(
            stage.elem_uvs.slice[dst_start .. dst_start + 2 * nodes_num],
            stage.elem_uvs_full.slice[src_start .. src_start + 2 * nodes_num],
        );
    }
}

const PrepareRasterHullsStage = struct {
    camera: *const cam.CameraPrepared,
    mesh_type: MeshType,
    elem_coords: *const ndarray.NDArray(f64),
    raster_hull: *ndarray.NDArray(f64),
};

fn runPrepareRasterHullsStage(
    ctx_ptr: *anyopaque,
    chunk_idx: usize,
    range_start: usize,
    range_end: usize,
) void {
    _ = chunk_idx;
    const stage: *PrepareRasterHullsStage = @ptrCast(@alignCast(ctx_ptr));
    rops.prepareVisibleRasterHullsRange(
        stage.camera,
        stage.mesh_type,
        stage.elem_coords,
        stage.raster_hull,
        range_start,
        range_end,
    );
}

//------------------------------------------------------------------------------------------
// Normal Generation: Threaded normal calculation stages
//------------------------------------------------------------------------------------------

fn prepareVisibleNormalsThreaded(
    allocator: std.mem.Allocator,
    mesh_type: MeshType,
    coords_nodes: *const meshio.Coords,
    connect: *const meshio.Connect,
    visible_orig_elem_indices: []const usize,
    normal_type: shaderops.NormalType,
    chunk_exec: ?*pce.ParaChunkExecutor,
    elem_chunk_size: usize,
    visible_chunk_size: usize,
) !ndarray.MappedNDArray(f64) {
    return switch (mesh_type) {
        .tri3 => try prepareVisibleNormalsThreadedN(
            allocator,
            mesh_type,
            coords_nodes,
            connect,
            visible_orig_elem_indices,
            normal_type,
            chunk_exec,
            elem_chunk_size,
            visible_chunk_size,
            3,
        ),
        .tri6 => try prepareVisibleNormalsThreadedN(
            allocator,
            mesh_type,
            coords_nodes,
            connect,
            visible_orig_elem_indices,
            normal_type,
            chunk_exec,
            elem_chunk_size,
            visible_chunk_size,
            6,
        ),
        .quad4ibi, .quad4newton => try prepareVisibleNormalsThreadedN(
            allocator,
            mesh_type,
            coords_nodes,
            connect,
            visible_orig_elem_indices,
            normal_type,
            chunk_exec,
            elem_chunk_size,
            visible_chunk_size,
            4,
        ),
        .quad8 => try prepareVisibleNormalsThreadedN(
            allocator,
            mesh_type,
            coords_nodes,
            connect,
            visible_orig_elem_indices,
            normal_type,
            chunk_exec,
            elem_chunk_size,
            visible_chunk_size,
            8,
        ),
        .quad9 => try prepareVisibleNormalsThreadedN(
            allocator,
            mesh_type,
            coords_nodes,
            connect,
            visible_orig_elem_indices,
            normal_type,
            chunk_exec,
            elem_chunk_size,
            visible_chunk_size,
            9,
        ),
    };
}

fn prepareVisibleNormalsThreadedN(
    allocator: std.mem.Allocator,
    mesh_type: MeshType,
    coords_nodes: *const meshio.Coords,
    connect: *const meshio.Connect,
    visible_orig_elem_indices: []const usize,
    normal_type: shaderops.NormalType,
    chunk_exec: ?*pce.ParaChunkExecutor,
    elem_chunk_size: usize,
    visible_chunk_size: usize,
    comptime N: usize,
) !ndarray.MappedNDArray(f64) {
    var prep_normals = try initIdentityMappedNormals(
        allocator,
        visible_orig_elem_indices.len,
        N,
    );

    switch (normal_type) {
        .none => unreachable,
        .exact => {
            var exact_stage = PrepareVisibleExactNormalsStage{
                .mesh_type = mesh_type,
                .coords_nodes = coords_nodes,
                .connect = connect,
                .visible_orig_elem_indices = visible_orig_elem_indices,
                .prep_normals = &prep_normals.array,
            };
            pce.runStaticRange(
                chunk_exec,
                &exact_stage,
                runPrepareVisibleExactNormalsStage,
                visible_orig_elem_indices.len,
                visible_chunk_size,
            );
        },
        .averaged => {
            const nodes_num = getConnectNodesNum(connect);
            const elem_chunks_num = pce.getChunksNum(connect.getElemsNum(), elem_chunk_size);
            const node_normals_stride = nodes_num * 3;
            const chunk_node_normals = try allocator.alloc(
                f64,
                elem_chunks_num * node_normals_stride,
            );
            defer allocator.free(chunk_node_normals);
            @memset(chunk_node_normals, 0.0);

            var accum_stage = AccumulateAveragedNormalsStage{
                .mesh_type = mesh_type,
                .coords_nodes = coords_nodes,
                .connect = connect,
                .chunk_node_normals = chunk_node_normals,
                .node_normals_stride = node_normals_stride,
            };
            pce.runStaticRange(
                chunk_exec,
                &accum_stage,
                runAccumulateAveragedNormalsStage,
                connect.getElemsNum(),
                elem_chunk_size,
            );

            const node_normals = try allocator.alloc(f64, node_normals_stride);
            defer allocator.free(node_normals);
            @memset(node_normals, 0.0);

            for (0..elem_chunks_num) |cc| {
                const chunk_start = cc * node_normals_stride;
                const chunk_end = chunk_start + node_normals_stride;
                for (chunk_start..chunk_end) |ii| {
                    node_normals[ii - chunk_start] += chunk_node_normals[ii];
                }
            }

            var write_stage = WriteVisibleAveragedNormalsStage{
                .mesh_type = mesh_type,
                .connect = connect,
                .visible_orig_elem_indices = visible_orig_elem_indices,
                .node_normals = node_normals,
                .prep_normals = &prep_normals.array,
            };
            pce.runStaticRange(
                chunk_exec,
                &write_stage,
                runWriteVisibleAveragedNormalsStage,
                visible_orig_elem_indices.len,
                visible_chunk_size,
            );
        },
    }

    return prep_normals;
}

fn getConnectNodesNum(connect: *const meshio.Connect) usize {
    var max_node_idx: usize = 0;
    for (connect.table_mem) |node_idx| {
        max_node_idx = @max(max_node_idx, node_idx);
    }
    return max_node_idx + 1;
}

fn initIdentityMappedNormals(
    allocator: std.mem.Allocator,
    prep_count: usize,
    comptime N: usize,
) !ndarray.MappedNDArray(f64) {
    const prep_normals = try ndarray.NDArray(f64).initFlat(
        allocator,
        &[_]usize{ prep_count, 3, N },
    );
    const map = try allocator.alloc(usize, prep_count);
    for (0..prep_count) |pp| {
        map[pp] = pp;
    }

    return .{
        .array = prep_normals,
        .map = map,
    };
}

const PrepareVisibleExactNormalsStage = struct {
    mesh_type: MeshType,
    coords_nodes: *const meshio.Coords,
    connect: *const meshio.Connect,
    visible_orig_elem_indices: []const usize,
    prep_normals: *ndarray.NDArray(f64),
};

fn runPrepareVisibleExactNormalsStage(
    ctx_ptr: *anyopaque,
    chunk_idx: usize,
    range_start: usize,
    range_end: usize,
) void {
    _ = chunk_idx;
    const stage: *PrepareVisibleExactNormalsStage = @ptrCast(@alignCast(ctx_ptr));
    rops.prepareVisibleExactNormalsRange(
        stage.mesh_type,
        stage.coords_nodes,
        stage.connect,
        stage.visible_orig_elem_indices,
        stage.prep_normals,
        range_start,
        range_end,
    );
}

const AccumulateAveragedNormalsStage = struct {
    mesh_type: MeshType,
    coords_nodes: *const meshio.Coords,
    connect: *const meshio.Connect,
    chunk_node_normals: []f64,
    node_normals_stride: usize,
};

fn runAccumulateAveragedNormalsStage(
    ctx_ptr: *anyopaque,
    chunk_idx: usize,
    range_start: usize,
    range_end: usize,
) void {
    const stage: *AccumulateAveragedNormalsStage = @ptrCast(@alignCast(ctx_ptr));
    const accum_start = chunk_idx * stage.node_normals_stride;
    const accum_end = accum_start + stage.node_normals_stride;
    rops.accumulateAveragedNodeNormalsRange(
        stage.mesh_type,
        stage.coords_nodes,
        stage.connect,
        stage.chunk_node_normals[accum_start..accum_end],
        range_start,
        range_end,
    );
}

const WriteVisibleAveragedNormalsStage = struct {
    mesh_type: MeshType,
    connect: *const meshio.Connect,
    visible_orig_elem_indices: []const usize,
    node_normals: []const f64,
    prep_normals: *ndarray.NDArray(f64),
};

fn runWriteVisibleAveragedNormalsStage(
    ctx_ptr: *anyopaque,
    chunk_idx: usize,
    range_start: usize,
    range_end: usize,
) void {
    _ = chunk_idx;
    const stage: *WriteVisibleAveragedNormalsStage = @ptrCast(@alignCast(ctx_ptr));
    rops.writeVisibleAveragedNormalsRange(
        stage.mesh_type,
        stage.connect,
        stage.visible_orig_elem_indices,
        stage.node_normals,
        stage.prep_normals,
        range_start,
        range_end,
    );
}

//------------------------------------------------------------------------------------------
// Frame Mesh Pipeline: Implementation of the frame-by-frame geometry pipeline
//------------------------------------------------------------------------------------------

const FrameMeshPipeline = struct {
    allocator: std.mem.Allocator,
    camera: *const cam.CameraPrepared,
    mesh_static: *const MeshStatic,
    frame_idx: usize,
    scaling_params: ?imageops.ScalingParams,
    chunk_exec: ?*pce.ParaChunkExecutor,
    workers_num: usize,
    nodes_num: usize,
    elems_num: usize,
    node_chunk_size: usize,
    elem_chunk_size: usize,
    elem_chunks_num: usize,
    visible_chunk_size: usize,
    mesh_frame: MeshFrameContext,

    fn init(
        allocator: std.mem.Allocator,
        camera: *const cam.CameraPrepared,
        mesh_static: *const MeshStatic,
        frame_idx: usize,
        scaling_params: ?imageops.ScalingParams,
        chunk_exec: ?*pce.ParaChunkExecutor,
    ) !FrameMeshPipeline {
        const workers_num = pce.getWorkerCount(chunk_exec);
        const nodes_num = mesh_static.coords_orig.mat.rows_num;
        const elems_num = mesh_static.connect.getElemsNum();
        const node_chunk_size = pce.getChunkSize(nodes_num, workers_num);
        const elem_chunk_size = pce.getChunkSize(elems_num, workers_num);

        return .{
            .allocator = allocator,
            .camera = camera,
            .mesh_static = mesh_static,
            .frame_idx = frame_idx,
            .scaling_params = scaling_params,
            .chunk_exec = chunk_exec,
            .workers_num = workers_num,
            .nodes_num = nodes_num,
            .elems_num = elems_num,
            .node_chunk_size = node_chunk_size,
            .elem_chunk_size = elem_chunk_size,
            .elem_chunks_num = pce.getChunksNum(elems_num, elem_chunk_size),
            .visible_chunk_size = 1,
            .mesh_frame = .{
                .frame_workspace = try initMeshFrameWorkspace(
                    allocator,
                    mesh_static,
                ),
                .visible_counts_by_chunk = &.{},
                .visible_offsets_by_chunk = &.{},
                .visible_elems_num = 0,
            },
        };
    }

    //--------------------------------------------------------------------------------------
    //
    fn run(self: *FrameMeshPipeline) !MeshFrame {
        self.prepareCoords();
        self.transformCoords();

        try self.cullVisible();
        var mesh_prep = try self.compactVisibleMesh();

        try self.prepareRasterHulls(&mesh_prep.coords);
        try self.prepareShader(&mesh_prep);

        self.assignVisibleElemIndices();

        return self.finish(mesh_prep);
    }
    //--------------------------------------------------------------------------------------

    fn prepareCoords(self: *FrameMeshPipeline) void {
        var prepare_stage = PrepareCoordsStage{
            .frame_workspace = &self.mesh_frame.frame_workspace,
            .mesh_static = self.mesh_static,
            .frame_idx = self.frame_idx,
        };
        pce.runDynamicRange(
            self.chunk_exec,
            &prepare_stage,
            runPrepareCoordsDynamicStage,
            self.nodes_num,
            self.node_chunk_size,
        );
    }

    fn transformCoords(self: *FrameMeshPipeline) void {
        var transform_stage = TransformCoordsStage{
            .camera = self.camera,
            .mesh_type = self.mesh_static.mesh_type,
            .frame_workspace = &self.mesh_frame.frame_workspace,
        };
        pce.runDynamicRange(
            self.chunk_exec,
            &transform_stage,
            runTransformCoordsDynamicStage,
            self.nodes_num,
            self.node_chunk_size,
        );
    }

    fn cullVisible(self: *FrameMeshPipeline) !void {
        self.mesh_frame.visible_counts_by_chunk = try self.allocator.alloc(
            usize,
            self.elem_chunks_num,
        );
        self.mesh_frame.visible_offsets_by_chunk = try self.allocator.alloc(
            usize,
            self.elem_chunks_num,
        );
        @memset(self.mesh_frame.visible_counts_by_chunk, 0);
        @memset(self.mesh_frame.visible_offsets_by_chunk, 0);

        var cull_count_stage = CullVisibleCountStage{
            .camera = self.camera,
            .mesh_type = self.mesh_static.mesh_type,
            .connect = &self.mesh_static.connect,
            .coords_nodes = &self.mesh_frame.frame_workspace.coords_nodes,
            .visible_counts_by_chunk = self.mesh_frame.visible_counts_by_chunk,
        };
        pce.runStaticRange(
            self.chunk_exec,
            &cull_count_stage,
            runCullVisibleCountStage,
            self.elems_num,
            self.elem_chunk_size,
        );
        prefixVisibleCounts(&self.mesh_frame);

        self.mesh_frame.frame_workspace.visible_orig_elem_indices =
            try self.allocator.alloc(usize, self.mesh_frame.visible_elems_num);
        self.mesh_frame.frame_workspace.elem_bboxes = try self.allocator.alloc(
            rops.ElemBBox,
            self.mesh_frame.visible_elems_num,
        );

        var cull_fill_stage = CullVisibleFillStage{
            .camera = self.camera,
            .mesh_type = self.mesh_static.mesh_type,
            .connect = &self.mesh_static.connect,
            .coords_nodes = &self.mesh_frame.frame_workspace.coords_nodes,
            .visible_orig_elem_indices = self.mesh_frame.frame_workspace.visible_orig_elem_indices,
            .elem_bboxes = self.mesh_frame.frame_workspace.elem_bboxes,
            .visible_offsets_by_chunk = self.mesh_frame.visible_offsets_by_chunk,
        };
        pce.runStaticRange(
            self.chunk_exec,
            &cull_fill_stage,
            runCullVisibleFillStage,
            self.elems_num,
            self.elem_chunk_size,
        );

        self.visible_chunk_size = pce.getChunkSize(
            self.mesh_frame.visible_elems_num,
            self.workers_num,
        );
    }

    fn compactVisibleMesh(self: *FrameMeshPipeline) !MeshPrepared {
        var elem_coords = try ndarray.NDArray(f64).initFlat(
            self.allocator,
            &[_]usize{
                self.mesh_frame.visible_elems_num,
                3,
                self.mesh_static.mesh_type.getNodesNum(),
            },
        );
        var compact_coords_stage = CompactVisibleCoordsStage{
            .mesh_static = self.mesh_static,
            .frame_workspace = &self.mesh_frame.frame_workspace,
            .elem_coords = &elem_coords,
        };
        pce.runDynamicRange(
            self.chunk_exec,
            &compact_coords_stage,
            runCompactVisibleCoordsDynamicStage,
            self.mesh_frame.visible_elems_num,
            self.visible_chunk_size,
        );

        return .{
            .mesh_type = self.mesh_static.mesh_type,
            .coords = elem_coords,
            .shader = undefined,
        };
    }

    fn prepareRasterHulls(
        self: *FrameMeshPipeline,
        elem_coords: *const ndarray.NDArray(f64),
    ) !void {
        self.mesh_frame.frame_workspace.raster_hull = switch (self.mesh_static.mesh_type) {
            .tri3 => null,
            .quad4ibi, .quad4newton => try ndarray.NDArray(f64).initFlat(
                self.allocator,
                &[_]usize{ self.mesh_frame.visible_elems_num, 2, 4 },
            ),
            .tri6 => try ndarray.NDArray(f64).initFlat(
                self.allocator,
                &[_]usize{ self.mesh_frame.visible_elems_num, 2, 6 },
            ),
            .quad8, .quad9 => try ndarray.NDArray(f64).initFlat(
                self.allocator,
                &[_]usize{ self.mesh_frame.visible_elems_num, 2, 8 },
            ),
        };

        if (self.mesh_frame.frame_workspace.raster_hull) |*raster_hull| {
            var hulls_stage = PrepareRasterHullsStage{
                .camera = self.camera,
                .mesh_type = self.mesh_static.mesh_type,
                .elem_coords = elem_coords,
                .raster_hull = raster_hull,
            };
            pce.runStaticRange(
                self.chunk_exec,
                &hulls_stage,
                runPrepareRasterHullsStage,
                self.mesh_frame.visible_elems_num,
                self.visible_chunk_size,
            );
        }
    }

    fn prepareShader(self: *FrameMeshPipeline, mesh_prep: *MeshPrepared) !void {
        switch (self.mesh_static.shader) {
            .nodal => |nodal_static| {
                mesh_prep.shader = try self.prepareNodalShader(nodal_static);
            },
            .tex => |tex_static| {
                mesh_prep.shader = try FrameMeshPipeline.prepareTexShaderN(
                    1,
                    self,
                    tex_static,
                );
            },
            .tex_rgb => |tex_static| {
                mesh_prep.shader = try FrameMeshPipeline.prepareTexShaderN(
                    3,
                    self,
                    tex_static,
                );
            },
        }
    }

    fn prepareNodalShader(
        self: *FrameMeshPipeline,
        nodal_static: shaderops.NodalStatic,
    ) !shaderops.ShaderPrepared {
        var elem_field = try ndarray.NDArray(f64).initFlat(
            self.allocator,
            &[_]usize{
                self.mesh_frame.visible_elems_num,
                @as(usize, nodal_static.field.getFieldsN()),
                self.mesh_static.connect.getNodesPerElem(),
            },
        );
        var field_stage = CompactVisibleFieldStage{
            .connect = &self.mesh_static.connect,
            .field = &nodal_static.field,
            .frame_idx = self.frame_idx,
            .visible_orig_elem_indices = self.mesh_frame.frame_workspace.visible_orig_elem_indices,
            .elem_field = &elem_field,
        };
        pce.runStaticRange(
            self.chunk_exec,
            &field_stage,
            runCompactVisibleFieldStage,
            self.mesh_frame.visible_elems_num,
            self.visible_chunk_size,
        );

        const factors = if (self.scaling_params) |sp|
            imageops.getScaleFactors(
                nodal_static.scaling,
                nodal_static.bits,
                sp,
            )
        else
            imageops.ScaleFactors{ .mul = 1.0, .add = 0.0 };

        return .{ .nodal = .{
            .elem_field = elem_field,
            .bits = nodal_static.bits,
            .scaling = nodal_static.scaling,
            .scale_over = nodal_static.scale_over,
            .scale_mul = factors.mul,
            .scale_add = factors.add,
            .normal_type = nodal_static.normal_type,
            .elem_normals = try self.prepareVisibleNormals(
                nodal_static.normal_type,
            ),
        } };
    }

    fn prepareTexShaderN(
        comptime channels: usize,
        self: *FrameMeshPipeline,
        tex_static: shaderops.TexStatic(channels),
    ) !shaderops.ShaderPrepared {
        const params = imageops.getScalingParamsTexture(
            channels,
            &tex_static.texture,
            tex_static.scaling,
        );
        const factors = imageops.getScaleFactors(
            tex_static.scaling,
            tex_static.bits,
            params,
        );
        var elem_uvs = try ndarray.NDArray(f64).initFlat(
            self.allocator,
            &[_]usize{
                self.mesh_frame.visible_elems_num,
                2,
                tex_static.elem_uvs.dims[2],
            },
        );
        var uv_stage = CompactVisibleUVStage{
            .elem_uvs_full = tex_static.elem_uvs,
            .visible_orig_elem_indices = self.mesh_frame.frame_workspace.visible_orig_elem_indices,
            .elem_uvs = &elem_uvs,
        };
        pce.runStaticRange(
            self.chunk_exec,
            &uv_stage,
            runCompactVisibleUVStage,
            self.mesh_frame.visible_elems_num,
            self.visible_chunk_size,
        );

        const elem_normals = try self.prepareVisibleNormals(tex_static.normal_type);
        if (channels == 1) {
            return .{ .tex = .{
                .elem_uvs = elem_uvs,
                .texture = tex_static.texture,
                .sample_config = tex_static.sample_config,
                .bits = tex_static.bits,
                .scaling = tex_static.scaling,
                .scale_mul = factors.mul,
                .scale_add = factors.add,
                .normal_type = tex_static.normal_type,
                .elem_normals = elem_normals,
            } };
        }

        return .{ .tex_rgb = .{
            .elem_uvs = elem_uvs,
            .texture = tex_static.texture,
            .sample_config = tex_static.sample_config,
            .bits = tex_static.bits,
            .scaling = tex_static.scaling,
            .scale_mul = factors.mul,
            .scale_add = factors.add,
            .normal_type = tex_static.normal_type,
            .elem_normals = elem_normals,
        } };
    }

    fn prepareVisibleNormals(
        self: *FrameMeshPipeline,
        normal_type: shaderops.NormalType,
    ) !?ndarray.MappedNDArray(f64) {
        if (normal_type == .none) {
            return null;
        }

        return try prepareVisibleNormalsThreaded(
            self.allocator,
            self.mesh_static.mesh_type,
            &self.mesh_frame.frame_workspace.coords_nodes,
            &self.mesh_static.connect,
            self.mesh_frame.frame_workspace.visible_orig_elem_indices,
            normal_type,
            self.chunk_exec,
            self.elem_chunk_size,
            self.visible_chunk_size,
        );
    }

    fn assignVisibleElemIndices(self: *FrameMeshPipeline) void {
        for (self.mesh_frame.frame_workspace.elem_bboxes, 0..) |*elem_bbox, pp| {
            elem_bbox.elem_idx = pp;
        }
    }

    fn finish(
        self: *FrameMeshPipeline,
        mesh_prep: MeshPrepared,
    ) MeshFrame {
        return .{
            .mesh = mesh_prep,
            .elem_bboxes = self.mesh_frame.frame_workspace.elem_bboxes,
            .elems_in_image = self.mesh_frame.frame_workspace.elems_in_image,
            .total_elems_num = self.mesh_static.connect.getElemsNum(),
            .raster_hull = self.mesh_frame.frame_workspace.raster_hull,
        };
    }
};

// We need this thin wrapper to expose this to tests that want to enter at this part of the
// pipeline with a single mesh.
pub fn prepareMeshFrame(
    allocator: std.mem.Allocator,
    chunk_exec: ?*pce.ParaChunkExecutor,
    camera: *const cam.CameraPrepared,
    mesh_static: *const MeshStatic,
    frame_idx: usize,
    scaling_params: ?imageops.ScalingParams,
) !MeshFrame {
    var pipeline = try FrameMeshPipeline.init(
        allocator,
        camera,
        mesh_static,
        frame_idx,
        scaling_params,
        chunk_exec,
    );
    return try pipeline.run();
}

//------------------------------------------------------------------------------------------
// Main Entry Point: Top-level function for preparing all frame meshes
//------------------------------------------------------------------------------------------

pub const FrameGeometryResult = struct {
    total_elems_num: usize,
    total_elems_in_image: usize,
};

//==========================================================================================
// Main Entry Point to Geometry Pipeline
pub fn prepareMeshFrames(
    arena_alloc: std.mem.Allocator,
    chunk_exec: ?*pce.ParaChunkExecutor,
    camera: *const cam.CameraPrepared,
    frame_idx: usize,
    static_meshes: []const MeshStatic,
    nodal_global_scaling: []const ?imageops.ScalingParams,
    frame_meshes: []MeshFrame,
) !FrameGeometryResult {
    var res = FrameGeometryResult{ .total_elems_num = 0, .total_elems_in_image = 0 };

    for (static_meshes, 0..) |*mesh_static, ii| {
        // Only needed for nodal interpolation shading and only if not .none. If .none we
        // directly render float fields unscaled.
        var nodal_frame_scaling: ?imageops.ScalingParams = null;
        switch (mesh_static.shader) {
            .nodal => |s| {
                if (s.scale_over == .over_frames) {
                    nodal_frame_scaling = nodal_global_scaling[ii];
                } else { // .within_frames
                    nodal_frame_scaling = imageops.getScalingParamsNDArray(
                        &s.field.array,
                        frame_idx,
                        s.scaling,
                    );
                }
            },
            else => {},
        }

        // Prepares meshes for each frame including coord transforms to camera space and
        // data reshaping to element order for a given frame.
        frame_meshes[ii] = try prepareMeshFrame(
            arena_alloc,
            chunk_exec,
            camera,
            mesh_static,
            frame_idx,
            nodal_frame_scaling,
        );
        res.total_elems_num += frame_meshes[ii].total_elems_num;
        res.total_elems_in_image += frame_meshes[ii].elems_in_image;
    }

    return res;
}
