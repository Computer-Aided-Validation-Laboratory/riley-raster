const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;

pub fn Pixel(comptime T: type, comptime channels: usize) type {
    return struct {
        channels: [channels]T,
    };
}

pub fn Texture(comptime T: type, comptime channels: usize) type {
    return struct {
        const Self = @This();
        const P = Pixel(T, channels);

        pixels: []P,
        rows_n: usize,
        cols_n: usize,

        pub fn init(allocator: std.mem.Allocator, rows: usize, cols: usize) !Self {
            const pixels = try allocator.alloc(P, rows * cols);
            return Self{
                .pixels = pixels,
                .rows_n = rows,
                .cols_n = cols,
            };
        }

        pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
            allocator.free(self.pixels);
        }

        pub fn getPixel(self: Self, row: usize, col: usize) P {
            assert(row < self.rows_n);
            assert(col < self.cols_n);
            return self.pixels[row * self.cols_n + col];
        }

        pub fn setPixel(self: *Self, row: usize, col: usize, pixel: P) void {
            assert(row < self.rows_n);
            assert(col < self.cols_n);
            self.pixels[row * self.cols_n + col] = pixel;
        }

        pub fn saveCSV(self: *const Self,
                       io: std.Io, 
                       out_dir: std.Io.Dir, 
                       file_name: []const u8) !void {
                       
            const csv_file = try out_dir.createFile(io, file_name, .{});
            defer csv_file.close(io);

            var write_buf: [4096]u8 = undefined;
            var file_writer = csv_file.writer(io, &write_buf);
            const writer = &file_writer.interface;

            for (0..self.rows_n) |rr| {
                for (0..self.cols_n) |cc| {
                    const px = self.getPixel(rr, cc);
                    for (0..channels) |ch| {
                        try writer.print("{d}", .{px.channels[ch]});
                        if (ch < channels - 1) {
                            try writer.writeAll(":");
                        }
                    }
                    try writer.writeAll(",");
                }
                try writer.print("\n",.{});
            }
            try writer.flush();
        }
    };
}

pub fn TextureTiled(comptime T: type, comptime channels: usize, comptime TileSize: usize) type {
    return struct {
        const Self = @This();
        const P = Pixel(T, channels);

        // Data format: [tile_row][tile_col][pixel_row][pixel_col]
        // Following NDArray inspiration with strides.
        pixels: []P,
        rows_n: usize,
        cols_n: usize,
        tiles_rows: usize,
        tiles_cols: usize,
        strides: [4]usize,

        pub fn init(allocator: std.mem.Allocator, rows: usize, cols: usize) !Self {
            const tiles_rows = (rows + TileSize - 1) / TileSize;
            const tiles_cols = (cols + TileSize - 1) / TileSize;
            const total_pixels = tiles_rows * tiles_cols * TileSize * TileSize;
            
            const pixels = try allocator.alloc(P, total_pixels);
            @memset(pixels, std.mem.zeroes(P));

            // calc strides (row-major order for the 4D array)
            const s3 = 1; // pixel_col stride
            const s2 = TileSize * s3; // pixel_row stride
            const s1 = TileSize * s2; // tile_col stride
            const s0 = tiles_cols * s1; // tile_row stride

            return Self{
                .pixels = pixels,
                .rows_n = rows,
                .cols_n = cols,
                .tiles_rows = tiles_rows,
                .tiles_cols = tiles_cols,
                .strides = [4]usize{s0, s1, s2, s3},
            };
        }

        pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
            allocator.free(self.pixels);
        }

        pub fn initFromTexture(allocator: std.mem.Allocator, source: anytype) !Self {
            var self = try Self.init(allocator, source.rows_n, source.cols_n);
            errdefer self.deinit(allocator);

            for (0..source.rows_n) |r| {
                for (0..source.cols_n) |c| {
                    self.setPixel(r, c, source.getPixel(r, c));
                }
            }
            return self;
        }

        pub fn getPixel(self: Self, row: usize, col: usize) P {
            assert(row < self.rows_n);
            assert(col < self.cols_n);

            const tr = row / TileSize;
            const tc = col / TileSize;
            const pr = row % TileSize;
            const pc = col % TileSize;

            const flat_idx = tr * self.strides[0] + 
                             tc * self.strides[1] + 
                             pr * self.strides[2] + 
                             pc * self.strides[3];
            
            return self.pixels[flat_idx];
        }

        pub fn setPixel(self: *Self, row: usize, col: usize, pixel: P) void {
            assert(row < self.rows_n);
            assert(col < self.cols_n);

            const tr = row / TileSize;
            const tc = col / TileSize;
            const pr = row % TileSize;
            const pc = col % TileSize;

            const flat_idx = tr * self.strides[0] + 
                             tc * self.strides[1] + 
                             pr * self.strides[2] + 
                             pc * self.strides[3];
            
            self.pixels[flat_idx] = pixel;
        }

        pub fn getTile(self: Self, tile_row: usize, tile_col: usize) []P {
            assert(tile_row < self.tiles_rows);
            assert(tile_col < self.tiles_cols);

            const start = tile_row * self.strides[0] + tile_col * self.strides[1];
            const end = start + TileSize * TileSize;
            return self.pixels[start..end];
        }
    };
}

