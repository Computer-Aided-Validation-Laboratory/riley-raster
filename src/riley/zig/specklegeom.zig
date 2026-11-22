// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2026 James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: James Panayis
// --------------------------------------------------------------------------------------
//! Reference-mesh calibration for physical procedural footprints. Preparation only.
const std = @import("std");
const F = @import("buildconfig.zig").F;
const geometry = @import("geometrykernels.zig");
const MeshType = geometry.MeshType;
const meshio = @import("meshio.zig");
const NDArray = @import("ndarray.zig").NDArray;
const shapefun = @import("shapefun.zig");
const vec = @import("vecstack.zig");
const Vec3 = vec.Vec3T(F);

/// Borrows mesh arrays without allocating. Returns Lu and Lv with Lu*Lv = Aphys/Auv.
/// Rejects uncertifiable UV bounds (InvalidSpeckleUvDomain) or unusable UV/reference
/// geometry (InvalidSpeckleUvGeometry, InvalidSpeckleReferenceGeometry). See dev/THEORY.md §6.
pub fn calibrateReferenceUv(
    mesh_type: MeshType,
    coords: *const meshio.Coords,
    connect: *const meshio.Connect,
    uvs: *const NDArray(F),
) ![2]F {
    return switch (mesh_type) {
        .tri3, .tri3opt => calibrate(3, coords, connect, uvs),
        .tri6 => calibrate(6, coords, connect, uvs),
        .quad4 => calibrate(4, coords, connect, uvs),
        .quad8 => calibrate(8, coords, connect, uvs),
        .quad9 => calibrate(9, coords, connect, uvs),
    };
}

fn calibrate(
    comptime N: usize,
    coords: *const meshio.Coords,
    connect: *const meshio.Connect,
    uvs: *const NDArray(F),
) ![2]F {
    std.debug.assert(connect.getNodesPerElem() == N);
    const points = comptime quadrature(N);
    // Widen before weighted products/reductions, including in f32 geometry builds.
    var physical_area: f64 = 0;
    var uv_area: f64 = 0;
    var weighted_log_ratio: f64 = 0;

    for (0..connect.getElemsNum()) |ee| {
        const nodes = connect.getElem(ee);
        var positions: [N]Vec3 = undefined;
        var texcoords: [N][2]F = undefined;
        var uv_nodes: if (N >= 6) [N]UvPoint else void = undefined;
        // Subtract an element origin to avoid translation-dependent cancellation in
        // shape derivatives, particularly for small elements far from the world origin.
        const origin = coords.getVec3(nodes[0]);
        const uv_origin = [2]F{ uvs.get(&.{ nodes[0], 0 }), uvs.get(&.{ nodes[0], 1 }) };
        for (nodes, 0..) |node, nn| {
            const position = coords.getVec3(node);
            positions[nn] = position.sub(origin);
            const u = uvs.get(&.{ node, 0 });
            const v = uvs.get(&.{ node, 1 });
            if (!uvInDomain(u, v)) return error.InvalidSpeckleUvDomain;
            if (N >= 6) uv_nodes[nn] = .{ u, v };
            texcoords[nn] = .{ u - uv_origin[0], v - uv_origin[1] };
        }
        // Affine triangles and bilinear quads are bounded by their nodal UVs.
        if (N >= 6 and !uvPatchInDomain(uv_nodes)) return error.InvalidSpeckleUvDomain;
        for (points) |point| {
            var dx = Vec3.initZeros();
            var de = Vec3.initZeros();
            var uv_x: [2]F = .{ 0, 0 };
            var uv_e: [2]F = .{ 0, 0 };
            for (0..N) |nn| {
                dx = dx.add(positions[nn].mulScal(point.dxi[nn]));
                de = de.add(positions[nn].mulScal(point.deta[nn]));
                for (0..2) |axis| {
                    uv_x[axis] += point.dxi[nn] * texcoords[nn][axis];
                    uv_e[axis] += point.deta[nn] * texcoords[nn][axis];
                }
            }
            const normal = vec.Vec3Ops.cross(F, dx, de);
            const jac_phys = normal.vecLen();
            const jac_uv = uv_x[0] * uv_e[1] - uv_x[1] * uv_e[0];
            // A zero UV Jacobian has no usable metric inverse, even when physical
            // area is positive. Do not silently omit such faces from calibration.
            if (jac_uv == 0) return error.InvalidSpeckleUvGeometry;
            // Nonfinite Jacobians propagate to the total-area/length checks below.
            const weight: f64 = point.weight;
            const physical_weight = weight * @as(f64, jac_phys);
            physical_area += physical_weight;
            uv_area += weight * @abs(@as(f64, jac_uv));
            // Zero physical area carries no aspect weight; avoid 0*log(0/0).
            // Keep its UV area and the UV-Jacobian rejection above.
            if (physical_weight == 0) continue;

            // X_u = Nu/jac_uv and X_v = Nv/jac_uv. The common denominator
            // cancels in the ratio, avoiding inverse-Jacobian amplification.
            var norm_u_squared: f64 = 0;
            var norm_v_squared: f64 = 0;
            for (dx.vec, de.vec) |x, e| {
                const nu = @as(f64, x) * uv_e[1] - @as(f64, e) * uv_x[1];
                const nv = @as(f64, e) * uv_x[0] - @as(f64, x) * uv_e[0];
                norm_u_squared += nu * nu;
                norm_v_squared += nv * nv;
            }
            weighted_log_ratio += physical_weight * 0.5 * @log(norm_u_squared / norm_v_squared);
        }
    }
    if (!std.math.isFinite(physical_area) or physical_area <= 0)
        return error.InvalidSpeckleReferenceGeometry;
    if (!std.math.isFinite(uv_area) or uv_area <= 0) return error.InvalidSpeckleUvGeometry;
    const area_length = @sqrt(physical_area / uv_area);
    const half_ratio = @exp(0.5 * weighted_log_ratio / physical_area);
    const lengths: [2]F = .{ @floatCast(area_length * half_ratio), @floatCast(area_length / half_ratio) };
    for (lengths) |length| {
        if (!std.math.isFinite(length) or length <= 0)
            return error.InvalidSpeckleReferenceGeometry;
    }
    return lengths;
}

