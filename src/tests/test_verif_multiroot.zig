// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("../riley/zig/buildconfig.zig");
const F = buildconfig.F;
const cam = @import("../riley/zig/camera.zig");
const gk = @import("../riley/zig/geometrykernels.zig");
const hull = @import("../riley/zig/hull.zig");
const multiroot = @import("../riley/zig/multiroothierarchy.zig");
const newton = @import("../riley/zig/newton.zig");
const rasterconfig = @import("../riley/zig/rasterconfig.zig");
const rops = @import("../riley/zig/rasterops.zig");
const rotation = @import("../riley/zig/rotation.zig");
const shapefun = @import("../riley/zig/shapefun.zig");

pub const CaseStats = struct {
    oracle_rays: usize = 0,
    fast_hits: usize = 0,
    fast_nearest: usize = 0,
    robust_hits: usize = 0,
    robust_nearest: usize = 0,

    pub fn record(
        self: *CaseStats,
        exact_depth: ?F,
        fast_depth: ?F,
        robust_depth: ?F,
    ) void {
        if (exact_depth) |oracle_z| {
            if (oracle_z > 0) {
                self.oracle_rays += 1;
                if (fast_depth) |fd| {
                    if (fd > 0) {
                        self.fast_hits += 1;
                        if (@abs(fd - oracle_z) <= 1e-6 * @max(1.0, oracle_z)) {
                            self.fast_nearest += 1;
                        }
                    }
                }
                if (robust_depth) |rd| {
                    if (rd > 0) {
                        self.robust_hits += 1;
                        if (@abs(rd - oracle_z) <= 1e-6 * @max(1.0, oracle_z)) {
                            self.robust_nearest += 1;
                        }
                    }
                }
            }
        }
    }

    pub fn verify(
        self: *const CaseStats,
        label: []const u8,
        min_fast_hits: usize,
        min_robust_hits: usize,
    ) !void {
        std.debug.print(
            "[{s}] oracle_rays={d}\n" ++
                "  fast:   hits={d} (expected>={d}) nearest={d}\n" ++
                "  robust: hits={d} (expected>={d}) nearest={d}\n",
            .{
                label,
                self.oracle_rays,
                self.fast_hits,
                min_fast_hits,
                self.fast_nearest,
                self.robust_hits,
                min_robust_hits,
                self.robust_nearest,
            },
        );
        if (self.oracle_rays == 0) {
            std.debug.print(
                "ERROR: [{s}] no oracle rays found\n",
                .{label},
            );
            return error.NoOracleRays;
        }
        if (self.fast_hits < min_fast_hits) {
            std.debug.print(
                "ERROR: [{s}] fast solver hit regression: got {d}, expected >= {d}\n",
                .{ label, self.fast_hits, min_fast_hits },
            );
            return error.FastSolverHitRegression;
        }
        if (self.robust_hits < min_robust_hits) {
            std.debug.print(
                "ERROR: [{s}] robust solver hit regression: got {d}, expected >= {d}\n",
                .{ label, self.robust_hits, min_robust_hits },
            );
            return error.RobustSolverHitRegression;
        }
        if (self.robust_hits < self.fast_hits) {
            std.debug.print(
                "ERROR: [{s}] robust hits ({d}) < fast hits ({d})\n",
                .{ label, self.robust_hits, self.fast_hits },
            );
            return error.RobustHitsLessThanFast;
        }
        if (self.robust_nearest < self.fast_nearest) {
            std.debug.print(
                "ERROR: [{s}] robust nearest ({d}) < fast nearest ({d})\n",
                .{ label, self.robust_nearest, self.fast_nearest },
            );
            return error.RobustNearestLessThanFast;
        }
    }
};

fn isInParent(comptime N: usize, u: F, v: F) bool {
    const eps: F = 1e-9;
    return if (N == 6)
        u >= -eps and v >= -eps and u + v <= 1 + eps
    else
        @abs(u) <= 1 + eps and @abs(v) <= 1 + eps;
}

fn validateNewtonHit(
    comptime N: usize,
    nodes: rops.Vec3Slices(F),
    px: F,
    py: F,
    result: gk.GeometryResult(N),
) ?F {
    const weights = result.weights orelse return null;
    if (!std.math.isFinite(result.xi_out) or
        !std.math.isFinite(result.eta_out) or
        !isInParent(N, result.xi_out, result.eta_out))
    {
        return null;
    }
    const state = newton.evaluateSolveState(
        N,
        px - 50,
        py - 50,
        nodes.x,
        nodes.y,
        nodes.z,
        result.xi_out,
        result.eta_out,
    );
    if (!std.math.isFinite(state.norm_resid_mag) or
        state.norm_resid_mag > buildconfig.config.tol.newton.norm_resid)
    {
        return null;
    }
    const facing = rops.projectedJacDetPhysical(
        N,
        nodes,
        result.xi_out,
        result.eta_out,
    );
    if (!std.math.isFinite(facing) or
        facing >= -buildconfig.config.tol.culling.projected_jacobian_abs)
    {
        return null;
    }
    const GK = if (N == 6)
        gk.Tri6Kernel()
    else if (N == 4)
        gk.Quad4Kernel()
    else
        gk.Quad89Kernel(N);
    const inv_z = GK.calcInvZ(nodes, weights);
    if (!std.math.isFinite(inv_z) or inv_z <= 0) return null;
    return inv_z;
}

const SeedZ = struct {
    z: F,
    index: u8,
};

