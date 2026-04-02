const simd_impl = @import("textureops_simd.zig");

pub const InterpType = simd_impl.InterpType;
pub const Pixel = simd_impl.Pixel;
pub const Texture = simd_impl.Texture;
pub const sampleGeneric = simd_impl.sampleGeneric;
pub const sampleGreyscale = simd_impl.sampleGreyscale;
pub const sampleGenericSIMD = simd_impl.sampleGenericSIMD;
pub const sampleGenericInnerSIMD = simd_impl.sampleGenericInnerSIMD;
pub const sampleGenericHybrid = simd_impl.sampleGenericHybrid;
pub const sampleGenericHybridTri3Local = simd_impl.sampleGenericHybridTri3Local;