const uv_domain_tol = 2e-5;
const UvPoint = @Vector(2, f64);
const UvPatch = [3][3]UvPoint;

fn uvInDomain(u: anytype, v: @TypeOf(u)) bool {
    const T = @TypeOf(u);
    return u >= -@as(T, uv_domain_tol) and u <= @as(T, 1 + uv_domain_tol) and
        v >= -@as(T, uv_domain_tol) and v <= @as(T, 1 + uv_domain_tol);
}

fn uvPatchInDomain(nodes: anytype) bool {
    const N = nodes.len;
    // Represent all quadratic maps on a tensor-product square. Duffy's map
    // (s,t) -> (s,(1-s)t) covers tri6 and preserves degree <= 2 in each axis.
    // Values below are the resulting 3x3 Lagrange samples, in parent node order.
    const half: UvPoint = @splat(0.5);
    const quarter: UvPoint = @splat(0.25);
    const patch: UvPatch = if (N == 6) .{
        .{ nodes[0], nodes[5], nodes[2] },
        .{ nodes[3], half * (nodes[3] + nodes[4]) +
            quarter * (nodes[5] - half * (nodes[0] + nodes[2])), nodes[4] },
        .{ nodes[1], nodes[1], nodes[1] },
    } else .{
        .{ nodes[0], nodes[7], nodes[3] },
        .{ nodes[4], if (N == 9) nodes[8] else half * (nodes[4] + nodes[5] + nodes[6] + nodes[7]) -
            quarter * (nodes[0] + nodes[1] + nodes[2] + nodes[3]), nodes[6] },
        .{ nodes[1], nodes[5], nodes[2] },
    };
    var controls = patch;
    const two: UvPoint = @splat(2);
    for (0..3) |ii| controls[ii][1] = two * patch[ii][1] - half * (patch[ii][0] + patch[ii][2]);
    for (0..3) |jj| controls[1][jj] = two * controls[1][jj] - half * (controls[0][jj] + controls[2][jj]);
    return boundUvPatch(&controls, 16);
}

fn boundUvPatch(patch: *const UvPatch, depth: u8) bool {
    // Bernstein controls bound the whole patch, but an exterior control alone
    // is not sufficient to reject it. Subdivide only uncertain patches. The
    // finite depth can reject near-tolerance maps whose bounds remain ambiguous.
    var all_inside = true;
    for (0..3) |ii| {
        for (0..3) |jj| {
            const uv = patch[ii][jj];
            if (uvInDomain(uv[0], uv[1])) continue;
            if (ii != 1 and jj != 1) return false; // Actual patch corner.
            all_inside = false;
        }
    }
    if (all_inside) return true;
    if (depth == 0) return false;

    // Bisect one axis by de Casteljau and transpose to alternate axes.
    const half: UvPoint = @splat(0.5);
    var left: UvPatch = undefined;
    var right: UvPatch = undefined;
    for (patch, 0..) |row, ii| {
        const a = half * (row[0] + row[1]);
        const b = half * (row[1] + row[2]);
        const mid = half * (a + b);
        left[0][ii] = row[0];
        left[1][ii] = a;
        left[2][ii] = mid;
        right[0][ii] = mid;
        right[1][ii] = b;
        right[2][ii] = row[2];
    }
    return boundUvPatch(&left, depth - 1) and boundUvPatch(&right, depth - 1);
}

