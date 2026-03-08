const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;

const MatSlice = @import("matslice.zig").MatSlice;

pub const ImageFormat = enum {
    csv,
    ppm,
    bmp,
    tiff,
};

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

//------------------------------------------------------------------------------
// MatSlice IO
//------------------------------------------------------------------------------

pub fn saveImage(io: std.Io,
                 out_dir: std.Io.Dir, 
                 file_name_no_ext: []const u8,
                 image: *const MatSlice(f64),
                 format: ImageFormat,
                 bits: u8,
                 ) !void {
                    
    var name_buff: [1024]u8 = undefined;                
       
    switch (format) {
        .csv => {
            const ext = ".csv";
            const file_name_ext = try std.fmt.bufPrint(name_buff[0..], 
                                                       "{s}{s}", 
                                                       .{ file_name_no_ext, ext });     
            try saveCSV(io,out_dir,file_name_ext,image,bits);
        },
        .ppm => {
            const ext = ".ppm";
            const file_name_ext = try std.fmt.bufPrint(name_buff[0..], 
                                                       "{s}{s}", 
                                                      .{ file_name_no_ext, ext });
            try savePPM(io,out_dir,file_name_ext,image,bits);
        },
        .bmp => {
            const ext = ".bmp";
            const file_name_ext = try std.fmt.bufPrint(name_buff[0..], 
                                                       "{s}{s}", 
                                                      .{ file_name_no_ext, ext });
            try saveBMP(io,out_dir,file_name_ext,image,bits);
        },
        .tiff => {
            const ext = ".tiff";
            const file_name_ext = try std.fmt.bufPrint(name_buff[0..], 
                                                       "{s}{s}", 
                                                      .{ file_name_no_ext, ext });
            try saveTIFF(io,out_dir,file_name_ext,image,bits);
        },
    }
}

pub fn savePPM(io: std.Io,
               out_dir: std.Io.Dir, 
               file_name: []const u8,
               image: *const MatSlice(f64),
               bits: u8,
               ) !void {

    const ppm_file: std.Io.File = try out_dir.createFile(io, file_name, .{});
    defer ppm_file.close(io);

    var write_buf: [4096]u8 = undefined;
    var file_writer = ppm_file.writer(io, &write_buf);
    const writer = &file_writer.interface;

    const max_val: u32 = (@as(u32, 1) << @as(u5, @intCast(bits))) - 1;
    try writer.print("P3\n{d} {d}\n{d}\n", .{ image.cols_n, image.rows_n, max_val});

    const px_min: f64 = std.mem.min(f64,image.elems);
    const px_max: f64 = std.mem.max(f64,image.elems);
    const px_rng: f64 = if (px_max > px_min) px_max - px_min else 1.0;
    const scale = @as(f64, @floatFromInt(max_val));

    for (0..image.rows_n) |rr| {
        for (0..image.cols_n) |cc| {
            const px_scaled = @as(u32,
                @intFromFloat((image.get(rr,cc) - px_min)/px_rng * scale)
            );  
            try writer.print("{d} {d} {d}\n", .{px_scaled,px_scaled,px_scaled});
        }
    }

    try writer.flush();   
}

pub fn saveCSV(io: std.Io,
               out_dir: std.Io.Dir, 
               file_name: []const u8,
               image: *const MatSlice(f64),
               bits: u8,
               ) !void {
    _ = bits; // CSV ignores bit depth as it saves raw floats
    const csv_file = try out_dir.createFile(io, file_name, .{});
    defer csv_file.close(io);

    var write_buf: [4096]u8 = undefined;
    var file_writer = csv_file.writer(io,&write_buf);
    const writer = &file_writer.interface;

    for (0..image.rows_n) |rr| {
        for (0..image.cols_n) |cc| {
            try writer.print("{d},", .{image.get(rr, cc)});
        }
        try writer.print("\n",.{});
    }

    try writer.flush();
}

