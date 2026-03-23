const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;

const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;

const texops = @import("textureops.zig");
const clibtiff = @import("clibtiff.zig");
pub const Pixel = texops.Pixel;
pub const Texture = texops.Texture;

const imageops = @import("imageops.zig");
pub const ScaleStrategy = imageops.ScaleStrategy;
pub const ScalingParams = imageops.ScalingParams;

pub const MAX_CHANNELS = 8;

pub const ImageFormat = enum {
    csv,
    ppm,
    bmp,
    tiff,
};

pub const ImageSaveOpts = struct {
    format: ImageFormat,
    bits: ?u8 = 8,
    scaling: ScaleStrategy = .none,
    channels: usize = 1,

    pub fn init(format: ImageFormat, 
                bits: ?u8, 
                scaling: ScaleStrategy, 
                channels: usize) ImageSaveOpts {
        return .{ 
            .format = format, 
            .bits = bits, 
            .scaling = scaling,
            .channels = channels,
        };
    }
};

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
                 image_arr: *const NDArray(f64),
                 start_field: usize,
                 opts: ImageSaveOpts,
                 ) !void {
                    
    var name_buff: [1024]u8 = undefined;                
    const ext = switch (opts.format) {
        .csv => ".csv",
        .ppm => ".ppm",
        .bmp => ".bmp",
        .tiff => ".tiff",
    };
    const file_name = try std.fmt.bufPrint(
        name_buff[0..], 
        "{s}{s}", 
        .{ file_name_no_ext, ext }
    );

    switch (opts.format) {
        .csv => try saveCSV(io, out_dir, file_name, image_arr, start_field, opts),
        .ppm => try savePPM(io, out_dir, file_name, image_arr, start_field, opts),
        .bmp => try saveBMP(io, out_dir, file_name, image_arr, start_field, opts),
        .tiff => try saveTIFF(io, out_dir, file_name, image_arr, start_field, opts),
    }
}

pub fn saveMatAsImage(io: std.Io,
                      out_dir: std.Io.Dir, 
                      file_name_no_ext: []const u8,
                      image: *const MatSlice(f64),
                      opts: ImageSaveOpts,
                      ) !void {
    var dims = [_]usize{ 1, image.rows_num, image.cols_num };
    var strides = [_]usize{ image.rows_num * image.cols_num, image.cols_num, 1 };
    const arr = NDArray(f64){
        .elems = image.elems,
        .dims = &dims,
        .strides = &strides,
    };
    try saveImage(io, out_dir, file_name_no_ext, &arr, 0, opts);
}


pub fn saveImages(
    io: std.Io,
    out_dir: ?std.Io.Dir,
    frame_idx: usize,
    num_fields: usize,
    pixels_num: [2]u32,
    frame_arr: *const NDArray(f64),
    opts_slice: []const ImageSaveOpts,
) !void {
    const save_dir = out_dir orelse return;
    var name_buff: [1024]u8 = undefined;
    _ = pixels_num;

    for (opts_slice) |opts| {
        var ff: usize = 0;
        while (ff + opts.channels <= num_fields) {
            const file_name = if (opts.channels == 1)
                try std.fmt.bufPrint(
                    name_buff[0..],
                    "frame_{d}_field_{d}",
                    .{ frame_idx, ff },
                )
            else if (opts.channels == 3)
                try std.fmt.bufPrint(
                    name_buff[0..],
                    "frame_{d}_field_{d}_rgb",
                    .{ frame_idx, ff },
                )
            else
                try std.fmt.bufPrint(
                    name_buff[0..],
                    "frame_{d}_field_{d}_{d}",
                    .{ frame_idx, ff, ff + opts.channels - 1 },
                );

            try saveImage(io, save_dir, file_name, frame_arr, ff, opts);
            ff += opts.channels;
        }
    }
}