fn QuadraturePoint(comptime N: usize) type {
    return struct { dxi: [N]F, deta: [N]F, weight: F };
}

// Fixed preparation quadrature; these derivatives are computed once per element type,
// not once per face. Duffy's map covers the triangular parent without triangulating
// curved physical elements or replacing their midside geometry by straight chords.
fn quadrature(comptime N: usize) [if (N == 3) 1 else 64]QuadraturePoint(N) {
    @setEvalBranchQuota(20_000);
    if (N == 3) {
        var shape: [N]F = undefined;
        var point: QuadraturePoint(N) = undefined;
        shapefun.shapeFunc(N, 1.0 / 3.0, 1.0 / 3.0, &shape, &point.dxi, &point.deta);
        point.weight = 0.5;
        return .{point}; // Both affine Jacobians and the UV metric are constant.
    }
    const nodes = [_]F{
        -0.9602898564975363, -0.7966664774136267, -0.5255324099163290, -0.1834346424956498,
        0.1834346424956498,  0.5255324099163290,  0.7966664774136267,  0.9602898564975363,
    };
    const weights = [_]F{
        0.1012285362903763, 0.2223810344533745, 0.3137066458778873, 0.3626837833783620,
        0.3626837833783620, 0.3137066458778873, 0.2223810344533745, 0.1012285362903763,
    };
    var points: [64]QuadraturePoint(N) = undefined;
    for (nodes, weights, 0..) |x, wx, ii| {
        for (nodes, weights, 0..) |y, wy, jj| {
            var xi = x;
            var eta = y;
            var weight = wx * wy;
            if (N == 6) {
                xi = (x + 1) * 0.5;
                eta = (1 - xi) * (y + 1) * 0.5;
                weight *= (1 - xi) * 0.25;
            }
            var shape: [N]F = undefined;
            var point: QuadraturePoint(N) = undefined;
            shapefun.shapeFunc(N, xi, eta, &shape, &point.dxi, &point.deta);
            point.weight = weight;
            points[ii * 8 + jj] = point;
        }
    }
    return points;
}

fn testNodes(comptime N: usize) [N][2]F {
    if (N == 3) return .{ .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 } };
    var nodes = geometry.parentNodeCoords(N);
    if (N != 6) for (&nodes) |*xy| {
        xy.* = .{ (xy[0] + 1) * 0.5, (xy[1] + 1) * 0.5 };
    };
    return nodes;
}

fn testCalibrate(comptime mesh_type: MeshType, positions: []F, texcoords: []F) ![2]F {
    const N = comptime mesh_type.getNodesNum();
    var indices: [N]usize = undefined;
    for (&indices, 0..) |*index, nn| index.* = nn;
    const coords = meshio.Coords.init(positions, positions.len / 3);
    const connect = meshio.Connect.init(&indices, 1, N);
    const uvs = try NDArray(F).init(std.testing.allocator, texcoords, &.{ positions.len / 3, 2 });
    defer uvs.deinit(std.testing.allocator);
    return calibrateReferenceUv(mesh_type, &coords, &connect, &uvs);
}

