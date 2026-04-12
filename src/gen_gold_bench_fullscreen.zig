const std = @import("std");
const common = @import("common/benchcommon.zig");
const mr = @import("zraster/zig/meshraster.zig");
const iio = @import("zraster/zig/imageio.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const texture_grey = try iio.loadImage(
        u8,
        1,
        allocator,
        io,
        "texture/speckle.bmp",
        .bmp,
    );
    defer texture_grey.deinit(allocator);
    const texture_rgb = try iio.loadImage(
        u8,
        3,
        allocator,
        io,
        "texture/speckle_rgb.bmp",
        .bmp,
    );
    defer texture_rgb.deinit(allocator);

    const out_dir_base = "gold-bench-fullscreen";
    const pixel_num = [_]u32{ 800, 500 };

    const mesh_types = comptime std.enums.values(mr.MeshType);
    const shader_types = comptime std.enums.values(common.ShaderType);
    const interp_types = [_]common.InterpType{
        .linear,
        .cubic,
        .cubic_lut_lerp,
        .quintic,
        .quintic_lut_lerp,
    };

    std.debug.print(
        "Generating Unified Fullscreen Gold data to {s}/...\n",
        .{out_dir_base},
    );

    inline for (mesh_types) |mt| {
        inline for (shader_types) |st| {
            inline for (interp_types) |it| {
                const data_dir = comptime "data-bench/" ++ @tagName(mt) ++ "_fullraster";
                if (common.shouldRun(.{ .run = .all }, mt, st, it, data_dir)) {
                    const case_name = if (st == .tex8_grey or st == .tex8_rgb)
                        comptime @tagName(mt) ++ "_" ++
                            @tagName(st) ++ "_" ++
                            @tagName(it)
                    else
                        comptime @tagName(mt) ++ "_" ++ @tagName(st);
                    std.debug.print("Rendering reference: {s}\n", .{case_name});

                    // We generate gold from the minimal 'fullraster' dataset
                    _ = try common.runBenchmark(
                        allocator,
                        io,
                        mt,
                        st,
                        it,
                        data_dir,
                        out_dir_base,
                        pixel_num,
                        texture_grey,
                        texture_rgb,
                    );
                }
            }
        }
    }

    std.debug.print("\nDone. Unified gold references established.\n", .{});
}
