const std = @import("std");

pub const SimdMode = enum {
    off,
    on,
};

pub const Dispatch = enum {
    run_time,
    comp_time,
};

pub const SimdTextureInterpMode = enum {
    inner,
    over_pixels,
};

pub const EdgeTolerance = struct {
    tri_weight_inclusion: f64 = 1e-9,
    simd_raster_weight_inclusion: f64 = 1e-9,
};

pub const HullTolerance = struct {
    scalar_inclusion: f64 = 1.0e-6,
    simd_inclusion: f64 = 1.0e-6,
};

pub const CullingTolerance = struct {
    higher_order_backface_nz: f64 = 1e-8,
    tri3_signed_area: f64 = 1e-12,
};

pub const NormalTolerance = struct {
    normalise_magnitude: f64 = 1e-12,
};

pub const NewtonTolerance = struct {
    residual: f64 = 1e-8,
    determinant: f64 = 1e-12,
    parametric_domain: f64 = 1e-7,
};

pub const NewtonSeedTolerance = struct {
    determinant: f64 = 1e-10,
    parametric_domain: f64 = 1e-5,
    residual_sq: f64 = 1e-4,
};

pub const GeometryTolerance = struct {
    bilinear_parametric_domain: f64 = 1e-8,
    bilinear_denom: f64 = 1e-12,
    quadratic_area: f64 = 1e-12,
};

pub const TextureTolerance = struct {
    lancsoz_centre_snap: f64 = 1e-6,
    weight_sum: f64 = 1e-9,
};

pub const ImageTolerance = struct {
    auto_scale_range: f64 = 1e-9,
};

pub const LegacyTolerance = struct {
    oldraster_area: f64 = 1e-12,
};

pub const Tolerance = struct {
    edge: EdgeTolerance = .{},
    hull: HullTolerance = .{},
    culling: CullingTolerance = .{},
    normals: NormalTolerance = .{},
    newton: NewtonTolerance = .{},
    newton_seed: NewtonSeedTolerance = .{},
    geometry: GeometryTolerance = .{},
    texture: TextureTolerance = .{},
    image: ImageTolerance = .{},
    legacy: LegacyTolerance = .{},
};

pub const Config = struct {
    simd: SimdMode = .on,
    simd_texture_interp: SimdTextureInterpMode = .inner,
    texture_sample_dispatch: Dispatch = .run_time,
    texture_sample_mode_dispatch: Dispatch = .comp_time,
    simd_vector_width: comptime_int = 8,
    max_nodal_fields: comptime_int = 8,
    max_image_channels: comptime_int = 8,
    newton_iter_max: comptime_int = 10,
    interp_lut_size: comptime_int = 1024,
    precision: type = f64,
    tolerance: Tolerance = .{},
};

pub const config = Config{
    .simd = .on,
    .simd_texture_interp = .inner,
    .texture_sample_dispatch = .run_time,
    .texture_sample_mode_dispatch = .comp_time,
    .simd_vector_width = 8,
    .max_nodal_fields = 8,
    .max_image_channels = 8,
    .newton_iter_max = 10,
    .interp_lut_size = 1024,
    .precision = f64,
    .tolerance = .{},
};

pub const SimdWidth = config.simd_vector_width;

pub const VecSF = @Vector(SimdWidth, f64);
pub const VecSU = @Vector(SimdWidth, usize);
pub const VecSI = @Vector(SimdWidth, isize);
pub const VecSB = @Vector(SimdWidth, bool);
pub const VecSU8 = @Vector(SimdWidth, u8);