test "physical UV calibration preserves unequal planar axes, rotation, units and partial UVs" {
    const tol: F = if (F == f32) 2e-4 else 2e-11;
    inline for ([_]MeshType{ .tri3, .tri3opt, .quad4, .tri6, .quad8, .quad9 }) |mesh_type| {
        const N = comptime mesh_type.getNodesNum();
        const nodes = testNodes(N);
        var positions: [(N + 1) * 3]F = undefined;
        var texcoords: [(N + 1) * 2]F = undefined;
        for ([_]F{ 1, 8, 1000 }) |units| {
            for (nodes, 0..) |xy, nn| {
                positions[3 * nn ..][0..3].* = .{
                    units * (7 + 2.4 * xy[0]), units * (-3 + 3.2 * xy[0]),
                    units * (11 + 3 * xy[1]),
                };
                texcoords[2 * nn ..][0..2].* = .{ 0.2 + 0.5 * xy[0], 0.1 + 0.25 * xy[1] };
            }
            // Unreferenced nodes must not affect geometry, area or finite checks.
            @memset(positions[N * 3 ..], std.math.nan(F));
            @memset(texcoords[N * 2 ..], std.math.nan(F));
            const cal = try testCalibrate(mesh_type, &positions, &texcoords);
            try std.testing.expectApproxEqRel(8 * units, cal[0], tol);
            try std.testing.expectApproxEqRel(12 * units, cal[1], tol);
            const fraction: F = if (N == 3 or N == 6) 0.5 else 1;
            const known_uv_area = 0.125 * fraction;
            try std.testing.expectApproxEqRel(
                12 * fraction * units * units,
                cal[0] * cal[1] * known_uv_area,
                tol,
            );
            if (mesh_type == .tri3)
                try std.testing.expectEqualDeep(cal, try testCalibrate(.tri3opt, &positions, &texcoords));
            for ([_]F{ 0.5, 0x1p-20 }) |uv_scale| {
                for (0..N * 2) |ii| texcoords[ii] *= uv_scale;
                const uv_scaled = try testCalibrate(mesh_type, &positions, &texcoords);
                for (uv_scaled, cal) |actual, expected|
                    try std.testing.expectApproxEqRel(expected / uv_scale, actual, tol);
                for (0..N * 2) |ii| texcoords[ii] /= uv_scale;
            }
            for (0..N) |nn| texcoords[2 * nn] = 1 - texcoords[2 * nn];
            const mirrored = try testCalibrate(mesh_type, &positions, &texcoords);
            for (mirrored, cal) |actual, expected|
                try std.testing.expectApproxEqRel(expected, actual, tol);
        }
    }
}

test "curved high-order calibration uses true geometry and UV Jacobian areas" {
    const tol: F = if (F == f32) 2e-5 else 2e-11;
    // X=(x,y,k*x*x), with a sheared quadratic UV map. Analytic surface area
    // integrates sqrt(1+4*k*k*x*x); triangle cross-sections have length 1-x.
    const k: F = 0.25;
    const b = 2 * k;
    const root = @sqrt(1 + b * b);
    const integral = 0.5 * (root + @log(b + root) / b);
    inline for ([_]MeshType{ .tri6, .quad8, .quad9 }) |mesh_type| {
        const N = comptime mesh_type.getNodesNum();
        var positions: [N * 3]F = undefined;
        var texcoords: [N * 2]F = undefined;
        for (testNodes(N), 0..) |xy, nn| {
            positions[3 * nn ..][0..3].* = .{ xy[0], xy[1], k * xy[0] * xy[0] };
            texcoords[2 * nn ..][0..2].* = .{
                0.1 + 0.6 * (xy[0] + 0.2 * xy[0] * xy[1]),
                0.1 + 0.5 * (xy[1] + 0.2 * xy[0] * xy[0]),
            };
        }
        const cal = try testCalibrate(mesh_type, &positions, &texcoords);
        const expected = if (N == 6) integral - (root * root * root - 1) / (3 * b * b) else integral;
        // det(dUV/dxy) = 0.3*(1 + 0.2*y - 0.08*x*x). Corner-only
        // triangles/quads have different areas: the UV midside nodes matter too.
        const expected_uv: F = if (N == 6)
            0.3 * (0.5 + 0.2 / 6.0 - 0.04 / 6.0)
        else
            0.3 * (1 + 0.1 - 0.08 / 3.0);
        try std.testing.expectApproxEqRel(expected, cal[0] * cal[1] * expected_uv, tol);
    }

    // Boundary collapse is allowed: X=(s,t,0), U=s, V=s*t on the unit square.
    // Aphys=1, Auv=1/2 and |Xu|/|Xv|=sqrt(s*s+t*t). Polar integration gives
    // mean(log ratio)=log(2)/2-3/2+pi/4, finite despite the corner singularity.
    // The fixed 8x8 rule approximates this integrable log with <8e-5 relative error.
    const mean_log = 0.5 * @log(@as(f64, 2)) - 1.5 + std.math.pi / 4.0;
    inline for ([_]MeshType{ .quad4, .quad8, .quad9 }) |mesh_type| {
        const N = comptime mesh_type.getNodesNum();
        var positions: [N * 3]F = undefined;
        var texcoords: [N * 2]F = undefined;
        for (testNodes(N), 0..) |xy, nn| {
            positions[3 * nn ..][0..3].* = .{ xy[0], xy[1], 0 };
            texcoords[2 * nn ..][0..2].* = .{ xy[0], xy[0] * xy[1] };
        }
        const cal = try testCalibrate(mesh_type, &positions, &texcoords);
        try std.testing.expectApproxEqRel(@as(F, 2), cal[0] * cal[1], tol);
        try std.testing.expectApproxEqRel(@exp(mean_log), @as(f64, cal[0]) / cal[1], 9e-5);
    }
}

