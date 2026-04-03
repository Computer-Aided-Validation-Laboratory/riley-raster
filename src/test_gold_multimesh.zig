const std = @import("std");
const common = @import("common/tests.zig");
const tcfg = @import("common/testconfig.zig");

test "Gold Multimesh Suite" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    try common.runMultimeshTest(allocator, io, tcfg.REL_TOL, tcfg.ABS_TOL);
    try common.runMultimeshMixedTest(allocator, io, tcfg.REL_TOL, tcfg.ABS_TOL);
    try common.runMultimeshMixedRGBTest(allocator, io, tcfg.REL_TOL, tcfg.ABS_TOL);
}
