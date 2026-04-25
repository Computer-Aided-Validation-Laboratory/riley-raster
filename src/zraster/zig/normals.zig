// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const tol = buildconfig.config.tolerance;
const ndarray = @import("ndarray.zig");
const meshio = @import("meshio.zig");
const shapefun = @import("shapefun.zig");
const shaderops = @import("shaderops.zig");
const pce = @import("parachunkexec.zig");
const geomkerns = @import("geometrykernels.zig");
const MeshType = geomkerns.MeshType;
const rops = @import("rasterops.zig");

//==========================================================================================
// Core Normal Calculation Primitives
//==========================================================================================

pub fn calcElementNodeNormal(
    comptime N: usize,
    nodal_derivs: shapefun.NodalDerivs,
    sx: []const f64,
    sy: []const f64,
    sz: []const f64,
    node_idx: usize,
) [3]f64 {
    var dx_dxi: f64 = 0;
    var dx_deta: f64 = 0;
    var dy_dxi: f64 = 0;
    var dy_deta: f64 = 0;
    var dz_dxi: f64 = 0;
    var dz_deta: f64 = 0;

    for (0..N) |nn| {
        const du = nodal_derivs.dNu[node_idx][nn];
        const dv = nodal_derivs.dNv[node_idx][nn];
        dx_dxi += du * sx[nn];
        dx_deta += dv * sx[nn];
        dy_dxi += du * sy[nn];
        dy_deta += dv * sy[nn];
        dz_dxi += du * sz[nn];
        dz_deta += dv * sz[nn];
    }

    return .{
        dy_dxi * dz_deta - dz_dxi * dy_deta,
        dz_dxi * dx_deta - dx_dxi * dz_deta,
        dx_dxi * dy_deta - dy_dxi * dx_deta,
    };
}

pub fn normalizeNormal(normal_vec: *[3]f64) void {
    const nx = normal_vec[0];
    const ny = normal_vec[1];
    const nz = normal_vec[2];
    const magnitude = @sqrt(nx * nx + ny * ny + nz * nz);

    if (magnitude > tol.normals.normalise_magnitude) {
        normal_vec[0] = nx / magnitude;
        normal_vec[1] = ny / magnitude;
        normal_vec[2] = nz / magnitude;
    }
}

//==========================================================================================
// Serial Normal Calculation Implementations
//==========================================================================================

pub fn calculateVisibleExactNormals(
    coords_nodes: *const meshio.Coords,
    connect: *const meshio.Connect,
    visible_orig_elem_indices: []const usize,
    prep_normals: *ndarray.NDArray(f64),
    comptime N: usize,
) void {
    const nodal_derivs = comptime shapefun.getNodalDerivs(N);

    for (visible_orig_elem_indices, 0..) |orig_ee, pp| {
        const coords_elem = rops.gatherElemNodeCoords(N, coords_nodes, connect, orig_ee);
        for (0..N) |nn| {
            var normal_vec = calcElementNodeNormal(
                N,
                nodal_derivs,
                &coords_elem.x,
                &coords_elem.y,
                &coords_elem.z,
                nn,
            );
            normalizeNormal(&normal_vec);
            prep_normals.set(&[_]usize{ pp, 0, nn }, normal_vec[0]);
            prep_normals.set(&[_]usize{ pp, 1, nn }, normal_vec[1]);
            prep_normals.set(&[_]usize{ pp, 2, nn }, normal_vec[2]);
        }
    }
}

