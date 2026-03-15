const std = @import("std");
const tests = @import("common/tests.zig");

const REL_TOL: f64 = 1e-9;
const ABS_TOL: f64 = 1e-9;

test "Gold Multimesh Suite" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    try tests.runMultimeshTest(allocator, io, REL_TOL, ABS_TOL);
}
