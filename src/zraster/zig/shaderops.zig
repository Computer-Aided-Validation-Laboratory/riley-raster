const cfg = @import("buildconfig.zig").config;
const impl = if (cfg.simd == .on)
    @import("shaderops_simd.zig")
else
    @import("shaderops_scalar.zig");
const simd_impl = @import("shaderops_simd.zig");

pub const ScaleOver = impl.ScaleOver;
pub const NormalType = impl.NormalType;
pub const LocalNodeBuffer = impl.LocalNodeBuffer;
pub const NodalInput = impl.NodalInput;
pub const NodalPrepared = impl.NodalPrepared;
pub const TexInput = impl.TexInput;
pub const TexPrepared = impl.TexPrepared;
pub const ShadeContext = impl.ShadeContext;
pub const InterpData = impl.InterpData;
pub const ShaderInput = impl.ShaderInput;
pub const ShaderPrepared = impl.ShaderPrepared;
pub const fillNodal = impl.fillNodal;
pub const fillNodalPerspective = impl.fillNodalPerspective;
pub const fillTex = impl.fillTex;
pub const fillTexPerspective = impl.fillTexPerspective;
pub const fillNodalSIMD = simd_impl.fillNodalSIMD;
pub const fillNodalPerspectiveSIMD = simd_impl.fillNodalPerspectiveSIMD;
pub const fillTexSIMD = simd_impl.fillTexSIMD;
pub const fillTexPerspectiveSIMD = simd_impl.fillTexPerspectiveSIMD;
pub const fillTexPerspectiveSIMDTri3 = simd_impl.fillTexPerspectiveSIMDTri3;

pub const fillFlat = fillNodal;
pub const fillFlatPerspective = fillNodalPerspective;
pub const fillFlatSIMD = fillNodalSIMD;
pub const fillFlatPerspectiveSIMD = fillNodalPerspectiveSIMD;