pub fn saveBMP(io: std.Io, 
               out_dir: std.Io.Dir, 
               file_name: []const u8, 
               image: *const MatSlice(f64), 
               bits: u8) !void {

    _ = bits; // BMP currently only supports 8-bit grayscale (as 24-bit RGB)
    const file = try out_dir.createFile(io, file_name, .{});
    defer file.close(io);

    var write_buf: [4096]u8 = undefined;
    var file_writer = file.writer(io, &write_buf);
    const writer = &file_writer.interface;

    const width = @as(u32, @intCast(image.cols_n));
    const height = @as(u32, @intCast(image.rows_n));
    const row_padding = (4 - (width * 3) % 4) % 4;
    const row_size = width * 3 + row_padding;
    const data_size = row_size * height;
    const offset = 14 + 40;
    const file_size = offset + data_size;

    // Bitmap File Header (14 bytes)
    try writer.writeAll("BM");
    try writer.writeInt(u32, file_size, .little);
    try writer.writeInt(u16, 0, .little); // Reserved 1
    try writer.writeInt(u16, 0, .little); // Reserved 2
    try writer.writeInt(u32, offset, .little);

    // DIB Header (BITMAPINFOHEADER, 40 bytes)
    try writer.writeInt(u32, 40, .little);
    try writer.writeInt(i32, @intCast(width), .little);
    try writer.writeInt(i32, @intCast(height), .little); // Positive = bottom-up
    try writer.writeInt(u16, 1, .little); // Planes
    try writer.writeInt(u16, 24, .little); // Bits per pixel
    try writer.writeInt(u32, 0, .little); // Compression (none)
    try writer.writeInt(u32, data_size, .little);
    try writer.writeInt(i32, 2835, .little); // 72 DPI (ppm)
    try writer.writeInt(i32, 2835, .little); // 72 DPI (ppm)
    try writer.writeInt(u32, 0, .little); // Colors in palette
    try writer.writeInt(u32, 0, .little); // Important colors

    const px_min = std.mem.min(f64, image.elems);
    const px_max = std.mem.max(f64, image.elems);
    const px_rng = if (px_max > px_min) px_max - px_min else 1.0;

    // BMP data is bottom-up
    var r: usize = image.rows_n;
    while (r > 0) {
        r -= 1;
        for (0..image.cols_n) |c| {
            const val = @as(u8, @intFromFloat(((image.get(r, c) - px_min) / px_rng) * 255.0));
            // BGR order
            try writer.writeByte(val); // Blue
            try writer.writeByte(val); // Green
            try writer.writeByte(val); // Red
        }
        for (0..row_padding) |_| try writer.writeByte(0);
    }
    try writer.flush();
}

