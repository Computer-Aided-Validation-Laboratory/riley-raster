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
const S = buildconfig.SimdWidth;
const VecSB = buildconfig.VecSB;
const VecSF = buildconfig.VecSF;
const cam = @import("../riley/zig/camera.zig");
const csvio = @import("../riley/zig/csvio.zig");
const fullfixtures = @import("../dev_support/fullfixtures.zig");
const cm = @import("../riley/zig/cameramodels.zig");
const Mat22f = @import("../riley/zig/matstack.zig").Mat22f;
const tcfg = @import("../dev_support/testconfig.zig");

const cases_path = "gold/verif/distortion_oracle_cases.csv";
const points_path = "gold/verif/distortion_oracle_points.csv";
const jacobians_path = "gold/verif/distortion_oracle_jacobians.csv";
const case_cols_num: usize = 90;
const points_cols_num: usize = 8;
const jac_cols_num: usize = 8;
const brown_start: usize = 4;
const coeffs_start: usize = 18;

fn buildPoly(row: []const F) !cam.PolyMap {
    const degree: u8 = @intFromFloat(row[2]);
    const mode: cam.PolyMode = switch (@as(u8, @intFromFloat(row[3]))) {
        0 => .coordinate,
        1 => .displacement,
        else => return error.InvalidPolyMode,
    };
    if (degree < 1 or degree > cam.POLY_MAX_DEGREE) return error.InvalidPolyDegree;
    return cam.PolyMap.init(degree, mode, row[coeffs_start..][0 .. 2 * cam.polyTermCount(degree)]);
}

fn buildBrown(row: []const F) cam.BrownCon.Params {
    return .{
        .k1 = row[brown_start + 0],
        .k2 = row[brown_start + 1],
        .k3 = row[brown_start + 4],
        .p1 = row[brown_start + 2],
        .p2 = row[brown_start + 3],
    };
}

fn buildBrownExt(row: []const F) cam.BrownConExt.Params {
    return .{
        .k1 = row[brown_start + 0],
        .k2 = row[brown_start + 1],
        .k3 = row[brown_start + 4],
        .k4 = row[brown_start + 5],
        .k5 = row[brown_start + 6],
        .k6 = row[brown_start + 7],
        .p1 = row[brown_start + 2],
        .p2 = row[brown_start + 3],
        .s1 = row[brown_start + 8],
        .s2 = row[brown_start + 9],
        .s3 = row[brown_start + 10],
        .s4 = row[brown_start + 11],
        .tau_x = row[brown_start + 12],
        .tau_y = row[brown_start + 13],
    };
}

fn buildModel(row: []const F) !cam.DistortModel {
    const model_tag: u8 = @intFromFloat(row[1]);
    const params: cam.DistortParams = switch (model_tag) {
        0 => .none,
        1 => .{ .brown_con = buildBrown(row) },
        2 => .{ .brown_con_ext = buildBrownExt(row) },
        3 => .{ .poly = try buildPoly(row) },
        4 => .{ .brown_con_poly = .{
            .brown_con = buildBrown(row),
            .poly = try buildPoly(row),
        } },
        5 => .{ .brown_con_ext_poly = .{
            .brown_con_ext = buildBrownExt(row),
            .poly = try buildPoly(row),
        } },
        else => return error.InvalidOracleModel,
    };
    return cam.DistortModel.init(params);
}

fn reportMismatch(
    operation: []const u8,
    case_id: usize,
    point_id: usize,
    expected: [2]F,
    actual: [2]F,
    tolerance: F,
) void {
    std.debug.print(
        "distortion oracle {s} mismatch: case={d}, point={d}, " ++
            "expected=({e},{e}), actual=({e},{e}), " ++
            "error=({e},{e}), tolerance={e}\n",
        .{
            operation,
            case_id,
            point_id,
            expected[0],
            expected[1],
            actual[0],
            actual[1],
            @abs(actual[0] - expected[0]),
            @abs(actual[1] - expected[1]),
            tolerance,
        },
    );
}

fn expectPairApprox(
    operation: []const u8,
    case_id: usize,
    point_id: usize,
    expected: [2]F,
    actual: [2]F,
    tolerance: F,
) !void {
    const error_x = @abs(actual[0] - expected[0]);
    const error_y = @abs(actual[1] - expected[1]);
    if (error_x > tolerance or error_y > tolerance) {
        reportMismatch(operation, case_id, point_id, expected, actual, tolerance);
        return error.DistortOracleMismatch;
    }
}