fn getFallbackSeeds(
    comptime N: usize,
    nodes: rops.Vec3Slices(F),
    coords: rops.GatheredElemCoords(N),
    fallback_uvs: *[3][2]F,
) usize {
    const count = gk.multiRootSeedCount(N);
    var seeds: [32]SeedZ = undefined;
    var available: usize = 0;
    for (0..count) |seed_idx| {
        const uv = gk.multiRootSeedCoords(N, @intCast(seed_idx));
        var weights: [N]F = undefined;
        var du: [N]F = undefined;
        var dv: [N]F = undefined;
        shapefun.shapeFunc(N, uv[0], uv[1], &weights, &du, &dv);
        var seed_z: F = 0;
        for (0..N) |nn| seed_z += weights[nn] * coords.z[nn];
        if (std.math.isFinite(seed_z) and seed_z > 0) {
            seeds[available] = .{
                .z = seed_z,
                .index = @intCast(seed_idx),
            };
            available += 1;
        }
    }
    for (1..available) |ii| {
        const seed = seeds[ii];
        var jj = ii;
        while (jj > 0 and (seeds[jj - 1].z > seed.z or
            (seeds[jj - 1].z == seed.z and
                seeds[jj - 1].index > seed.index)))
        {
            seeds[jj] = seeds[jj - 1];
            jj -= 1;
        }
        seeds[jj] = seed;
    }
    var tier: [32]SeedZ = undefined;
    var tier_len: usize = 0;
    for (seeds[0..available]) |seed| {
        const uv = gk.multiRootSeedCoords(N, seed.index);
        const facing = rops.projectedJacDetPhysical(N, nodes, uv[0], uv[1]);
        const front = std.math.isFinite(facing) and
            facing < -buildconfig.config.tol.culling.projected_jacobian_abs;
        if (front) {
            tier[tier_len] = seed;
            tier_len += 1;
        }
    }
    var ordered: [32]SeedZ = undefined;
    var length: usize = 0;
    var used = [_]bool{false} ** 32;
    for (0..tier_len) |ii| {
        const remaining = tier_len - ii;
        const rank = switch (ii % 3) {
            0 => @as(usize, 0),
            1 => remaining / 2,
            else => remaining - 1,
        };
        var seen: usize = 0;
        for (0..tier_len) |jj| {
            if (used[jj]) continue;
            if (seen == rank) {
                ordered[length] = tier[jj];
                length += 1;
                used[jj] = true;
                break;
            }
            seen += 1;
        }
    }
    const fallback_count = @min(3, length);
    for (0..fallback_count) |ii| {
        fallback_uvs[ii] = gk.multiRootSeedCoords(N, ordered[ii].index);
    }
    return fallback_count;
}

fn solveMultirootPoint(
    comptime N: usize,
    mode: rasterconfig.MultirootSolverMode,
    camera: *const cam.CameraPrepared,
    coords: rops.GatheredElemCoords(N),
    px: F,
    py: F,
) ?F {
    const candidate = hull.buildMultiRootHullFromClip(N, camera, coords);
    if (!candidate.contains(px, py)) return null;

    var leaves: [4]multiroot.Leaf = undefined;
    multiroot.prepareFixed4(N, camera, coords, &leaves);

    var mutable_coords = coords;
    const nodes = rops.Vec3Slices(F){
        .x = &mutable_coords.x,
        .y = &mutable_coords.y,
        .z = &mutable_coords.z,
    };
    const GK = if (N == 6)
        gk.Tri6Kernel()
    else if (N == 4)
        gk.Quad4Kernel()
    else
        gk.Quad89Kernel(N);

    var best_inv_z: F = -std.math.inf(F);
    var had_candidate_child = false;

    for (&leaves) |*leaf| {
        if (!leaf.contains(px, py)) continue;
        had_candidate_child = true;
        const result = GK.solveWeightsNewton(
            nodes,
            px,
            py,
            50,
            50,
            leaf.seed[0],
            leaf.seed[1],
        );
        if (validateNewtonHit(N, nodes, px, py, result)) |inv_z| {
            best_inv_z = @max(best_inv_z, inv_z);
        }
    }

    if (best_inv_z <= 0 and had_candidate_child and mode == .robust) {
        var fallback_uvs: [3][2]F = undefined;
        const fallback_count = getFallbackSeeds(N, nodes, coords, &fallback_uvs);
        for (fallback_uvs[0..fallback_count]) |seed_uv| {
            const result = GK.solveWeightsNewton(
                nodes,
                px,
                py,
                50,
                50,
                seed_uv[0],
                seed_uv[1],
            );
            if (validateNewtonHit(N, nodes, px, py, result)) |inv_z| {
                best_inv_z = @max(best_inv_z, inv_z);
            }
        }
    }

    return if (best_inv_z > 0) best_inv_z else null;
}

const AnalyticFold2D = struct {
    ridge: F,
    c: F,
    s: F,
    polarity: F,
};

fn evalCubic(coeffs: [4]F, u: F) F {
    return ((coeffs[3] * u + coeffs[2]) * u + coeffs[1]) * u + coeffs[0];
}

fn addAnalyticRoot(roots: *[3]F, count: *usize, root: F) void {
    if (!std.math.isFinite(root) or root < -1 - 1e-10 or root > 1 + 1e-10) return;
    for (roots[0..count.*]) |known| {
        if (@abs(root - known) < 1e-8) return;
    }
    std.debug.assert(count.* < roots.len);
    roots[count.*] = @max(-1, @min(1, root));
    count.* += 1;
}

fn quadraticRealRoots(a: F, b: F, c: F, roots: *[2]F) usize {
    const scale = @max(@as(F, 1), @max(@abs(a), @max(@abs(b), @abs(c))));
    if (@abs(a) <= 1e-14 * scale) {
        if (@abs(b) <= 1e-14 * scale) return 0;
        roots[0] = -c / b;
        return 1;
    }
    const discriminant = b * b - 4 * a * c;
    if (discriminant < -1e-12 * scale * scale) return 0;
    const sqrt_disc = @sqrt(@max(@as(F, 0), discriminant));
    roots[0] = (-b - sqrt_disc) / (2 * a);
    roots[1] = (-b + sqrt_disc) / (2 * a);
    return if (sqrt_disc <= 1e-13 * scale) 1 else 2;
}

