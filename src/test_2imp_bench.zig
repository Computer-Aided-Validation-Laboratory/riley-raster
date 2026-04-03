const common = @import("common/test2imp.zig");

pub fn main() !void {
    try common.run(.bench);
}

test "2imp bench" {
    try common.run(.bench);
}