pub fn savePPM(io: std.Io,
               out_dir: std.Io.Dir, 
               file_name: []const u8,
               image_arr: *const NDArray(f64),
               start_field: usize,
               opts: ImageSaveOpts,
               ) !void {

    const ppm_file: std.Io.File = try out_dir.createFile(io, file_name, .{});
    defer ppm_file.close(io);

    var write_buf: [4096]u8 = undefined;
    var file_writer = ppm_file.writer(io, &write_buf);
    const writer = &file_writer.interface;

    const bits = opts.bits orelse 8;
    const max_val_f = imageops.getScaleMax(bits);
    const max_val = @as(u32, @intFromFloat(max_val_f));
    
    const rows = image_arr.dims[1];
    const cols = image_arr.dims[2];
    
    try writer.print("P3\n{d} {d}\n{d}\n", .{ cols, rows, max_val});

    // We need scaling params per field if we are doing auto scaling
    var params_array: [3]ScalingParams = undefined;
    for (0..opts.channels) |ch| {
        const field_idx = start_field + ch;
        const slice = image_arr.getSlice(&[_]usize{ field_idx, 0, 0 }, 0);
        const mat = MatSlice(f64).init(slice, rows, cols);
        params_array[ch] = imageops.getScalingParams(&mat, opts.scaling);
    }

    for (0..rows) |rr| {
        for (0..cols) |cc| {
            for (0..3) |ch| {
                const field_idx = if (ch < opts.channels) start_field + ch else start_field;
                const raw_val = image_arr.get(&[_]usize{ field_idx, rr, cc });
                const params = if (ch < opts.channels) params_array[ch] else params_array[0];
                
                var val = imageops.applyScaling(raw_val, opts.scaling, opts.bits, params);
                if (opts.bits == null) {
                    val *= imageops.getScaleMax(bits);
                }
                const px = @as(u32, @intFromFloat(imageops.applyClamping(val, bits)));
                try writer.print("{d}", .{px});
                if (ch < 2) try writer.writeByte(' ');
            }
            try writer.writeByte(' ');
        }
        try writer.writeByte('\n');
    }

    try writer.flush();   
}

pub fn saveCSV(io: std.Io,
               out_dir: std.Io.Dir, 
               file_name: []const u8,
               image_arr: *const NDArray(f64),
               start_field: usize,
               opts: ImageSaveOpts,
               ) !void {
    const csv_file = try out_dir.createFile(io, file_name, .{});
    defer csv_file.close(io);

    var write_buf: [4096]u8 = undefined;
    var file_writer = csv_file.writer(io,&write_buf);
    const writer = &file_writer.interface;

    const rows = image_arr.dims[1];
    const cols = image_arr.dims[2];

    var params_array: [MAX_CHANNELS]ScalingParams = undefined;
    const channels = @min(opts.channels, MAX_CHANNELS);
    for (0..channels) |ch| {
        const field_idx = start_field + ch;
        const slice = image_arr.getSlice(&[_]usize{ field_idx, 0, 0 }, 0);
        const mat = MatSlice(f64).init(slice, rows, cols);
        params_array[ch] = imageops.getScalingParams(&mat, opts.scaling);
    }

    for (0..rows) |rr| {
        for (0..cols) |cc| {
            for (0..channels) |ch| {
                const field_idx = start_field + ch;
                const raw_val = image_arr.get(&[_]usize{ field_idx, rr, cc });
                const params = params_array[ch];
                
                var val = imageops.applyScaling(raw_val, opts.scaling, opts.bits, params);
                if (opts.scaling == .none and opts.bits != null) {
                    val = imageops.applyClamping(val, opts.bits);
                }
                try writer.print("{d}", .{val});
                if (ch < channels - 1) try writer.writeByte(':');
            }
            try writer.writeByte(',');
        }
        try writer.print("\n",.{});
    }

    try writer.flush();
}