fn analyticUnitRoots(coeffs: [4]F) struct { values: [3]F, len: usize } {
    const scale = @max(@as(F, 1), @max(
        @abs(coeffs[0]),
        @max(@abs(coeffs[1]), @max(@abs(coeffs[2]), @abs(coeffs[3]))),
    ));
    var degree: usize = 3;
    while (degree > 0 and @abs(coeffs[degree]) <= 1e-14 * scale) {
        degree -= 1;
    }
    var stationary: [2]F = undefined;
    const stationary_count = switch (degree) {
        3 => quadraticRealRoots(3 * coeffs[3], 2 * coeffs[2], coeffs[1], &stationary),
        2 => blk: {
            stationary[0] = -coeffs[1] / (2 * coeffs[2]);
            break :blk @as(usize, 1);
        },
        else => 0,
    };
    if (stationary_count == 2 and stationary[0] > stationary[1]) {
        std.mem.swap(F, &stationary[0], &stationary[1]);
    }
    var cuts: [4]F = undefined;
    cuts[0] = -1;
    var cut_count: usize = 1;
    for (stationary[0..stationary_count]) |root| {
        if (root <= -1 or root >= 1) continue;
        cuts[cut_count] = root;
        cut_count += 1;
    }
    cuts[cut_count] = 1;
    cut_count += 1;
    var roots: [3]F = undefined;
    var root_count: usize = 0;
    const zero_tol = 1e-12 * scale;
    for (0..cut_count - 1) |ii| {
        var lo = cuts[ii];
        var hi = cuts[ii + 1];
        var lo_value = evalCubic(coeffs, lo);
        const hi_value = evalCubic(coeffs, hi);
        const lo_is_root = @abs(lo_value) <= zero_tol;
        const hi_is_root = @abs(hi_value) <= zero_tol;
        if (lo_is_root) addAnalyticRoot(&roots, &root_count, lo);
        if (hi_is_root) addAnalyticRoot(&roots, &root_count, hi);
        if (lo_is_root or hi_is_root) continue;
        if ((lo_value > 0) == (hi_value > 0)) continue;
        for (0..60) |_| {
            const mid = 0.5 * (lo + hi);
            const mid_value = evalCubic(coeffs, mid);
            if ((mid_value > 0) == (lo_value > 0)) {
                lo = mid;
                lo_value = mid_value;
            } else {
                hi = mid;
            }
        }
        addAnalyticRoot(&roots, &root_count, 0.5 * (lo + hi));
    }
    return .{ .values = roots, .len = root_count };
}

fn analyticFoldDepth(
    comptime N: usize,
    params: AnalyticFold2D,
    nodes: rops.Vec3Slices(F),
    px: F,
    py: F,
) F {
    const dx = px - 50;
    const dy = py - 50;
    const qx = params.c * dx + params.s * dy;
    const qy = -params.s * dx + params.c * dy;
    const y_scale = -20 * params.polarity;
    const w = qy / y_scale;
    const ridge = params.ridge;
    const coeffs: [4]F = if (N == 4) .{
        -qx / 20,
        w - ridge - 0.1 * qx / 20,
        0.1 * w,
        0,
    } else .{
        20 * ridge * ridge - qx,
        -40 * ridge - 0.2 * qx,
        20,
        0,
    };
    const roots = analyticUnitRoots(coeffs);
    const z_slope: F = if (N == 4) 0.1 else 0.2;
    var best: F = 0;
    for (roots.values[0..roots.len]) |u| {
        const z = 1 + z_slope * u;
        const v = w * z;
        if (z <= 0 or !isInParent(N, u, v)) continue;
        const facing = rops.projectedJacDetPhysical(N, nodes, u, v);
        if (std.math.isFinite(facing) and facing <
            -buildconfig.config.tol.culling.projected_jacobian_abs)
        {
            best = @max(best, 1 / z);
        }
    }
    return best;
}

const OraclePoly = [9]F;
const OracleSurface = [3][3]OraclePoly;

const OracleRoots = struct {
    values: [8]F = undefined,
    len: usize = 0,

    fn add(self: *@This(), value: F) void {
        if (!std.math.isFinite(value)) return;
        for (self.values[0..self.len]) |known| {
            if (@abs(known - value) <= 1e-8) return;
        }
        std.debug.assert(self.len < self.values.len);
        self.values[self.len] = value;
        self.len += 1;
    }
};

fn oracleTerms(comptime N: usize) [N][2]u8 {
    return switch (N) {
        6 => .{
            .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 },
            .{ 2, 0 }, .{ 1, 1 }, .{ 0, 2 },
        },
        8 => .{
            .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 }, .{ 2, 0 },
            .{ 1, 1 }, .{ 0, 2 }, .{ 2, 1 }, .{ 1, 2 },
        },
        9 => .{
            .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 }, .{ 2, 0 },
            .{ 1, 1 }, .{ 0, 2 }, .{ 2, 1 }, .{ 1, 2 },
            .{ 2, 2 },
        },
        else => @compileError("oracle requires a high-order element"),
    };
}

fn oraclePower(value: F, exponent: u8) F {
    return switch (exponent) {
        0 => 1,
        1 => value,
        2 => value * value,
        else => @panic("oracle exponent exceeds quadratic basis"),
    };
}

