// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const NDArray = @import("ndarray.zig").NDArray;
const MappedNDArray = @import("ndarray.zig").MappedNDArray;
const MatSlice = @import("matslice.zig").MatSlice;

const meshio = @import("meshio.zig");
const Coords = meshio.Coords;
const Connect = meshio.Connect;
const Field = meshio.Field;

const uvio = @import("uvio.zig");

const imageio = @import("imageio.zig");
const ImageFormat = imageio.ImageFormat;

const imageops = @import("imageops.zig");
const ScalingParams = imageops.ScalingParams;
const Camera = @import("camera.zig").Camera;
const geomthread = @import("geomthread.zig");
const rops = @import("rasterops.zig");
const ElemBBox = rops.ElemBBox;
const texops = @import("textureops.zig");
const TextureSampleConfig = texops.TextureSampleConfig;

const shaderops = @import("shaderops.zig");
const NodalInput = shaderops.NodalInput;
const TexInput = shaderops.TexInput;
const ShaderInput = shaderops.ShaderInput;
const ShaderPrepared = shaderops.ShaderPrepared;

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

pub const MeshInput = struct {
    mesh_type: MeshType,
    coords: Coords,
    connect: Connect,
    disp: ?Field,
    shader: shaderops.ShaderInput,
};

pub const MeshPrepared = struct {
    mesh_type: MeshType,
    coords: NDArray(f64),
    connect: Connect,
    shader: shaderops.ShaderPrepared,
};

pub const MeshStaticPrepared = struct {
    mesh_type: MeshType,
    coords_orig: Coords,
    connect: Connect,
    disp: ?Field,
    shader: ShaderStaticPrepared,
};

pub const FrameMeshWorkspace = struct {
    coords_nodes: Coords,
    visible_orig_elem_indices: []usize,
    elem_bboxes: []ElemBBox,
    elems_in_image: usize,
    raster_hull: ?NDArray(f64),
};

pub const FrameMeshPrepared = struct {
    mesh: MeshPrepared,
    elem_bboxes: []ElemBBox,
    elems_in_image: usize,
    total_elems_num: usize,
    raster_hull: ?NDArray(f64),
};

pub const NodalStaticPrepared = struct {
    field: Field,
    bits: ?u8 = 8,
    scaling: imageops.ScaleStrategy = .none,
    scale_over: shaderops.ScaleOver = .over_frames,
    normal_type: shaderops.NormalType = .none,
};

pub fn TexStaticPrepared(comptime channels: usize) type {
    return struct {
        elem_uvs: NDArray(f64),
        texture: imageio.Texture(channels),
        sample_config: TextureSampleConfig = .{
            .sample = .cubic_catmull_rom,
            .mode = .lut_lerp,
        },
        bits: ?u8 = 8,
        scaling: imageops.ScaleStrategy = .none,
        normal_type: shaderops.NormalType = .none,
    };
}

pub const ShaderStaticPrepared = union(enum) {
    nodal: NodalStaticPrepared,
    tex: TexStaticPrepared(1),
    tex_rgb: TexStaticPrepared(3),
};