pub fn loadBMP(allocator: std.mem.Allocator, io: std.Io, path: []const u8, comptime T: type, comptime channels: usize) !Texture(T, channels) {
    const cwd = std.Io.Dir.cwd();
    const file = try cwd.openFile(io, path, .{});
    defer file.close(io);

    var read_buf: [4096]u8 = undefined;
    var file_reader = file.reader(io, &read_buf);
    const reader = &file_reader.interface;

    var header: [14]u8 = undefined;
    try reader.readSliceAll(&header);
    if (!std.mem.eql(u8, header[0..2], "BM")) return error.NotABMP;

    const offset = std.mem.readInt(u32, header[10..14], .little);

    const dib_size = try reader.takeInt(u32, .little);

    var width: i32 = 0;
    var height: i32 = 0;
    var bit_count: u16 = 0;

    if (dib_size >= 40) {
        width = try reader.takeInt(i32, .little);
        height = try reader.takeInt(i32, .little);
        _ = try reader.takeInt(u16, .little); // planes
        bit_count = try reader.takeInt(u16, .little);
        const compression = try reader.takeInt(u32, .little);
        if (compression != 0) return error.CompressionNotSupported;
        // Skip rest of DIB header
        try file_reader.seekBy(@as(i64, @intCast(dib_size)) - 20);
    } else {
        return error.UnsupportedDIBHeader;
    }

    const abs_height = @as(usize, @intCast(@abs(height)));
    const abs_width = @as(usize, @intCast(@abs(width)));

    var texture = try Texture(T, channels).init(allocator, abs_height, abs_width);
    errdefer texture.deinit(allocator);

    if (bit_count == 24) {
        try file_reader.seekTo(offset);
        const row_padding = (4 - (abs_width * 3) % 4) % 4;
        for (0..abs_height) |y| {
            const r = if (height > 0) abs_height - 1 - y else y;
            for (0..abs_width) |x| {
                var bgr: [3]u8 = undefined;
                try reader.readSliceAll(&bgr);
                
                var px: Pixel(T, channels) = undefined;
                if (channels == 3) {
                    px.channels[0] = convertValue(T, bgr[2]); // R
                    px.channels[1] = convertValue(T, bgr[1]); // G
                    px.channels[2] = convertValue(T, bgr[0]); // B
                } else if (channels == 1) {
                    const val = 0.299 * @as(f64, @floatFromInt(bgr[2])) + 0.587 * @as(f64, @floatFromInt(bgr[1])) + 0.114 * @as(f64, @floatFromInt(bgr[0]));
                    px.channels[0] = convertValue(T, val);
                }
                texture.setPixel(r, x, px);
            }
            try file_reader.seekBy(@intCast(row_padding));
        }
    } else if (bit_count == 8) {
        try file_reader.seekTo(14 + dib_size);
        const palette_size = (offset - (14 + dib_size)) / 4;
        const palette = try allocator.alloc([4]u8, palette_size);
        defer allocator.free(palette);
        for (0..palette_size) |i| {
            try reader.readSliceAll(&palette[i]);
        }

        try file_reader.seekTo(offset);
        const row_padding = (4 - abs_width % 4) % 4;
        for (0..abs_height) |y| {
            const r = if (height > 0) abs_height - 1 - y else y;
            for (0..abs_width) |x| {
                const index = try reader.takeByte();
                const color = palette[index];
                var px: Pixel(T, channels) = undefined;
                if (channels == 3) {
                    px.channels[0] = convertValue(T, color[2]); // R
                    px.channels[1] = convertValue(T, color[1]); // G
                    px.channels[2] = convertValue(T, color[0]); // B
                } else if (channels == 1) {
                    const val = 0.299 * @as(f64, @floatFromInt(color[2])) + 0.587 * @as(f64, @floatFromInt(color[1])) + 0.114 * @as(f64, @floatFromInt(color[0]));
                    px.channels[0] = convertValue(T, val);
                }
                texture.setPixel(r, x, px);
            }
            try file_reader.seekBy(@intCast(row_padding));
        }
    } else {
        return error.UnsupportedBitCount;
    }

    return texture;
}

