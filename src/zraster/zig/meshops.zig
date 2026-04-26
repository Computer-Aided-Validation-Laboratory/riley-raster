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
const normals = @import("normals.zig");
const geomkerns = @import("geometrykernels.zig");

//------------------------------------------------------------------------------------------
// External Helper Functions: General geometry and mesh utilities
//------------------------------------------------------------------------------------------

pub const MeshType = geomkerns.MeshType;
pub const ShaderInput = shaderops.ShaderInput;

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
// Shader UVs: Element-order (gathered during static init as they are usually static).
pub const MeshStatic = struct {
    mesh_type: MeshType,
    coords_orig: meshio.Coords,
    connect: meshio.Connect,
    disp: ?meshio.Field,
    shader: shaderops.ShaderStatic,
};

// Workspace: Temporary node-order working area for the geometry pipeline.
// meshio.Coords: Node-order [total_nodes, 3]. Holds coords for a single frame after 
// displacement.
pub const MeshFrameWorkspace = struct {
    coords_nodes: meshio.Coords,
    visible_orig_elem_indices: []usize,
    elem_bboxes: []rops.ElemBBox,
    elems_in_image: usize,
    raster_hull: ?ndarray.NDArray(f64),
    visible_counts_by_chunk: []usize,
    visible_offsets_by_chunk: []usize,
};

// Frame: Wraps the Prepared payload with per-frame spatial metadata.
// Prepared means culled element-order ndarray.NDArray data ready for the raster loop.
pub const MeshFrame = struct {
    mesh: MeshPrepared,
    elem_bboxes: []rops.ElemBBox,
    elems_in_image: usize,
    total_elems_num: usize,
    raster_hull: ?ndarray.NDArray(f64),
    frame_workspace: MeshFrameWorkspace,
};

// Prepared: Data culled and gathered for the raster loop for a SINGLE frame.
// Prepared means culled element-order ndarray.NDArray data ready for the raster loop.
// Element-order [visible_elems, field, nodes_per_elem]
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

            const format: imageio.ImageFormat = if (
                std.mem.endsWith(u8, texture_path.?, ".bmp")
            )
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

// Outside of pipeline because these are static - we gather these into an NDarray once 
// for all frames and cameras
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
        .visible_counts_by_chunk = &.{},
        .visible_offsets_by_chunk = &.{},
    };
}

//------------------------------------------------------------------------------------------
// Geometry Pipeline Stages: meshio.Coords, Transform, Culling and Gathering
//------------------------------------------------------------------------------------------

fn prefixVisibleCounts(mesh_workspace: *MeshFrameWorkspace) void {
    var running_total: usize = 0;
    for (mesh_workspace.visible_counts_by_chunk, 0..) |visible_count, cc| {
        mesh_workspace.visible_offsets_by_chunk[cc] = running_total;
        running_total += visible_count;
    }
    mesh_workspace.elems_in_image = running_total;
}

fn getConnectNodesNum(connect: *const meshio.Connect) usize {
    var max_node_idx: usize = 0;
    for (connect.table_mem) |node_idx| {
        max_node_idx = @max(max_node_idx, node_idx);
    }
    return max_node_idx + 1;
}

//------------------------------------------------------------------------------------------
// Frame Mesh Pipeline: Implementation of the frame-by-frame geometry pipeline
//------------------------------------------------------------------------------------------

