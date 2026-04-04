pub const CoordSpace = @import("geometrykernels.zig").CoordSpace;

pub inline fn recordDepth(
    ctx_perf: anytype,
    global_subx: usize,
    global_suby: usize,
    sub_pixel_z: f64,
) void {
    if (@TypeOf(ctx_perf).mode == .perf) {
        ctx_perf.recordDepth(global_subx, global_suby, 1.0 / sub_pixel_z);
    }
}
