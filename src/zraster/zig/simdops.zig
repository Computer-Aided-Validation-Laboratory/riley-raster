const buildconfig = @import("buildconfig.zig");
const S = buildconfig.SimdWidth;
const VecSF = buildconfig.VecSF;

pub inline fn loadVecSF(subpx_vals: []const f64, start_u: usize) VecSF {
    const lane_vals: [S]f64 = subpx_vals[start_u..][0..S].*;
    return @as(VecSF, lane_vals);
}

pub inline fn storeVecSF(subpx_vals: []f64, start_u: usize, v_vals: VecSF) void {
    const lane_vals: [S]f64 = @as([S]f64, v_vals);
    subpx_vals[start_u..][0..S].* = lane_vals;
}
