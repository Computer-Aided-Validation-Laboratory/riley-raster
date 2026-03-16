const std = @import("std");
const common = @import("common/tests.zig");

const REL_TOL: f64 = 1e-9;
const ABS_TOL: f64 = 1e-9;

test "Gold Multimesh Suite" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    try common.runMultimeshTest(allocator, io, REL_TOL, ABS_TOL);
    try common.runMultimeshMixedTest(allocator, io, REL_TOL, ABS_TOL);
}