fn oracleSurface(
    comptime N: usize,
    coords: rops.GatheredElemCoords(N),
) OracleSurface {
    const parents = comptime gk.parentNodeCoords(N);
    const terms = comptime oracleTerms(N);
    var matrix: [N][N + 3]F = undefined;
    for (parents, 0..) |parent, row| {
        for (terms, 0..) |term, col| {
            matrix[row][col] = oraclePower(parent[0], term[0]) *
                oraclePower(parent[1], term[1]);
        }
        matrix[row][N] = coords.x[row];
        matrix[row][N + 1] = coords.y[row];
        matrix[row][N + 2] = coords.z[row];
    }
    for (0..N) |col| {
        var pivot = col;
        for (col + 1..N) |row| {
            if (@abs(matrix[row][col]) > @abs(matrix[pivot][col])) {
                pivot = row;
            }
        }
        std.debug.assert(@abs(matrix[pivot][col]) > 1e-12);
        if (pivot != col) std.mem.swap([N + 3]F, &matrix[pivot], &matrix[col]);
        const inv_pivot = 1 / matrix[col][col];
        for (col..N + 3) |jj| matrix[col][jj] *= inv_pivot;
        for (0..N) |row| {
            if (row == col) continue;
            const factor = matrix[row][col];
            for (col..N + 3) |jj| {
                matrix[row][jj] -= factor * matrix[col][jj];
            }
        }
    }
    var surface = std.mem.zeroes(OracleSurface);
    for (terms, 0..) |term, row| {
        for (0..3) |axis| {
            surface[axis][term[1]][term[0]] = matrix[row][N + axis];
        }
    }
    return surface;
}

fn oraclePolyEval(poly: OraclePoly, degree: usize, value: F) F {
    var result = poly[degree];
    var ii = degree;
    while (ii > 0) {
        ii -= 1;
        result = result * value + poly[ii];
    }
    return result;
}

fn oraclePolyMul(a: OraclePoly, b: OraclePoly) OraclePoly {
    var result = [_]F{0} ** 9;
    for (0..9) |ii| {
        if (a[ii] == 0) continue;
        for (0..9 - ii) |jj| result[ii + jj] += a[ii] * b[jj];
    }
    return result;
}

fn oraclePolySub(a: OraclePoly, b: OraclePoly) OraclePoly {
    var result: OraclePoly = undefined;
    for (0..9) |ii| result[ii] = a[ii] - b[ii];
    return result;
}

fn oracleRealRoots(
    poly: OraclePoly,
    max_degree: usize,
    lo: F,
    hi: F,
) OracleRoots {
    var scale: F = 0;
    for (poly[0 .. max_degree + 1]) |value| scale = @max(scale, @abs(value));
    if (scale == 0) return .{};
    var normalized: OraclePoly = undefined;
    for (0..9) |ii| normalized[ii] = poly[ii] / scale;
    var degree = max_degree;
    while (degree > 0 and @abs(normalized[degree]) <= 1e-13) degree -= 1;
    var result = OracleRoots{};
    if (degree == 0) return result;
    if (degree == 1) {
        const root = -normalized[0] / normalized[1];
        if (root >= lo - 1e-10 and root <= hi + 1e-10) {
            result.add(@max(lo, @min(hi, root)));
        }
        return result;
    }
    var derivative = [_]F{0} ** 9;
    for (1..degree + 1) |ii| {
        derivative[ii - 1] = @as(F, @floatFromInt(ii)) * normalized[ii];
    }
    const stationary = oracleRealRoots(derivative, degree - 1, lo, hi);
    var cuts: [9]F = undefined;
    cuts[0] = lo;
    var count: usize = 1;
    for (stationary.values[0..stationary.len]) |root| {
        if (root <= lo + 1e-10 or root >= hi - 1e-10) continue;
        cuts[count] = root;
        count += 1;
    }
    cuts[count] = hi;
    count += 1;
    for (0..count - 1) |ii| {
        var lower = cuts[ii];
        var upper = cuts[ii + 1];
        var lower_value = oraclePolyEval(normalized, degree, lower);
        const upper_value = oraclePolyEval(normalized, degree, upper);
        const lower_is_root = @abs(lower_value) <= 1e-11;
        const upper_is_root = @abs(upper_value) <= 1e-11;
        if (lower_is_root) result.add(lower);
        if (upper_is_root) result.add(upper);
        if (lower_is_root or upper_is_root) continue;
        if ((lower_value > 0) == (upper_value > 0)) continue;
        for (0..60) |_| {
            const middle = 0.5 * (lower + upper);
            const middle_value = oraclePolyEval(normalized, degree, middle);
            if ((middle_value > 0) == (lower_value > 0)) {
                lower = middle;
                lower_value = middle_value;
            } else {
                upper = middle;
            }
        }
        result.add(0.5 * (lower + upper));
    }
    return result;
}

