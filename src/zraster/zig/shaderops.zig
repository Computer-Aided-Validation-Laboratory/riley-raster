const cfg = @import("buildconfig.zig").config;
const common = @import("shaderops_common.zig");
const impl = if (cfg.simd == .on)
    @import("shaderops_simd.zig")
else
    @import("shaderops_scalar.zig");
const simd_impl = @import("shaderops_simd.zig");

pub const ScaleOver = common.ScaleOver;
pub const NormalType = common.NormalType;
pub const LocalShaderBuffer = common.LocalShaderBuffer;
pub const NodalInput = common.NodalInput;
pub const NodalPrepared = common.NodalPrepared;
pub const TexInput = common.TexInput;
pub const TexPrepared = common.TexPrepared;
pub const ShadeContext = common.ShadeContext;
pub const InterpData = common.InterpData;
pub const ShaderInput = common.ShaderInput;
pub const ShaderPrepared = common.ShaderPrepared;
pub const fillNodal = impl.fillNodal;
pub const fillNodalPerspective = impl.fillNodalPerspective;
pub const fillTexClip = impl.fillTexClip;
pub const fillTexPerspective = impl.fillTexPerspective;
pub const fillNodalSIMD = simd_impl.fillNodalSIMD;
pub const fillNodalPerspectiveSIMD = simd_impl.fillNodalPerspectiveSIMD;
pub const fillTexClipSIMD = simd_impl.fillTexClipSIMD;
pub const fillTexPerspectiveSIMD = simd_impl.fillTexPerspectiveSIMD;
pub const fillTexPerspectiveSIMDTri3 = simd_impl.fillTexPerspectiveSIMDTri3;

pub const fillFlat = fillNodal;
pub const fillFlatPerspective = fillNodalPerspective;
pub const fillFlatSIMD = fillNodalSIMD;
pub const fillFlatPerspectiveSIMD = fillNodalPerspectiveSIMD;
