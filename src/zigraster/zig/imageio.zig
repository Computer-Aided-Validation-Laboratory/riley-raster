const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;

const MatSlice = @import("matslice.zig").MatSlice;
const texops = @import("textureops.zig");
pub const Pixel = texops.Pixel;
pub const Texture = texops.Texture;

pub const ImageFormat = enum {
    csv,
    ppm,
    bmp,
    tiff,
};

//------------------------------------------------------------------------------
// Generic IO
//------------------------------------------------------------------------------

pub fn loadImage(allocator: std.mem.Allocator,
                 io: std.Io,
                 path: []const u8,
                 format: ImageFormat,
                 comptime T: type,
                 comptime channels: usize) !Texture(T, channels) {
    return switch (format) {
        .csv => try loadCSV(allocator, io, path, T, channels),
        .ppm => try loadPPM(allocator, io, path, T, channels),
        .bmp => try loadBMP(allocator, io, path, T, channels),
        .tiff => try loadTIFF(allocator, io, path, T, channels),
    };
}

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

//------------------------------------------------------------------------------
// MatSlice IO
//------------------------------------------------------------------------------

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

pub fn loadPPM(allocator: std.mem.Allocator,
                io: std.Io,
                path: []const u8,
                comptime T: type,
                comptime channels: usize) !Texture(T, channels) {
    const cwd = std.Io.Dir.cwd();
    const file = try cwd.openFile(io, path, .{ .mode = .read_only });
    defer file.close(io);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    var read_buf: [4096]u8 = undefined;
    var file_reader = file.reader(io, &read_buf);
    const reader = &file_reader.interface;

    var header: [2]u8 = undefined;
    try reader.readSliceAll(&header);
    if (!std.mem.eql(u8, &header, "P3")) return error.NotAPPM;

    // Helper to read next token skipping comments
    const readToken = struct {
        fn readToken(r: anytype, a: std.mem.Allocator) ![]const u8 {
            while (true) {
                const char = try r.takeByte();
                if (char == '#') {
                    _ = try r.takeDelimiter('\n');
                    continue;
                }
                if (std.ascii.isWhitespace(char)) continue;
                
                var list: std.ArrayList(u8) = .{};
                try list.append(a, char);
                while (true) {
                    const next_char = r.takeByte() catch |err| switch (err) {
                        error.EndOfStream => break,
                        else => return err,
                    };
                    if (std.ascii.isWhitespace(next_char)) break;
                    if (next_char == '#') {
                        break; 
                    }
                    try list.append(a, next_char);
                }
                return list.toOwnedSlice(a);
            }
        }
    }.readToken;

    const width_str = try readToken(reader, aa);
    const height_str = try readToken(reader, aa);
    const max_val_str = try readToken(reader, aa);

    const width = try std.fmt.parseInt(usize, width_str, 10);
    const height = try std.fmt.parseInt(usize, height_str, 10);
    const max_val = try std.fmt.parseInt(u32, max_val_str, 10);

    var texture = try Texture(T, channels).init(allocator, height, width);
    errdefer texture.deinit(allocator);

    for (0..height) |rr| {
        for (0..width) |cc| {
            var px: Pixel(T, channels) = undefined;
            var rgb: [3]u32 = undefined;
            for (0..3) |i| {
                const val_str = try readToken(reader, aa);
                rgb[i] = try std.fmt.parseInt(u32, val_str, 10);
            }

            if (channels == 3) {
                px.channels[0] = convertValue(T, @as(f64, @floatFromInt(rgb[0])) / @as(f64, @floatFromInt(max_val)) * 255.0);
                px.channels[1] = convertValue(T, @as(f64, @floatFromInt(rgb[1])) / @as(f64, @floatFromInt(max_val)) * 255.0);
                px.channels[2] = convertValue(T, @as(f64, @floatFromInt(rgb[2])) / @as(f64, @floatFromInt(max_val)) * 255.0);
            } else if (channels == 1) {
                const val = 0.299 * @as(f64, @floatFromInt(rgb[0])) 
                          + 0.587 * @as(f64, @floatFromInt(rgb[1])) 
                          + 0.114 * @as(f64, @floatFromInt(rgb[2]));
                px.channels[0] = convertValue(T, val / @as(f64, @floatFromInt(max_val)) * 255.0);
            }
            texture.setPixel(rr, cc, px);
        }
    }

    return texture;
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

pub fn loadCSV(allocator: std.mem.Allocator,
                io: std.Io,
                path: []const u8,
                comptime T: type,
                comptime channels: usize) !Texture(T, channels) {
    const cwd = std.Io.Dir.cwd();
    const file = try cwd.openFile(io, path, .{ .mode = .read_only });
    defer file.close(io);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    var read_buf: [4096]u8 = undefined;
    var file_reader = file.reader(io, &read_buf);
    const reader = &file_reader.interface;

    var lines: std.ArrayList([]const u8) = .{};
    while (try reader.takeDelimiter('\n')) |line| {
        const line_trimmed = std.mem.trim(u8, line, " \r\t");
        if (line_trimmed.len == 0) continue;
        const line_dup = try aa.dupe(u8, line_trimmed);
        try lines.append(aa, line_dup);
    }

    if (lines.items.len == 0) return error.EmptyFile;

    const rows = lines.items.len;
    var first_line_iter = std.mem.splitScalar(u8, lines.items[0], ',');
    var cols: usize = 0;
    while (first_line_iter.next()) |val| {
        if (val.len > 0) cols += 1;
    }

    var texture = try Texture(T, channels).init(allocator, rows, cols);
    errdefer texture.deinit(allocator);

    for (lines.items, 0..) |line, rr| {
        var col_iter = std.mem.splitScalar(u8, line, ',');
        for (0..cols) |cc| {
            const val_str = col_iter.next() orelse break;
            if (val_str.len == 0) continue;
            
            var px: Pixel(T, channels) = undefined;
            var vals_iter = std.mem.splitScalar(u8, val_str, ':');
            for (0..channels) |ch| {
                const ch_val_str = vals_iter.next() orelse "0";
                const val = try std.fmt.parseFloat(f64, std.mem.trim(u8, ch_val_str, " \t\r"));
                px.channels[ch] = convertValue(T, val);
            }
            texture.setPixel(rr, cc, px);
        }
    }

    return texture;
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
    if (bits == 16) {
        for (0..image.rows_n) |r| {
            for (0..image.cols_n) |c| {
                const val = @as(u16,@intFromFloat(image.get(r, c) * 257.0)); // scale 0-255 to 0-65535
                try writer.writeInt(u16, val, .little);
            }
        }
    } else {
        for (0..image.rows_n) |r| {
            for (0..image.cols_n) |c| {
                const val = @as(u8, @intFromFloat(@max(0.0, @min(255.0, image.get(r, c)))));
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
    const file = try cwd.openFile(io, path, .{ .mode = .read_only });
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

// Hand-written TIFF loader for basic grayscale TIFFs (like those saved by saveTIFF)
pub fn loadTIFF(allocator: std.mem.Allocator, 
                io: std.Io, 
                path: []const u8, 
                comptime T: type, 
                comptime channels: usize) !Texture(T, channels) {
    const cwd = std.Io.Dir.cwd();
    const file = try cwd.openFile(io, path, .{ .mode = .read_only });
    defer file.close(io);

    var read_buf: [4096]u8 = undefined;
    var file_reader = file.reader(io, &read_buf);
    const reader = &file_reader.interface;

    var header: [4]u8 = undefined;
    try reader.readSliceAll(&header);
    
    const is_little = if (std.mem.eql(u8, header[0..2], "II")) true 
                      else if (std.mem.eql(u8, header[0..2], "MM")) false
                      else return error.NotATIFF;
    
    const endian: std.builtin.Endian = if (is_little) .little else .big;
    const magic = std.mem.readInt(u16, header[2..4], endian);
    if (magic != 42) return error.InvalidTIFFMagic;

    const ifd_offset = try reader.takeInt(u32, endian);
    try file_reader.seekTo(ifd_offset);

    const num_tags = try reader.takeInt(u16, endian);
    
    var width: u32 = 0;
    var height: u32 = 0;
    var bits_per_sample: u16 = 8;
    var strip_offsets: u32 = 0;
    var samples_per_pixel: u16 = 1;

    for (0..num_tags) |_| {
        const tag_id = try reader.takeInt(u16, endian);
        const tag_type = try reader.takeInt(u16, endian);
        const tag_count = try reader.takeInt(u32, endian);
        const tag_value = try reader.takeInt(u32, endian);

        switch (tag_id) {
            256 => width = if (tag_type == 3) @as(u32, @intCast(tag_value & 0xFFFF)) else tag_value, // Width
            257 => height = if (tag_type == 3) @as(u32, @intCast(tag_value & 0xFFFF)) else tag_value, // Height
            258 => bits_per_sample = @intCast(tag_value & 0xFFFF), // BitsPerSample
            273 => strip_offsets = tag_value, // StripOffsets
            277 => samples_per_pixel = @intCast(tag_value & 0xFFFF), // SamplesPerPixel
            else => {},
        }
        _ = tag_count;
    }

    if (samples_per_pixel != 1) return error.UnsupportedTIFFColorSpace;

    var texture = try Texture(T, channels).init(allocator, height, width);
    errdefer texture.deinit(allocator);

    try file_reader.seekTo(strip_offsets);

    for (0..height) |rr| {
        for (0..width) |cc| {
            var px: Pixel(T, channels) = undefined;
            const val_f: f64 = if (bits_per_sample == 16) 
                @as(f64, @floatFromInt(try reader.takeInt(u16, endian))) / 65535.0 * 255.0
            else 
                @as(f64, @floatFromInt(try reader.takeByte()));

            if (channels == 3) {
                px.channels[0] = convertValue(T, val_f);
                px.channels[1] = convertValue(T, val_f);
                px.channels[2] = convertValue(T, val_f);
            } else if (channels == 1) {
                px.channels[0] = convertValue(T, val_f);
            }
            texture.setPixel(rr, cc, px);
        }
    }

    return texture;
}

// TODO: try and fix this hard coded dynamic library mess.
pub fn CLoadTIFF(allocator: std.mem.Allocator, 
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
            texture.setPixel(row, col, px);
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

test "Verify hand-written TIFF loader" {
    const allocator = testing.allocator;
    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();
    
    // 1. Load using C loader (libtiff)
    var tex_c = try CLoadTIFF(allocator, io, "texture/speckle.tiff", u8, 1);
    defer tex_c.deinit(allocator);

    // 2. Save using our saveTIFF
    const out_dir = std.Io.Dir.cwd();
    const mat_size = tex_c.rows_n * tex_c.cols_n;
    const mat_mem = try allocator.alloc(f64, mat_size);
    defer allocator.free(mat_mem);
    for (0..tex_c.rows_n) |rr| {
        for (0..tex_c.cols_n) |cc| {
            mat_mem[rr * tex_c.cols_n + cc] = @as(f64, @floatFromInt(tex_c.getPixel(rr, cc).channels[0]));
        }
    }
    const mat = MatSlice(f64).init(mat_mem, tex_c.rows_n, tex_c.cols_n);
    
    try saveTIFF(io, out_dir, "texture/speckle-simple.tiff", &mat, 8);

    // 3. Load using our hand-written loadTIFF via generic loadImage
    var tex_zig = try loadImage(allocator, io, "texture/speckle-simple.tiff", .tiff, u8, 1);
    defer tex_zig.deinit(allocator);

    try testing.expectEqual(tex_c.rows_n, tex_zig.rows_n);
    try testing.expectEqual(tex_c.cols_n, tex_zig.cols_n);

    for (0..tex_c.rows_n) |rr| {
        for (0..tex_c.cols_n) |cc| {
            const p1 = tex_c.getPixel(rr, cc).channels[0];
            const p2 = tex_zig.getPixel(rr, cc).channels[0];
            const p1_f: f64 = @floatFromInt(p1);
            const p2_f: f64 = @floatFromInt(p2);
            try testing.expectApproxEqAbs(p1_f, p2_f, 1.0);
        }
    }
}

test "Save and Load All Formats" {
    const allocator = testing.allocator;
    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();
    const out_dir = std.Io.Dir.cwd();

    // Create a dummy 4x4 grayscale image
    const rows = 4;
    const cols = 4;
    const mat_mem = try allocator.alloc(f64, rows * cols);
    defer allocator.free(mat_mem);
    for (0..rows) |r| {
        for (0..cols) |c| {
            mat_mem[r * cols + c] = @as(f64, @floatFromInt(r * cols + c)) * 10.0;
        }
    }
    const mat = MatSlice(f64).init(mat_mem, rows, cols);

    const formats = std.enums.values(ImageFormat);
    for (formats) |fmt| {
        const base_name = "texture/test_io";
        try saveImage(io, out_dir, base_name, &mat, fmt, 8);
        
        var ext_buff: [1024]u8 = undefined;
        const ext = switch(fmt) {
            .csv => ".csv",
            .ppm => ".ppm",
            .bmp => ".bmp",
            .tiff => ".tiff",
        };
        const full_path = try std.fmt.bufPrint(ext_buff[0..], "{s}{s}", .{base_name, ext});

        var loaded = try loadImage(allocator, io, full_path, fmt, u8, 1);
        defer loaded.deinit(allocator);

        try testing.expectEqual(rows, loaded.rows_n);
        try testing.expectEqual(cols, loaded.cols_n);
    }
}
