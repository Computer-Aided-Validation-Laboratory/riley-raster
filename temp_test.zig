const std = @import("std");
const other = struct {
    pub const A = 1;
};
const B = other.B; // B does not exist in 'other'
pub fn main() void {
    std.debug.print("Hello\n", .{});
}
