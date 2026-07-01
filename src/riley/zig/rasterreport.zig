// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;
const newton = @import("newton.zig");
const Timestamp = std.Io.Clock.Timestamp;
const rastcfg = @import("rasterconfig.zig");
const rops = @import("rasterops.zig");


// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

pub const ReportMode = rastcfg.ReportMode;

pub const TileScope = struct {
    start: ?Timestamp = null,
};


// --------------------------------------------------------------------------------------
// Public Entry-Point Functions
// --------------------------------------------------------------------------------------

pub inline fn beginTile(
    comptime report_mode: ReportMode,
    io: std.Io,
) TileScope {
    return .{
        .start = if (comptime report_mode == .full_stats)
            Timestamp.now(io, .awake)
        else
            null,
    };
}

pub inline fn finishTile(
    comptime report_mode: ReportMode,
    io: std.Io,
    ctx_report: anytype,
    ctx_rast: rops.RasterContext,
    tile: rops.ActiveTile,
    scope: TileScope,
    shaded_px: u64,
    elem_count: usize,
    cam_duration_ns: u64,
    resolve_duration_ns: u64,
) void {
    const tile_duration_ns: u64 =
        if (comptime report_mode == .full_stats)
            @intCast(
                scope.start.?.durationTo(
                    Timestamp.now(io, .awake),
                ).raw.nanoseconds,
            )
        else
            0;
    const screen_px_x = @as(
        u16,
        @intCast(ctx_rast.camera.pixels_num[0]),
    );
    const tiles_x =
        (screen_px_x + ctx_rast.tile_size - 1) /
        ctx_rast.tile_size;
    const spatial_idx =
        (tile.y_px_min / ctx_rast.tile_size) * tiles_x +
        (tile.x_px_min / ctx_rast.tile_size);
    ctx_report.recordTile(
        spatial_idx,
        tile_duration_ns,
        shaded_px,
        elem_count,
    );
    ctx_report.recordCamTime(cam_duration_ns);
    ctx_report.recordResolveTime(resolve_duration_ns);
}

pub inline fn recordEarlyOut(
    comptime report_mode: ReportMode,
    ctx_report: anytype,
    global_subx: usize,
    global_suby: usize,
    passed: bool,
) void {
    if (comptime report_mode == .full_stats) {
        ctx_report.recordEarlyOut(global_subx, global_suby, passed);
    }
}

pub inline fn recordPixelConvergedStats(
    comptime report_mode: ReportMode,
    ctx_report: anytype,
    global_subx: usize,
    global_suby: usize,
    converged: bool,
    xi: F,
    eta: F,
    jacobian_det: F,
) void {
    if (comptime report_mode == .full_stats) {
        ctx_report.recordPixelConverged(global_subx, global_suby, converged);
        ctx_report.recordPixelXi(global_subx, global_suby, xi);
        ctx_report.recordPixelEta(global_subx, global_suby, eta);
        ctx_report.recordPixelJacobianDet(global_subx, global_suby, jacobian_det);
    }
}

pub inline fn recordPixelSolverDiagnostics(
    comptime report_mode: ReportMode,
    ctx_report: anytype,
    global_subx: usize,
    global_suby: usize,
    status: newton.NewtonStatus,
    pre_domain_converged: bool,
    hit_iter_limit: bool,
    residual_x: F,
    residual_y: F,
    interpolated_w: F,
    residual_mag: F,
    normalized_residual_mag: F,
    domain_violation: F,
) void {
    if (comptime report_mode == .full_stats) {
        ctx_report.recordPixelSolverStatus(
            global_subx,
            global_suby,
            status,
        );
        ctx_report.recordPixelPreDomainConverged(
            global_subx,
            global_suby,
            pre_domain_converged,
        );
        ctx_report.recordPixelHitIterLimit(
            global_subx,
            global_suby,
            hit_iter_limit,
        );
        ctx_report.recordPixelResidualX(
            global_subx,
            global_suby,
            residual_x,
        );
        ctx_report.recordPixelResidualY(
            global_subx,
            global_suby,
            residual_y,
        );
        ctx_report.recordPixelInterpolatedW(
            global_subx,
            global_suby,
            interpolated_w,
        );
        ctx_report.recordPixelResidualMag(
            global_subx,
            global_suby,
            residual_mag,
        );
        ctx_report.recordPixelNormalizedResidualMag(
            global_subx,
            global_suby,
            normalized_residual_mag,
        );
        ctx_report.recordPixelDomainViolation(
            global_subx,
            global_suby,
            domain_violation,
        );
    }
}

pub inline fn recordPixelIterAndOccupancy(
    comptime report_mode: ReportMode,
    ctx_report: anytype,
    global_subx: usize,
    global_suby: usize,
    iters: u8,
    occupancy_x: usize,
    occupancy_y: usize,
) void {
    if (comptime report_mode == .full_stats) {
        ctx_report.recordPixelIters(global_subx, global_suby, iters);
        ctx_report.recordPixelOccupancy(occupancy_x, occupancy_y);
    }
}

pub inline fn recordPixelIters(
    comptime report_mode: ReportMode,
    ctx_report: anytype,
    global_subx: usize,
    global_suby: usize,
    iters: u8,
) void {
    if (comptime report_mode == .full_stats) {
        ctx_report.recordPixelIters(global_subx, global_suby, iters);
    }
}