test "quad9 calibration includes centre curvature against independent dense area integration" {
    var positions: [27]F = undefined;
    var texcoords: [18]F = undefined;
    const height: F = 0.05;
    const uv_bulge: F = 0.07;
    for (testNodes(9), 0..) |xy, nn| {
        positions[3 * nn ..][0..3].* = .{ xy[0], xy[1], if (nn == 8) height else 0 };
        texcoords[2 * nn ..][0..2].* = .{
            xy[0] + (if (nn == 8) uv_bulge else 0), xy[1],
        };
    }
    const cal = try testCalibrate(.quad9, &positions, &texcoords);
    const steps = 512;
    var area: f64 = 0;
    var weighted_log_ratio: f64 = 0;
    for (0..steps) |ii| {
        const x = (@as(f64, @floatFromInt(ii)) + 0.5) / steps;
        for (0..steps) |jj| {
            const y = (@as(f64, @floatFromInt(jj)) + 0.5) / steps;
            // The centre-only biquadratic graph is z=16*h*x*(1-x)*y*(1-y).
            const bx = 16 * (1 - 2 * x) * y * (1 - y);
            const by = 16 * x * (1 - x) * (1 - 2 * y);
            const dx = height * bx;
            const dy = height * by;
            const physical_weight = @sqrt(1 + dx * dx + dy * dy) / (steps * steps);
            area += physical_weight;
            // U=x+uv_bulge*bubble, V=y. Independent analytic inverse derivatives.
            const ux = 1 + uv_bulge * bx;
            const uy = uv_bulge * by;
            const vx = -uy / ux;
            const vz = dy - dx * uy / ux;
            const guu = (1 + dx * dx) / (ux * ux);
            const gvv = vx * vx + 1 + vz * vz;
            weighted_log_ratio += physical_weight * 0.5 * @log(guu / gvv);
        }
    }
    // The bubble vanishes on the boundary, so the mapped UV domain remains the unit square.
    const known_uv_area: f64 = 1;
    const calibrated_area = @as(f64, cal[0]) * cal[1] * known_uv_area;
    try std.testing.expect(calibrated_area > 1);
    try std.testing.expectApproxEqAbs(area, calibrated_area, 2e-6);
    try std.testing.expectApproxEqAbs(
        @exp(weighted_log_ratio / area),
        @as(f64, cal[0]) / cal[1],
        2e-6,
    );
}

test "physical UV calibration varies continuously with tiny UV perturbations on an 8 by 12 plate" {
    inline for ([_]MeshType{ .tri3, .tri3opt, .tri6, .quad4, .quad8, .quad9 }) |mesh_type| {
        const N = comptime mesh_type.getNodesNum();
        var positions: [N * 3]F = undefined;
        var texcoords: [N * 2]F = undefined;
        for (testNodes(N), 0..) |xy, nn| {
            positions[3 * nn ..][0..3].* = .{ 8 * xy[0], 12 * xy[1], 0 };
            texcoords[2 * nn ..][0..2].* = xy;
        }
        const baseline = try testCalibrate(mesh_type, &positions, &texcoords);
        // Includes f32 texture-export noise and progressively larger small deformations.
        for ([_]F{ 1e-8, 1e-7, 1e-5, 1e-4 }) |perturbation| {
            texcoords[0] = perturbation;
            const lengths = try testCalibrate(mesh_type, &positions, &texcoords);
            const tol = 32 * perturbation + (if (F == f32) @as(F, 2e-6) else 2e-13);
            for (lengths, baseline) |actual, expected|
                try std.testing.expectApproxEqRel(expected, actual, tol);
            try std.testing.expectApproxEqRel(@as(F, 8.0 / 12.0), lengths[0] / lengths[1], tol);
        }
    }
}