fn oracleFeDepth(
    comptime N: usize,
    surface: OracleSurface,
    nodes: rops.Vec3Slices(F),
    px: F,
    py: F,
) F {
    var ray: [2][3]OraclePoly = undefined;
    for (0..3) |vv| {
        for (0..9) |uu| {
            ray[0][vv][uu] = surface[0][vv][uu] - (px - 50) * surface[2][vv][uu];
            ray[1][vv][uu] = surface[1][vv][uu] - (py - 50) * surface[2][vv][uu];
        }
    }
    const a = ray[0][2];
    const b = ray[0][1];
    const c = ray[0][0];
    const d = ray[1][2];
    const e = ray[1][1];
    const h = ray[1][0];
    var max_quadratic: F = 0;
    for (a, d) |av, dv| {
        max_quadratic = @max(max_quadratic, @max(@abs(av), @abs(dv)));
    }
    const resultant = if (max_quadratic < 1e-12)
        oraclePolySub(oraclePolyMul(b, h), oraclePolyMul(c, e))
    else blk: {
        const ah_cd = oraclePolySub(oraclePolyMul(a, h), oraclePolyMul(c, d));
        const ae_bd = oraclePolySub(oraclePolyMul(a, e), oraclePolyMul(b, d));
        const bh_ce = oraclePolySub(oraclePolyMul(b, h), oraclePolyMul(c, e));
        break :blk oraclePolySub(
            oraclePolyMul(ah_cd, ah_cd),
            oraclePolyMul(ae_bd, bh_ce),
        );
    };
    const u_lo: F = if (N == 6) 0 else -1;
    const u_roots = oracleRealRoots(resultant, 8, u_lo, 1);
    var best: F = 0;
    for (u_roots.values[0..u_roots.len]) |u| {
        const av = oraclePolyEval(a, 2, u);
        const bv = oraclePolyEval(b, 2, u);
        const cv = oraclePolyEval(c, 2, u);
        const dv = oraclePolyEval(d, 2, u);
        const ev = oraclePolyEval(e, 2, u);
        const hv = oraclePolyEval(h, 2, u);
        const denom = dv * bv - av * ev;
        var v_candidates: [2]F = undefined;
        const v_count: usize = if (@abs(denom) > 1e-9) blk: {
            v_candidates[0] = (av * hv - dv * cv) / denom;
            break :blk 1;
        } else if (@abs(av) > 1e-10 or @abs(bv) > 1e-10) blk: {
            break :blk quadraticRealRoots(av, bv, cv, &v_candidates);
        } else blk: {
            break :blk quadraticRealRoots(dv, ev, hv, &v_candidates);
        };
        for (v_candidates[0..v_count]) |v| {
            if (!isInParent(N, u, v)) continue;
            const f_residual = (av * v + bv) * v + cv;
            const g_residual = (dv * v + ev) * v + hv;
            const ray_scale = @max(@as(F, 1), @max(
                @abs(av) + @abs(bv) + @abs(cv),
                @abs(dv) + @abs(ev) + @abs(hv),
            ));
            if (@abs(f_residual) > 1e-7 * ray_scale or
                @abs(g_residual) > 1e-7 * ray_scale) continue;
            var z: F = 0;
            for (0..3) |vv| {
                const v_power = oraclePower(v, @intCast(vv));
                z += oraclePolyEval(surface[2][vv], 2, u) * v_power;
            }
            if (z <= 0) continue;
            const facing = rops.projectedJacDetPhysical(N, nodes, u, v);
            if (std.math.isFinite(facing) and facing <
                -buildconfig.config.tol.culling.projected_jacobian_abs)
            {
                best = @max(best, 1 / z);
            }
        }
    }
    return best;
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    _ = io;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const local_alloc = arena.allocator();
    const camera = try cam.CameraPrepared.init(local_alloc, .{
        .pixels_num = .{ 100, 100 },
        .pixels_size = .{ 5.3e-6, 5.3e-6 },
        .pos_world = .{ .vec = .{ 0, 0, -1 } },
        .rot_world = rotation.Rotation.init(0, 0, 0),
        .roi_cent_world = .{ .vec = .{ 0, 0, 0 } },
        .focal_length = 5.0e-2,
        .sub_sample = 1,
    });

    inline for (.{ 4, 6, 8, 9 }) |N| {
        const parents = comptime gk.parentNodeCoords(N);
        const center = [2]F{
            if (N == 6) 1.0 / 3.0 else 0,
            if (N == 6) 1.0 / 3.0 else 0,
        };
        const expected_count: usize = if (N == 9) 17 else 2 * N + 1;
        try std.testing.expectEqual(expected_count, gk.multiRootSeedCount(N));
        for (0..N) |nn| {
            const node = gk.multiRootSeedCoords(N, @intCast(nn));
            try std.testing.expectEqualDeep(parents[nn], node);
            if (N == 9 and nn == 8) continue;
            const midpoint = gk.multiRootSeedCoords(N, @intCast(N + nn));
            try std.testing.expectApproxEqAbs(
                0.5 * (center[0] + node[0]),
                midpoint[0],
                1e-14,
            );
            try std.testing.expectApproxEqAbs(
                0.5 * (center[1] + node[1]),
                midpoint[1],
                1e-14,
            );
        }
        if (N != 9) {
            try std.testing.expectEqualDeep(
                center,
                gk.multiRootSeedCoords(N, @intCast(2 * N)),
            );
        }
    }

    const xi_nodes = [_]F{ -1, 1, 1, -1, 0, 1, 0, -1, 0 };
    const eta_nodes = [_]F{ -1, -1, 1, 1, -1, 0, 1, 0, 0 };
    var coords: rops.GatheredElemCoords(9) = undefined;
    var projected: rops.RasterCoords2D(9) = undefined;
    for (0..9) |nn| {
        const xi = xi_nodes[nn];
        coords.x[nn] = 100 * (xi - 0.8 * xi * xi);
        coords.y[nn] = -100 * eta_nodes[nn];
        coords.z[nn] = 1 + 0.2 * xi;
        projected.x[nn] = coords.x[nn] / coords.z[nn] + 50;
        projected.y[nn] = coords.y[nn] / coords.z[nn] + 50;
    }
    try std.testing.expectEqual(
        rops.RootClass.multi_root,
        rops.classifyHighOrdFacing(9, projected).?,
    );

    const target_x: F = 0.2;
    const discriminant = @sqrt(0.96 * 0.96 - 4 * 0.8 * 0.2);
    const near_xi = (0.96 - discriminant) / 1.6;
    const far_xi = (0.96 + discriminant) / 1.6;
    const nodes = rops.Vec3Slices(F){
        .x = &coords.x,
        .y = &coords.y,
        .z = &coords.z,
    };
    const GK = gk.Quad89Kernel(9);
    const near = GK.solveWeightsNewton(
        nodes,
        50 + 100 * target_x,
        50,
        50,
        50,
        near_xi * 0.9,
        0,
    );
    const far = GK.solveWeightsNewton(
        nodes,
        50 + 100 * target_x,
        50,
        50,
        50,
        far_xi * 0.9,
        0,
    );
    try std.testing.expect(near.weights != null);
    try std.testing.expect(far.weights != null);
    try std.testing.expectApproxEqAbs(near_xi, near.xi_out, 1e-8);
    try std.testing.expectApproxEqAbs(far_xi, far.xi_out, 1e-8);
    try std.testing.expect(rops.projectedJacDetPhysical(
        9,
        nodes,
        near.xi_out,
        0,
    ) < 0);
    try std.testing.expect(rops.projectedJacDetPhysical(
        9,
        nodes,
        far.xi_out,
        0,
    ) > 0);
    try std.testing.expect(GK.calcInvZ(nodes, near.weights.?) >
        GK.calcInvZ(nodes, far.weights.?));

    const candidate = hull.buildMultiRootHullFromClip(9, &camera, coords);
    try std.testing.expect(candidate.contains(50 + 100 * target_x, 50));

    try checkControlNearPlane(&camera);
    try checkParentOnlyHierarchyMisses(&camera);
    try checkThreeRootQuad8(&camera);

    var folded_stats = CaseStats{};
    inline for (.{ 4, 6, 8, 9 }) |N| {
        try checkFoldedMatrix(N, &camera, &folded_stats);
    }
    try folded_stats.verify("folded", 1010, 1026);

    var saddle_stats = CaseStats{};
    inline for (.{ 8, 9 }) |N| {
        try checkQuadraticSaddle(N, &camera, &saddle_stats);
    }
    try saddle_stats.verify("saddle", 108, 112);

    var curved_stats = CaseStats{};
    inline for (.{ 6, 8, 9 }) |N| {
        try checkOutwardCurvedMatrix(N, false, &camera, &curved_stats);
        try checkOutwardCurvedMatrix(N, true, &camera, &curved_stats);
    }
    try curved_stats.verify("curved", 12620, 13172);

    var threeroot_stats = CaseStats{};
    try checkThreeRootMatrix(&camera, &threeroot_stats);
    try threeroot_stats.verify("threeroot", 36, 68);
}

