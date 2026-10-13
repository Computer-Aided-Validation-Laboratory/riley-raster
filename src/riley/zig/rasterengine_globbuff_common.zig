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
const ndarray = @import("ndarray.zig");
const rops = @import("rasterfrontend.zig");
const bin = @import("elemtilebinning.zig");
const report = @import("report.zig");
const rasterengine = @import("rasterengine_common.zig");
const mo = @import("meshpipeline.zig");
const subpxframe = @import("subpxframe_globbuff.zig");

// --------------------------------------------------------------------------------------
// Public Entry-Point Func
// --------------------------------------------------------------------------------------

pub fn rasterSceneGlobBuff(
    comptime RasterBackend: type,
    comptime report_mode: report.ReportMode,
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    requested_workers: u16,
    tiling: bin.TilingOverlaps,
    meshes: []const mo.MeshPrepared,
    root_inputs: mo.MeshRootInputs,
    target: *subpxframe.SubpxTarget,
    image_out_arr: *ndarray.NDArray(F),
) !usize {
    return rasterengine.rasterSceneGlobBuff(
        RasterBackend,
        report_mode,
        outer_alloc,
        io,
        ctx_rast,
        ctx_report,
        requested_workers,
        tiling,
        meshes,
        root_inputs,
        target,
        image_out_arr,
    );
}
