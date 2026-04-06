pub const CoordSpace = @import("geometrykernels.zig").CoordSpace;
const report = @import("report.zig");

pub inline fn recordDepth(
    ctx_perf: anytype,
    global_subx: usize,
    global_suby: usize,
    sub_pixel_z: f64,
) void {
    if (@TypeOf(ctx_perf).mode_tag == .full_stats) {
        report.maybeRecordDepth(ctx_perf, global_subx, global_suby, sub_pixel_z);
    }
}
