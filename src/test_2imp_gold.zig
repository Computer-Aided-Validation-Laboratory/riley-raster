const common = @import("common/test2imp.zig");

pub fn main() !void {
    try common.run(.gold);
}

test "2imp gold" {
    try common.run(.gold);
}
