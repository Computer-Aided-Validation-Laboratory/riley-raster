const common = @import("test_2imp_common.zig");

pub fn main() !void {
    try common.run(.bench);
}

test "2imp bench" {
    try common.run(.bench);
}
