const std = @import("std");
const NDArray = @import("ndarray.zig").NDArray;
const meshio = @import("meshio.zig");

pub const TexMap = struct {
    array: NDArray(f64),
    buffer: []f64,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, node_n: usize) !Self {
        const buffer = try allocator.alloc(f64, node_n * 2);
        @memset(buffer, 0.0);

        const dims = [_]usize{ node_n, 2 }; // u, v

        const array = try NDArray(f64).init(allocator, buffer, dims[0..]);

        return .{
            .array = array,
            .buffer = buffer,
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.array.deinit(allocator);
        allocator.free(self.buffer);
    }

    pub fn getU(self: *const Self, node_idx: usize) f64 {
        return self.array.get(&[_]usize{ node_idx, 0 });
    }

    pub fn getV(self: *const Self, node_idx: usize) f64 {
        return self.array.get(&[_]usize{ node_idx, 1 });
    }

    pub fn getUV(self: *const Self, node_idx: usize) []f64 {
        const start = node_idx * 2;
        return self.buffer[start .. start + 2];
    }

    pub fn setUV(self: *Self, node_idx: usize, u: f64, v: f64) void {
        self.array.set(&[_]usize{ node_idx, 0 }, u);
        self.array.set(&[_]usize{ node_idx, 1 }, v);
    }
};

pub fn loadTexMap(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !TexMap {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const lines = try meshio.readCsvToList(arena_alloc, io, path);
    const node_n = lines.items.len;

    var tex_map = try TexMap.init(allocator, node_n);
    errdefer tex_map.deinit(allocator);

    for (lines.items, 0..) |line, i| {
        var split_iter = std.mem.splitScalar(u8, line, ',');
        const u_str = split_iter.next() orelse return error.InvalidCsvFormat;
        const v_str = split_iter.next() orelse return error.InvalidCsvFormat;

        const u = try std.fmt.parseFloat(f64, std.mem.trim(u8, u_str, " "));
        const v = try std.fmt.parseFloat(f64, std.mem.trim(u8, v_str, " "));

        tex_map.setUV(i, u, v);
    }

    return tex_map;
}

pub fn load_uvs(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !NDArray(f64) {
    const tex_map = try loadTexMap(allocator, io, path);
    return tex_map.array;
}

const testing = std.testing;

test "Load TexMap from tri3_fullscreen/uvs.csv" {
    const allocator = testing.allocator;
    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const path = "data-simple/tri3_fullscreen/uvs.csv";
    var tex_map = try loadTexMap(allocator, io, path);
    defer tex_map.deinit(allocator);

    try testing.expectEqual(@as(usize, 4), tex_map.array.dims[0]);
    
    // First row: 0.4, 0.4
    try testing.expectApproxEqAbs(@as(f64, 0.4), tex_map.getU(0), 1e-8);
    try testing.expectApproxEqAbs(@as(f64, 0.4), tex_map.getV(0), 1e-8);

    // Last row: 0.4, 0.6
    try testing.expectApproxEqAbs(@as(f64, 0.4), tex_map.getU(3), 1e-8);
    try testing.expectApproxEqAbs(@as(f64, 0.6), tex_map.getV(3), 1e-8);

    const uv = tex_map.getUV(0);
    try testing.expectApproxEqAbs(@as(f64, 0.4), uv[0], 1e-8);
    try testing.expectApproxEqAbs(@as(f64, 0.4), uv[1], 1e-8);
}

test "Load TexMap from tri6_fullscreen/uvs.csv" {
    const allocator = testing.allocator;
    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const path = "data-simple/tri6_fullscreen/uvs.csv";
    var tex_map = try loadTexMap(allocator, io, path);
    defer tex_map.deinit(allocator);

    try testing.expectEqual(@as(usize, 9), tex_map.array.dims[0]);
}

test "Load TexMap from tri3_single/uvs.csv" {
    const allocator = testing.allocator;
    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const path = "data-simple/tri3_single/uvs.csv";
    var tex_map = try loadTexMap(allocator, io, path);
    defer tex_map.deinit(allocator);

    try testing.expectEqual(@as(usize, 3), tex_map.array.dims[0]);
}

test "Load TexMap from tri6_single/uvs.csv" {
    const allocator = testing.allocator;
    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const path = "data-simple/tri6_single/uvs.csv";
    var tex_map = try loadTexMap(allocator, io, path);
    defer tex_map.deinit(allocator);

    try testing.expectEqual(@as(usize, 6), tex_map.array.dims[0]);
}
