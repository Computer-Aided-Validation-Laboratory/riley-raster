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
    solver: SolverPolicy = .{},
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

pub const SolverPolicy = struct {
    hull_mode: HullMode = .on_no_fallback,
    one_root: OneRootSeedPolicy = .{},
    multi_root: MultiRootSeedPolicy = .{},
};

pub const OneRootSeedPolicy = struct {
    mode: NewtonSeedMode = .centroid,
    reuse: NewtonSeedReuse = .off,
};

pub const MultiRootSeedPolicy = struct {
    /// The default tries three front-facing seeds in near/middle/far order.
    method: MultiRootMethod = .legacy_front,
    /// Maximum legacy Newton starts per multi-root element.
    /// Candidates are nodes, centroid-to-node midpoints, and the centroid.
    /// Quad9 uses its center node instead of a duplicate virtual centroid.
    /// Valid range: 1..17; each element uses at most its candidate count.
    seed_bank_depth: u8 = 3,
    /// Maximum gap, in raster subpixel rows, for same-column child-root reuse.
    reuse_radius_rows: u8 = 1,
    /// Local predictor used by the fixed4 reuse experiment methods.
    reuse_method: @import("coherentseed.zig").ReuseMethod = .column,
    /// Diagnostic: retry the legacy bank when all child-centre solves fail.
    legacy_fallback: bool = false,
    /// Diagnostic single-step frozen-Jacobian seed refinement.
    single_frozen_jac: bool = false,
    child_seed: MultiRootChildSeed = .center,
    /// Adaptive preprocessing only; the raster loop visits flat leaves.
    adaptive_max_depth: u8 = 3,
    adaptive_stop_px: F = 8,
};

pub const MultiRootMethod = enum {
    legacy_depth,
    legacy_front,
    fixed4,
    fixed4_reuse,
    fixed4_centre_reuse,
    fixed16,
    adaptive,
    patch_center,
    patch_reuse,
    patch_reuse_seedbank,
    patch_extrapolate,
    patch_extrapolate_seedbank,
    all_seeds,
};

pub const MultiRootChildSeed = enum {
    center,
    front_near,
    front_strong,
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

test "multi-root default remains the three-seed front-facing policy" {
    const policy = MultiRootSeedPolicy{};
    try std.testing.expectEqual(MultiRootMethod.legacy_front, policy.method);
    try std.testing.expectEqual(@as(u8, 3), policy.seed_bank_depth);
}
