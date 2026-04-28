// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const cam = @import("../zraster/zig/camera.zig");
const csvio = @import("../zraster/zig/csvio.zig");
const gk = @import("../zraster/zig/geometrykernels.zig");
const iio = @import("../zraster/zig/imageio.zig");
const matrix = @import("../zraster/zig/matstack.zig");
const ndarray = @import("../zraster/zig/ndarray.zig");
const newton = @import("../zraster/zig/newton.zig");
const rops = @import("../zraster/zig/rasterops.zig");
const shapefun = @import("../zraster/zig/shapefun.zig");
const vecstack = @import("../zraster/zig/vecstack.zig");

pub const Vec3 = struct {
    x: f64,
    y: f64,
    z: f64,
};

pub const SampleKind = enum {
    structured,
    random,
    boundary,
    corner,
};

pub const invalid_grid_idx = std.math.maxInt(usize);

pub const SamplePoint = struct {
    sample_kind: SampleKind,
    xi_true: f64,
    eta_true: f64,
    row_idx: usize = invalid_grid_idx,
    col_idx: usize = invalid_grid_idx,
};

pub const SampleRecord = struct {
    sample_kind: SampleKind,
    xi_true: f64,
    eta_true: f64,
    xi_rec: f64,
    eta_rec: f64,
    err_xi: f64,
    err_eta: f64,
    err_param: f64,
    ideal_target_x: f64,
    ideal_target_y: f64,
    observed_target_x: f64,
    observed_target_y: f64,
    observed_reproj_x: f64,
    observed_reproj_y: f64,
    reproj_err: f64,
    iters: u8,
    converged: bool,
    in_domain: bool,
    row_idx: usize = invalid_grid_idx,
    col_idx: usize = invalid_grid_idx,
};

pub const ScalarStats = struct {
    min: f64,
    q1: f64,
    median: f64,
    q3: f64,
    max: f64,
    mean: f64,
    rms: f64,
};

pub const CaseSummary = struct {
    mesh_type: gk.MeshType,
    geom_case_name: []const u8,
    camera_case_name: []const u8,
    samples_num: usize,
    nonconverged_num: usize,
    out_of_domain_num: usize,
    reproj_stats: ScalarStats,
    param_stats: ScalarStats,
    iter_stats: ScalarStats,
};

pub fn ElementNodes(comptime N: usize) type {
    return struct {
        x: [N]f64,
        y: [N]f64,
        z: [N]f64,
    };
}

pub fn forwardMapWorld(
    comptime N: usize,
    xi: f64,
    eta: f64,
    node_values: *[N]f64,
    deriv_xi: *[N]f64,
    deriv_eta: *[N]f64,
    node_x: []const f64,
    node_y: []const f64,
    node_z: []const f64,
) Vec3 {
    shapefun.shapeFunctions(
        N,
        xi,
        eta,
        node_values,
        deriv_xi,
        deriv_eta,
    );

    var x_world: f64 = 0.0;
    var y_world: f64 = 0.0;
    var z_world: f64 = 0.0;

    for (0..N) |nn| {
        const node_weight = node_values[nn];
        x_world += node_weight * node_x[nn];
        y_world += node_weight * node_y[nn];
        z_world += node_weight * node_z[nn];
    }

    return .{
        .x = x_world,
        .y = y_world,
        .z = z_world,
    };
}

fn forwardMapQuad4Ibi(
    xi: f64,
    eta: f64,
    node_x: []const f64,
    node_y: []const f64,
    node_z: []const f64,
) Vec3 {
    const weight_0 = (1.0 - xi) * (1.0 - eta);
    const weight_1 = xi * (1.0 - eta);
    const weight_2 = xi * eta;
    const weight_3 = (1.0 - xi) * eta;

    return .{
        .x = weight_0 * node_x[0] + weight_1 * node_x[1] +
            weight_2 * node_x[2] + weight_3 * node_x[3],
        .y = weight_0 * node_y[0] + weight_1 * node_y[1] +
            weight_2 * node_y[2] + weight_3 * node_y[3],
        .z = weight_0 * node_z[0] + weight_1 * node_z[1] +
            weight_2 * node_z[2] + weight_3 * node_z[3],
    };
}

