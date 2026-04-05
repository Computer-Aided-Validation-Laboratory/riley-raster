const cfg = @import("buildconfig.zig").config;
const impl = if (cfg.simd == .on)
    @import("shaderops_simd.zig")
else
    @import("shaderops_scalar.zig");
const simd_impl = @import("shaderops_simd.zig");

pub const ScaleOver = impl.ScaleOver;
pub const NormalType = impl.NormalType;
pub const MAX_FIELDS = impl.MAX_FIELDS;
pub const LocalNodeBuffer = impl.LocalNodeBuffer;
pub const FlatInput = impl.FlatInput;
pub const FlatPrepared = impl.FlatPrepared;
pub const TexInput = impl.TexInput;
pub const TexPrepared = impl.TexPrepared;
pub const ShadeContext = impl.ShadeContext;
pub const InterpData = impl.InterpData;
pub const ShaderInput = impl.ShaderInput;
pub const ShaderPrepared = impl.ShaderPrepared;
pub const fillFlat = impl.fillFlat;
pub const fillFlatPerspective = impl.fillFlatPerspective;
pub const fillTex = impl.fillTex;
pub const fillTexPerspective = impl.fillTexPerspective;
pub const fillFlatSIMD = simd_impl.fillFlatSIMD;
pub const fillFlatPerspectiveSIMD = simd_impl.fillFlatPerspectiveSIMD;
pub const fillTexSIMD = simd_impl.fillTexSIMD;
pub const fillTexPerspectiveSIMD = simd_impl.fillTexPerspectiveSIMD;
pub const fillTexPerspectiveSIMDTri3 = simd_impl.fillTexPerspectiveSIMDTri3;
