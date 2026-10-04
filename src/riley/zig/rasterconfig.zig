// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
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
    /// Maximum Newton starts per multi-root element, ordered by camera depth.
    /// Candidates are nodes, centroid-to-node midpoints, and the centroid.
    /// Quad9 uses its center node instead of a duplicate virtual centroid.
    /// Valid range: 1..17; each element uses at most its candidate count.
    seed_bank_depth: u8 = 3,
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