pub fn forwardMapWorldForMeshType(
    comptime mesh_type: gk.MeshType,
    xi: f64,
    eta: f64,
    node_x: []const f64,
    node_y: []const f64,
    node_z: []const f64,
) Vec3 {
    const N = comptime mesh_type.getNodesNum();

    if (mesh_type == .quad4ibi) {
        return forwardMapQuad4Ibi(
            xi,
            eta,
            node_x,
            node_y,
            node_z,
        );
    }

    var node_values: [N]f64 = undefined;
    var deriv_xi: [N]f64 = undefined;
    var deriv_eta: [N]f64 = undefined;
    return forwardMapWorld(
        N,
        xi,
        eta,
        &node_values,
        &deriv_xi,
        &deriv_eta,
        node_x,
        node_y,
        node_z,
    );
}

fn worldToCamera(
    camera: *const cam.CameraPrepared,
    world_point: Vec3,
) vecstack.Vec3f {
    return matrix.Mat44Ops.mulVec3(
        f64,
        camera.world_to_cam_mat,
        .{ .slice = .{ world_point.x, world_point.y, world_point.z } },
    );
}

pub fn worldToIdealRaster(
    camera: *const cam.CameraPrepared,
    world_point: Vec3,
) [2]f64 {
    const coord_cam = worldToCamera(camera, world_point);
    const focal_px = camera.calcFocalPx();
    const offsets = camera.calcRasterOffsets();
    const inv_neg_z = 1.0 / (-coord_cam.slice[2]);

    return .{
        offsets.x_off + coord_cam.slice[0] * inv_neg_z * focal_px.fx,
        offsets.y_off - coord_cam.slice[1] * inv_neg_z * focal_px.fy,
    };
}

pub fn idealToObservedRaster(
    camera: *const cam.CameraPrepared,
    ideal_xy: [2]f64,
) ![2]f64 {
    const focal_px = camera.calcFocalPx();
    const offsets = camera.calcRasterOffsets();
    const x_norm = (ideal_xy[0] - offsets.x_off) / focal_px.fx;
    const y_norm = (ideal_xy[1] - offsets.y_off) / focal_px.fy;

    return switch (camera.distortion) {
        .none => ideal_xy,
        .brown_conrady => |distortion| blk: {
            const distorted = distortion.forward(x_norm, y_norm);
            break :blk .{
                distorted[0] * focal_px.fx + offsets.x_off,
                distorted[1] * focal_px.fy + offsets.y_off,
            };
        },
        .brown_conrady_ext => |distortion| blk: {
            const distorted = distortion.forward(x_norm, y_norm);
            break :blk .{
                distorted[0] * focal_px.fx + offsets.x_off,
                distorted[1] * focal_px.fy + offsets.y_off,
            };
        },
    };
}

pub fn observedToIdealRaster(
    camera: *const cam.CameraPrepared,
    observed_xy: [2]f64,
) ![2]f64 {
    const focal_px = camera.calcFocalPx();
    const offsets = camera.calcRasterOffsets();
    const x_dist = (observed_xy[0] - offsets.x_off) / focal_px.fx;
    const y_dist = (observed_xy[1] - offsets.y_off) / focal_px.fy;

    return switch (camera.distortion) {
        .none => observed_xy,
        .brown_conrady => |distortion| blk: {
            const solved = try distortion.inverse(x_dist, y_dist);
            break :blk .{
                solved.x * focal_px.fx + offsets.x_off,
                solved.y * focal_px.fy + offsets.y_off,
            };
        },
        .brown_conrady_ext => |distortion| blk: {
            const solved = try distortion.inverse(x_dist, y_dist);
            break :blk .{
                solved.x * focal_px.fx + offsets.x_off,
                solved.y * focal_px.fy + offsets.y_off,
            };
        },
    };
}

pub fn worldNodesToSolverCoords(
    comptime mesh_type: gk.MeshType,
    camera: *const cam.CameraPrepared,
    node_x: []const f64,
    node_y: []const f64,
    node_z: []const f64,
) ElementNodes(mesh_type.getNodesNum()) {
    const N = comptime mesh_type.getNodesNum();
    const focal_px = camera.calcFocalPx();
    const offsets = camera.calcRasterOffsets();
    var solver_nodes: ElementNodes(N) = undefined;

    for (0..N) |nn| {
        const world_point = Vec3{
            .x = node_x[nn],
            .y = node_y[nn],
            .z = node_z[nn],
        };
        const coord_cam = worldToCamera(camera, world_point);
        const inv_neg_z = 1.0 / (-coord_cam.slice[2]);

        if (mesh_type == .tri3) {
            solver_nodes.x[nn] = offsets.x_off +
                coord_cam.slice[0] * inv_neg_z * focal_px.fx;
            solver_nodes.y[nn] = offsets.y_off -
                coord_cam.slice[1] * inv_neg_z * focal_px.fy;
            solver_nodes.z[nn] = -coord_cam.slice[2];
        } else {
            solver_nodes.x[nn] = coord_cam.slice[0] * focal_px.fx;
            solver_nodes.y[nn] = -coord_cam.slice[1] * focal_px.fy;
            solver_nodes.z[nn] = -coord_cam.slice[2];
        }
    }

    return solver_nodes;
}

