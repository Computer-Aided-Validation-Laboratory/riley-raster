const cfg = @import("buildconfig.zig").config;
const impl = if (cfg.simd == .on)
    @import("rasterengine_simd.zig")
else
    @import("rasterengine_scalar.zig");
const simd_impl = @import("rasterengine_simd.zig");

pub const ScratchBuffers = simd_impl.ScratchBuffers;
pub const rasterScene = impl.rasterScene;
pub const RasterPass = impl.RasterPass;
pub const resolveScratchDirect = simd_impl.resolveScratchDirect;
pub const averageScratch = impl.averageScratch;