fn checkFoldedMatrix(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    stats: *CaseStats,
) !void {
    const parents = comptime gk.parentNodeCoords(N);
    const splits = [_]F{ 0.1, 0.25, 0.5, 0.75, 0.9 };
    const angles = [_]F{
        0,
        std.math.pi / 4.0,
        std.math.pi / 2.0,
        3.0 * std.math.pi / 4.0,
    };
    for (splits) |split| {
        const ridge: F = if (N == 6)
            1 - @sqrt(1 - split)
        else
            2 * split - 1;
        for (angles) |angle| {
            const c = @cos(angle);
            const s = @sin(angle);
            for ([_]F{ -1, 1 }) |polarity| {
                var coords: rops.GatheredElemCoords(N) = undefined;
                var projected: rops.RasterCoords2D(N) = undefined;
                for (parents, 0..) |parent, nn| {
                    const u = parent[0];
                    const v = parent[1];
                    const x = if (N == 4)
                        20 * u * (v - ridge)
                    else
                        20 * (u - ridge) * (u - ridge);
                    const y = polarity * -20 * v;
                    coords.x[nn] = c * x - s * y;
                    coords.y[nn] = s * x + c * y;
                    coords.z[nn] = 1 + (if (N == 4) @as(F, 0.1) else 0.2) * u;
                    projected.x[nn] = coords.x[nn] / coords.z[nn] + 50;
                    projected.y[nn] = coords.y[nn] / coords.z[nn] + 50;
                }
                try std.testing.expectEqual(
                    rops.RootClass.multi_root,
                    rops.classifyHighOrdFacing(N, projected).?,
                );
                const candidate = hull.buildMultiRootHullFromClip(N, camera, coords);
                var mutable_coords = coords;
                const nodes = rops.Vec3Slices(F){
                    .x = &mutable_coords.x,
                    .y = &mutable_coords.y,
                    .z = &mutable_coords.z,
                };
                const params = AnalyticFold2D{
                    .ridge = ridge,
                    .c = c,
                    .s = s,
                    .polarity = polarity,
                };
                for (0..10) |yy| {
                    const py: F = @as(F, @floatFromInt(yy)) * 10.0 + 5.0;
                    for (0..10) |xx| {
                        const px: F = @as(F, @floatFromInt(xx)) * 10.0 + 5.0;
                        if (!candidate.contains(px, py)) continue;
                        const oracle_z = analyticFoldDepth(N, params, nodes, px, py);
                        if (oracle_z <= 0) continue;
                        const fast_z = solveMultirootPoint(
                            N,
                            .fast,
                            camera,
                            coords,
                            px,
                            py,
                        );
                        const robust_z = solveMultirootPoint(
                            N,
                            .robust,
                            camera,
                            coords,
                            px,
                            py,
                        );
                        stats.record(oracle_z, fast_z, robust_z);
                    }
                }
            }
        }
    }
}

fn checkQuadraticSaddle(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    stats: *CaseStats,
) !void {
    const parents = comptime gk.parentNodeCoords(N);
    const ridges = [_]F{ -0.5, 0.0, 0.5 };
    const rotations = [_]F{ 0, std.math.pi / 4.0 };
    for (ridges) |ridge| {
        for (rotations) |angle| {
            const c = @cos(angle);
            const s = @sin(angle);
            var coords: rops.GatheredElemCoords(N) = undefined;
            for (parents, 0..) |parent, nn| {
                const u = parent[0];
                const v = parent[1];
                const x = 20 * (u - ridge) * (u - ridge) + 30 * v * (u * u - 1);
                const y = -20 * v;
                coords.x[nn] = c * x - s * y;
                coords.y[nn] = s * x + c * y;
                coords.z[nn] = 1 + 0.2 * u;
            }
            const candidate = hull.buildMultiRootHullFromClip(N, camera, coords);
            const surface = oracleSurface(N, coords);
            var mutable_coords = coords;
            const nodes = rops.Vec3Slices(F){
                .x = &mutable_coords.x,
                .y = &mutable_coords.y,
                .z = &mutable_coords.z,
            };
            for (0..10) |yy| {
                const py: F = @as(F, @floatFromInt(yy)) * 10.0 + 5.0;
                for (0..10) |xx| {
                    const px: F = @as(F, @floatFromInt(xx)) * 10.0 + 5.0;
                    if (!candidate.contains(px, py)) continue;
                    const oracle_z = oracleFeDepth(N, surface, nodes, px, py);
                    if (oracle_z <= 0) continue;
                    const fast_z = solveMultirootPoint(
                        N,
                        .fast,
                        camera,
                        coords,
                        px,
                        py,
                    );
                    const robust_z = solveMultirootPoint(
                        N,
                        .robust,
                        camera,
                        coords,
                        px,
                        py,
                    );
                    stats.record(oracle_z, fast_z, robust_z);
                }
            }
        }
    }
}