pub fn loadTIFF(allocator: std.mem.Allocator, io: std.Io, path: []const u8, comptime T: type, comptime channels: usize) !Texture(T, channels) {
    _ = io;
    const RTLD_LAZY = 1;
    const handle = dlopen("/usr/lib/x86_64-linux-gnu/libtiff.so.6", RTLD_LAZY) orelse return error.DlOpenFailed;
    defer _ = dlclose(handle);

    const TIFFOpen = @as(*const fn ([*:0]const u8, [*:0]const u8) callconv(.c) ?*anyopaque, @ptrCast(dlsym(handle, "TIFFOpen") orelse return error.SymbolNotFound));
    const TIFFClose = @as(*const fn (*anyopaque) callconv(.c) void, @ptrCast(dlsym(handle, "TIFFClose") orelse return error.SymbolNotFound));
    const TIFFGetField = @as(*const fn (*anyopaque, u32, ...) callconv(.c) c_int, @ptrCast(dlsym(handle, "TIFFGetField") orelse return error.SymbolNotFound));
    const TIFFReadRGBAImage = @as(*const fn (*anyopaque, u32, u32, [*]u32, c_int) callconv(.c) c_int, @ptrCast(dlsym(handle, "TIFFReadRGBAImage") orelse return error.SymbolNotFound));

    const path_c = try allocator.dupeZ(u8, path);
    defer allocator.free(path_c);

    const tif = TIFFOpen(path_c, "r") orelse return error.OpenFailed;
    defer TIFFClose(tif);

    var w: u32 = 0;
    var h: u32 = 0;
    _ = TIFFGetField(tif, @as(u32, 256), &w);
    _ = TIFFGetField(tif, @as(u32, 257), &h);

    const pixel_count = w * h;
    const raster = try allocator.alloc(u32, pixel_count);
    defer allocator.free(raster);

    if (TIFFReadRGBAImage(tif, w, h, raster.ptr, 0) == 0) return error.ReadFailed;

    var texture = try Texture(T, channels).init(allocator, h, w);
    errdefer texture.deinit(allocator);

    for (0..h) |row| {
        const src_row = (h - 1 - row) * w;
        const dst_row = row * w;
        for (0..w) |col| {
            const pixel = raster[src_row + col];
            const r = @as(u8, @intCast(pixel & 0xFF));
            const g = @as(u8, @intCast((pixel >> 8) & 0xFF));
            const b = @as(u8, @intCast((pixel >> 16) & 0xFF));
            
            var px: Pixel(T, channels) = undefined;
            if (channels == 3) {
                px.channels[0] = convertValue(T, r);
                px.channels[1] = convertValue(T, g);
                px.channels[2] = convertValue(T, b);
            } else if (channels == 1) {
                const val = 0.299 * @as(f64, @floatFromInt(r)) + 0.587 * @as(f64, @floatFromInt(g)) + 0.114 * @as(f64, @floatFromInt(b));
                px.channels[0] = convertValue(T, val);
            }
            texture.pixels[dst_row + col] = px;
        }
    }

    return texture;
}

