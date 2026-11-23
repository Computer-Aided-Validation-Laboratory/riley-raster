//! Argument handling only; the tutorials own all scene and render configuration.
const std = @import("std");

const flags = std.StaticStringMap(enum { pattern, output, width, height }).initComptime(.{
    .{ "--pattern", .pattern },
    .{ "--output", .output },
    .{ "--width", .width },
    .{ "--height", .height },
});

pub fn Options(comptime Pattern: type) type {
    return struct {
        pattern: Pattern = .disk,
        out_dir: []const u8,
    };
}

/// Returns null after printing help. Only demos supplying dimensions accept size flags.
pub fn parse(
    comptime Pattern: type,
    io: std.Io,
    args: []const []const u8,
    usage: []const u8,
    default_out_dir: []const u8,
    pixels_num: ?*[2]u32,
) !?Options(Pattern) {
    var options: Options(Pattern) = .{ .out_dir = default_out_dir };
    var ii: usize = 1;
    while (ii < args.len) : (ii += 2) {
        const flag = args[ii];
        if (std.mem.eql(u8, flag, "--help") or std.mem.eql(u8, flag, "-h")) {
            try std.Io.File.stdout().writeStreamingAll(io, usage);
            return null;
        }
        const option = flags.get(flag) orelse reject(io, usage, flag, "unknown option");
        if ((option == .width or option == .height) and pixels_num == null)
            reject(io, usage, flag, "unknown option");
        if (ii + 1 >= args.len or std.mem.startsWith(u8, args[ii + 1], "--") or
            std.mem.eql(u8, args[ii + 1], "-h"))
            reject(io, usage, flag, "missing value");
        const value = args[ii + 1];
        switch (option) {
            .pattern => options.pattern = std.meta.stringToEnum(Pattern, value) orelse
                reject(io, usage, flag, "expected disk, gaussian, or perlin"),
            .output => {
                if (value.len == 0) reject(io, usage, flag, "expected a non-empty directory");
                options.out_dir = value;
            },
            .width, .height => {
                const count = std.fmt.parseInt(u32, value, 10) catch
                    reject(io, usage, flag, "expected a positive integer");
                if (count == 0) reject(io, usage, flag, "expected a positive integer");
                pixels_num.?[if (option == .width) 0 else 1] = count;
            },
        }
    }
    return options;
}

pub fn reject(io: std.Io, usage: []const u8, flag: []const u8, message: []const u8) noreturn {
    var buffer: [512]u8 = undefined;
    var stderr = std.Io.File.stderr().writerStreaming(io, &buffer);
    stderr.interface.print("error: {s}: {s}\n{s}", .{ flag, message, usage }) catch
        std.process.exit(1);
    stderr.interface.flush() catch std.process.exit(1);
    std.process.exit(1);
}
