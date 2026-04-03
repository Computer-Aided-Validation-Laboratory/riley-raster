const std = @import("std");
extern fn system(command: [*:0]const u8) c_int;

const buildconfig_path = "src/zigraster/zig/buildconfig.zig";

pub const TestKind = enum {
    gold,
    bench,
};

fn modeConfigText(mode_name: []const u8) []const u8 {
    return if (std.mem.eql(u8, mode_name, "on"))
        \\pub const SimdMode = enum {
        \\    off,
        \\    on,
        \\};
        \\
        \\pub const Config = struct {
        \\    simd: SimdMode = .on,
        \\    simd_vector_width: comptime_int = 8,
        \\    precision: type = f64,
        \\};
        \\
        \\pub const config = Config{
        \\    .simd = .on,
        \\    .simd_vector_width = 8,
        \\    .precision = f64,
        \\};
    else
        \\pub const SimdMode = enum {
        \\    off,
        \\    on,
        \\};
        \\
        \\pub const Config = struct {
        \\    simd: SimdMode = .on,
        \\    simd_vector_width: comptime_int = 8,
        \\    precision: type = f64,
        \\};
        \\
        \\pub const config = Config{
        \\    .simd = .off,
        \\    .simd_vector_width = 8,
        \\    .precision = f64,
        \\};
    ;
}

fn targetCommand(kind: TestKind) [:0]const u8 {
    return switch (kind) {
        .gold => "zig test -lc -O ReleaseSafe ./src/test_gold_all.zig",
        .bench => "zig test -lc -O ReleaseSafe ./src/test_bench.zig",
    };
}

pub fn run(kind: TestKind) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();
    const original_text = try cwd.readFileAlloc(
        io,
        buildconfig_path,
        allocator,
        .limited(1024 * 1024),
    );
    defer allocator.free(original_text);

    defer cwd.writeFile(io, .{
        .sub_path = buildconfig_path,
        .data = original_text,
    }) catch {};

    const modes = [_][]const u8{ "off", "on" };

    for (modes) |mode_name| {
        try cwd.writeFile(io, .{
            .sub_path = buildconfig_path,
            .data = modeConfigText(mode_name),
        });

        std.debug.print("Running {s} tests with .simd = .{s}...\n", .{
            @tagName(kind), mode_name,
        });

        const exit_code = system(targetCommand(kind));
        if (exit_code != 0) {
            return error.ChildProcessFailed;
        }
    }
}