fn convertValue(comptime T: type, val: anytype) T {
    const val_f64 = switch (@typeInfo(@TypeOf(val))) {
        .int => @as(f64, @floatFromInt(val)),
        .float => @as(f64, val),
        else => @compileError("Unsupported type"),
    };

    switch (@typeInfo(T)) {
        .int => return @as(T, @intFromFloat(val_f64)),
        .float => return @as(T, @floatCast(val_f64)),
        else => @compileError("Unsupported type"),
    }
}

extern "c" fn dlopen(filename: [*:0]const u8, flags: c_int) ?*anyopaque;
extern "c" fn dlsym(handle: ?*anyopaque, symbol: [*:0]const u8) ?*anyopaque;
extern "c" fn dlclose(handle: ?*anyopaque) c_int;

const testing = std.testing;

test "Texture BMP load and CSV save" {
    const allocator = testing.allocator;
    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();
    const path = "texture/speckle.bmp";
    
    var texture = try loadBMP(allocator, io, path, u8, 1);
    defer texture.deinit(allocator);

    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, "raster-out", .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    cwd.createDir(io, "raster-out/test", .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    var out_dir = try cwd.openDir(io, "raster-out/test", .{});
    defer out_dir.close(io);

    try texture.saveCSV(io, out_dir, "speckle_bmp.csv");
}

test "Texture TIFF load and CSV save" {
    const allocator = testing.allocator;
    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();
    const path = "texture/speckle.tiff";
    
    var texture = try loadTIFF(allocator, io, path, u8, 1);
    defer texture.deinit(allocator);

    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, "raster-out", .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    cwd.createDir(io, "raster-out/test", .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    var out_dir = try cwd.openDir(io, "raster-out/test", .{});
    defer out_dir.close(io);

    try texture.saveCSV(io, out_dir, "speckle_tiff.csv");
}

test "Compare BMP and TIFF load" {
    const allocator = testing.allocator;
    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();
    
    var tex_bmp = try loadBMP(allocator, io, "texture/speckle.bmp", u8, 1);
    defer tex_bmp.deinit(allocator);

    var tex_tiff = try loadTIFF(allocator, io, "texture/speckle.tiff", u8, 1);
    defer tex_tiff.deinit(allocator);

    try testing.expectEqual(tex_bmp.rows_n, tex_tiff.rows_n);
    try testing.expectEqual(tex_bmp.cols_n, tex_tiff.cols_n);

    for (0..tex_bmp.pixels.len) |i| {
        const p1 = tex_bmp.pixels[i].channels[0];
        const p2 = tex_tiff.pixels[i].channels[0];
        if (p1 > p2) {
            try testing.expect(p1 - p2 <= 1);
        } else {
            try testing.expect(p2 - p1 <= 1);
        }
    }
}

test "TextureTiled verification" {
    const allocator = testing.allocator;
    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();
    
    const tex_bmp = try loadBMP(allocator, io, "texture/speckle.bmp", u8, 1);
    defer tex_bmp.deinit(allocator);

    var tex_tiled = try TextureTiled(u8, 1, 32).initFromTexture(allocator, tex_bmp);
    defer tex_tiled.deinit(allocator);

    try testing.expectEqual(tex_bmp.rows_n, tex_tiled.rows_n);
    try testing.expectEqual(tex_bmp.cols_n, tex_tiled.cols_n);

    // Check random pixels
    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();

    for (0..100) |_| {
        const r = random.uintAtMost(usize, tex_bmp.rows_n - 1);
        const c = random.uintAtMost(usize, tex_bmp.cols_n - 1);
        
        const p1 = tex_bmp.getPixel(r, c);
        const p2 = tex_tiled.getPixel(r, c);
        try testing.expectEqual(p1.channels[0], p2.channels[0]);
    }

    // Check a tile
    const tile = tex_tiled.getTile(0, 0);
    try testing.expectEqual(tile.len, 32 * 32);
    for (0..32) |r| {
        for (0..32) |c| {
            const p_tile = tile[r * 32 + c];
            const p_orig = tex_bmp.getPixel(r, c);
            try testing.expectEqual(p_orig.channels[0], p_tile.channels[0]);
        }
    }
}