test "multipart calibration uses physical-area-weighted log axes with f64 reductions" {
    const alloc = std.testing.allocator;
    // Disconnected triangles have metrics (2,3) and (4,5), with UV areas in ratio 1:3.
    var positions = [_]F{ 0, 0, 0, 0.002, 0, 0, 0, 0.003, 0, 0, 0, 1, 0.012, 0, 1, 0, 0.005, 1 };
    var texcoords = [_]F{ 0, 0, 0.001, 0, 0, 0.001, 0, 0, 0.003, 0, 0, 0.001 };
    const coords = meshio.Coords.init(&positions, 6);
    const uvs = try NDArray(F).init(alloc, &texcoords, &.{ 6, 2 });
    defer uvs.deinit(alloc);
    // Physical areas are 3e-6 and 30e-6: exact affine log weights are 1:10.
    const mean_log = (@log(@as(f64, 2.0 / 3.0)) + 10 * @log(@as(f64, 4.0 / 5.0))) / 11;
    const expected_u = @sqrt(@as(f64, 16.5)) * @exp(0.5 * mean_log);
    const expected_v = @sqrt(@as(f64, 16.5)) / @exp(0.5 * mean_log);
    const tol: f64 = if (F == f32) 1e-6 else 2e-10;
    // Repeated coincident faces exercise the actual production reduction/cast path,
    // without a million coordinate rows or a synthetic copy of the accumulation formula.
    for ([_]usize{ 1, 500_000 }) |repeats| {
        const indices = try alloc.alloc(usize, repeats * 6);
        defer alloc.free(indices);
        for (indices, 0..) |*index, ii| index.* = ii % 6;
        const connect = meshio.Connect.init(indices, repeats * 2, 3);
        const lengths = try calibrateReferenceUv(.tri3, &coords, &connect, &uvs);
        try std.testing.expectApproxEqRel(expected_u, @as(f64, lengths[0]), tol);
        try std.testing.expectApproxEqRel(expected_v, @as(f64, lengths[1]), tol);
        const known_uv_area = 2e-6 * @as(f64, @floatFromInt(repeats));
        const expected_area = 33e-6 * @as(f64, @floatFromInt(repeats));
        try std.testing.expectApproxEqRel(
            expected_area,
            @as(f64, lengths[0]) * lengths[1] * known_uv_area,
            tol,
        );
    }

    // A 20x20 triangulated 8x12 plate plus one extra grid-sized physical face
    // (0.12 area, 0.125% of the plate) with progressively compressed UV height.
    // All faces are affine, so the independent weighted-log reference is exact.
    const side = 20;
    const grid_nodes = (side + 1) * (side + 1);
    var plate_positions: [(grid_nodes + 3) * 3]F = undefined;
    var plate_uvs: [(grid_nodes + 3) * 2]F = undefined;
    var plate_indices: [(side * side * 2 + 1) * 3]usize = undefined;
    for (0..side + 1) |jj| {
        for (0..side + 1) |ii| {
            const nn = jj * (side + 1) + ii;
            const u = @as(F, @floatFromInt(ii)) / side;
            const v = @as(F, @floatFromInt(jj)) / side;
            plate_positions[3 * nn ..][0..3].* = .{ 8 * u, 12 * v, 0 };
            plate_uvs[2 * nn ..][0..2].* = .{ u, v };
        }
    }
    for (0..side) |jj| {
        for (0..side) |ii| {
            const nn = jj * (side + 1) + ii;
            const offset = 6 * (jj * side + ii);
            plate_indices[offset..][0..6].* = .{
                nn, nn + 1, nn + side + 1, nn + 1, nn + side + 2, nn + side + 1,
            };
        }
    }
    plate_positions[3 * grid_nodes ..][0..9].* = .{ 0, 0, 1, 0.4, 0, 1, 0, 0.6, 1 };
    plate_uvs[2 * grid_nodes ..][0..6].* = .{ 0, 0, 0.05, 0, 0, 0 };
    plate_indices[6 * side * side ..][0..3].* = .{ grid_nodes, grid_nodes + 1, grid_nodes + 2 };
    const plate_coords = meshio.Coords.init(&plate_positions, grid_nodes + 3);
    const plate_connect = meshio.Connect.init(&plate_indices, side * side * 2 + 1, 3);
    const plate_uv_array = try NDArray(F).init(alloc, &plate_uvs, &.{ grid_nodes + 3, 2 });
    defer plate_uv_array.deinit(alloc);
    for ([_]F{ 5e-3, 5e-4, 5e-5, 5e-6 }) |height| {
        plate_uvs[2 * grid_nodes + 5] = height;
        const lengths = try calibrateReferenceUv(.tri3, &plate_coords, &plate_connect, &plate_uv_array);
        const plate_mean_log = (96 * @log(@as(f64, 8.0 / 12.0)) +
            0.12 * @log(8 * @as(f64, height) / 0.6)) / 96.12;
        const expected_ratio = @exp(plate_mean_log);
        const known_uv_area = 1 + 0.025 * @as(f64, height);
        try std.testing.expectApproxEqRel(expected_ratio, @as(f64, lengths[0]) / lengths[1], tol);
        try std.testing.expectApproxEqRel(96.12, @as(f64, lengths[0]) * lengths[1] * known_uv_area, tol);
    }
}

