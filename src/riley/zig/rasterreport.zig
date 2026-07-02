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
// Public Entry-Point Func
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

pub inline fn recordPixelConvStats(
    comptime report_mode: ReportMode,
    ctx_report: anytype,
    global_subx: usize,
    global_suby: usize,
    conv: bool,
    xi: F,
    eta: F,
    jac_det: F,
) void {
    if (comptime report_mode == .full_stats) {
        ctx_report.recordPixelConv(global_subx, global_suby, conv);
        ctx_report.recordPixelXi(global_subx, global_suby, xi);
        ctx_report.recordPixelEta(global_subx, global_suby, eta);
        ctx_report.recordPixelJacDet(global_subx, global_suby, jac_det);
    }
}

pub inline fn recordPixelSolverDiagnostics(
    comptime report_mode: ReportMode,
    ctx_report: anytype,
    global_subx: usize,
    global_suby: usize,
    status: newton.NewtonStatus,
    pre_dom_conv: bool,
    hit_iter_lim: bool,
    resid_x: F,
    resid_y: F,
    interp_w: F,
    resid_mag: F,
    norm_resid_mag: F,
    dom_violation: F,
) void {
    if (comptime report_mode == .full_stats) {
        ctx_report.recordPixelSolverStatus(
            global_subx,
            global_suby,
            status,
        );
        ctx_report.recordPixelPreDomConv(
            global_subx,
            global_suby,
            pre_dom_conv,
        );
        ctx_report.recordPixelHitIterLimit(
            global_subx,
            global_suby,
            hit_iter_lim,
        );
        ctx_report.recordPixelResidualX(
            global_subx,
            global_suby,
            resid_x,
        );
        ctx_report.recordPixelResidualY(
            global_subx,
            global_suby,
            resid_y,
        );
        ctx_report.recordPixelInterpolatedW(
            global_subx,
            global_suby,
            interp_w,
        );
        ctx_report.recordPixelResidualMag(
            global_subx,
            global_suby,
            resid_mag,
        );
        ctx_report.recordPixelNormalizedResidualMag(
            global_subx,
            global_suby,
            norm_resid_mag,
        );
        ctx_report.recordPixelDomViolation(
            global_subx,
            global_suby,
            dom_violation,
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