pub fn toVec3Slices(
    comptime N: usize,
    nodes: *const ElementNodes(N),
) rops.Vec3Slices(f64) {
    return .{
        .x = @constCast(nodes.x[0..]),
        .y = @constCast(nodes.y[0..]),
        .z = @constCast(nodes.z[0..]),
    };
}

pub const SolveResult = struct {
    converged: bool,
    xi_rec: f64,
    eta_rec: f64,
    iters: u8,
};

pub fn solveParentFromIdealRaster(
    comptime mesh_type: gk.MeshType,
    camera: *const cam.CameraPrepared,
    solver_nodes: *const ElementNodes(mesh_type.getNodesNum()),
    ideal_x: f64,
    ideal_y: f64,
) SolveResult {
    const offsets = camera.calcRasterOffsets();
    const nodes = toVec3Slices(mesh_type.getNodesNum(), solver_nodes);

    return switch (mesh_type) {
        .tri3 => blk: {
            const GK = gk.Tri3Kernel();
            const inv_area = GK.getInvElemArea(nodes);
            const result = GK.solveWeightsHyperb(
                nodes,
                ideal_x,
                ideal_y,
                inv_area,
            );
            if (result.weights) |weights| {
                const inv_z = GK.calcInvZ(nodes, weights);
                const xi_rec = weights[1] * (1.0 / nodes.z[1]) / inv_z;
                const eta_rec = weights[2] * (1.0 / nodes.z[2]) / inv_z;
                break :blk .{
                    .converged = true,
                    .xi_rec = xi_rec,
                    .eta_rec = eta_rec,
                    .iters = result.iters,
                };
            }
            break :blk .{
                .converged = false,
                .xi_rec = 0.0,
                .eta_rec = 0.0,
                .iters = result.iters,
            };
        },
        .tri6 => blk: {
            const GK = gk.Tri6Kernel();
            const seed = GK.initSeed(null);
            const result = GK.solveWeightsNewton(
                nodes,
                ideal_x,
                ideal_y,
                offsets.x_off,
                offsets.y_off,
                seed.xi,
                seed.eta,
            );
            break :blk .{
                .converged = result.weights != null,
                .xi_rec = result.xi_out,
                .eta_rec = result.eta_out,
                .iters = result.iters,
            };
        },
        .quad4ibi => blk: {
            const GK = gk.Quad4IBIKernel();
            const params = GK.getBilinearParams(nodes);
            const result = GK.solveWeightsInvBi(
                ideal_x,
                ideal_y,
                offsets.x_off,
                offsets.y_off,
                params,
            );
            break :blk .{
                .converged = result.weights != null,
                .xi_rec = result.xi_out,
                .eta_rec = result.eta_out,
                .iters = result.iters,
            };
        },
        .quad4newton => blk: {
            const GK = gk.Quad4NewtonKernel();
            const seed = GK.initSeed(null);
            const result = GK.solveWeightsNewton(
                nodes,
                ideal_x,
                ideal_y,
                offsets.x_off,
                offsets.y_off,
                seed.xi,
                seed.eta,
            );
            break :blk .{
                .converged = result.weights != null,
                .xi_rec = result.xi_out,
                .eta_rec = result.eta_out,
                .iters = result.iters,
            };
        },
        .quad8 => blk: {
            const GK = gk.Quad89Kernel(8);
            const seed = GK.initSeed(null);
            const result = GK.solveWeightsNewton(
                nodes,
                ideal_x,
                ideal_y,
                offsets.x_off,
                offsets.y_off,
                seed.xi,
                seed.eta,
            );
            break :blk .{
                .converged = result.weights != null,
                .xi_rec = result.xi_out,
                .eta_rec = result.eta_out,
                .iters = result.iters,
            };
        },
        .quad9 => blk: {
            const GK = gk.Quad89Kernel(9);
            const seed = GK.initSeed(null);
            const result = GK.solveWeightsNewton(
                nodes,
                ideal_x,
                ideal_y,
                offsets.x_off,
                offsets.y_off,
                seed.xi,
                seed.eta,
            );
            break :blk .{
                .converged = result.weights != null,
                .xi_rec = result.xi_out,
                .eta_rec = result.eta_out,
                .iters = result.iters,
            };
        },
    };
}