test "calibration rejects translated and partially out-of-range affine UVs" {
    var positions = [_]F{ 0, 0, 0, 1, 0, 0, 0, 1, 0 };
    for ([_]F{ 0.5, 2 }) |offset| {
        var texcoords = [_]F{ offset, 0, 1 + offset, 0, offset, 1 };
        try std.testing.expectError(
            error.InvalidSpeckleUvDomain,
            testCalibrate(.tri3, &positions, &texcoords),
        );
    }
}

test "quadratic UV bounds reject between-node overshoot but accept boundary tangency" {
    inline for ([_]MeshType{ .tri6, .quad8, .quad9 }) |mesh_type| {
        const N = comptime mesh_type.getNodesNum();
        var positions: [N * 3]F = undefined;
        var texcoords: [N * 2]F = undefined;
        for (testNodes(N), 0..) |xy, nn| {
            const x = xy[0];
            const y = xy[1];
            positions[3 * nn ..][0..3].* = .{ x, y, 0 };
            texcoords[2 * nn ..][0..2].* = if (N == 6)
                .{ 1 - y + 0.5 * x * (0.5 - x), x }
            else
                .{ x * (1 + 0.5 * y * (0.5 - y)), y };
            try std.testing.expect(uvInDomain(texcoords[2 * nn], texcoords[2 * nn + 1]));
        }
        // Both analytic maps are regular and reach U=1.03125 on an edge.
        try std.testing.expectError(
            error.InvalidSpeckleUvDomain,
            testCalibrate(mesh_type, &positions, &texcoords),
        );
        for (testNodes(N), 0..) |xy, nn| {
            const x = xy[0];
            const y = xy[1];
            const d = (if (N == 6) x else y) - 0.27;
            texcoords[2 * nn ..][0..2].* = if (N == 6)
                .{ 1 - 0.75 * y - 0.25 * d * d, x }
            else
                .{ x * (1 - 0.25 * d * d), y };
        }
        // U touches 1 at an off-node edge maximum. The whole-element
        // Bernstein hull overshoots even though the true map stays in range.
        _ = try testCalibrate(mesh_type, &positions, &texcoords);
    }
}

test "quadratic UV bounds detect an interior-only maximum" {
    inline for ([_]MeshType{ .tri6, .quad8, .quad9 }) |mesh_type| {
        const N = comptime mesh_type.getNodesNum();
        // An off-axis tri6 peak distinguishes the two axis-edge midside nodes.
        // The smaller peak margin is sensitive to errors in the interior sample.
        const centre: [2]F = switch (N) {
            6 => .{ 0.30, 0.25 },
            8 => .{ 0.5, 0.5 },
            9 => .{ 0.25, 0.25 },
            else => unreachable,
        };
        const curvature: F = if (N == 6) 1.2 else if (N == 9) 0.85 else 0.4;
        const cx, const cy = centre;
        const diagonal_dist = 1 - cx - cy;
        // The perpendicular projection of the peak lies on each edge, so its
        // squared distance gives the exact drop in the paraboloid maximum.
        const edge_dist_squared = if (N == 6)
            [_]F{ cx * cx, cy * cy, diagonal_dist * diagonal_dist / 2 }
        else
            [_]F{ cx * cx, cy * cy, (1 - cx) * (1 - cx), (1 - cy) * (1 - cy) };
        const peaks = if (N == 6) [_]F{ 1.003, 0.997 } else [_]F{ 1.05, 0.98 };
        var positions: [N * 3]F = undefined;
        var texcoords: [N * 2]F = undefined;
        for (peaks) |peak| {
            for (edge_dist_squared) |dist_squared| {
                try std.testing.expect(peak - curvature * dist_squared < 1);
            }
            for (testNodes(N), 0..) |xy, nn| {
                const dx = xy[0] - cx;
                const dy = xy[1] - cy;
                const u = peak - curvature * (dx * dx + dy * dy);
                const v = 0.1 + 0.8 * xy[1];
                try std.testing.expect(0 <= u and u <= 1 and 0 <= v and v <= 1);
                positions[3 * nn ..][0..3].* = .{ xy[0], xy[1], 0 };
                texcoords[2 * nn ..][0..2].* = .{ u, v };
            }
            const result = testCalibrate(mesh_type, &positions, &texcoords);
            if (peak > 1) {
                try std.testing.expectError(error.InvalidSpeckleUvDomain, result);
            } else {
                _ = try result;
            }
        }
    }
}

