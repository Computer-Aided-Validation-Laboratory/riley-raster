const cfg = @import("buildconfig.zig").config;
const impl = if (cfg.simd == .on)
    @import("shaderkernels_simd.zig")
else
    @import("shaderkernels_scalar.zig");

pub const NodalKernel = impl.NodalKernel;
pub const TexKernel = impl.TexKernel;
