// Generates only shaderpipe-specific gold images for review. Existing gold
// directories are never touched by this program.
const std = @import("std");
const basic = @import("tests/test_basic_shaderpipe.zig");
const full = @import("tests/test_full_shaderpipe.zig");

pub fn main(init: std.process.Init) !void {
    try basic.generateGold(init.gpa, init.io);
    try full.generateGold(init.gpa, init.io);
}