pub fn isInParametricDomain(
    comptime mesh_type: gk.MeshType,
    xi: f64,
    eta: f64,
) bool {
    const eps = 1.0e-8;
    return switch (mesh_type) {
        .tri3, .tri6 => xi >= -eps and eta >= -eps and xi + eta <= 1.0 + eps,
        .quad4ibi => xi >= -eps and xi <= 1.0 + eps and eta >= -eps and
            eta <= 1.0 + eps,
        .quad4newton, .quad8, .quad9 => @abs(xi) <= 1.0 + eps and
            @abs(eta) <= 1.0 + eps,
    };
}

pub fn structuredGridDims(comptime mesh_type: gk.MeshType) struct {
    rows_num: usize,
    cols_num: usize,
} {
    _ = mesh_type;
    return .{ .rows_num = 0, .cols_num = 0 };
}

pub fn appendStructuredSamples(
    comptime mesh_type: gk.MeshType,
    allocator: std.mem.Allocator,
    list: *std.ArrayList(SamplePoint),
    grid_num: usize,
) !struct { rows_num: usize, cols_num: usize } {
    if (mesh_type == .tri3 or mesh_type == .tri6) {
        for (0..grid_num) |rr| {
            const eta = @as(f64, @floatFromInt(rr)) /
                @as(f64, @floatFromInt(grid_num - 1));
            for (0..grid_num) |cc| {
                const xi = @as(f64, @floatFromInt(cc)) /
                    @as(f64, @floatFromInt(grid_num - 1));
                if (xi + eta <= 1.0) {
                    try list.append(allocator, .{
                        .sample_kind = .structured,
                        .xi_true = xi,
                        .eta_true = eta,
                        .row_idx = rr,
                        .col_idx = cc,
                    });
                }
            }
        }
    } else {
        const xi_min = if (mesh_type == .quad4ibi) 0.0 else -1.0;
        const xi_max = 1.0;
        const eta_min = if (mesh_type == .quad4ibi) 0.0 else -1.0;
        const eta_max = 1.0;
        for (0..grid_num) |rr| {
            const eta = eta_min +
                (@as(f64, @floatFromInt(rr)) /
                    @as(f64, @floatFromInt(grid_num - 1))) * (eta_max - eta_min);
            for (0..grid_num) |cc| {
                const xi = xi_min +
                    (@as(f64, @floatFromInt(cc)) /
                        @as(f64, @floatFromInt(grid_num - 1))) * (xi_max - xi_min);
                try list.append(allocator, .{
                    .sample_kind = .structured,
                    .xi_true = xi,
                    .eta_true = eta,
                    .row_idx = rr,
                    .col_idx = cc,
                });
            }
        }
    }

    return .{ .rows_num = grid_num, .cols_num = grid_num };
}

pub fn appendRandomSamples(
    comptime mesh_type: gk.MeshType,
    allocator: std.mem.Allocator,
    list: *std.ArrayList(SamplePoint),
    rng: *std.Random,
    samples_num: usize,
) !void {
    if (mesh_type == .tri3 or mesh_type == .tri6) {
        for (0..samples_num) |_| {
            var xi = rng.float(f64);
            var eta = rng.float(f64);
            if (xi + eta > 1.0) {
                xi = 1.0 - xi;
                eta = 1.0 - eta;
            }
            try list.append(allocator, .{
                .sample_kind = .random,
                .xi_true = xi,
                .eta_true = eta,
            });
        }
    } else {
        const xi_min = if (mesh_type == .quad4ibi) 0.0 else -1.0;
        const eta_min = if (mesh_type == .quad4ibi) 0.0 else -1.0;
        const span = if (mesh_type == .quad4ibi) 1.0 else 2.0;

        for (0..samples_num) |_| {
            try list.append(allocator, .{
                .sample_kind = .random,
                .xi_true = xi_min + rng.float(f64) * span,
                .eta_true = eta_min + rng.float(f64) * span,
            });
        }
    }
}

