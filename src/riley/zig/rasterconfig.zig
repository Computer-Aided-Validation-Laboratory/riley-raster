// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
// --------------------------------------------------------------------------------------
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

/// Top-level rendering options: scheduling, output, validation, reporting, and advanced
/// tuning.
pub const RasterConfig = struct {
    pub const default_output_name_format =
        "cam{camera}_frame{frame}_field{field}";

    // Core rendering behaviour.
    render_mode: RenderMode = .offline,

    // Common parallel resource control.
    parallel: ParallelConfig = .auto,

    // Common output behaviour.
    save_strategy: SaveStrategy = .memory,
    output_name_format: []const u8 = default_output_name_format,

    // Sub-configuration groups.
    output: OutputConfig = .{},
    report_perf: ReportMode = .off,
    report_console: bool = false,
    validation: ValidateInput = .fast,

    // Deep implementation tuning.
    advanced: AdvancedConfig = .{},
};

/// Render thread budget: infer it from the machine, render serially, or supply a budget.
pub const ParallelConfig = union(enum) {
    auto,
    serial,
    threads: u16,
};

/// Controls disk-write overlap and the number of frame buffers available for saving.
pub const OutputConfig = struct {
    disk_save_overlap: bool = false,
    save_frame_buff_count: usize = buildconfig.SaveFrameBuffCount,
};

/// Groups raster, lens-distortion, and geometry-solver tuning options.
pub const AdvancedConfig = struct {
    raster: RasterTuning = .{},
    distortion: DistortionTuning = .{},
    solver: SolverTuning = .{},
};

/// Overrides or bounds the automatically chosen tile, stripe, and raster buffer settings.
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

/// Controls spacing, in pixels, between samples along edges used to bound distorted
/// geometry.
pub const DistortionTuning = struct {
    edge_spacing_px: F = 1.0,
};

/// Separate tuning for elements classified as single-root or potentially multi-root under
/// projection.
pub const SolverTuning = struct {
    oneroot: SolverTuningOneRoot = .{},
    multiroot: SolverTuningMultiroot = .{},
};

/// Hull, edge-function, and Newton-seed policies for the single-root path.
pub const SolverTuningOneRoot = struct {
    hull_mode: HullMode = .on_no_fallback,
    edge_fun_mode: EdgeFunMode = .on_the_fly,
    newton_seed_mode: NewtonSeedMode = .centroid,
    newton_seed_reuse: NewtonSeedReuse = .off,
};

/// Edge-function and search-recovery policies for the potentially multi-root path.
pub const SolverTuningMultiroot = struct {
    mode: MultirootSolverMode = .fast,
    edge_fun_mode: EdgeFunMode = .pre_calc,
};

/// Selects whether edge functions are evaluated on demand or precomputed.
pub const EdgeFunMode = enum {
    on_the_fly,
    pre_calc,
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

/// Input-validation level, from disabled through fast checks to full validation.
pub const ValidateInput = enum(u32) {
    off = 0,
    fast = 1,
    full = 2,
};

/// Subpixel raster storage: tile-local scratch, a full-frame buffer, or a stripe buffer.
pub const BufferMode = enum {
    tile_local,
    global_subpx_full,
    global_subpx_stripe,
};

/// Frame scheduling policy: process frames in time order or allow offline scheduling across
/// frames.
pub const RenderMode = enum {
    in_order,
    offline,
};

pub const GeometrySchedulingMode = enum {
    spread,
    pack,
    auto,
};

/// Selects whether rendered images go to disk, memory, both, or neither.
pub const SaveStrategy = enum {
    disk,
    memory,
    both,
    none,
};

/// Selects whether to collect benchmark timings and counters.
pub const ReportMode = enum {
    off,
    bench,
};

/// Controls whether single-root hull preparation can fall back to a convex hull.
pub const HullMode = enum(u32) {
    on_no_fallback = 1,
    on_convex_fallback = 2,
};

/// Selects the centroid or hull-based initial seed for single-root Newton iteration.
pub const NewtonSeedMode = enum {
    centroid,
    hull,
};

/// Controls whether the single-root solver can reuse its last converged seed.
pub const NewtonSeedReuse = enum {
    off,
    last_conv,
};