pub fn findAlignedCentroid(coords: *const Coords) struct {
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

            const format: ImageFormat = if (std.mem.endsWith(u8, texture_path.?, ".bmp"))
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

pub fn prepareMesh(
    outer_alloc: std.mem.Allocator,
    mesh_input: *const MeshInput,
    coords: *const MatSlice(f64),
    scaling_params: ?ScalingParams,
) !MeshPrepared {
    const wrap_coords = Coords.init(coords.slice, coords.rows_num);
    const elem_coords = try prepareCoords(
        outer_alloc,
        &wrap_coords,
        &mesh_input.connect,
    );

    var mesh_prep = MeshPrepared{
        .mesh_type = mesh_input.mesh_type,
        .coords = elem_coords,
        .connect = mesh_input.connect,
        .shader = undefined,
    };

    switch (mesh_input.shader) {
        .nodal => |*nodal_in| {
            const elem_field = try prepareField(
                outer_alloc,
                &mesh_input.connect,
                &nodal_in.field,
            );

            const factors = if (scaling_params) |sp|
                imageops.getScaleFactors(nodal_in.scaling, nodal_in.bits, sp)
            else
                imageops.ScaleFactors{ .mul = 1.0, .add = 0.0 };

            mesh_prep.shader = .{ .nodal = .{
                .elem_field = elem_field,
                .bits = nodal_in.bits,
                .scaling = nodal_in.scaling,
                .scale_over = nodal_in.scale_over,
                .scale_mul = factors.mul,
                .scale_add = factors.add,
                .normal_type = nodal_in.normal_type,
                .elem_normals = null,
            } };
        },
        .tex => |*tex_in| {
            const elem_uvs = try prepareUVs(
                outer_alloc,
                &tex_in.uvs,
                &mesh_input.connect,
            );
            const params = imageops.getScalingParamsTexture(
                1,
                &tex_in.texture,
                tex_in.scaling,
            );
            const factors = imageops.getScaleFactors(tex_in.scaling, tex_in.bits, params);
            mesh_prep.shader = .{ .tex = .{
                .elem_uvs = elem_uvs,
                .texture = tex_in.texture,
                .sample_config = tex_in.sample_config,
                .bits = tex_in.bits,
                .scaling = tex_in.scaling,
                .scale_mul = factors.mul,
                .scale_add = factors.add,
                .normal_type = tex_in.normal_type,
                .elem_normals = null,
            } };
        },
        .tex_rgb => |*tex_in| {
            const elem_uvs = try prepareUVs(
                outer_alloc,
                &tex_in.uvs,
                &mesh_input.connect,
            );
            const params = imageops.getScalingParamsTexture(
                3,
                &tex_in.texture,
                tex_in.scaling,
            );
            const factors = imageops.getScaleFactors(tex_in.scaling, tex_in.bits, params);
            mesh_prep.shader = .{ .tex_rgb = .{
                .elem_uvs = elem_uvs,
                .texture = tex_in.texture,
                .sample_config = tex_in.sample_config,
                .bits = tex_in.bits,
                .scaling = tex_in.scaling,
                .scale_mul = factors.mul,
                .scale_add = factors.add,
                .normal_type = tex_in.normal_type,
                .elem_normals = null,
            } };
        },
    }

    return mesh_prep;
}

pub fn prepareMeshStatic(
    allocator: std.mem.Allocator,
    mesh_input: *const MeshInput,
) !MeshStaticPrepared {
    const coords_orig = try copyCoordsAlloc(allocator, &mesh_input.coords);

    var shader_static: ShaderStaticPrepared = undefined;
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

pub fn prepareCoords(
    outer_alloc: std.mem.Allocator,
    coords: *const Coords,
    connect: *const Connect,
) !NDArray(f64) {
    const coord_dims = [_]usize{ connect.getElemsNum(), 3, connect.getNodesPerElem() };
    var elem_coord_arr = try NDArray(f64).initFlat(outer_alloc, coord_dims[0..]);
    @memset(elem_coord_arr.slice, 0.0);

    const dim_elem: usize = 0;
    const dim_field: usize = 1;
    const dim_node: usize = 2;

    var elem_idxs = [_]usize{ 0, 0, 0 };

    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        elem_idxs[dim_elem] = ee;
        const coord_inds: []usize = connect.getElem(ee);

        for (0..elem_coord_arr.dims[dim_node]) |nn| {
            elem_idxs[dim_node] = nn;

            const node_idx = coord_inds[nn];
            const x = coords.x(node_idx);
            const y = coords.y(node_idx);
            const z = coords.z(node_idx);

            elem_idxs[dim_field] = 0;
            elem_coord_arr.set(elem_idxs[0..], x);
            elem_idxs[dim_field] = 1;
            elem_coord_arr.set(elem_idxs[0..], y);
            elem_idxs[dim_field] = 2;
            elem_coord_arr.set(elem_idxs[0..], z);
        }
    }

    return elem_coord_arr;
}

pub fn prepareField(
    outer_alloc: std.mem.Allocator,
    connect: *const Connect,
    field: *const Field,
) !NDArray(f64) {
    // dims=(times_num,elems_num,fields_num,nodes_per_elem)
    const field_dims = [_]usize{
        field.getTimeN(),
        connect.getElemsNum(),
        field.getFieldsN(),
        connect.getNodesPerElem(),
    };
    var elem_field_arr = try NDArray(f64).initFlat(outer_alloc, field_dims[0..]);
    @memset(elem_field_arr.slice, 0.0);

    const dim_time: usize = 0;
    const dim_elem: usize = 1;
    const dim_field: usize = 2;
    const dim_node: usize = 3;

    var set_elem_idxs = [_]usize{ 0, 0, 0, 0 }; // dims=(time,elem,field,node)
    var get_field_idxs = [_]usize{ 0, 0, 0 }; // dims=(time,coord,field)

    for (0..elem_field_arr.dims[dim_time]) |tt| {
        get_field_idxs[0] = @min(tt, field.array.dims[0] - 1);
        set_elem_idxs[dim_time] = tt;

        for (0..elem_field_arr.dims[dim_elem]) |ee| {
            set_elem_idxs[dim_elem] = ee;
            const coord_inds: []usize = connect.getElem(ee);

            for (0..elem_field_arr.dims[dim_node]) |nn| {
                set_elem_idxs[dim_node] = nn;
                get_field_idxs[1] = coord_inds[nn];

                for (0..elem_field_arr.dims[dim_field]) |ff| {
                    get_field_idxs[2] = ff;
                    const field_val: f64 = field.array.get(get_field_idxs[0..]);

                    set_elem_idxs[dim_field] = ff;
                    elem_field_arr.set(set_elem_idxs[0..], field_val);
                }
            }
        }
    }

    return elem_field_arr;
}

pub fn prepareUVs(
    outer_alloc: std.mem.Allocator,
    uvs: *const NDArray(f64),
    connect: *const Connect,
) !NDArray(f64) {
    const elems_num = connect.getElemsNum();
    const nodes_per_elem = connect.getNodesPerElem();
    var elem_uv_arr = try NDArray(f64).initFlat(
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
    coords: *const Coords,
) !Coords {
    const coords_copy = try Coords.initAlloc(allocator, coords.mat.rows_num);
    @memcpy(coords_copy.mem, coords.mem);
    return coords_copy;
}

//------------------------------------------------------------------------------------------
// Geometry Workspace and Chunks: Pipeline workspace and chunking utilities
//------------------------------------------------------------------------------------------

const MeshFrameContext = struct {
    frame_workspace: FrameMeshWorkspace,
    visible_counts_by_chunk: []usize,
    visible_offsets_by_chunk: []usize,
    visible_elems_num: usize,
};

fn initFrameMeshWorkspace(
    allocator: std.mem.Allocator,
    mesh_static: *const MeshStaticPrepared,
) !FrameMeshWorkspace {
    return .{
        .coords_nodes = try Coords.initAlloc(
            allocator,
            mesh_static.coords_orig.mat.rows_num,
        ),
        .visible_orig_elem_indices = &.{},
        .elem_bboxes = &.{},
        .elems_in_image = 0,
        .raster_hull = null,
    };
}

fn getChunkSize(domain_len: usize, workers_num: usize) usize {
    if (domain_len == 0) {
        return 1;
    }

    const chunk_count = @max(@as(usize, 1), workers_num * 4);
    return @max(@as(usize, 1), (domain_len + chunk_count - 1) / chunk_count);
}

fn getChunksNum(domain_len: usize, chunk_size: usize) usize {
    if (domain_len == 0) {
        return 0;
    }
    return (domain_len + chunk_size - 1) / chunk_size;
}

fn getWorkerCount(geom_pool: ?*geomthread.GeometryWorkerPool) usize {
    if (geom_pool) |pool| {
        return pool.workers_num;
    }
    return 1;
}

fn runStageRange(
    geom_pool: ?*geomthread.GeometryWorkerPool,
    ctx_ptr: *anyopaque,
    job_func: geomthread.RangeFn,
    domain_len: usize,
    chunk_size: usize,
) void {
    if (domain_len == 0) {
        return;
    }

    if (geom_pool) |pool| {
        pool.runRange(ctx_ptr, job_func, domain_len, chunk_size) catch unreachable;
        return;
    }

    const chunks_num = getChunksNum(domain_len, chunk_size);
    for (0..chunks_num) |chunk_idx| {
        const range_start = chunk_idx * chunk_size;
        const range_end = @min(domain_len, range_start + chunk_size);
        job_func(ctx_ptr, chunk_idx, range_start, range_end);
    }
}

//------------------------------------------------------------------------------------------
// Geometry Pipeline Stages: Coords, Transform, Culling and Compaction
//------------------------------------------------------------------------------------------

fn prepareFrameMeshCoordsRange(
    frame_workspace: *FrameMeshWorkspace,
    mesh_static: *const MeshStaticPrepared,
    frame_idx: usize,
    node_start: usize,
    node_end: usize,
) void {
    const actual_frame_idx = if (mesh_static.disp) |disp|
        @min(frame_idx, disp.array.dims[0] - 1)
    else
        0;

    for (node_start..node_end) |nn| {
        const coord_off = nn * 3;
        frame_workspace.coords_nodes.mem[coord_off + 0] =
            mesh_static.coords_orig.mem[coord_off + 0];
        frame_workspace.coords_nodes.mem[coord_off + 1] =
            mesh_static.coords_orig.mem[coord_off + 1];
        frame_workspace.coords_nodes.mem[coord_off + 2] =
            mesh_static.coords_orig.mem[coord_off + 2];

        if (mesh_static.disp) |disp| {
            for (0..3) |cc| {
                frame_workspace.coords_nodes.mem[coord_off + cc] += disp.array.get(
                    &[_]usize{ actual_frame_idx, nn, cc },
                );
            }
        }
    }
}

fn transformFrameMeshCoordsRange(
    camera: *const Camera,
    mesh_type: MeshType,
    frame_workspace: *FrameMeshWorkspace,
    node_start: usize,
    node_end: usize,
) void {
    switch (mesh_type) {
        .tri3 => rops.nodesToRasterRangeInPlace(
            camera,
            &frame_workspace.coords_nodes,
            node_start,
            node_end,
        ),
        .quad4ibi => rops.nodesToClipPxLengRangeInPlace(
            camera,
            &frame_workspace.coords_nodes,
            node_start,
            node_end,
        ),
        .tri6,
        .quad4newton,
        .quad8,
        .quad9,
        => rops.nodesToClipPxLengRangeInPlace(
            camera,
            &frame_workspace.coords_nodes,
            node_start,
            node_end,
        ),
    }
}

fn compactVisibleCoordsRange(
    mesh_static: *const MeshStaticPrepared,
    frame_workspace: *const FrameMeshWorkspace,
    elem_coords: *NDArray(f64),
    visible_start: usize,
    visible_end: usize,
) void {
    const nodes_num = mesh_static.mesh_type.getNodesNum();

    for (visible_start..visible_end) |pp| {
        const orig_ee = frame_workspace.visible_orig_elem_indices[pp];
        const coord_inds = mesh_static.connect.getElem(orig_ee);
        for (0..nodes_num) |nn| {
            const node_idx = coord_inds[nn];
            elem_coords.set(
                &[_]usize{ pp, 0, nn },
                frame_workspace.coords_nodes.x(node_idx),
            );
            elem_coords.set(
                &[_]usize{ pp, 1, nn },
                frame_workspace.coords_nodes.y(node_idx),
            );
            elem_coords.set(
                &[_]usize{ pp, 2, nn },
                frame_workspace.coords_nodes.z(node_idx),
            );
        }
    }
}

fn compactVisibleUVsRange(
    elem_uvs_full: NDArray(f64),
    visible_orig_elem_indices: []const usize,
    elem_uvs: *NDArray(f64),
    visible_start: usize,
    visible_end: usize,
) void {
    const nodes_num = elem_uvs_full.dims[2];

    for (visible_start..visible_end) |pp| {
        const orig_ee = visible_orig_elem_indices[pp];
        const src_start = elem_uvs_full.getFlatIdx(&[_]usize{ orig_ee, 0, 0 });
        const dst_start = elem_uvs.getFlatIdx(&[_]usize{ pp, 0, 0 });
        @memcpy(
            elem_uvs.slice[dst_start .. dst_start + 2 * nodes_num],
            elem_uvs_full.slice[src_start .. src_start + 2 * nodes_num],
        );
    }
}

fn compactVisibleFieldFrameRange(
    connect: *const Connect,
    field: *const Field,
    frame_idx: usize,
    visible_orig_elem_indices: []const usize,
    elem_field: *NDArray(f64),
    visible_start: usize,
    visible_end: usize,
) void {
    const actual_frame_idx = @min(frame_idx, field.array.dims[0] - 1);
    const fields_num = field.getFieldsN();
    const nodes_num = connect.getNodesPerElem();

    for (visible_start..visible_end) |pp| {
        const orig_ee = visible_orig_elem_indices[pp];
        const coord_inds = connect.getElem(orig_ee);
        for (0..nodes_num) |nn| {
            for (0..@as(usize, fields_num)) |ff| {
                const field_val = field.array.get(
                    &[_]usize{ actual_frame_idx, coord_inds[nn], ff },
                );
                elem_field.set(&[_]usize{ pp, ff, nn }, field_val);
            }
        }
    }
}

const PrepareFrameCoordsStage = struct {
    frame_workspace: *FrameMeshWorkspace,
    mesh_static: *const MeshStaticPrepared,
    frame_idx: usize,
};

fn runPrepareFrameCoordsStage(
    ctx_ptr: *anyopaque,
    chunk_idx: usize,
    range_start: usize,
    range_end: usize,
) void {
    _ = chunk_idx;
    const stage: *PrepareFrameCoordsStage = @ptrCast(@alignCast(ctx_ptr));
    prepareFrameMeshCoordsRange(
        stage.frame_workspace,
        stage.mesh_static,
        stage.frame_idx,
        range_start,
        range_end,
    );
}

const TransformFrameCoordsStage = struct {
    camera: *const Camera,
    mesh_type: MeshType,
    frame_workspace: *FrameMeshWorkspace,
};

fn runTransformFrameCoordsStage(
    ctx_ptr: *anyopaque,
    chunk_idx: usize,
    range_start: usize,
    range_end: usize,
) void {
    _ = chunk_idx;
    const stage: *TransformFrameCoordsStage = @ptrCast(@alignCast(ctx_ptr));
    transformFrameMeshCoordsRange(
        stage.camera,
        stage.mesh_type,
        stage.frame_workspace,
        range_start,
        range_end,
    );
}

const CullVisibleCountStage = struct {
    camera: *const Camera,
    mesh_type: MeshType,
    connect: *const Connect,
    coords_nodes: *const Coords,
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
    camera: *const Camera,
    mesh_type: MeshType,
    connect: *const Connect,
    coords_nodes: *const Coords,
    visible_orig_elem_indices: []usize,
    elem_bboxes: []ElemBBox,
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
    mesh_static: *const MeshStaticPrepared,
    frame_workspace: *const FrameMeshWorkspace,
    elem_coords: *NDArray(f64),
};

fn runCompactVisibleCoordsStage(
    ctx_ptr: *anyopaque,
    chunk_idx: usize,
    range_start: usize,
    range_end: usize,
) void {
    _ = chunk_idx;
    const stage: *CompactVisibleCoordsStage = @ptrCast(@alignCast(ctx_ptr));
    compactVisibleCoordsRange(
        stage.mesh_static,
        stage.frame_workspace,
        stage.elem_coords,
        range_start,
        range_end,
    );
}

const CompactVisibleFieldStage = struct {
    connect: *const Connect,
    field: *const Field,
    frame_idx: usize,
    visible_orig_elem_indices: []const usize,
    elem_field: *NDArray(f64),
};

fn runCompactVisibleFieldStage(
    ctx_ptr: *anyopaque,
    chunk_idx: usize,
    range_start: usize,
    range_end: usize,
) void {
    _ = chunk_idx;
    const stage: *CompactVisibleFieldStage = @ptrCast(@alignCast(ctx_ptr));
    compactVisibleFieldFrameRange(
        stage.connect,
        stage.field,
        stage.frame_idx,
        stage.visible_orig_elem_indices,
        stage.elem_field,
        range_start,
        range_end,
    );
}

const CompactVisibleUVStage = struct {
    elem_uvs_full: NDArray(f64),
    visible_orig_elem_indices: []const usize,
    elem_uvs: *NDArray(f64),
};

fn runCompactVisibleUVStage(
    ctx_ptr: *anyopaque,
    chunk_idx: usize,
    range_start: usize,
    range_end: usize,
) void {
    _ = chunk_idx;
    const stage: *CompactVisibleUVStage = @ptrCast(@alignCast(ctx_ptr));
    compactVisibleUVsRange(
        stage.elem_uvs_full,
        stage.visible_orig_elem_indices,
        stage.elem_uvs,
        range_start,
        range_end,
    );
}

const PrepareVisibleHullsStage = struct {
    camera: *const Camera,
    mesh_type: MeshType,
    elem_coords: *const NDArray(f64),
    raster_hull: *NDArray(f64),
};

fn runPrepareVisibleHullsStage(
    ctx_ptr: *anyopaque,
    chunk_idx: usize,
    range_start: usize,
    range_end: usize,
) void {
    _ = chunk_idx;
    const stage: *PrepareVisibleHullsStage = @ptrCast(@alignCast(ctx_ptr));
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
    coords_nodes: *const Coords,
    connect: *const Connect,
    visible_orig_elem_indices: []const usize,
    normal_type: shaderops.NormalType,
    geom_pool: ?*geomthread.GeometryWorkerPool,
    elem_chunk_size: usize,
    visible_chunk_size: usize,
) !MappedNDArray(f64) {
    return switch (mesh_type) {
        .tri3 => try prepareVisibleNormalsThreadedN(
            allocator,
            mesh_type,
            coords_nodes,
            connect,
            visible_orig_elem_indices,
            normal_type,
            geom_pool,
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
            geom_pool,
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
            geom_pool,
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
            geom_pool,
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
            geom_pool,
            elem_chunk_size,
            visible_chunk_size,
            9,
        ),
    };
}

fn prepareVisibleNormalsThreadedN(
    allocator: std.mem.Allocator,
    mesh_type: MeshType,
    coords_nodes: *const Coords,
    connect: *const Connect,
    visible_orig_elem_indices: []const usize,
    normal_type: shaderops.NormalType,
    geom_pool: ?*geomthread.GeometryWorkerPool,
    elem_chunk_size: usize,
    visible_chunk_size: usize,
    comptime N: usize,
) !MappedNDArray(f64) {
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
            runStageRange(
                geom_pool,
                &exact_stage,
                runPrepareVisibleExactNormalsStage,
                visible_orig_elem_indices.len,
                visible_chunk_size,
            );
        },
        .averaged => {
            const nodes_num = getConnectNodesNum(connect);
            const elem_chunks_num = getChunksNum(connect.getElemsNum(), elem_chunk_size);
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
            runStageRange(
                geom_pool,
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
            runStageRange(
                geom_pool,
                &write_stage,
                runWriteVisibleAveragedNormalsStage,
                visible_orig_elem_indices.len,
                visible_chunk_size,
            );
        },
    }

    return prep_normals;
}

fn getConnectNodesNum(connect: *const Connect) usize {
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
) !MappedNDArray(f64) {
    const prep_normals = try NDArray(f64).initFlat(
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
    coords_nodes: *const Coords,
    connect: *const Connect,
    visible_orig_elem_indices: []const usize,
    prep_normals: *NDArray(f64),
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
    coords_nodes: *const Coords,
    connect: *const Connect,
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
    connect: *const Connect,
    visible_orig_elem_indices: []const usize,
    node_normals: []const f64,
    prep_normals: *NDArray(f64),
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
    camera: *const Camera,
    mesh_static: *const MeshStaticPrepared,
    frame_idx: usize,
    scaling_params: ?ScalingParams,
    geom_pool: ?*geomthread.GeometryWorkerPool,
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
        camera: *const Camera,
        mesh_static: *const MeshStaticPrepared,
        frame_idx: usize,
        scaling_params: ?ScalingParams,
        geom_pool: ?*geomthread.GeometryWorkerPool,
    ) !FrameMeshPipeline {
        const workers_num = getWorkerCount(geom_pool);
        const nodes_num = mesh_static.coords_orig.mat.rows_num;
        const elems_num = mesh_static.connect.getElemsNum();
        const node_chunk_size = getChunkSize(nodes_num, workers_num);
        const elem_chunk_size = getChunkSize(elems_num, workers_num);

        return .{
            .allocator = allocator,
            .camera = camera,
            .mesh_static = mesh_static,
            .frame_idx = frame_idx,
            .scaling_params = scaling_params,
            .geom_pool = geom_pool,
            .workers_num = workers_num,
            .nodes_num = nodes_num,
            .elems_num = elems_num,
            .node_chunk_size = node_chunk_size,
            .elem_chunk_size = elem_chunk_size,
            .elem_chunks_num = getChunksNum(elems_num, elem_chunk_size),
            .visible_chunk_size = 1,
            .mesh_frame = .{
                .frame_workspace = try initFrameMeshWorkspace(
                    allocator,
                    mesh_static,
                ),
                .visible_counts_by_chunk = &.{},
                .visible_offsets_by_chunk = &.{},
                .visible_elems_num = 0,
            },
        };
    }

    fn run(self: *FrameMeshPipeline) !FrameMeshPrepared {
        self.prepareCoords();
        self.transformCoords();
        try self.cullVisible();

        var mesh_prep = try self.compactVisibleMesh();
        try self.prepareRasterHulls(&mesh_prep.coords);
        try self.prepareShader(&mesh_prep);
        self.assignVisibleElemIndices();
        return self.finish(mesh_prep);
    }

    fn prepareCoords(self: *FrameMeshPipeline) void {
        var prepare_stage = PrepareFrameCoordsStage{
            .frame_workspace = &self.mesh_frame.frame_workspace,
            .mesh_static = self.mesh_static,
            .frame_idx = self.frame_idx,
        };
        runStageRange(
            self.geom_pool,
            &prepare_stage,
            runPrepareFrameCoordsStage,
            self.nodes_num,
            self.node_chunk_size,
        );
    }

    fn transformCoords(self: *FrameMeshPipeline) void {
        var transform_stage = TransformFrameCoordsStage{
            .camera = self.camera,
            .mesh_type = self.mesh_static.mesh_type,
            .frame_workspace = &self.mesh_frame.frame_workspace,
        };
        runStageRange(
            self.geom_pool,
            &transform_stage,
            runTransformFrameCoordsStage,
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
        runStageRange(
            self.geom_pool,
            &cull_count_stage,
            runCullVisibleCountStage,
            self.elems_num,
            self.elem_chunk_size,
        );
        prefixVisibleCounts(&self.mesh_frame);

        self.mesh_frame.frame_workspace.visible_orig_elem_indices =
            try self.allocator.alloc(usize, self.mesh_frame.visible_elems_num);
        self.mesh_frame.frame_workspace.elem_bboxes = try self.allocator.alloc(
            ElemBBox,
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
        runStageRange(
            self.geom_pool,
            &cull_fill_stage,
            runCullVisibleFillStage,
            self.elems_num,
            self.elem_chunk_size,
        );

        self.visible_chunk_size = getChunkSize(
            self.mesh_frame.visible_elems_num,
            self.workers_num,
        );
    }

    fn compactVisibleMesh(self: *FrameMeshPipeline) !MeshPrepared {
        var elem_coords = try NDArray(f64).initFlat(
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
        runStageRange(
            self.geom_pool,
            &compact_coords_stage,
            runCompactVisibleCoordsStage,
            self.mesh_frame.visible_elems_num,
            self.visible_chunk_size,
        );

        return .{
            .mesh_type = self.mesh_static.mesh_type,
            .coords = elem_coords,
            .connect = self.mesh_static.connect,
            .shader = undefined,
        };
    }

    fn prepareRasterHulls(
        self: *FrameMeshPipeline,
        elem_coords: *const NDArray(f64),
    ) !void {
        self.mesh_frame.frame_workspace.raster_hull = switch (self.mesh_static.mesh_type) {
            .tri3 => null,
            .quad4ibi, .quad4newton => try NDArray(f64).initFlat(
                self.allocator,
                &[_]usize{ self.mesh_frame.visible_elems_num, 2, 4 },
            ),
            .tri6 => try NDArray(f64).initFlat(
                self.allocator,
                &[_]usize{ self.mesh_frame.visible_elems_num, 2, 6 },
            ),
            .quad8, .quad9 => try NDArray(f64).initFlat(
                self.allocator,
                &[_]usize{ self.mesh_frame.visible_elems_num, 2, 8 },
            ),
        };

        if (self.mesh_frame.frame_workspace.raster_hull) |*raster_hull| {
            var hulls_stage = PrepareVisibleHullsStage{
                .camera = self.camera,
                .mesh_type = self.mesh_static.mesh_type,
                .elem_coords = elem_coords,
                .raster_hull = raster_hull,
            };
            runStageRange(
                self.geom_pool,
                &hulls_stage,
                runPrepareVisibleHullsStage,
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
        nodal_static: NodalStaticPrepared,
    ) !ShaderPrepared {
        var elem_field = try NDArray(f64).initFlat(
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
        runStageRange(
            self.geom_pool,
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
        tex_static: TexStaticPrepared(channels),
    ) !ShaderPrepared {
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
        var elem_uvs = try NDArray(f64).initFlat(
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
        runStageRange(
            self.geom_pool,
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
    ) !?MappedNDArray(f64) {
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
            self.geom_pool,
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
    ) FrameMeshPrepared {
        return .{
            .mesh = mesh_prep,
            .elem_bboxes = self.mesh_frame.frame_workspace.elem_bboxes,
            .elems_in_image = self.mesh_frame.frame_workspace.elems_in_image,
            .total_elems_num = self.mesh_static.connect.getElemsNum(),
            .raster_hull = self.mesh_frame.frame_workspace.raster_hull,
        };
    }
};

fn prepareVisibleFrameMesh(
    allocator: std.mem.Allocator,
    camera: *const Camera,
    mesh_static: *const MeshStaticPrepared,
    frame_idx: usize,
    scaling_params: ?ScalingParams,
    geom_pool: ?*geomthread.GeometryWorkerPool,
) !FrameMeshPrepared {
    var pipeline = try FrameMeshPipeline.init(
        allocator,
        camera,
        mesh_static,
        frame_idx,
        scaling_params,
        geom_pool,
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
pub fn prepareFrameMeshes(
    arena_alloc: std.mem.Allocator,
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    camera: *const Camera,
    frame_idx: usize,
    mesh_static_prepared: []const MeshStaticPrepared,
    nodal_global_scaling: []const ?imageops.ScalingParams,
    geom_threads: u16,
    frame_meshes: []FrameMeshPrepared,
    prep_meshes: []MeshPrepared,
    elem_bboxes_by_mesh: [][]ElemBBox,
    elems_in_image_by_mesh: []usize,
    raster_hulls: []?NDArray(f64),
) !FrameGeometryResult {
    var geom_pool: ?geomthread.GeometryWorkerPool = null;
    if (geom_threads > 1) {
        var pool: geomthread.GeometryWorkerPool = undefined;
        try pool.init(outer_alloc, io, geom_threads);
        geom_pool = pool;
    }
    defer if (geom_pool) |*pool| pool.deinit(outer_alloc);

    var res = FrameGeometryResult{ .total_elems_num = 0, .total_elems_in_image = 0 };

    for (mesh_static_prepared, 0..) |*mesh_static, ii| {
        var nodal_frame_scaling: ?imageops.ScalingParams = null;
        switch (mesh_static.shader) {
            .nodal => |s| {
                if (s.scale_over == .over_frames) {
                    nodal_frame_scaling = nodal_global_scaling[ii];
                } else {
                    nodal_frame_scaling = imageops.getScalingParamsNDArray(
                        &s.field.array,
                        frame_idx,
                        s.scaling,
                    );
                }
            },
            else => {},
        }

        frame_meshes[ii] = try prepareVisibleFrameMesh(
            arena_alloc,
            camera,
            mesh_static,
            frame_idx,
            nodal_frame_scaling,
            if (geom_pool) |*p| p else null,
        );
        prep_meshes[ii] = frame_meshes[ii].mesh;
        elem_bboxes_by_mesh[ii] = frame_meshes[ii].elem_bboxes;
        elems_in_image_by_mesh[ii] = frame_meshes[ii].elems_in_image;
        raster_hulls[ii] = frame_meshes[ii].raster_hull;
        res.total_elems_num += frame_meshes[ii].total_elems_num;
        res.total_elems_in_image += frame_meshes[ii].elems_in_image;
    }

    return res;
}