pub fn appendBoundarySamples(
    comptime mesh_type: gk.MeshType,
    allocator: std.mem.Allocator,
    list: *std.ArrayList(SamplePoint),
    samples_num: usize,
) !void {
    const boundary_eps = 1.0e-4;

    if (mesh_type == .tri3 or mesh_type == .tri6) {
        const per_edge = @max(@as(usize, 1), samples_num / 3);
        for (0..per_edge) |nn| {
            const tt = @as(f64, @floatFromInt(nn)) /
                @as(f64, @floatFromInt(@max(@as(usize, 1), per_edge - 1)));
            try list.append(allocator, .{
                .sample_kind = .boundary,
                .xi_true = tt * (1.0 - boundary_eps),
                .eta_true = boundary_eps,
            });
            try list.append(allocator, .{
                .sample_kind = .boundary,
                .xi_true = boundary_eps,
                .eta_true = tt * (1.0 - boundary_eps),
            });
            try list.append(allocator, .{
                .sample_kind = .boundary,
                .xi_true = tt * (1.0 - boundary_eps),
                .eta_true = 1.0 - boundary_eps - tt * (1.0 - boundary_eps),
            });
        }
    } else {
        const per_edge = @max(@as(usize, 1), samples_num / 4);
        const min_val = if (mesh_type == .quad4ibi) 0.0 else -1.0;
        const max_val = 1.0;
        const edge_lo = min_val + boundary_eps;
        const edge_hi = max_val - boundary_eps;
        for (0..per_edge) |nn| {
            const tt = @as(f64, @floatFromInt(nn)) /
                @as(f64, @floatFromInt(@max(@as(usize, 1), per_edge - 1)));
            const xi = min_val + tt * (max_val - min_val);
            const eta = min_val + tt * (max_val - min_val);
            try list.append(allocator, .{
                .sample_kind = .boundary,
                .xi_true = xi,
                .eta_true = edge_lo,
            });
            try list.append(allocator, .{
                .sample_kind = .boundary,
                .xi_true = xi,
                .eta_true = edge_hi,
            });
            try list.append(allocator, .{
                .sample_kind = .boundary,
                .xi_true = edge_lo,
                .eta_true = eta,
            });
            try list.append(allocator, .{
                .sample_kind = .boundary,
                .xi_true = edge_hi,
                .eta_true = eta,
            });
        }
    }
}

pub fn appendCornerSamples(
    comptime mesh_type: gk.MeshType,
    allocator: std.mem.Allocator,
    list: *std.ArrayList(SamplePoint),
    samples_num: usize,
) !void {
    const corner_eps = 5.0e-5;
    const per_corner = @max(@as(usize, 1), samples_num / 4);

    if (mesh_type == .tri3 or mesh_type == .tri6) {
        for (0..per_corner) |nn| {
            const scale = 1.0 + @as(f64, @floatFromInt(nn));
            const eps = corner_eps * scale;
            try list.append(allocator, .{
                .sample_kind = .corner,
                .xi_true = eps,
                .eta_true = eps,
            });
            try list.append(allocator, .{
                .sample_kind = .corner,
                .xi_true = 1.0 - 2.0 * eps,
                .eta_true = eps,
            });
            try list.append(allocator, .{
                .sample_kind = .corner,
                .xi_true = eps,
                .eta_true = 1.0 - 2.0 * eps,
            });
        }
    } else {
        const min_val = if (mesh_type == .quad4ibi) 0.0 else -1.0;
        const max_val = 1.0;
        for (0..per_corner) |nn| {
            const scale = 1.0 + @as(f64, @floatFromInt(nn));
            const eps = corner_eps * scale;
            try list.append(allocator, .{
                .sample_kind = .corner,
                .xi_true = min_val + eps,
                .eta_true = min_val + eps,
            });
            try list.append(allocator, .{
                .sample_kind = .corner,
                .xi_true = max_val - eps,
                .eta_true = min_val + eps,
            });
            try list.append(allocator, .{
                .sample_kind = .corner,
                .xi_true = max_val - eps,
                .eta_true = max_val - eps,
            });
            try list.append(allocator, .{
                .sample_kind = .corner,
                .xi_true = min_val + eps,
                .eta_true = max_val - eps,
            });
        }
    }
}