fn checkOutwardCurvedMatrix(
    comptime N: usize,
    comptime is_sphere: bool,
    camera: *const cam.CameraPrepared,
    stats: *CaseStats,
) !void {
    const parents = comptime gk.parentNodeCoords(N);
    const theta_centers = [_]F{ -1.0, -0.7, 0.7, 1.0 };
    const secondary_values = [_]F{ -0.55, 0, 0.55 };
    const rolls = [_]F{
        0,
        std.math.pi / 4.0,
        std.math.pi / 2.0,
        3.0 * std.math.pi / 4.0,
    };
    const image_scale: F = 30;
    const center_z: F = 2.2;
    const angular_span: F = if (N == 6) 1.2 else 0.6;

    for (theta_centers) |theta_center| {
        for (secondary_values) |secondary| {
            for (rolls) |roll| {
                const c = @cos(roll);
                const s = @sin(roll);
                const ct = @cos(secondary);
                const st = @sin(secondary);
                var coords: rops.GatheredElemCoords(N) = undefined;
                var projected: rops.RasterCoords2D(N) = undefined;
                for (parents, 0..) |parent, nn| {
                    const u = if (N == 6) parent[0] - 1.0 / 3.0 else parent[0];
                    const v = if (N == 6) parent[1] - 1.0 / 3.0 else parent[1];
                    const theta = theta_center + angular_span * u;
                    const local_x = @sin(theta);
                    const local_y: F = if (is_sphere)
                        @sin(secondary - angular_span * v)
                    else
                        -0.45 * v * ct + @cos(theta) * st;
                    const local_z: F = if (is_sphere)
                        -@cos(theta) * @cos(secondary - angular_span * v)
                    else
                        -0.45 * v * st - @cos(theta) * ct;
                    const sphere_x = if (is_sphere)
                        local_x * @cos(secondary - angular_span * v)
                    else
                        local_x;
                    coords.x[nn] = image_scale * (c * sphere_x - s * local_y);
                    coords.y[nn] = image_scale * (s * sphere_x + c * local_y);
                    coords.z[nn] = center_z + local_z;
                    projected.x[nn] = coords.x[nn] / coords.z[nn] + 50;
                    projected.y[nn] = coords.y[nn] / coords.z[nn] + 50;
                }
                if (rops.classifyHighOrdFacing(N, projected) != .multi_root) {
                    continue;
                }
                const candidate = hull.buildMultiRootHullFromClip(
                    N,
                    camera,
                    coords,
                );
                const surface = oracleSurface(N, coords);
                var mutable_coords = coords;
                const nodes = rops.Vec3Slices(F){
                    .x = &mutable_coords.x,
                    .y = &mutable_coords.y,
                    .z = &mutable_coords.z,
                };
                for (0..7) |ui| {
                    for (0..7) |vi| {
                        const u_frac = (@as(F, @floatFromInt(ui)) + 0.5) / 7.0;
                        const v_frac = (@as(F, @floatFromInt(vi)) + 0.5) / 7.0;
                        const u = if (N == 6) u_frac else 2 * u_frac - 1;
                        const v = if (N == 6) (1 - u) * v_frac else 2 * v_frac - 1;
                        var weights: [N]F = undefined;
                        var du: [N]F = undefined;
                        var dv: [N]F = undefined;
                        shapefun.shapeFunc(N, u, v, &weights, &du, &dv);
                        var pos = [_]F{0} ** 3;
                        for (0..N) |nn| {
                            const node = [3]F{
                                coords.x[nn] / image_scale,
                                coords.y[nn] / image_scale,
                                coords.z[nn] - center_z,
                            };
                            for (0..3) |axis| {
                                pos[axis] += weights[nn] * node[axis];
                            }
                        }
                        const px = image_scale * pos[0] / (center_z + pos[2]) + 50;
                        const py = image_scale * pos[1] / (center_z + pos[2]) + 50;
                        if (px < 0 or px >= 100 or py < 0 or py >= 100) continue;
                        if (!candidate.contains(px, py)) continue;
                        const oracle_z = oracleFeDepth(N, surface, nodes, px, py);
                        if (oracle_z <= 0) continue;
                        const fast_z = solveMultirootPoint(
                            N,
                            .fast,
                            camera,
                            coords,
                            px,
                            py,
                        );
                        const robust_z = solveMultirootPoint(
                            N,
                            .robust,
                            camera,
                            coords,
                            px,
                            py,
                        );
                        stats.record(oracle_z, fast_z, robust_z);
                    }
                }
            }
        }
    }
}