pub fn calculateVisibleAveragedNormals(
    allocator: std.mem.Allocator,
    coords_nodes: *const meshio.Coords,
    connect: *const meshio.Connect,
    visible_orig_elem_indices: []const usize,
    prep_normals: *ndarray.NDArray(f64),
    comptime N: usize,
) !void {
    const nodal_derivs = comptime shapefun.getNodalDerivs(N);
    var max_node_idx: usize = 0;
    for (connect.table_mem) |node_idx| {
        max_node_idx = @max(max_node_idx, node_idx);
    }

    const nodes_num = max_node_idx + 1;
    const node_normals = try allocator.alloc(f64, nodes_num * 3);
    defer allocator.free(node_normals);
    @memset(node_normals, 0.0);

    for (0..connect.getElemsNum()) |ee| {
        const coords_elem = rops.gatherElemNodeCoords(N, coords_nodes, connect, ee);
        const coord_inds = connect.getElem(ee);

        for (0..N) |nn| {
            const normal_vec = calcElementNodeNormal(
                N,
                nodal_derivs,
                &coords_elem.x,
                &coords_elem.y,
                &coords_elem.z,
                nn,
            );
            const node_idx = coord_inds[nn];
            node_normals[node_idx * 3 + 0] += normal_vec[0];
            node_normals[node_idx * 3 + 1] += normal_vec[1];
            node_normals[node_idx * 3 + 2] += normal_vec[2];
        }
    }

    for (visible_orig_elem_indices, 0..) |orig_ee, pp| {
        const coord_inds = connect.getElem(orig_ee);
        for (0..N) |nn| {
            const node_idx = coord_inds[nn];
            var normal_vec = [3]f64{
                node_normals[node_idx * 3 + 0],
                node_normals[node_idx * 3 + 1],
                node_normals[node_idx * 3 + 2],
            };
            normalizeNormal(&normal_vec);
            prep_normals.set(&[_]usize{ pp, 0, nn }, normal_vec[0]);
            prep_normals.set(&[_]usize{ pp, 1, nn }, normal_vec[1]);
            prep_normals.set(&[_]usize{ pp, 2, nn }, normal_vec[2]);
        }
    }
}

pub fn prepareVisibleNormals(
    comptime MT: MeshType,
    allocator: std.mem.Allocator,
    coords_nodes: *const meshio.Coords,
    connect: *const meshio.Connect,
    visible_orig_elem_indices: []const usize,
    normal_type: shaderops.NormalType,
) !ndarray.MappedNDArray(f64) {
    const N = comptime MT.getNodesNum();
    var prep_normals = try initIdentityMappedNormals(
        N,
        allocator,
        visible_orig_elem_indices.len,
    );
    switch (normal_type) {
        .none => unreachable,
        .exact => calculateVisibleExactNormals(
            coords_nodes,
            connect,
            visible_orig_elem_indices,
            &prep_normals.array,
            N,
        ),
        .averaged => try calculateVisibleAveragedNormals(
            allocator,
            coords_nodes,
            connect,
            visible_orig_elem_indices,
            &prep_normals.array,
            N,
        ),
    }
    return prep_normals;
}

//==========================================================================================
// Threaded Normal Calculation Stages
//==========================================================================================

pub fn prepareVisibleExactNormalsRange(
    comptime MT: MeshType,
    coords_nodes: *const meshio.Coords,
    connect: *const meshio.Connect,
    visible_orig_elem_indices: []const usize,
    prep_normals: *ndarray.NDArray(f64),
    visible_start: usize,
    visible_end: usize,
) void {
    const N = comptime MT.getNodesNum();
    const nodal_derivs = comptime shapefun.getNodalDerivs(N);

    for (visible_start..visible_end) |pp| {
        const orig_ee = visible_orig_elem_indices[pp];
        const coords_elem = rops.gatherElemNodeCoords(N, coords_nodes, connect, orig_ee);
        for (0..N) |nn| {
            var normal_vec = calcElementNodeNormal(
                N,
                nodal_derivs,
                &coords_elem.x,
                &coords_elem.y,
                &coords_elem.z,
                nn,
            );
            normalizeNormal(&normal_vec);
            prep_normals.set(&[_]usize{ pp, 0, nn }, normal_vec[0]);
            prep_normals.set(&[_]usize{ pp, 1, nn }, normal_vec[1]);
            prep_normals.set(&[_]usize{ pp, 2, nn }, normal_vec[2]);
        }
    }
}

