// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
pub inline fn finishTile(
    ctx_report: anytype,
    shaded_px: u64,
    elem_count: usize,
    cam_duration_ns: u64,
    elem_duration_ns: u64,
    resolve_duration_ns: u64,
) void {
    ctx_report.recordTile(shaded_px, elem_count);
    ctx_report.recordCamTime(cam_duration_ns);
    ctx_report.recordElemTime(elem_duration_ns);
    ctx_report.recordResolveTime(resolve_duration_ns);
}
