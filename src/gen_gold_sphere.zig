const std = @import("std");
const common = @import("bench_common.zig");
const mr = @import("zigraster/zig/meshraster.zig");
const iio = @import("zigraster/zig/imageio.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const texture_grey = try iio.loadImage(allocator, io, "texture/speckle.bmp", .bmp, u8, 1);
    defer texture_grey.deinit(allocator);
    const texture_rgb = try iio.loadImage(allocator, io, "texture/speckle_rgb.bmp", .bmp, u8, 3);
    defer texture_rgb.deinit(allocator);

    const pixel_num = [_]u32{ 800, 500 };

    const mesh_types = comptime std.enums.values(mr.MeshType);
    const shader_types = comptime std.enums.values(common.ShaderType);
    const interp_types = [_]common.InterpType{ .linear, .cubic, .cubic_lut_lerp, .quintic, .quintic_lut_lerp };

    const cases = [_]struct { ds: []const u8, out: []const u8 }{
        .{ .ds = "sphere200", .out = "gold-sphere200" },
        .{ .ds = "sphere2000", .out = "gold-sphere2000" },
    };

    std.debug.print("Generating Sphere Gold data...\n", .{});

    for (cases) |case| {
        inline for (mesh_types) |mt| {
            inline for (shader_types) |st| {
                inline for (interp_types) |it| {
                    const data_dir = try std.fmt.allocPrint(allocator, "data-bench/{s}_{s}", .{@tagName(mt), case.ds});
                    defer allocator.free(data_dir);

                    if (common.shouldRun(.{ .run = .all, .skip_quad4ibi_sphere = true }, mt, st, it, data_dir)) {
                        const case_name = if (st == .tex8_grey or st == .tex8_rgb)
                            comptime @tagName(mt) ++ "_" ++ @tagName(st) ++ "_" ++ @tagName(it)
                        else
                            comptime @tagName(mt) ++ "_" ++ @tagName(st);

                        std.debug.print("Rendering reference: {s}/{s}\n", .{case.out, case_name});
                        
                        _ = try common.runBenchmark(allocator, io, mt, st, it, data_dir, case.out, pixel_num, texture_grey, texture_rgb);
                    }
                }
            }
        }
    }

    std.debug.print("\nDone. Sphere gold references established.\n", .{});
}