pub fn saveBMP(io: std.Io,
                out_dir: std.Io.Dir, 
                file_name: []const u8,
                image_arr: *const NDArray(f64),
                start_field: usize,
                opts: ImageSaveOpts) !void {

    const file = try out_dir.createFile(io, file_name, .{});
    defer file.close(io);

    var write_buf: [4096]u8 = undefined;
    var file_writer = file.writer(io, &write_buf);
    const writer = &file_writer.interface;

    const bits = opts.bits orelse 8;
    const is_16bit = (bits == 16);
    const bpp: u16 = if (is_16bit) 48 else 24;

    const rows = image_arr.dims[1];
    const cols = image_arr.dims[2];

    const width = @as(u32, @intCast(cols));
    const height = @as(u32, @intCast(rows));
    const bytes_per_px: u32 = if (is_16bit) 6 else 3;
    const row_padding = (4 - (width * bytes_per_px) % 4) % 4;
    const row_size = width * bytes_per_px + row_padding;
    const data_size = row_size * height;
    const header_size: u32 = 14 + 40;
    const file_size = header_size + data_size;

    // Bitmap File Header (14 bytes)
    try writer.writeAll("BM");
    try writer.writeInt(u32, file_size, .little);
    try writer.writeInt(u16, 0, .little);
    try writer.writeInt(u16, 0, .little);
    try writer.writeInt(u32, header_size, .little);

    // DIB Header (BITMAPINFOHEADER - 40 bytes)
    try writer.writeInt(u32, 40, .little);
    try writer.writeInt(i32, @intCast(width), .little);
    try writer.writeInt(i32, @intCast(height), .little);
    try writer.writeInt(u16, 1, .little);
    try writer.writeInt(u16, bpp, .little);
    try writer.writeInt(u32, 0, .little); // BI_RGB
    try writer.writeInt(u32, data_size, .little);
    try writer.writeInt(i32, 2835, .little);
    try writer.writeInt(i32, 2835, .little);
    try writer.writeInt(u32, 0, .little);
    try writer.writeInt(u32, 0, .little);

    var params_array: [3]ScalingParams = undefined;
    for (0..@min(opts.channels, 3)) |ch| {
        const field_idx = start_field + ch;
        const slice = image_arr.getSlice(&[_]usize{ field_idx, 0, 0 }, 0);
        const mat = MatSlice(f64).init(slice, rows, cols);
        params_array[ch] = imageops.getScalingParams(&mat, opts.scaling);
    }

    // BMP data is bottom-up
    var rr: usize = rows;
    while (rr > 0) {
        rr -= 1;
        for (0..cols) |cc| {
            // Write BGR
            const bgr_inds = [_]usize{ 2, 1, 0 };
            for (bgr_inds) |ch| {
                const field_idx = if (ch < opts.channels) start_field + ch else start_field;
                const raw_val = image_arr.get(&[_]usize{ field_idx, rr, cc });
                const params = if (ch < opts.channels) params_array[ch] else params_array[0];

                var val = imageops.applyScaling(raw_val, opts.scaling, opts.bits, params);
                if (opts.bits == null and opts.scaling != .none) {
                    val *= if (is_16bit) 65535.0 else 255.0;
                }
                const px_f = imageops.applyClamping(val, bits);
                if (is_16bit) {
                    try writer.writeInt(u16, @as(u16, @intFromFloat(px_f)), .little);
                } else {
                    try writer.writeByte(@as(u8, @intFromFloat(px_f)));
                }
            }
        }
        for (0..row_padding) |_| try writer.writeByte(0);
    }
    try writer.flush();
}
pub fn saveTIFF(io: std.Io, 
                out_dir: std.Io.Dir, 
                file_name: []const u8, 
                image_arr: *const NDArray(f64),
                start_field: usize,
                opts: ImageSaveOpts) !void {

    const rows = image_arr.dims[1];
    const cols = image_arr.dims[2];
    const slice = image_arr.getSlice(&[_]usize{ start_field, 0, 0 }, 0);
    const image = MatSlice(f64).init(slice, rows, cols);
                
    const file = try out_dir.createFile(io, file_name, .{});
    defer file.close(io);

    var write_buf: [4096]u8 = undefined;
    var file_writer = file.writer(io, &write_buf);
    const writer = &file_writer.interface;

    const bits = opts.bits orelse 8;
    const width = @as(u32, @intCast(image.cols_num));
    const height = @as(u32, @intCast(image.rows_num));
    const pixel_data_offset: u32 = 8;
    const bytes_per_pixel: u32 = if (bits == 16) 2 else 1;
    const pixel_data_size = width * height * bytes_per_pixel;
    const ifd_offset = pixel_data_offset + pixel_data_size;

    // 1. Header (8 bytes)
    try writer.writeAll("II"); // Little Endian
    try writer.writeInt(u16, 42, .little);
    try writer.writeInt(u32, ifd_offset, .little);

    const params = imageops.getScalingParams(&image, opts.scaling);
    const max_v = imageops.getScaleMax(bits);

    // 2. Pixel Data
    for (0..image.rows_num) |r| {
        for (0..image.cols_num) |c| {
            const raw_val = image.get(r, c);
            var val = imageops.applyScaling(raw_val, opts.scaling, opts.bits, params);
            if (opts.bits == null and opts.scaling != .none) {
                val *= max_v;
            }
            
            const px_clamped = imageops.applyClamping(val, bits);
            if (bits == 16) {
                try writer.writeInt(u16, @as(u16, @intFromFloat(px_clamped)), .little);
            } else {
                try writer.writeByte(@as(u8, @intFromFloat(px_clamped)));
            }
        }
    }

    // 3. IFD
    const num_tags: u16 = 10;
    try writer.writeInt(u16, num_tags, .little);

    const Tag = struct {
        id: u16, type: u16, count: u32, value: u32,
        fn write(self: @This(), w: anytype) !void {
            try w.writeInt(u16, self.id, .little);
            try w.writeInt(u16, self.type, .little);
            try w.writeInt(u32, self.count, .little);
            try w.writeInt(u32, self.value, .little);
        }
    };

    try (Tag{ .id = 256, .type = 3, .count = 1, .value = width }).write(writer);
    try (Tag{ .id = 257, .type = 3, .count = 1, .value = height }).write(writer);
    try (Tag{ .id = 258, .type = 3, .count = 1, .value = bits }).write(writer);
    try (Tag{ .id = 259, .type = 3, .count = 1, .value = 1 }).write(writer);
    try (Tag{ .id = 262, .type = 3, .count = 1, .value = 1 }).write(writer);
    try (Tag{ .id = 273, .type = 4, .count = 1, .value = pixel_data_offset }).write(writer);
    try (Tag{ .id = 277, .type = 3, .count = 1, .value = 1 }).write(writer);
    try (Tag{ .id = 278, .type = 3, .count = 1, .value = height }).write(writer);
    try (Tag{ .id = 279, .type = 4, .count = 1, .value = pixel_data_size }).write(writer);
    try (Tag{ .id = 296, .type = 3, .count = 1, .value = 2 }).write(writer);

    try writer.writeInt(u32, 0, .little);
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
                    if (next_char == '#') break; 
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

    const max_val_f = @as(f64, @floatFromInt(max_val));

    for (0..height) |rr| {
        for (0..width) |cc| {
            var px: Pixel(T, channels) = undefined;
            var rgb: [3]u32 = undefined;
            for (0..3) |i| {
                const val_str = try readToken(reader, aa);
                rgb[i] = try std.fmt.parseInt(u32, val_str, 10);
            }

            if (channels == 3) {
                const s0 = @as(f64, @floatFromInt(rgb[0])) / max_val_f;
                const s1 = @as(f64, @floatFromInt(rgb[1])) / max_val_f;
                const s2 = @as(f64, @floatFromInt(rgb[2])) / max_val_f;
                px.channels[0] = convertToTarget(T, s0);
                px.channels[1] = convertToTarget(T, s1);
                px.channels[2] = convertToTarget(T, s2);
            } else if (channels == 1) {
                const val = 0.299 * @as(f64, @floatFromInt(rgb[0])) 
                          + 0.587 * @as(f64, @floatFromInt(rgb[1])) 
                          + 0.114 * @as(f64, @floatFromInt(rgb[2]));
                px.channels[0] = convertToTarget(T, val / max_val_f);
            }
            texture.setPixel(rr, cc, px);
        }
    }

    return texture;
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
        _ = try reader.takeInt(u16, .little);
        bit_count = try reader.takeInt(u16, .little);
        const compression = try reader.takeInt(u32, .little);
        if (compression != 0) return error.CompressionNotSupported;
        try file_reader.seekBy(@as(i64, @intCast(dib_size)) - 20);
    } else return error.UnsupportedDIBHeader;

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
                    px.channels[0] = convertToTarget(T, 
                        @as(f64, @floatFromInt(bgr[2])) / 255.0);
                    px.channels[1] = convertToTarget(T, 
                        @as(f64, @floatFromInt(bgr[1])) / 255.0);
                    px.channels[2] = convertToTarget(T, 
                        @as(f64, @floatFromInt(bgr[0])) / 255.0);
                } else if (channels == 1) {
                    const val = 0.299 * @as(f64, @floatFromInt(bgr[2])) 
                              + 0.587 * @as(f64, @floatFromInt(bgr[1])) 
                              + 0.114 * @as(f64, @floatFromInt(bgr[0]));
                    px.channels[0] = convertToTarget(T, val / 255.0);
                }
                texture.setPixel(r, x, px);
            }
            try file_reader.seekBy(@intCast(row_padding));
        }
    } else if (bit_count == 48) {
        try file_reader.seekTo(offset);
        const row_padding = (4 - (abs_width * 6) % 4) % 4;
        for (0..abs_height) |y| {
            const r = if (height > 0) abs_height - 1 - y else y;
            for (0..abs_width) |x| {
                var bgr: [3]u16 = undefined;
                bgr[0] = try reader.takeInt(u16, .little);
                bgr[1] = try reader.takeInt(u16, .little);
                bgr[2] = try reader.takeInt(u16, .little);
                var px: Pixel(T, channels) = undefined;
                if (channels == 3) {
                    px.channels[0] = convertToTarget(T, 
                        @as(f64, @floatFromInt(bgr[2])) / 65535.0);
                    px.channels[1] = convertToTarget(T, 
                        @as(f64, @floatFromInt(bgr[1])) / 65535.0);
                    px.channels[2] = convertToTarget(T, 
                        @as(f64, @floatFromInt(bgr[0])) / 65535.0);
                } else if (channels == 1) {
                    const val = 0.299 * @as(f64, @floatFromInt(bgr[2])) 
                              + 0.587 * @as(f64, @floatFromInt(bgr[1])) 
                              + 0.114 * @as(f64, @floatFromInt(bgr[0]));
                    px.channels[0] = convertToTarget(T, val / 65535.0);
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
        for (0..palette_size) |i| try reader.readSliceAll(&palette[i]);

        try file_reader.seekTo(offset);
        const row_padding = (4 - abs_width % 4) % 4;
        for (0..abs_height) |y| {
            const r = if (height > 0) abs_height - 1 - y else y;
            for (0..abs_width) |x| {
                const index = try reader.takeByte();
                const color = palette[index];
                var px: Pixel(T, channels) = undefined;
                if (channels == 3) {
                    px.channels[0] = convertToTarget(T, 
                        @as(f64, @floatFromInt(color[2])) / 255.0);
                    px.channels[1] = convertToTarget(T, 
                        @as(f64, @floatFromInt(color[1])) / 255.0);
                    px.channels[2] = convertToTarget(T, 
                        @as(f64, @floatFromInt(color[0])) / 255.0);
                } else if (channels == 1) {
                    const val = 0.299 * @as(f64, @floatFromInt(color[2])) 
                              + 0.587 * @as(f64, @floatFromInt(color[1])) 
                              + 0.114 * @as(f64, @floatFromInt(color[0]));
                    px.channels[0] = convertToTarget(T, val / 255.0);
                }
                texture.setPixel(r, x, px);
            }
            try file_reader.seekBy(@intCast(row_padding));
        }
    } else return error.UnsupportedBitCount;

    return texture;
}

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
            256 => width = if (tag_type == 3) @as(u32, @intCast(tag_value & 0xFFFF)) 
                else tag_value,
            257 => height = if (tag_type == 3) @as(u32, @intCast(tag_value & 0xFFFF)) 
                else tag_value,
            258 => bits_per_sample = @intCast(tag_value & 0xFFFF),
            273 => strip_offsets = tag_value,
            277 => samples_per_pixel = @intCast(tag_value & 0xFFFF),
            else => {},
        }
        _ = tag_count;
    }

    if (samples_per_pixel != 1) return error.UnsupportedTIFFColorSpace;

    var texture = try Texture(T, channels).init(allocator, height, width);
    errdefer texture.deinit(allocator);

    try file_reader.seekTo(strip_offsets);

    const max_val_f: f64 = if (bits_per_sample == 16) 65535.0 else 255.0;

    for (0..height) |rr| {
        for (0..width) |cc| {
            var px: Pixel(T, channels) = undefined;
            const val_raw: f64 = if (bits_per_sample == 16) 
                @as(f64, @floatFromInt(try reader.takeInt(u16, endian)))
            else 
                @as(f64, @floatFromInt(try reader.takeByte()));

            const norm = val_raw / max_val_f;

            if (channels == 3) {
                px.channels[0] = convertToTarget(T, norm);
                px.channels[1] = convertToTarget(T, norm);
                px.channels[2] = convertToTarget(T, norm);
            } else if (channels == 1) {
                px.channels[0] = convertToTarget(T, norm);
            }
            texture.setPixel(rr, cc, px);
        }
    }

    return texture;
}