fn quantileFromSorted(sorted_vals: []const f64, q: f64) f64 {
    if (sorted_vals.len == 0) {
        return std.math.nan(f64);
    }
    if (sorted_vals.len == 1) {
        return sorted_vals[0];
    }

    const idx_f = q * @as(f64, @floatFromInt(sorted_vals.len - 1));
    const idx_lo: usize = @intFromFloat(@floor(idx_f));
    const idx_hi: usize = @intFromFloat(@ceil(idx_f));
    const frac = idx_f - @as(f64, @floatFromInt(idx_lo));

    return sorted_vals[idx_lo] * (1.0 - frac) + sorted_vals[idx_hi] * frac;
}

pub fn calcScalarStats(
    allocator: std.mem.Allocator,
    vals: []const f64,
) !ScalarStats {
    const sorted_vals = try allocator.alloc(f64, vals.len);
    defer allocator.free(sorted_vals);
    @memcpy(sorted_vals, vals);
    std.sort.pdq(
        f64,
        sorted_vals,
        {},
        std.sort.asc(f64),
    );

    var sum: f64 = 0.0;
    var sum_sq: f64 = 0.0;
    for (vals) |val| {
        sum += val;
        sum_sq += val * val;
    }

    const inv_len = 1.0 / @as(f64, @floatFromInt(vals.len));
    return .{
        .min = sorted_vals[0],
        .q1 = quantileFromSorted(sorted_vals, 0.25),
        .median = quantileFromSorted(sorted_vals, 0.5),
        .q3 = quantileFromSorted(sorted_vals, 0.75),
        .max = sorted_vals[sorted_vals.len - 1],
        .mean = sum * inv_len,
        .rms = @sqrt(sum_sq * inv_len),
    };
}

pub fn openOutputDir(io: std.Io, dir_name: []const u8) !std.Io.Dir {
    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, dir_name, .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };
    return try cwd.openDir(io, dir_name, .{});
}

fn sampleKindName(sample_kind: SampleKind) []const u8 {
    return switch (sample_kind) {
        .structured => "structured",
        .random => "random",
        .boundary => "boundary",
        .corner => "corner",
    };
}

pub fn writeSampleRecordsCsv(
    io: std.Io,
    out_dir: std.Io.Dir,
    file_name: []const u8,
    records: []const SampleRecord,
) !void {
    const csv_file = try out_dir.createFile(io, file_name, .{});
    defer csv_file.close(io);

    var write_buf: [4096]u8 = undefined;
    var file_writer = csv_file.writer(io, &write_buf);
    const writer = &file_writer.interface;

    try writer.writeAll(
        "sample_kind,xi_true,eta_true,xi_rec,eta_rec,err_xi,err_eta," ++
            "err_param,ideal_target_x,ideal_target_y,observed_target_x," ++
            "observed_target_y,observed_reproj_x,observed_reproj_y,reproj_err," ++
            "iters,converged,in_domain,row_idx,col_idx\n",
    );

    for (records) |record| {
        try writer.print(
            "{s},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d}," ++
                "{d},{d},{d},{d},{d}\n",
            .{
                sampleKindName(record.sample_kind),
                record.xi_true,
                record.eta_true,
                record.xi_rec,
                record.eta_rec,
                record.err_xi,
                record.err_eta,
                record.err_param,
                record.ideal_target_x,
                record.ideal_target_y,
                record.observed_target_x,
                record.observed_target_y,
                record.observed_reproj_x,
                record.observed_reproj_y,
                record.reproj_err,
                record.iters,
                @intFromBool(record.converged),
                @intFromBool(record.in_domain),
                record.row_idx,
                record.col_idx,
            },
        );
    }

    try file_writer.flush();
}