test "affine UV bounds permit roundoff at both unit-square limits" {
    var positions = [_]F{ 0, 0, 0, 1, 0, 0, 0, 1, 0 };
    for ([_]F{ -1, 1 }) |direction| {
        const boundary: F = if (direction < 0) 0 else 1;
        const index: usize = if (direction < 0) 0 else 2;
        var texcoords = [_]F{ 0, 0, 1, 0, 0, 1 };
        texcoords[index] = boundary + direction * 1e-5;
        _ = try testCalibrate(.tri3, &positions, &texcoords);
        texcoords[index] = boundary + direction * 3e-5;
        try std.testing.expectError(
            error.InvalidSpeckleUvDomain,
            testCalibrate(.tri3, &positions, &texcoords),
        );
    }
}

test "physical edge collapse with distinct nodes preserves the interior area" {
    // X=(s,s*t,0) has a collapsed s=0 edge, but jac_phys=s>0 in the interior.
    // The UV map (s,t) remains regular, so Lu*Lv equals the physical area 1/2.
    var positions = [_]F{ 0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 0, 0 };
    var texcoords = [_]F{ 0, 0, 1, 0, 1, 1, 0, 1 };
    const lengths = try testCalibrate(.quad4, &positions, &texcoords);
    try std.testing.expectApproxEqAbs(@as(F, 0.5), lengths[0] * lengths[1], 1e-6);
}

test "calibration rejects zero or nonfinite reference and UV geometry" {
    var positions = [_]F{ 0, 0, 0, 1, 0, 0, 0, 1, 0 };
    var texcoords = [_]F{ 0, 0, 1, 0, 0, 1 };
    texcoords[2] = 0;
    try std.testing.expectError(
        error.InvalidSpeckleUvGeometry,
        testCalibrate(.tri3, &positions, &texcoords),
    );
    for ([_]F{ std.math.nan(F), std.math.inf(F) }) |invalid| {
        texcoords[2] = invalid;
        try std.testing.expectError(
            error.InvalidSpeckleUvDomain,
            testCalibrate(.tri3, &positions, &texcoords),
        );
    }
    texcoords[2] = 1;
    for ([_]F{ 0, std.math.nan(F), std.math.inf(F) }) |invalid| {
        positions[3] = invalid;
        try std.testing.expectError(error.InvalidSpeckleReferenceGeometry, testCalibrate(.tri3, &positions, &texcoords));
    }

    // A valid face must not hide a second positive-area face with collapsed UVs.
    var mixed_positions = [_]F{ 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 1, 0, 1, 0, 1, 1 };
    var mixed_uvs = [_]F{ 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0 };
    var indices = [_]usize{ 0, 1, 2, 3, 4, 5 };
    const coords = meshio.Coords.init(&mixed_positions, 6);
    const connect = meshio.Connect.init(&indices, 2, 3);
    const uvs = try NDArray(F).init(std.testing.allocator, &mixed_uvs, &.{ 6, 2 });
    defer uvs.deinit(std.testing.allocator);
    try std.testing.expectError(
        error.InvalidSpeckleUvGeometry,
        calibrateReferenceUv(.tri3, &coords, &connect, &uvs),
    );

    // A zero-area physical face has no log-ratio weight, even if both axis
    // numerators vanish. Its usable UV area still belongs to the area integral.
    mixed_positions[9..][0..9].* = .{ 0, 0, 1, 0, 0, 1, 0, 0, 1 };
    mixed_uvs[6..][0..6].* = .{ 0, 0, 1, 0, 0, 1 };
    const lengths = try calibrateReferenceUv(.tri3, &coords, &connect, &uvs);
    const tol: F = if (F == f32) 1e-6 else 1e-14;
    for (lengths) |length| try std.testing.expectApproxEqRel(@sqrt(@as(F, 0.5)), length, tol);
}