pub fn CLoadTIFF(allocator: std.mem.Allocator, 
                io: std.Io, 
                path: []const u8, 
                comptime T: type, 
                comptime channels: usize) !Texture(T, channels) {
    _ = io;
    var libtiff = try clibtiff.LibTiff.init();
    defer libtiff.deinit();

    const path_c = try allocator.dupeZ(u8, path);
    defer allocator.free(path_c);

    const tif = libtiff.open(path_c, "r") orelse return error.OpenFailed;
    defer libtiff.close(tif);

    var w: u32 = 0;
    var h: u32 = 0;
    _ = libtiff.getField(tif, 256, &w);
    _ = libtiff.getField(tif, 257, &h);

    const pixel_count = w * h;
    const raster = try allocator.alloc(u32, pixel_count);
    defer allocator.free(raster);

    if (libtiff.readRGBAImage(tif, w, h, raster.ptr, 0) == 0) return error.ReadFailed;

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
                px.channels[0] = convertToTarget(T, @as(f64, @floatFromInt(r)) / 255.0);
                px.channels[1] = convertToTarget(T, @as(f64, @floatFromInt(g)) / 255.0);
                px.channels[2] = convertToTarget(T, @as(f64, @floatFromInt(b)) / 255.0);
            } else if (channels == 1) {
                const val = 0.299 * @as(f64, @floatFromInt(r)) 
                          + 0.587 * @as(f64, @floatFromInt(g)) 
                          + 0.114 * @as(f64, @floatFromInt(b));
                px.channels[0] = convertToTarget(T, val / 255.0);
            }
            texture.setPixel(row, col, px);
        }
    }

    return texture;
}

