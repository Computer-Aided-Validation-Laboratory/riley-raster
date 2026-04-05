const cfg = @import("buildconfig.zig").config;
const impl = if (cfg.simd == .on)
    @import("shaderkernels_simd.zig")
else
    @import("shaderkernels_scalar.zig");

pub const shaderops = @import("shaderops.zig");
pub const FlatKernel = impl.FlatKernel;
pub const NormalKernel = impl.NormalKernel;
pub const TexKernel = impl.TexKernel;
