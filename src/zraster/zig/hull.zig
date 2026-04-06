const cfg = @import("buildconfig.zig").config;
const impl = if (cfg.simd == .on)
    @import("hull_simd.zig")
else
    @import("hull_scalar.zig");
const simd_impl = @import("hull_simd.zig");

pub const TessTriangle = impl.TessTriangle;
pub const HullResultSIMD = simd_impl.HullResultSIMD;
pub const Tessellation = impl.Tessellation;
pub const getTessellation = impl.getTessellation;
pub const buildAdaptiveHulls = impl.buildAdaptiveHulls;