fn convertToTarget(comptime T: type, norm: f64) T {
    const scale = switch (@typeInfo(T)) {
        .int => |info| (@as(f64, 1.0) 
            * @as(f64, @floatFromInt((@as(u64, 1) << info.bits) - 1))),
        .float => 1.0,
        else => @compileError("Unsupported type"),
    };
    const val = norm * scale;
    switch (@typeInfo(T)) {
        .int => return @as(T, @intFromFloat(@round(@max(0.0, @min(scale, val))))),
        .float => return @as(T, @floatCast(val)),
        else => @compileError("Unsupported type"),
    }
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

const testing = std.testing;

test "Verify hand-written TIFF loader" {
    const allocator = testing.allocator;
    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();
    
    var tex_c = try CLoadTIFF(allocator, io, "texture/speckle.tiff", u8, 1);
    defer tex_c.deinit(allocator);

    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, "temp-test", .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    const out_dir = cwd;
    const mat_size = tex_c.rows_num * tex_c.cols_num;
    const mat_mem = try allocator.alloc(f64, mat_size);
    defer allocator.free(mat_mem);
    for (0..tex_c.rows_num) |rr| {
        for (0..tex_c.cols_num) |cc| {
            mat_mem[rr * tex_c.cols_num + cc] = @as(f64, 
                @floatFromInt(tex_c.getPixel(rr, cc).channels[0]));
        }
    }
    const mat = MatSlice(f64).init(mat_mem, tex_c.rows_num, tex_c.cols_num);
    
    try saveMatAsImage(io, out_dir, "temp-test/speckle-simple", &mat, 
        .{ .format = .tiff, .bits = 8, .scaling = .none });

    var tex_zig = try loadImage(allocator, io, "temp-test/speckle-simple.tiff", .tiff, u8, 1);
    defer tex_zig.deinit(allocator);

    try testing.expectEqual(tex_c.rows_num, tex_zig.rows_num);
    try testing.expectEqual(tex_c.cols_num, tex_zig.cols_num);

    for (0..tex_c.rows_num) |rr| {
        for (0..tex_c.cols_num) |cc| {
            const p1 = tex_c.getPixel(rr, cc).channels[0];
            const p2 = tex_zig.getPixel(rr, cc).channels[0];
            const p1_f: f64 = @floatFromInt(p1);
            const p2_f: f64 = @floatFromInt(p2);
            try testing.expectApproxEqAbs(p1_f, p2_f, 1.0);
        }
    }
}

test "Save and Load All Formats 8-bit and 16-bit" {
    const allocator = testing.allocator;
    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, "temp-test", .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    const out_dir = cwd;

    const rows = 4;
    const cols = 4;
    const mat_mem = try allocator.alloc(f64, rows * cols);
    defer allocator.free(mat_mem);
    // Data in [0, 100] range
    for (0..rows) |rr| {
        for (0..cols) |cc| {
            mat_mem[rr * cols + cc] = @as(f64, @floatFromInt(rr * cols + cc)) * 5.0;
        }
    }
    const mat = MatSlice(f64).init(mat_mem, rows, cols);

    const formats = [_]ImageFormat{ .csv, .ppm, .tiff, .bmp };
    const bit_depths = [_]u8{ 8, 16 };

    for (formats) |fmt| {
        for (bit_depths) |bits| {
            const base_name = try std.fmt.allocPrint(
                allocator, "temp-test/test_io_{s}_{d}bit", 
                .{ @tagName(fmt), bits }
            );
            defer allocator.free(base_name);

            // 1. Save with auto-scaling
            try saveMatAsImage(io, out_dir, base_name, &mat, 
                .{ .format = fmt, .bits = bits, .scaling = .auto });
            
            var ext_buff: [1024]u8 = undefined;
            const ext = switch(fmt) {
                .csv => ".csv", .ppm => ".ppm", .bmp => ".bmp", .tiff => ".tiff",
            };
            const full_path = try std.fmt.bufPrint(ext_buff[0..], "{s}{s}", .{base_name, ext});

            // 2. Load back into u8 or u16
            if (bits == 8) {
                var loaded = try loadImage(allocator, io, full_path, fmt, u8, 1);
                defer loaded.deinit(allocator);
                try testing.expectEqual(rows, loaded.rows_num);
                try testing.expectEqual(cols, loaded.cols_num);
            } else {
                var loaded = try loadImage(allocator, io, full_path, fmt, u16, 1);
                defer loaded.deinit(allocator);
                try testing.expectEqual(rows, loaded.rows_num);
                try testing.expectEqual(cols, loaded.cols_num);
            }
        }
    }
}

test "Scaling Strategy: Fractional" {
    const allocator = testing.allocator;
    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();
    
    const rows = 2;
    const cols = 2;
    const mat_mem = try allocator.alloc(f64, rows * cols);
    defer allocator.free(mat_mem);
    // Data [0, 10]
    mat_mem[0] = 0.0; mat_mem[1] = 10.0;
    mat_mem[2] = 5.0; mat_mem[3] = 2.5;
    const mat = MatSlice(f64).init(mat_mem, rows, cols);

    // Test 1: Frac [0.4, 0.6], bits = null (CSV) -> should map [0, 10] to [0.4, 0.6]
    const opts1 = ImageSaveOpts{ 
        .format = .csv, .bits = null, .scaling = .{ .frac = .{ 0.4, 0.6 } } 
    };
    try saveMatAsImage(io, cwd, "temp-test/test_frac_float", &mat, opts1);
    
    var loaded1 = try loadImage(allocator, io, "temp-test/test_frac_float.csv", .csv, f64, 1);
    defer loaded1.deinit(allocator);
    try testing.expectApproxEqAbs(loaded1.getPixel(0, 0).channels[0], 0.4, 1e-6);
    try testing.expectApproxEqAbs(loaded1.getPixel(0, 1).channels[0], 0.6, 1e-6);
    try testing.expectApproxEqAbs(loaded1.getPixel(1, 0).channels[0], 0.5, 1e-6);
    try testing.expectApproxEqAbs(loaded1.getPixel(1, 1).channels[0], 0.45, 1e-6);

    // Test 2: Frac [0.4, 0.6], bits = 8 (CSV) -> should map [0, 10] to [0.4*255, 0.6*255]
    const opts2 = ImageSaveOpts{ 
        .format = .csv, .bits = 8, .scaling = .{ .frac = .{ 0.4, 0.6 } } 
    };
    try saveMatAsImage(io, cwd, "temp-test/test_frac_bits", &mat, opts2);
    
    var loaded2 = try loadImage(allocator, io, "temp-test/test_frac_bits.csv", .csv, f64, 1);
    defer loaded2.deinit(allocator);
    try testing.expectApproxEqAbs(loaded2.getPixel(0, 0).channels[0], 0.4 * 255.0, 1e-6);
    try testing.expectApproxEqAbs(loaded2.getPixel(0, 1).channels[0], 0.6 * 255.0, 1e-6);
    try testing.expectApproxEqAbs(loaded2.getPixel(1, 0).channels[0], 0.5 * 255.0, 1e-6);
    try testing.expectApproxEqAbs(loaded2.getPixel(1, 1).channels[0], 0.45 * 255.0, 1e-6);
}
