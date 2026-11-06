const std = @import("std");
const abi = @import("riley/zig/c-riley.zig");

extern fn rileyTestAbiLayout(index: usize) usize;

test "C compiler and Zig agree on every ABI descriptor layout" {
    var index: usize = 0;
    inline for (comptime std.meta.declarations(abi)) |decl| {
        if (comptime std.mem.startsWith(u8, decl.name, "C") and
            @TypeOf(@field(abi, decl.name)) == type)
        {
            const T = @field(abi, decl.name);
            try std.testing.expectEqual(@sizeOf(T), rileyTestAbiLayout(index));
            index += 1;
            try std.testing.expectEqual(@alignOf(T), rileyTestAbiLayout(index));
            index += 1;
            inline for (comptime std.meta.fields(T)) |field| {
                const offset = if (comptime @typeInfo(T) == .@"union") 0 else @offsetOf(T, field.name);
                try std.testing.expectEqual(offset, rileyTestAbiLayout(index));
                index += 1;
            }
        }
    }
}