pub fn writeSummaryCsv(
    io: std.Io,
    out_dir: std.Io.Dir,
    file_name: []const u8,
    summaries: []const CaseSummary,
) !void {
    const csv_file = try out_dir.createFile(io, file_name, .{});
    defer csv_file.close(io);

    var write_buf: [4096]u8 = undefined;
    var file_writer = csv_file.writer(io, &write_buf);
    const writer = &file_writer.interface;

    try writer.writeAll(
        "mesh_type,geom_case,camera_case,samples_num,nonconverged_num," ++
            "out_of_domain_num,reproj_min,reproj_q1,reproj_median,reproj_q3," ++
            "reproj_max,reproj_mean,reproj_rms,param_min,param_q1,param_median," ++
            "param_q3,param_max,param_mean,param_rms,iter_min,iter_q1," ++
            "iter_median,iter_q3,iter_max,iter_mean,iter_rms\n",
    );

    for (summaries) |summary| {
        try writer.print(
            "{s},{s},{s},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d}," ++
                "{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d}\n",
            .{
                @tagName(summary.mesh_type),
                summary.geom_case_name,
                summary.camera_case_name,
                summary.samples_num,
                summary.nonconverged_num,
                summary.out_of_domain_num,
                summary.reproj_stats.min,
                summary.reproj_stats.q1,
                summary.reproj_stats.median,
                summary.reproj_stats.q3,
                summary.reproj_stats.max,
                summary.reproj_stats.mean,
                summary.reproj_stats.rms,
                summary.param_stats.min,
                summary.param_stats.q1,
                summary.param_stats.median,
                summary.param_stats.q3,
                summary.param_stats.max,
                summary.param_stats.mean,
                summary.param_stats.rms,
                summary.iter_stats.min,
                summary.iter_stats.q1,
                summary.iter_stats.median,
                summary.iter_stats.q3,
                summary.iter_stats.max,
                summary.iter_stats.mean,
                summary.iter_stats.rms,
            },
        );
    }

    try file_writer.flush();
}

pub fn writeScalarMapCsv(
    io: std.Io,
    out_dir: std.Io.Dir,
    file_name: []const u8,
    rows_num: usize,
    cols_num: usize,
    vals: []const f64,
) !void {
    const Ctx = struct {
        vals: []const f64,
        cols_num: usize,

        fn getVal(self: @This(), rr: usize, cc: usize) f64 {
            return self.vals[rr * self.cols_num + cc];
        }
    };

    try csvio.saveScalarGridCSV(
        io,
        out_dir,
        file_name,
        rows_num,
        cols_num,
        Ctx{
            .vals = vals,
            .cols_num = cols_num,
        },
        Ctx.getVal,
    );
}

pub fn writeScalarMapBmp(
    allocator: std.mem.Allocator,
    io: std.Io,
    out_dir: std.Io.Dir,
    file_name_no_ext: []const u8,
    rows_num: usize,
    cols_num: usize,
    vals: []const f64,
) !void {
    var image = try ndarray.NDArray(f64).initFlat(
        allocator,
        &[_]usize{ 1, rows_num, cols_num },
    );
    defer {
        allocator.free(image.slice);
        image.deinit(allocator);
    }

    for (0..rows_num) |rr| {
        for (0..cols_num) |cc| {
            image.set(&[_]usize{ 0, rr, cc }, vals[rr * cols_num + cc]);
        }
    }

    try iio.saveImage(
        io,
        out_dir,
        file_name_no_ext,
        &image,
        0,
        .{
            .format = .bmp,
            .bits = 8,
            .scaling = .auto,
            .channels = 1,
        },
    );
}

pub fn writeBinaryMaskBmp(
    allocator: std.mem.Allocator,
    io: std.Io,
    out_dir: std.Io.Dir,
    file_name_no_ext: []const u8,
    rows_num: usize,
    cols_num: usize,
    vals: []const f64,
) !void {
    var image = try ndarray.NDArray(f64).initFlat(
        allocator,
        &[_]usize{ 1, rows_num, cols_num },
    );
    defer {
        allocator.free(image.slice);
        image.deinit(allocator);
    }

    for (0..rows_num) |rr| {
        for (0..cols_num) |cc| {
            image.set(&[_]usize{ 0, rr, cc }, vals[rr * cols_num + cc]);
        }
    }

    try iio.saveImage(
        io,
        out_dir,
        file_name_no_ext,
        &image,
        0,
        .{
            .format = .bmp,
            .bits = 8,
            .scaling = .{ .fixed = .{ 0.0, 1.0 } },
            .channels = 1,
        },
    );
}

pub fn compareTol(stats: ScalarStats, tol_val: f64) struct {
    median_ratio: f64,
    q3_ratio: f64,
    max_ratio: f64,
} {
    return .{
        .median_ratio = stats.median / tol_val,
        .q3_ratio = stats.q3 / tol_val,
        .max_ratio = stats.max / tol_val,
    };
}
