// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const Timestamp = std.Io.Clock.Timestamp;
const rastcfg = @import("rasterconfig.zig");
const rops = @import("rasterops.zig");

pub const ReportMode = rastcfg.ReportMode;

pub const TileScope = struct {
    start: ?Timestamp = null,
};

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
) void {
    const tile_duration_ns: u64 = if (comptime report_mode == .full_stats)
        @intCast(scope.start.?.durationTo(Timestamp.now(io, .awake)).raw.nanoseconds)
    else
        0;
    const screen_px_x = @as(u16, @intCast(ctx_rast.camera.pixels_num[0]));
    const tiles_x = (screen_px_x + ctx_rast.tile_size - 1) / ctx_rast.tile_size;
    const spatial_idx = (tile.y_px_min / ctx_rast.tile_size) * tiles_x +
        (tile.x_px_min / ctx_rast.tile_size);
    ctx_report.recordTile(
        spatial_idx,
        tile_duration_ns,
        shaded_px,
        elem_count,
    );
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
    xi: f64,
    eta: f64,
    jacobian_det: f64,
) void {
    if (comptime report_mode == .full_stats) {
        ctx_report.recordPixelConverged(global_subx, global_suby, converged);
        ctx_report.recordPixelXi(global_subx, global_suby, xi);
        ctx_report.recordPixelEta(global_subx, global_suby, eta);
        ctx_report.recordPixelJacobianDet(global_subx, global_suby, jacobian_det);
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
