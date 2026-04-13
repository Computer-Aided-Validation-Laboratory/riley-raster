const cfg = @import("buildconfig.zig").config;
const scalar_impl = @import("textureops_scalar.zig");
const simd_impl = @import("textureops_simd.zig");
const impl = if (cfg.simd == .on) simd_impl else scalar_impl;

pub const InterpType = impl.InterpType;
pub const Texture = impl.Texture;
pub const sampleGeneric = impl.sampleGeneric;
pub const sampleGreyscale = impl.sampleGreyscale;
pub const sampleOverPixelsSIMD = simd_impl.sampleOverPixelsSIMD;
pub const samplePerPixelInnerSIMD = simd_impl.samplePerPixelInnerSIMD;
pub const samplePerLaneInnerSIMD = simd_impl.samplePerLaneInnerSIMD;
pub const samplePerLaneTri3SIMD = simd_impl.samplePerLaneTri3SIMD;