pub fn saveTIFF(io: std.Io, 
                out_dir: std.Io.Dir, 
                file_name: []const u8, 
                image: *const MatSlice(f64), 
                bits: u8) !void {
                
    const file = try out_dir.createFile(io, file_name, .{});
    defer file.close(io);

    var write_buf: [4096]u8 = undefined;
    var file_writer = file.writer(io, &write_buf);
    const writer = &file_writer.interface;

    const width = @as(u32, @intCast(image.cols_n));
    const height = @as(u32, @intCast(image.rows_n));
    const pixel_data_offset: u32 = 8; // Header is 8 bytes
    const bytes_per_pixel: u32 = if (bits == 16) 2 else 1;
    const pixel_data_size = width * height * bytes_per_pixel;
    const ifd_offset = pixel_data_offset + pixel_data_size;

    // 1. Header (8 bytes)
    try writer.writeAll("II"); // Little Endian
    try writer.writeInt(u16, 42, .little); // Magic number
    try writer.writeInt(u32, ifd_offset, .little);

    // 2. Pixel Data (Grayscale)
    const px_min = std.mem.min(f64, image.elems);
    const px_max = std.mem.max(f64, image.elems);
    const px_rng = if (px_max > px_min) px_max - px_min else 1.0;

    if (bits == 16) {
        for (0..image.rows_n) |r| {
            for (0..image.cols_n) |c| {
                const val_f = ((image.get(r, c) - px_min) / px_rng) * 65535.0;
                const val = @as(u16,@intFromFloat(val_f));
                try writer.writeInt(u16, val, .little);
            }
        }
    } else {
        for (0..image.rows_n) |r| {
            for (0..image.cols_n) |c| {
                const val_f = ((image.get(r, c) - px_min) / px_rng) * 255.0;
                const val = @as(u8, @intFromFloat(val_f));
                try writer.writeByte(val);
            }
        }
    }

    // 3. Image File Directory (IFD)
    // We'll write 10 tags
    const num_tags: u16 = 10;
    try writer.writeInt(u16, num_tags, .little);

    // Helper to write a TIFF tag
    const Tag = struct {
        id: u16, type: u16, count: u32, value: u32,
        fn write(self: @This(), w: anytype) !void {
            try w.writeInt(u16, self.id, .little);
            try w.writeInt(u16, self.type, .little);
            try w.writeInt(u32, self.count, .little);
            try w.writeInt(u32, self.value, .little);
        }
    };

    // ID: 256 (Width), Type: 3 (Short), Count: 1
    try (Tag{ .id = 256, .type = 3, .count = 1, .value = width }).write(writer);
    // ID: 257 (Length/Height), Type: 3 (Short), Count: 1
    try (Tag{ .id = 257, .type = 3, .count = 1, .value = height }).write(writer);
    // ID: 258 (BitsPerSample), Type: 3 (Short), Count: 1
    try (Tag{ .id = 258, .type = 3, .count = 1, .value = bits }).write(writer);
    // ID: 259 (Compression), Type: 3 (Short), Count: 1, Value: 1 (None)
    try (Tag{ .id = 259, .type = 3, .count = 1, .value = 1 }).write(writer);
    // ID: 262 (PhotometricInterpretation), Type: 3 (Short), Count: 1, Value: 1 (BlackIsZero)
    try (Tag{ .id = 262, .type = 3, .count = 1, .value = 1 }).write(writer);
    // ID: 273 (StripOffsets), Type: 4 (Long), Count: 1
    try (Tag{ .id = 273, .type = 4, .count = 1, .value = pixel_data_offset }).write(writer);
    // ID: 277 (SamplesPerPixel), Type: 3 (Short), Count: 1
    try (Tag{ .id = 277, .type = 3, .count = 1, .value = 1 }).write(writer);
    // ID: 278 (RowsPerStrip), Type: 3 (Short), Count: 1
    try (Tag{ .id = 278, .type = 3, .count = 1, .value = height }).write(writer);
    // ID: 279 (StripByteCounts), Type: 4 (Long), Count: 1
    try (Tag{ .id = 279, .type = 4, .count = 1, .value = pixel_data_size }).write(writer);
    // ID: 282 (XResolution), Type: 5 (Rational) - simplified: just use long 72
    // For simplicity, we skip complex rationals and just set min required tags correctly.
    // Let's use ResolutionUnit (296) instead of XRes for minimum compliance.
    try (Tag{ .id = 296, .type = 3, .count = 1, .value = 2 }).write(writer); // Inch

    try writer.writeInt(u32, 0, .little); // End of IFD
    try writer.flush();
}

//------------------------------------------------------------------------------
// Texture IO
//------------------------------------------------------------------------------

pub fn loadBMP(allocator: std.mem.Allocator, 
               io: std.Io, 
               path: []const u8, 
               comptime T: type, 
               comptime channels: usize) !Texture(T, channels) {

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
                    const val = 0.299 * @as(f64, @floatFromInt(bgr[2])) 
                              + 0.587 * @as(f64, @floatFromInt(bgr[1])) 
                              + 0.114 * @as(f64, @floatFromInt(bgr[0]));
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
                    const val = 0.299 * @as(f64, @floatFromInt(color[2])) 
                              + 0.587 * @as(f64, @floatFromInt(color[1])) 
                              + 0.114 * @as(f64, @floatFromInt(color[0]));
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

// TODO: try and fix this hard coded dynamic library mess.
pub fn loadTIFF(allocator: std.mem.Allocator, 
                io: std.Io, 
                path: []const u8, 
                comptime T: type, 
                comptime channels: usize) !Texture(T, channels) {
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
                const val = 0.299 * @as(f64, @floatFromInt(r)) 
                          + 0.587 * @as(f64, @floatFromInt(g)) 
                          + 0.114 * @as(f64, @floatFromInt(b));
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
