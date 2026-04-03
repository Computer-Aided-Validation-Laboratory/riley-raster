pub const SimdMode = enum {
    off,
    on,
};

pub const Config = struct {
    simd: SimdMode = .on,
    simd_vector_width: comptime_int = 8,
    precision: type = f64,
};

pub const config = Config{
    .simd = .on,
    .simd_vector_width = 8,
    .precision = f64,
};
