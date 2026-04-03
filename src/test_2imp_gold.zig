const common = @import("test_2imp_common.zig");

pub fn main() !void {
    try common.run(.gold);
}

test "2imp gold" {
    try common.run(.gold);
}
