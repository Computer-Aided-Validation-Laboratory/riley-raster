const std = @import("std");
const c = @import("riley_c");
const abi = @import("riley/zig/c-riley.zig");

extern fn rileyTestAbiLayout(index: usize) usize;

test "C speckle constants match the Zig ABI" {
    inline for (.{
        "RILEY_SHADER_SPECKLE",
        "RILEY_SPECKLE_DISK",
        "RILEY_SPECKLE_GAUSSIAN",
        "RILEY_SPECKLE_PERLIN",
        "RILEY_SPECKLE_BITS_NONE",
        "RILEY_SPECKLE_DEFAULT_SEED",
        "RILEY_PERLIN_DEFAULT_TRANSITION_WIDTH",
    }) |name| {
        const expected = @field(abi, name);
        try std.testing.expectEqual(expected, @as(@TypeOf(expected), @field(c, name)));
    }
}

test "C compiler and Zig agree on every ABI descriptor layout" {
    var index: usize = 0;
    inline for (@typeInfo(abi).@"struct".decl_names) |name| {
        if (comptime std.mem.startsWith(u8, name, "C") and
            @TypeOf(@field(abi, name)) == type)
        {
            const T = @field(abi, name);
            try std.testing.expectEqual(@sizeOf(T), rileyTestAbiLayout(index));
            index += 1;
            try std.testing.expectEqual(@alignOf(T), rileyTestAbiLayout(index));
            index += 1;
            const info = @typeInfo(T);
            const field_names = switch (info) {
                .@"struct" => |s| s.field_names,
                .@"union" => |u| u.field_names,
                else => unreachable,
            };
            inline for (field_names) |field_name| {
                const offset = if (comptime info == .@"union") 0 else @offsetOf(T, field_name);
                try std.testing.expectEqual(offset, rileyTestAbiLayout(index));
                index += 1;
            }
        }
    }
}