pub fn accumulateAveragedNodeNormalsRange(
    comptime MT: MeshType,
    coords_nodes: *const meshio.Coords,
    connect: *const meshio.Connect,
    node_normals: []f64,
    elem_start: usize,
    elem_end: usize,
) void {
    const N = comptime MT.getNodesNum();
    const nodal_derivs = comptime shapefun.getNodalDerivs(N);

    for (elem_start..elem_end) |ee| {
        const coords_elem = rops.gatherElemNodeCoords(N, coords_nodes, connect, ee);
        const coord_inds = connect.getElem(ee);

        for (0..N) |nn| {
            const normal_vec = calcElementNodeNormal(
                N,
                nodal_derivs,
                &coords_elem.x,
                &coords_elem.y,
                &coords_elem.z,
                nn,
            );
            const node_idx = coord_inds[nn];
            node_normals[node_idx * 3 + 0] += normal_vec[0];
            node_normals[node_idx * 3 + 1] += normal_vec[1];
            node_normals[node_idx * 3 + 2] += normal_vec[2];
        }
    }
}

pub fn writeVisibleAveragedNormalsRange(
    comptime MT: MeshType,
    connect: *const meshio.Connect,
    visible_orig_elem_indices: []const usize,
    node_normals: []const f64,
    prep_normals: *ndarray.NDArray(f64),
    visible_start: usize,
    visible_end: usize,
) void {
    const N = comptime MT.getNodesNum();
    for (visible_start..visible_end) |pp| {
        const coord_inds = connect.getElem(visible_orig_elem_indices[pp]);
        for (0..N) |nn| {
            const node_idx = coord_inds[nn];
            var normal_vec = [3]f64{
                node_normals[node_idx * 3 + 0],
                node_normals[node_idx * 3 + 1],
                node_normals[node_idx * 3 + 2],
            };
            normalizeNormal(&normal_vec);
            prep_normals.set(&[_]usize{ pp, 0, nn }, normal_vec[0]);
            prep_normals.set(&[_]usize{ pp, 1, nn }, normal_vec[1]);
            prep_normals.set(&[_]usize{ pp, 2, nn }, normal_vec[2]);
        }
    }
}

pub fn NormalStages(comptime MT: MeshType) type {
    return struct {
        const ExactNormalsStage = struct {
            coords_nodes: *const meshio.Coords,
            connect: *const meshio.Connect,
            visible_orig_elem_indices: []const usize,
            prep_normals: *ndarray.NDArray(f64),
        };

        pub fn runPrepareVisibleExactNormals(
            ctx_ptr: *anyopaque,
            chunk_idx: usize,
            range_start: usize,
            range_end: usize,
        ) void {
            _ = chunk_idx;
            const stage: *ExactNormalsStage = @ptrCast(@alignCast(ctx_ptr));
            prepareVisibleExactNormalsRange(
                MT,
                stage.coords_nodes,
                stage.connect,
                stage.visible_orig_elem_indices,
                stage.prep_normals,
                range_start,
                range_end,
            );
        }

        const AccumulateAveragedNormalsStage = struct {
            coords_nodes: *const meshio.Coords,
            connect: *const meshio.Connect,
            chunk_node_normals: []f64,
            node_normals_stride: usize,
        };

        pub fn runAccumulateAveragedNormals(
            ctx_ptr: *anyopaque,
            chunk_idx: usize,
            range_start: usize,
            range_end: usize,
        ) void {
            const stage: *AccumulateAveragedNormalsStage = @ptrCast(@alignCast(ctx_ptr));
            const accum_start = chunk_idx * stage.node_normals_stride;
            const accum_end = accum_start + stage.node_normals_stride;
            accumulateAveragedNodeNormalsRange(
                MT,
                stage.coords_nodes,
                stage.connect,
                stage.chunk_node_normals[accum_start..accum_end],
                range_start,
                range_end,
            );
        }

        const WriteVisibleAveragedNormalsStage = struct {
            connect: *const meshio.Connect,
            visible_orig_elem_indices: []const usize,
            node_normals: []const f64,
            prep_normals: *ndarray.NDArray(f64),
        };

        pub fn runWriteVisibleAveragedNormals(
            ctx_ptr: *anyopaque,
            chunk_idx: usize,
            range_start: usize,
            range_end: usize,
        ) void {
            _ = chunk_idx;
            const stage: *WriteVisibleAveragedNormalsStage = @ptrCast(@alignCast(ctx_ptr));
            writeVisibleAveragedNormalsRange(
                MT,
                stage.connect,
                stage.visible_orig_elem_indices,
                stage.node_normals,
                stage.prep_normals,
                range_start,
                range_end,
            );
        }
    };
}

