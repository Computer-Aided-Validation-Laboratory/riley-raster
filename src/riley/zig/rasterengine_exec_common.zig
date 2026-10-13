// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const F = @import("buildconfig.zig").F;
const rops = @import("rasterfrontend.zig");
const report = @import("report.zig");
const ReportMode = report.ReportMode;

pub fn tileScratchSubpxSize(
    ctx_rast: rops.RasterContext,
) usize {
    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
    const raster_halo_px = ctx_rast.camera.prep_psf.halo_px;
    const scratch_tile_px: usize =
        @as(usize, @intCast(ctx_rast.tile_size)) +
        2 * @as(usize, raster_halo_px);
    return scratch_tile_px * sub_samp;
}

fn initThreadReportLog(
    comptime report_mode: ReportMode,
) report.LogType(report_mode) {
    return switch (report_mode) {
        .off => .{},
        .bench => .{},
        .full_stats => .{},
    };
}

pub fn ThreadState(
    comptime RasterBackend: type,
    comptime report_mode: ReportMode,
) type {
    return struct {
        const Self = @This();

        arena: std.heap.ArenaAllocator,
        subpx_scratch: RasterBackend.SubpxScratchBuffs,
        log: report.LogType(report_mode),
        rasterized_tiles: usize = 0,

        pub fn init(
            outer_alloc: std.mem.Allocator,
            fields_num: usize,
            subpx_tile_size: usize,
        ) !Self {
            var arena = std.heap.ArenaAllocator.init(outer_alloc);
            errdefer arena.deinit();
            const arena_alloc = arena.allocator();

            return .{
                .arena = arena,
                .subpx_scratch = try RasterBackend.initSubpxScratch(
                    arena_alloc,
                    @intCast(fields_num),
                    subpx_tile_size,
                ),
                .log = initThreadReportLog(report_mode),
            };
        }

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
        }
    };
}
