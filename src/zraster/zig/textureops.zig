const cfg = @import("buildconfig.zig").config;
const scalar_impl = @import("textureops_scalar.zig");
const simd_impl = @import("textureops_simd.zig");
const impl = if (cfg.simd == .on) simd_impl else scalar_impl;

pub const InterpType = impl.InterpType;
pub const Texture = impl.Texture;
pub const sampleGeneric = impl.sampleGeneric;
pub const sampleGreyscale = impl.sampleGreyscale;
pub const sampleGenericSIMD = simd_impl.sampleGenericSIMD;
pub const sampleGenericInnerSIMD = simd_impl.sampleGenericInnerSIMD;
pub const sampleGenericHybrid = simd_impl.sampleGenericHybrid;
pub const sampleGenericHybridTri3Local = simd_impl.sampleGenericHybridTri3Local;
