const cfg = @import("buildconfig.zig").config;

pub const simd_on = cfg.simd == .on;