fn checkScalarPoints(cases: anytype, points: anytype) !void {
    const tolerance = tcfg.DISTORT_ORACLE_TOL;
    for (0..points.dims[0]) |rr| {
        const point_row = points.slice[rr * points_cols_num ..][0..points_cols_num];
        const case_id: usize = @intFromFloat(point_row[0]);
        const point_id: usize = @intFromFloat(point_row[1]);
        const case_row = cases.slice[case_id * case_cols_num ..][0..case_cols_num];
        const model = try buildModel(case_row);
        const ideal = [2]F{ point_row[2], point_row[3] };
        const expected_observed = [2]F{ point_row[4], point_row[5] };
        const expected_inv = [2]F{ point_row[6], point_row[7] };
        const actual_observed = cam.fordDistortModelScal(
            model,
            ideal[0],
            ideal[1],
        );
        try expectPairApprox(
            "scalar forward",
            case_id,
            point_id,
            expected_observed,
            .{ actual_observed.x, actual_observed.y },
            tolerance.ford_abs_norm,
        );

        const recovered = try cam.invDistortModelScal(
            model,
            expected_observed[0],
            expected_observed[1],
        );
        try expectPairApprox(
            "scalar inverse",
            case_id,
            point_id,
            expected_inv,
            .{ recovered.x, recovered.y },
            tolerance.inv_abs_norm,
        );
    }
}

fn checkSIMDPoints(cases: anytype, points: anytype) !void {
    const tolerance = tcfg.DISTORT_ORACLE_TOL.backend_abs_norm;
    var row_start: usize = 0;
    while (row_start < points.dims[0]) {
        const first_row = points.slice[row_start * points_cols_num ..][0..points_cols_num];
        const case_id: usize = @intFromFloat(first_row[0]);
        var lane_count: usize = 0;
        while (lane_count < S and row_start + lane_count < points.dims[0]) {
            const row_offset = (row_start + lane_count) * points_cols_num;
            const row = points.slice[row_offset..][0..points_cols_num];
            if (@as(usize, @intFromFloat(row[0])) != case_id) break;
            lane_count += 1;
        }

        var ideal_x = [_]F{0.0} ** S;
        var ideal_y = [_]F{0.0} ** S;
        var observed_x = [_]F{0.0} ** S;
        var observed_y = [_]F{0.0} ** S;
        var active = [_]bool{false} ** S;
        for (0..lane_count) |lane| {
            const row_offset = (row_start + lane) * points_cols_num;
            const row = points.slice[row_offset..][0..points_cols_num];
            ideal_x[lane] = row[2];
            ideal_y[lane] = row[3];
            observed_x[lane] = row[4];
            observed_y[lane] = row[5];
            active[lane] = true;
        }

        const case_row = cases.slice[case_id * case_cols_num ..][0..case_cols_num];
        const model = try buildModel(case_row);
        const actual_ford: ?cm.DistortCoordsSIMD = cam.fordDistortModelSIMD(
            model,
            @as(VecSF, ideal_x),
            @as(VecSF, ideal_y),
        );
        if (actual_ford) |ford| {
            const ford_x: [S]F = ford.x;
            const ford_y: [S]F = ford.y;
            for (0..lane_count) |lane| {
                const row_offset = (row_start + lane) * points_cols_num;
                const row = points.slice[row_offset..][0..points_cols_num];
                try expectPairApprox(
                    "SIMD forward",
                    case_id,
                    @intFromFloat(row[1]),
                    .{ row[4], row[5] },
                    .{ ford_x[lane], ford_y[lane] },
                    tolerance,
                );
            }
        }
        const solved = try cam.invDistortModelSIMD(
            model,
            @as(VecSF, observed_x),
            @as(VecSF, observed_y),
            @as(VecSB, active),
        );
        const recovered_x: [S]F = solved.x;
        const recovered_y: [S]F = solved.y;
        for (0..lane_count) |lane| {
            const row = points.slice[(row_start + lane) * points_cols_num ..][0..points_cols_num];
            try expectPairApprox(
                "SIMD inverse",
                case_id,
                @intFromFloat(row[1]),
                .{ row[6], row[7] },
                .{ recovered_x[lane], recovered_y[lane] },
                tolerance,
            );
        }
        row_start += lane_count;
    }
}

