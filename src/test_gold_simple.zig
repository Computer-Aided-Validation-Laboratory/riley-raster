const std = @import("std");
const common = @import("common/tests.zig");

// NOTE: should probably be 1e-9 to 1e-11
const REL_TOL: f64 = 1e-9;
const ABS_TOL: f64 = 1e-9;
const SHADER_FILTER: common.ShaderFilter = .both; // .flat, .tex, or .both

test "Gold Simple Suite" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    // Load original using C loader once, then save as simple TIFF
    // and reload using our simple loader to ensure compatibility.
    const texture = blk: {
        const tex_orig = try common.iio.CLoadTIFF(allocator, io, "texture/speckle.tiff", u8, 1);
        defer tex_orig.deinit(allocator);
        
        const mat_size = tex_orig.rows_n * tex_orig.cols_n;
        const mat_mem = try allocator.alloc(f64, mat_size);
        defer allocator.free(mat_mem);
        for (0..mat_size) |i| {
            mat_mem[i] = @as(f64, @floatFromInt(tex_orig.pixels[i].channels[0]));
        }
        const mat = common.MatSlice(f64).init(mat_mem, tex_orig.rows_n, tex_orig.cols_n);
        
        var io_threaded_internal = std.Io.Threaded.init_single_threaded;
        const io_internal = io_threaded_internal.io();
        const out_dir = std.Io.Dir.cwd();
        
        try common.iio.saveTIFF(io_internal, out_dir, "temp-test/speckle-simple.tiff", &mat, 8);
        break :blk try common.iio.loadImage(
            allocator, io, "temp-test/speckle-simple.tiff", .tiff, u8, 1
        );
    };
    defer texture.deinit(allocator);

    const mesh_types = [_]common.MeshType{ .tri3, //.tri3opt, 
                                           .tri6, 
                                           .quad4ibi, .quad4newton,
                                           .quad8, .quad9 };
    const interp_types = [_]common.texops.InterpType{ .cubic_lut_lerp };
    const pixel_num = [_]u32{ 800, 500 };

    const start_time = std.Io.Clock.Timestamp.now(io, .awake);

    for (mesh_types) |mt| {
        // try common.runTestInternal(allocator, 
        //                            io, 
        //                            "single", 
        //                            mt, 
        //                            1.1, 
        //                            texture, 
        //                            pixel_num, 
        //                            &interp_types, 
        //                            "gold-simple", 
        //                            "data-simple", 
        //                            REL_TOL,
        //                            ABS_TOL, 
        //                            SHADER_FILTER);

        try common.runTestInternal(allocator, 
                                   io, 
                                   "twoelems", 
                                   mt, 
                                   1.1, 
                                   texture, 
                                   pixel_num, 
                                   &interp_types, 
                                   "gold-simple", 
                                   "data-simple", 
                                   REL_TOL,
                                   ABS_TOL, 
                                   SHADER_FILTER);
    }

    const end_time = std.Io.Clock.Timestamp.now(io, .awake);
    const duration_ms = @as(f64, @floatFromInt(
        start_time.durationTo(end_time).raw.nanoseconds)) / 1e6;
    std.debug.print("\nGold Simple Test Suite took {d:.3} ms\n", .{duration_ms});
}