//==========================================================================================
// Pipeline Integration Helpers
//==========================================================================================

pub fn prepareVisibleNormalsThreaded(
    comptime MT: MeshType,
    allocator: std.mem.Allocator,
    coords_nodes: *const meshio.Coords,
    connect: *const meshio.Connect,
    visible_orig_elem_indices: []const usize,
    normal_type: shaderops.NormalType,
    chunk_exec: ?*pce.ParaChunkExecutor,
    elem_chunk_size: usize,
    visible_chunk_size: usize,
) !ndarray.MappedNDArray(f64) {
    return try prepareVisibleNormalsThreadedN(
        comptime MT.getNodesNum(),
        MT,
        allocator,
        coords_nodes,
        connect,
        visible_orig_elem_indices,
        normal_type,
        chunk_exec,
        elem_chunk_size,
        visible_chunk_size,
    );
}

pub fn prepareVisibleNormalsThreadedN(
    comptime N: usize,
    comptime MT: MeshType,
    allocator: std.mem.Allocator,
    coords_nodes: *const meshio.Coords,
    connect: *const meshio.Connect,
    visible_orig_elem_indices: []const usize,
    normal_type: shaderops.NormalType,
    chunk_exec: ?*pce.ParaChunkExecutor,
    elem_chunk_size: usize,
    visible_chunk_size: usize,
) !ndarray.MappedNDArray(f64) {
    var prep_normals = try initIdentityMappedNormals(
        N,
        allocator,
        visible_orig_elem_indices.len,
    );

    const Stages = NormalStages(MT);

    switch (normal_type) {
        .none => unreachable,
        .exact => {
            var exact_stage = Stages.ExactNormalsStage{
                .coords_nodes = coords_nodes,
                .connect = connect,
                .visible_orig_elem_indices = visible_orig_elem_indices,
                .prep_normals = &prep_normals.array,
            };
            pce.runStaticRange(
                chunk_exec,
                &exact_stage,
                Stages.runPrepareVisibleExactNormals,
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

            var accum_stage = Stages.AccumulateAveragedNormalsStage{
                .coords_nodes = coords_nodes,
                .connect = connect,
                .chunk_node_normals = chunk_node_normals,
                .node_normals_stride = node_normals_stride,
            };
            pce.runStaticRange(
                chunk_exec,
                &accum_stage,
                Stages.runAccumulateAveragedNormals,
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

            var write_stage = Stages.WriteVisibleAveragedNormalsStage{
                .connect = connect,
                .visible_orig_elem_indices = visible_orig_elem_indices,
                .node_normals = node_normals,
                .prep_normals = &prep_normals.array,
            };
            pce.runStaticRange(
                chunk_exec,
                &write_stage,
                Stages.runWriteVisibleAveragedNormals,
                visible_orig_elem_indices.len,
                visible_chunk_size,
            );
        },
    }

    return prep_normals;
}

pub fn getConnectNodesNum(connect: *const meshio.Connect) usize {
    var max_node_idx: usize = 0;
    for (connect.table_mem) |node_idx| {
        max_node_idx = @max(max_node_idx, node_idx);
    }
    return max_node_idx + 1;
}

pub fn initIdentityMappedNormals(
    comptime N: usize,
    allocator: std.mem.Allocator,
    prep_count: usize,
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