fn modelJacobian(model: cam.DistortModel, x: F, y: F) ?Mat22f {
    return switch (model) {
        .brown_con => |brown| cam.BrownCon.fordWithJac(brown, x, y).jac,
        .brown_con_ext => |brown| cam.BrownConExt.fordWithJac(brown, x, y).jac,
        .poly => |poly| poly.fordWithJac(x, y).jac,
        .brown_con_poly => |chain| chain.fordWithJac(x, y).jac,
        .brown_con_ext_poly => |chain| chain.fordWithJac(x, y).jac,
        else => null,
    };
}

fn polyJacobianSIMD(model: cam.DistortModel, x: F, y: F) ?cm.DistortFordJacSIMDResult {
    const vx: VecSF = @splat(x);
    const vy: VecSF = @splat(y);
    const poly = switch (model) {
        .poly => |map| return cm.PolyMapSIMD.fordWithJac(map, vx, vy),
        .brown_con_poly => |chain| chain.poly,
        .brown_con_ext_poly => |chain| chain.poly,
        else => return null,
    };
    const brown = switch (model) {
        .brown_con_poly => |chain| cm.fordDistortWithJacSIMD(
            cam.BrownCon.Params,
            chain.brown_con,
            vx,
            vy,
        ),
        .brown_con_ext_poly => |chain| cm.fordDistortWithJacSIMD(
            cam.BrownConExt,
            chain.brown_con_ext,
            vx,
            vy,
        ),
        else => unreachable,
    };
    var result = cm.PolyMapSIMD.fordWithJac(poly, brown.coords.x, brown.coords.y);
    const p = result.jac;
    const b = brown.jac;
    result.jac = .{
        .xx = p.xx * b.xx + p.xy * b.yx,
        .xy = p.xx * b.xy + p.xy * b.yy,
        .yx = p.yx * b.xx + p.yy * b.yx,
        .yy = p.yx * b.xy + p.yy * b.yy,
    };
    return result;
}

fn checkJacobians(cases: anytype, jacobians: anytype) !void {
    const tolerance = tcfg.DISTORT_ORACLE_TOL;
    for (0..jacobians.dims[0]) |rr| {
        const row = jacobians.slice[rr * jac_cols_num ..][0..jac_cols_num];
        const case_id: usize = @intFromFloat(row[0]);
        const case_row = cases.slice[case_id * case_cols_num ..][0..case_cols_num];
        const model = try buildModel(case_row);
        const actual = modelJacobian(model, row[2], row[3]) orelse continue;
        const expected = [2][2]F{
            .{ row[4], row[5] },
            .{ row[6], row[7] },
        };
        if (polyJacobianSIMD(model, row[2], row[3])) |simd| {
            const values = [_]VecSF{ simd.jac.xx, simd.jac.xy, simd.jac.yx, simd.jac.yy };
            for (values, 0..) |value, index| {
                const target = expected[index / 2][index % 2];
                const allowed = @max(
                    tolerance.jac_abs,
                    tolerance.jac_rel * @max(1.0, @abs(target)),
                );
                try std.testing.expectApproxEqAbs(target, value[0], allowed);
            }
        }
        for (0..2) |jj| {
            for (0..2) |ii| {
                const scale = @max(1.0, @abs(expected[jj][ii]));
                const allowed = @max(
                    tolerance.jac_abs,
                    tolerance.jac_rel * scale,
                );
                if (@abs(actual.get(jj, ii) - expected[jj][ii]) > allowed) {
                    std.debug.print(
                        "distortion oracle Jacobian mismatch: case={d}, " ++
                            "point={d}, entry=({d},{d}), expected={e}, " ++
                            "actual={e}, tolerance={e}\n",
                        .{
                            case_id,
                            @as(usize, @intFromFloat(row[1])),
                            jj,
                            ii,
                            expected[jj][ii],
                            actual.get(jj, ii),
                            allowed,
                        },
                    );
                    return error.DistortOracleJacobianMismatch;
                }
            }
        }
    }
}

