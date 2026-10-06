// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const iio = @import("imageio.zig");
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

pub const RasterConfig = struct {
    pub const default_output_name_format =
        "cam{camera}_frame{frame}_field{field}";

    // Core rendering behaviour.
    render_mode: RenderMode = .offline,
    background_value: F = 0.0,

    // Common parallel resource control.
    parallel: ParallelConfig = .auto,

    // Common output behaviour.
    save_strategy: SaveStrategy = .memory,
    output_name_format: []const u8 = default_output_name_format,

    // Sub-configuration groups.
    output: OutputConfig = .{},
    report: ReportConfig = .{},
    validation: ValidateInput = .fast,

    // Deep implementation tuning.
    advanced: AdvancedConfig = .{},
};

pub const ParallelConfig = union(enum) {
    auto,
    serial,
    threads: u16,
};

pub const OutputConfig = struct {
    image_save_mode: ImageSaveMode = .multifield,
    image_save_opts: []const iio.ImageSaveOpts = &[_]iio.ImageSaveOpts{
        .{ .format = .bmp, .bits = 8, .scaling = .none },
    },
    disk_save_overlap: bool = false,
    save_frame_buff_count: usize = buildconfig.SaveFrameBuffCount,
};

pub const ReportConfig = struct {
    mode: ReportMode = .bench,
    full_stats_opts: FullStatsOpts = .{},
};

pub const AdvancedConfig = struct {
    raster: RasterTuning = .{},
    distortion: DistortionTuning = .{},
    solver: SolverTuning = .{},
};

pub const RasterTuning = struct {
    tile_size_override: ?u16 = null,
    tile_size_min: u16 = 1,
    tile_size_max: u16 = 256,
    buffer_mode: BufferMode = .tile_local,
    global_subpx_tile_size_override: ?u16 = null,
    global_subpx_tile_size_min: u16 = 64,
    global_subpx_tile_size_max: u16 = 1024,
    global_subpx_stripe_size_override: ?u16 = null,
    global_subpx_stripe_size_min: u16 = 256,
    global_subpx_stripe_size_max: u16 = 4096,
    raster_halo_px_override: ?u16 = null,
};

pub const DistortionTuning = struct {
    edge_spacing_px: F = 1.0,
};

pub const SolverTuning = struct {
    oneroot: SolverTuningOneRoot = .{},
    multiroot: SolverTuningMultiroot = .{},
};

pub const SolverTuningOneRoot = struct {
    hull_mode: HullMode = .on_no_fallback,
    newton_seed_mode: NewtonSeedMode = .centroid,
    newton_seed_reuse: NewtonSeedReuse = .off,
};

pub const SolverTuningMultiroot = struct {
    mode: MultirootSolverMode = .fast,
};

/// Controls the solver used for elements classified as potentially multi-root
/// under camera projection.
///
/// Both modes use the same fixed four-child Bézier patch hierarchy:
///
/// 1. test the whole-element conservative projected hull;
/// 2. test the four conservative projected child-patch hulls;
/// 3. for each candidate child, start Newton from that child's parent-space
///    centre;
/// 4. retain the nearest accepted front-facing root.
///
/// `.fast`
///     Uses only the fixed4 child-centre solves.
///
///     This is the default and preferred engineering mode. It provides the
///     best measured throughput/accuracy tradeoff for Riley's supported
///     geometry while keeping work bounded and simple. Some difficult
///     saddle/multi-root rays may be missed when the child-centre seed lies
///     outside the desired Newton basin.
///
/// `.robust`
///     Runs the same fixed4 child-centre path first. If no candidate child
///     yields an accepted front-facing root, Riley performs one additional
///     bounded fallback using the front-facing, camera-depth-ordered seed bank
///     with depth 3.
///
///     This improves recovery on difficult multi-root/saddle cases at higher
///     computational cost. The fallback is sample-wide and runs only after
///     all fixed4 child-centre attempts fail.
///
/// Neither mode attempts exhaustive global root finding. Riley intentionally
/// uses bounded engineering strategies rather than unbounded or full-bank
/// searches.
pub const MultirootSolverMode = enum {
    fast,
    robust,
};

pub const ValidateInput = enum(u32) {
    off = 0,
    fast = 1,
    full = 2,
};

pub const BufferMode = enum {
    tile_local,
    global_subpx_full,
    global_subpx_stripe,
};

pub const RenderMode = enum {
    in_order,
    offline,
};

pub const GeometrySchedulingMode = enum {
    spread,
    pack,
    auto,
};

pub const SaveStrategy = enum {
    disk,
    memory,
    both,
    none,
};

pub const ImageSaveMode = enum {
    grey,
    rgb,
    multifield,
};

pub const ReportMode = enum {
    off,
    bench,
    full_stats,
};

pub const HullMode = enum(u32) {
    on_no_fallback = 1,
    on_convex_fallback = 2,
};

pub const NewtonSeedMode = enum {
    centroid,
    hull,
};

pub const NewtonSeedReuse = enum {
    off,
    last_conv,
};

pub const FullStatsOpts = struct {
    formats: []const iio.ImageSaveOpts = &[_]iio.ImageSaveOpts{
        .{ .format = .bmp, .bits = 8, .scaling = .auto },
        .{ .format = .csv, .bits = null, .scaling = .none },
    },
    save_solver_csv: bool = false,
    save_iter_map: bool = true,
    save_xi_map: bool = true,
    save_eta_map: bool = true,
    save_conv_map: bool = true,
    save_jac_det_map: bool = true,
    save_tile_timing_map: bool = true,
    save_tile_density_map: bool = true,
    save_tile_occupancy_map: bool = true,
    save_depth_map: bool = true,
    save_earlyout_map: bool = true,
    save_pixel_occupancy_map: bool = true,
    save_normals_map: bool = false,
};

test "multiroot default solver mode is fast" {
    const config = RasterConfig{};
    try std.testing.expectEqual(
        MultirootSolverMode.fast,
        config.advanced.solver.multiroot.mode,
    );
}
