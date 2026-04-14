const std = @import("std");
const common = @import("common/benchcommon.zig");
const mr = @import("zraster/zig/meshraster.zig");
const iio = @import("zraster/zig/imageio.zig");
const buildconfig = @import("zraster/zig/buildconfig.zig");

const simd_on = buildconfig.config.simd == .on;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const texture_grey = try iio.loadImage(
        allocator,
        io,
        "texture/speckle.bmp",
        .bmp,
        u8,
        1,
    );
    defer texture_grey.deinit(allocator);
    const texture_rgb = try iio.loadImage(
        allocator,
        io,
        "texture/speckle_rgb.bmp",
        .bmp,
        u8,
        3,
    );
    defer texture_rgb.deinit(allocator);

    const pixel_num = [_]u32{ 800, 500 };

    const mesh_types = comptime std.enums.values(mr.MeshType);
    const shader_types = comptime std.enums.values(common.ShaderType);
    const sample_configs = [_]common.TextureSampleConfig{
        .{ .sample = .nearest, .mode = .direct },
        .{ .sample = .linear, .mode = .direct },
        .{ .sample = .cubic_catmull_rom, .mode = .direct },
        .{ .sample = .cubic_catmull_rom, .mode = .lut_lerp },
        .{ .sample = .cubic_mitchell_netravali, .mode = .lut_lerp },
        .{ .sample = .lanczos3, .mode = .lut_lerp },
        .{ .sample = .cubic_bspline, .mode = .lut_lerp },
        .{ .sample = .quintic_bspline, .mode = .direct },
        .{ .sample = .quintic_bspline, .mode = .lut_lerp },
    };

    const cases = [_]struct { ds: []const u8, out: []const u8 }{
        .{
            .ds = "sphere200",
            .out = if (simd_on) "gold-simd-sphere200" else "gold-sphere200",
        },
        .{
            .ds = "sphere2000",
            .out = if (simd_on) "gold-simd-sphere2000" else "gold-sphere2000",
        },
    };

    std.debug.print("Generating Sphere Gold data with .simd = .{s}...\n", .{
        if (simd_on) "on" else "off",
    });

    for (cases) |case| {
        inline for (mesh_types) |mt| {
            inline for (shader_types) |st| {
                inline for (sample_configs) |sc| {
                    const data_dir = try std.fmt.allocPrint(
                        allocator,
                        "data-bench/{s}_{s}",
                        .{ @tagName(mt), case.ds },
                    );
                    defer allocator.free(data_dir);

                    if (common.shouldRun(
                        .{ .run = .all, .skip_quad4ibi_sphere = true },
                        mt,
                        st,
                        sc,
                        data_dir,
                    )) {
                        const case_name = if (st == .tex8_grey or st == .tex8_rgb)
                            try std.fmt.allocPrint(
                                allocator,
                                "{s}_{s}_{s}_{s}",
                                .{ @tagName(mt), @tagName(st), @tagName(sc.sample), @tagName(sc.mode) },
                            )
                        else
                            try std.fmt.allocPrint(
                                allocator,
                                "{s}_{s}",
                                .{ @tagName(mt), @tagName(st) },
                            );
                        defer if (st == .tex8_grey or st == .tex8_rgb or true) allocator.free(case_name);

                        std.debug.print(
                            "Rendering reference: {s}/{s}\n",
                            .{ case.out, case_name },
                        );

                        _ = try common.runBenchmark(
                            allocator,
                            io,
                            mt,
                            st,
                            sc,
                            data_dir,
                            case.out,
                            pixel_num,
                            texture_grey,
                            texture_rgb,
                        );
                    }
                }
            }
        }
    }

    std.debug.print("\nDone. Sphere gold references established.\n", .{});
}