fn checkBrownConPolyEquivalence() !void {
    const equivalent = fullfixtures.getEquivalentBrownConPoly();
    const brown_model: cam.DistortModel = .{
        .brown_con = equivalent.brown_con,
    };
    const poly_model: cam.DistortModel = .{
        .poly = equivalent.poly,
    };
    const poly_map = equivalent.poly;
    const points = [_][2]F{
        .{ -0.010, -0.009 },
        .{ -0.008, 0.006 },
        .{ -0.004, -0.007 },
        .{ 0.003, 0.009 },
        .{ 0.007, -0.005 },
        .{ 0.010, 0.008 },
    };
    const ford_tolerance: F = 1.0e-14;
    const jacobian_tolerance: F = 1.0e-12;

    for (points, 0..) |point, point_id| {
        const brown_ford = cam.fordDistortModelScal(
            brown_model,
            point[0],
            point[1],
        );
        const poly_ford = cam.fordDistortModelScal(
            poly_model,
            point[0],
            point[1],
        );
        try expectPairApprox(
            "Brown-Conrady/polynomial scalar forward equivalence",
            0,
            point_id,
            .{ brown_ford.x, brown_ford.y },
            .{ poly_ford.x, poly_ford.y },
            ford_tolerance,
        );

        const brown_jac = cam.BrownCon.fordWithJac(
            equivalent.brown_con,
            point[0],
            point[1],
        ).jac;
        const poly_jac = poly_map.fordWithJac(
            point[0],
            point[1],
        ).jac;
        for (0..2) |row| {
            for (0..2) |col| {
                try std.testing.expectApproxEqAbs(
                    brown_jac.get(row, col),
                    poly_jac.get(row, col),
                    jacobian_tolerance,
                );
            }
        }

        const brown_inv = try cam.invDistortModelScal(
            brown_model,
            brown_ford.x,
            brown_ford.y,
        );
        const poly_inv = try cam.invDistortModelScal(
            poly_model,
            brown_ford.x,
            brown_ford.y,
        );
        try expectPairApprox(
            "Brown-Conrady/polynomial scalar inverse equivalence",
            0,
            point_id,
            .{ brown_inv.x, brown_inv.y },
            .{ poly_inv.x, poly_inv.y },
            tcfg.DISTORT_ORACLE_TOL.inv_abs_norm,
        );

        var observed_x = [_]F{0.0} ** S;
        var observed_y = [_]F{0.0} ** S;
        var active = [_]bool{false} ** S;
        observed_x[0] = brown_ford.x;
        observed_y[0] = brown_ford.y;
        active[0] = true;
        const brown_simd_inv = try cam.invDistortModelSIMD(
            brown_model,
            @as(VecSF, observed_x),
            @as(VecSF, observed_y),
            @as(VecSB, active),
        );
        const poly_simd_inv = try cam.invDistortModelSIMD(
            poly_model,
            @as(VecSF, observed_x),
            @as(VecSF, observed_y),
            @as(VecSB, active),
        );
        const brown_simd_x: [S]F = brown_simd_inv.x;
        const brown_simd_y: [S]F = brown_simd_inv.y;
        const poly_simd_x: [S]F = poly_simd_inv.x;
        const poly_simd_y: [S]F = poly_simd_inv.y;
        try expectPairApprox(
            "Brown-Conrady/polynomial SIMD inverse equivalence",
            0,
            point_id,
            .{ brown_simd_x[0], brown_simd_y[0] },
            .{ poly_simd_x[0], poly_simd_y[0] },
            tcfg.DISTORT_ORACLE_TOL.backend_abs_norm,
        );
    }
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    var cases = try csvio.loadScalarCsv2D(allocator, io, cases_path);
    defer {
        allocator.free(cases.slice);
        cases.deinit(allocator);
    }
    var points = try csvio.loadScalarCsv2D(allocator, io, points_path);
    defer {
        allocator.free(points.slice);
        points.deinit(allocator);
    }
    var jacobians = try csvio.loadScalarCsv2D(allocator, io, jacobians_path);
    defer {
        allocator.free(jacobians.slice);
        jacobians.deinit(allocator);
    }

    try std.testing.expectEqual(case_cols_num, cases.dims[1]);
    try std.testing.expectEqual(points_cols_num, points.dims[1]);
    try std.testing.expectEqual(jac_cols_num, jacobians.dims[1]);
    try checkScalarPoints(cases, points);
    try checkSIMDPoints(cases, points);
    try checkJacobians(cases, jacobians);
    try checkBrownConPolyEquivalence();
}