fn checkThreeRootMatrix(
    camera: *const cam.CameraPrepared,
    stats: *CaseStats,
) !void {
    const parents = comptime gk.parentNodeCoords(8);
    const spreads = [_]F{ 0.05, 0.1, 0.15 };
    const depths = [_]F{ 0.02, 0.06, 0.1 };
    const angles = [_]F{
        0,
        std.math.pi / 4.0,
        std.math.pi / 2.0,
        3.0 * std.math.pi / 4.0,
    };
    for ([_]F{ -1, 1 }) |polarity| {
        for (spreads) |spread| {
            const pair_sum = 3 - spread * spread;
            const product = 1 - spread * spread;
            for (depths) |depth_scale| {
                for (angles) |angle| {
                    const c = @cos(angle);
                    const s = @sin(angle);
                    var coords: rops.GatheredElemCoords(8) = undefined;
                    var projected: rops.RasterCoords2D(8) = undefined;
                    for (parents, 0..) |parent, nn| {
                        const u = 1 + 0.2 * parent[0];
                        const v = 1 + 0.2 * parent[1];
                        const q = u * u * v - 3 * u * u +
                            pair_sum * u - product;
                        const x = 20 * u;
                        const y = polarity * 20 * v;
                        coords.x[nn] = c * x - s * y;
                        coords.y[nn] = s * x + c * y;
                        coords.z[nn] = u + depth_scale * q;
                        projected.x[nn] = coords.x[nn] / coords.z[nn] + 50;
                        projected.y[nn] = coords.y[nn] / coords.z[nn] + 50;
                    }
                    try std.testing.expectEqual(
                        rops.RootClass.multi_root,
                        rops.classifyHighOrdFacing(8, projected).?,
                    );
                    const px = 20 * (c - s * polarity) + 50;
                    const py = 20 * (s + c * polarity) + 50;
                    const candidate = hull.buildMultiRootHullFromClip(
                        8,
                        camera,
                        coords,
                    );
                    if (!candidate.contains(px, py)) continue;
                    var mutable_coords = coords;
                    const nodes = rops.Vec3Slices(F){
                        .x = &mutable_coords.x,
                        .y = &mutable_coords.y,
                        .z = &mutable_coords.z,
                    };
                    var oracle_best: ?F = null;
                    for ([_]F{ -spread / 0.2, 0, spread / 0.2 }) |root| {
                        const facing = rops.projectedJacDetPhysical(
                            8,
                            nodes,
                            root,
                            root,
                        );
                        if (facing <
                            -buildconfig.config.tol.culling.projected_jacobian_abs)
                        {
                            const inv_z = 1 / (1 + 0.2 * root);
                            oracle_best = @max(oracle_best orelse 0, inv_z);
                        }
                    }
                    const oracle_z = oracle_best orelse continue;
                    const fast_z = solveMultirootPoint(
                        8,
                        .fast,
                        camera,
                        coords,
                        px,
                        py,
                    );
                    const robust_z = solveMultirootPoint(
                        8,
                        .robust,
                        camera,
                        coords,
                        px,
                        py,
                    );
                    stats.record(oracle_z, fast_z, robust_z);
                }
            }
        }
    }
}

fn checkControlNearPlane(camera: *const cam.CameraPrepared) !void {
    const parents = comptime gk.parentNodeCoords(8);
    var coords: rops.GatheredElemCoords(8) = undefined;
    for (parents, 0..) |parent, nn| {
        const u = parent[0];
        const v = parent[1];
        coords.x[nn] = 20 * u * u;
        coords.y[nn] = -20 * v;
        coords.z[nn] = 0.1 + 0.9 * u * u;
    }
    const candidate = hull.buildMultiRootHullFromClip(8, camera, coords);
    for (0..21) |ui| {
        for (0..21) |vi| {
            const u = @as(F, @floatFromInt(ui)) / 10 - 1;
            const v = @as(F, @floatFromInt(vi)) / 10 - 1;
            const z = 0.1 + 0.9 * u * u;
            try std.testing.expect(candidate.contains(
                20 * u * u / z + 50,
                -20 * v / z + 50,
            ));
        }
    }
}

fn checkParentOnlyHierarchyMisses(camera: *const cam.CameraPrepared) !void {
    const parents = comptime gk.parentNodeCoords(9);
    var coords: rops.GatheredElemCoords(9) = undefined;
    for (parents, 0..) |parent, nn| {
        const u = parent[0];
        const v = parent[1];
        coords.x[nn] = 100 * (u - 0.8 * u * u);
        coords.y[nn] = -100 * v;
        coords.z[nn] = 1 + 0.2 * u;
    }
    const parent_hull = hull.buildMultiRootHullFromClip(9, camera, coords);
    var leaves: [4]multiroot.Leaf = undefined;
    multiroot.prepareFixed4(9, camera, coords, &leaves);
    var rejected_misses: usize = 0;
    for (0..100) |yy| {
        const py: F = @as(F, @floatFromInt(yy)) + 0.5;
        for (0..100) |xx| {
            const px: F = @as(F, @floatFromInt(xx)) + 0.5;
            if (!parent_hull.contains(px, py)) continue;
            var child_admits = false;
            for (leaves) |leaf| {
                if (leaf.contains(px, py)) {
                    child_admits = true;
                    break;
                }
            }
            if (!child_admits) rejected_misses += 1;
        }
    }
    try std.testing.expect(rejected_misses > 0);
}

fn checkThreeRootQuad8(camera: *const cam.CameraPrepared) !void {
    const parents = comptime gk.parentNodeCoords(8);
    for ([_]F{ -1, 1 }) |polarity| {
        var coords: rops.GatheredElemCoords(8) = undefined;
        for (parents, 0..) |parent, nn| {
            const u = parent[0];
            const v = parent[1];
            coords.x[nn] = 20 * (u * u * u - 0.25 * u);
            coords.y[nn] = polarity * -20 * v;
            coords.z[nn] = 1 + 0.2 * u;
        }
        const candidate = hull.buildMultiRootHullFromClip(8, camera, coords);
        try std.testing.expect(candidate.contains(50, 50));
    }
}