fn FrameMeshPipeline(comptime MT: MeshType) type {
    return struct {
        const FrameMeshPipelineType = @This();

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
        mesh_workspace: MeshFrameWorkspace,

        fn init(
            allocator: std.mem.Allocator,
            camera: *const cam.CameraPrepared,
            mesh_static: *const MeshStatic,
            frame_idx: usize,
            scaling_params: ?imageops.ScalingParams,
            chunk_exec: ?*pce.ParaChunkExecutor,
        ) !FrameMeshPipelineType {
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
                .mesh_workspace = try initMeshFrameWorkspace(
                    allocator,
                    mesh_static,
                ),
            };
        }

        fn run(self: *FrameMeshPipelineType) !MeshFrame {
            self.displaceCoords();
            self.transformCoords();

            try self.cullVisible();
            var mesh_prep = try self.gatherVisibleCoords();

            try self.prepareRasterHulls(&mesh_prep.coords);
            try self.prepareShader(&mesh_prep);

            self.remapVisibleElemIndices();

            return .{
                .mesh = mesh_prep,
                .elem_bboxes = self.mesh_workspace.elem_bboxes,
                .elems_in_image = self.mesh_workspace.elems_in_image,
                .total_elems_num = self.mesh_static.connect.getElemsNum(),
                .raster_hull = self.mesh_workspace.raster_hull,
                .frame_workspace = self.mesh_workspace,
            };
        }

        const DisplaceCoordsStage = struct {
            frame_workspace: *MeshFrameWorkspace,
            mesh_static: *const MeshStatic,
            frame_idx: usize,
        };

        fn runDisplaceCoords(
            ctx_ptr: *anyopaque,
            chunk_idx: usize,
            range_start: usize,
            range_end: usize,
        ) void {
            _ = chunk_idx;
            const stage: *DisplaceCoordsStage = @ptrCast(@alignCast(ctx_ptr));

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
                        stage.frame_workspace.coords_nodes.mem[coord_off + cc] +=
                            disp.array.get(&[_]usize{ actual_frame_idx, nn, cc });
                    }
                }
            }
        }

        fn displaceCoords(self: *FrameMeshPipelineType) void {
            var displace_stage = DisplaceCoordsStage{
                .frame_workspace = &self.mesh_workspace,
                .mesh_static = self.mesh_static,
                .frame_idx = self.frame_idx,
            };
            pce.runStaticRange(
                self.chunk_exec,
                &displace_stage,
                runDisplaceCoords,
                self.nodes_num,
                self.node_chunk_size,
            );
        }

        const TransformCoordsStage = struct {
            camera: *const cam.CameraPrepared,
            frame_workspace: *MeshFrameWorkspace,
        };

        fn runTransformCoords(
            ctx_ptr: *anyopaque,
            chunk_idx: usize,
            range_start: usize,
            range_end: usize,
        ) void {
            _ = chunk_idx;
            const stage: *TransformCoordsStage = @ptrCast(@alignCast(ctx_ptr));
            if (MT == .tri3) {
                rops.nodesToRasterRangeInPlace(
                    stage.camera,
                    &stage.frame_workspace.coords_nodes,
                    range_start,
                    range_end,
                );
            } else {
                rops.nodesToClipPxLengRangeInPlace(
                    stage.camera,
                    &stage.frame_workspace.coords_nodes,
                    range_start,
                    range_end,
                );
            }
        }

        fn transformCoords(self: *FrameMeshPipelineType) void {
            var transform_stage = TransformCoordsStage{
                .camera = self.camera,
                .frame_workspace = &self.mesh_workspace,
            };
            pce.runStaticRange(
                self.chunk_exec,
                &transform_stage,
                runTransformCoords,
                self.nodes_num,
                self.node_chunk_size,
            );
        }

        const CullVisibleCountStage = struct {
            camera: *const cam.CameraPrepared,
            connect: *const meshio.Connect,
            coords_nodes: *const meshio.Coords,
            visible_counts_by_chunk: []usize,
        };

        fn runCullVisibleCount(
            ctx_ptr: *anyopaque,
            chunk_idx: usize,
            range_start: usize,
            range_end: usize,
        ) void {
            const stage: *CullVisibleCountStage = @ptrCast(@alignCast(ctx_ptr));
            var visible_count: usize = 0;

            const N = comptime MT.getNodesNum();
            for (range_start..range_end) |ee| {
                const bbox = if (MT == .tri3)
                    rops.calcVisibleNodeBBoxTri3(
                        stage.camera,
                        stage.coords_nodes,
                        stage.connect,
                        ee,
                    )
                else
                    rops.calcVisibleNodeBBoxHighOrd(
                        N,
                        stage.camera,
                        stage.coords_nodes,
                        stage.connect,
                        ee,
                    );

                if (bbox != null) {
                    visible_count += 1;
                }
            }
            stage.visible_counts_by_chunk[chunk_idx] = visible_count;
        }

        fn cullVisible(self: *FrameMeshPipelineType) !void {
            self.mesh_workspace.visible_counts_by_chunk = try self.allocator.alloc(
                usize,
                self.elem_chunks_num,
            );
            self.mesh_workspace.visible_offsets_by_chunk = try self.allocator.alloc(
                usize,
                self.elem_chunks_num,
            );
            @memset(self.mesh_workspace.visible_counts_by_chunk, 0);
            @memset(self.mesh_workspace.visible_offsets_by_chunk, 0);

            var cull_count_stage = CullVisibleCountStage{
                .camera = self.camera,
                .connect = &self.mesh_static.connect,
                .coords_nodes = &self.mesh_workspace.coords_nodes,
                .visible_counts_by_chunk = self.mesh_workspace.visible_counts_by_chunk,
            };
            pce.runStaticRange(
                self.chunk_exec,
                &cull_count_stage,
                runCullVisibleCount,
                self.elems_num,
                self.elem_chunk_size,
            );

            prefixVisibleCounts(&self.mesh_workspace);

            self.mesh_workspace.visible_orig_elem_indices =
                try self.allocator.alloc(usize, self.mesh_workspace.elems_in_image);
            self.mesh_workspace.elem_bboxes = try self.allocator.alloc(
                rops.ElemBBox,
                self.mesh_workspace.elems_in_image,
            );

            var cull_fill_stage = CullVisibleFillStage{
                .camera = self.camera,
                .connect = &self.mesh_static.connect,
                .coords_nodes = &self.mesh_workspace.coords_nodes,
                .visible_orig_elem_indices = self.mesh_workspace.visible_orig_elem_indices,
                .elem_bboxes = self.mesh_workspace.elem_bboxes,
                .visible_offsets_by_chunk = self.mesh_workspace.visible_offsets_by_chunk,
            };
            pce.runStaticRange(
                self.chunk_exec,
                &cull_fill_stage,
                runCullVisibleFill,
                self.elems_num,
                self.elem_chunk_size,
            );

            self.visible_chunk_size = pce.getChunkSize(
                self.mesh_workspace.elems_in_image,
                self.workers_num,
            );
        }

        const CullVisibleFillStage = struct {
            camera: *const cam.CameraPrepared,
            connect: *const meshio.Connect,
            coords_nodes: *const meshio.Coords,
            visible_orig_elem_indices: []usize,
            elem_bboxes: []rops.ElemBBox,
            visible_offsets_by_chunk: []const usize,
        };

        fn runCullVisibleFill(
            ctx_ptr: *anyopaque,
            chunk_idx: usize,
            range_start: usize,
            range_end: usize,
        ) void {
            const stage: *CullVisibleFillStage = @ptrCast(@alignCast(ctx_ptr));
            var write_idx = stage.visible_offsets_by_chunk[chunk_idx];

            const N = comptime MT.getNodesNum();
            for (range_start..range_end) |ee| {
                const bbox = if (comptime MT == .tri3)
                    rops.calcVisibleNodeBBoxTri3(
                        stage.camera,
                        stage.coords_nodes,
                        stage.connect,
                        ee,
                    )
                else
                    rops.calcVisibleNodeBBoxHighOrd(
                        N,
                        stage.camera,
                        stage.coords_nodes,
                        stage.connect,
                        ee,
                    );

                if (bbox) |b| {
                    stage.visible_orig_elem_indices[write_idx] = ee;
                    stage.elem_bboxes[write_idx] = b;
                    write_idx += 1;
                }
            }
        }

        const GatherVisibleCoordsStage = struct {
            connect: *const meshio.Connect,
            coords_nodes: *const meshio.Coords,
            visible_orig_elem_indices: []const usize,
            elem_coords: *ndarray.NDArray(f64),
        };

        fn runGatherVisibleCoords(
            ctx_ptr: *anyopaque,
            chunk_idx: usize,
            range_start: usize,
            range_end: usize,
        ) void {
            _ = chunk_idx;
            const stage: *GatherVisibleCoordsStage = @ptrCast(@alignCast(ctx_ptr));
            const N = comptime MT.getNodesNum();

            for (range_start..range_end) |pp| {
                const orig_ee = stage.visible_orig_elem_indices[pp];
                const coord_inds = stage.connect.getElem(orig_ee);
                for (0..N) |nn| {
                    const node_idx = coord_inds[nn];
                    stage.elem_coords.set(
                        &[_]usize{ pp, 0, nn },
                        stage.coords_nodes.x(node_idx),
                    );
                    stage.elem_coords.set(
                        &[_]usize{ pp, 1, nn },
                        stage.coords_nodes.y(node_idx),
                    );
                    stage.elem_coords.set(
                        &[_]usize{ pp, 2, nn },
                        stage.coords_nodes.z(node_idx),
                    );
                }
            }
        }

        fn gatherVisibleCoords(self: *FrameMeshPipelineType) !MeshPrepared {
            const N = comptime MT.getNodesNum();
            var elem_coords = try ndarray.NDArray(f64).initFlat(
                self.allocator,
                &[_]usize{ self.mesh_workspace.elems_in_image, 3, N },
            );

            var gather_coords_stage = GatherVisibleCoordsStage{
                .connect = &self.mesh_static.connect,
                .coords_nodes = &self.mesh_workspace.coords_nodes,
                .visible_orig_elem_indices = self.mesh_workspace.visible_orig_elem_indices,
                .elem_coords = &elem_coords,
            };

            pce.runStaticRange(
                self.chunk_exec,
                &gather_coords_stage,
                runGatherVisibleCoords,
                self.mesh_workspace.elems_in_image,
                self.visible_chunk_size,
            );

            return .{
                .mesh_type = MT,
                .coords = elem_coords,
                .shader = undefined,
            };
        }

        const PrepareRasterHullsStage = struct {
            camera: *const cam.CameraPrepared,
            elem_coords: *const ndarray.NDArray(f64),
            raster_hull: *ndarray.NDArray(f64),
        };

        fn runPrepareRasterHulls(
            ctx_ptr: *anyopaque,
            chunk_idx: usize,
            range_start: usize,
            range_end: usize,
        ) void {
            _ = chunk_idx;
            const stage: *PrepareRasterHullsStage = @ptrCast(@alignCast(ctx_ptr));
            rops.prepareVisibleRasterHullsRange(
                MT,
                stage.camera,
                stage.elem_coords,
                stage.raster_hull,
                range_start,
                range_end,
            );
        }

        fn prepareRasterHulls(
            self: *FrameMeshPipelineType,
            elem_coords: *const ndarray.NDArray(f64),
        ) !void {
            if (comptime MT == .tri3) {
                self.mesh_workspace.raster_hull = null;
                return;
            }

            const NH = comptime MT.getNumHullPoints();
            self.mesh_workspace.raster_hull = try ndarray.NDArray(f64).initFlat(
                self.allocator,
                &[_]usize{ self.mesh_workspace.elems_in_image, 2, NH },
            );

            var hulls_stage = PrepareRasterHullsStage{
                .camera = self.camera,
                .elem_coords = elem_coords,
                .raster_hull = &self.mesh_workspace.raster_hull.?,
            };
            pce.runStaticRange(
                self.chunk_exec,
                &hulls_stage,
                runPrepareRasterHulls,
                self.mesh_workspace.elems_in_image,
                self.visible_chunk_size,
            );
        }

        fn prepareShader(self: *FrameMeshPipelineType, mesh_prep: *MeshPrepared) !void {
            switch (self.mesh_static.shader) {
                .nodal => |nodal_static| {
                    mesh_prep.shader = try self.prepareNodalShader(nodal_static);
                },
                .tex => |tex_static| {
                    mesh_prep.shader = try prepareTexShader(1, self, tex_static);
                },
                .tex_rgb => |tex_static| {
                    mesh_prep.shader = try prepareTexShader(3, self, tex_static);
                },
            }
        }

        const GatherVisibleFieldStage = struct {
            connect: *const meshio.Connect,
            field: *const meshio.Field,
            frame_idx: usize,
            visible_orig_elem_indices: []const usize,
            elem_field: *ndarray.NDArray(f64),
        };

        fn runGatherVisibleField(
            ctx_ptr: *anyopaque,
            chunk_idx: usize,
            range_start: usize,
            range_end: usize,
        ) void {
            _ = chunk_idx;
            const stage: *GatherVisibleFieldStage = @ptrCast(@alignCast(ctx_ptr));
            const actual_frame_idx = @min(stage.frame_idx, stage.field.array.dims[0] - 1);
            const fields_num = stage.field.getFieldsN();
            const N = comptime MT.getNodesNum();

            for (range_start..range_end) |pp| {
                const orig_ee = stage.visible_orig_elem_indices[pp];
                const coord_inds = stage.connect.getElem(orig_ee);
                for (0..N) |nn| {
                    for (0..@as(usize, fields_num)) |ff| {
                        const field_val = stage.field.array.get(
                            &[_]usize{ actual_frame_idx, coord_inds[nn], ff },
                        );
                        stage.elem_field.set(&[_]usize{ pp, ff, nn }, field_val);
                    }
                }
            }
        }

        fn prepareNodalShader(
            self: *FrameMeshPipelineType,
            nodal_static: shaderops.NodalStatic,
        ) !shaderops.ShaderPrepared {
            const N = comptime MT.getNodesNum();
            var elem_field = try ndarray.NDArray(f64).initFlat(
                self.allocator,
                &[_]usize{
                    self.mesh_workspace.elems_in_image,
                    @as(usize, nodal_static.field.getFieldsN()),
                    N,
                },
            );

            var field_stage = GatherVisibleFieldStage{
                .connect = &self.mesh_static.connect,
                .field = &nodal_static.field,
                .frame_idx = self.frame_idx,
                .visible_orig_elem_indices = self.mesh_workspace.visible_orig_elem_indices,
                .elem_field = &elem_field,
            };

            pce.runStaticRange(
                self.chunk_exec,
                &field_stage,
                runGatherVisibleField,
                self.mesh_workspace.elems_in_image,
                self.visible_chunk_size,
            );

            const factors = if (self.scaling_params) |sp|
                imageops.getScaleFactors(nodal_static.scaling, nodal_static.bits, sp)
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
                .elem_normals = try self.prepareVisibleNormals(nodal_static.normal_type),
            } };
        }

        const GatherVisibleUVStage = struct {
            elem_uvs_full: ndarray.NDArray(f64),
            visible_orig_elem_indices: []const usize,
            elem_uvs: *ndarray.NDArray(f64),
        };

        fn runGatherVisibleUV(
            ctx_ptr: *anyopaque,
            chunk_idx: usize,
            range_start: usize,
            range_end: usize,
        ) void {
            _ = chunk_idx;
            const stage: *GatherVisibleUVStage = @ptrCast(@alignCast(ctx_ptr));
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

        fn prepareTexShader(
            comptime channels: usize,
            self: *FrameMeshPipelineType,
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
                    self.mesh_workspace.elems_in_image,
                    2,
                    tex_static.elem_uvs.dims[2],
                },
            );

            var uv_stage = GatherVisibleUVStage{
                .elem_uvs_full = tex_static.elem_uvs,
                .visible_orig_elem_indices = self.mesh_workspace.visible_orig_elem_indices,
                .elem_uvs = &elem_uvs,
            };

            pce.runStaticRange(
                self.chunk_exec,
                &uv_stage,
                runGatherVisibleUV,
                self.mesh_workspace.elems_in_image,
                self.visible_chunk_size,
            );

            const elem_normals = try self.prepareVisibleNormals(tex_static.normal_type);
            if (comptime channels == 1) {
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
            } else {
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
        }

        fn prepareVisibleNormals(
            self: *FrameMeshPipelineType,
            normal_type: shaderops.NormalType,
        ) !?ndarray.MappedNDArray(f64) {
            if (normal_type == .none) {
                return null;
            }

            return try normals.prepareVisibleNormalsThreaded(
                MT,
                self.allocator,
                &self.mesh_workspace.coords_nodes,
                &self.mesh_static.connect,
                self.mesh_workspace.visible_orig_elem_indices,
                normal_type,
                self.chunk_exec,
                self.elem_chunk_size,
                self.visible_chunk_size,
            );
        }

        fn remapVisibleElemIndices(self: *FrameMeshPipelineType) void {
            for (self.mesh_workspace.elem_bboxes, 0..) |*elem_bbox, pp| {
                elem_bbox.elem_idx = pp;
            }
        }
    };
}

pub fn prepareMeshFrame(
    allocator: std.mem.Allocator,
    chunk_exec: ?*pce.ParaChunkExecutor,
    camera: *const cam.CameraPrepared,
    mesh_static: *const MeshStatic,
    frame_idx: usize,
    scaling_params: ?imageops.ScalingParams,
) !MeshFrame {
    return switch (mesh_static.mesh_type) {
        inline else => |MT| {
            var pipeline = try FrameMeshPipeline(MT).init(
                allocator,
                camera,
                mesh_static,
                frame_idx,
                scaling_params,
                chunk_exec,
            );
            return try pipeline.run();
        },
    };
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
