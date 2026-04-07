const std = @import("std");
const zraster = @import("zraster/zig/zraster.zig");
const meshio = @import("zraster/zig/meshio.zig");
const iio = @import("zraster/zig/imageio.zig");
const uvio = @import("zraster/zig/uvio.zig");
const Camera = @import("zraster/zig/camera.zig").Camera;
const CameraOps = @import("zraster/zig/camera.zig").CameraOps;
const Rotation = @import("zraster/zig/camera.zig").Rotation;
const MeshInput = @import("zraster/zig/meshraster.zig").MeshInput;
const mr = @import("zraster/zig/meshraster.zig");
const MatSlice = @import("zraster/zig/matslice.zig").MatSlice;

pub fn main() !void {
    const outer_alloc = std.heap.page_allocator;

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const out_dir_root = "out-bench-rgb";
    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, out_dir_root, .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    var out_dir = try cwd.openDir(io, out_dir_root, .{});
    defer out_dir.close(io);

    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const aa = arena.allocator();

    const dir_paths = [_][]const u8{
        "data-simple/tri3_twoelems/",
        "data-simple/tri6_twoelems/",
        "data-simple/quad4_twoelems/",
        "data-simple/quad8_twoelems/",
        "data-simple/quad9_twoelems/",
    };

    const mesh_types = [_]mr.MeshType{
        .tri3,
        .tri6,
        .quad4ibi,
        .quad8,
        .quad9,
    };

    const sim_datas = try meshio.loadMultiSimData(aa, io, &dir_paths, .{});

    // Load RGB Texture
    const texture = try iio.loadImage(aa, io, "texture/speckle_rgb.bmp", .bmp, u8, 3);

    var mesh_inputs = try aa.alloc(MeshInput, 10);

    // Top Row (0-4): Texture RGB Shading
    for (0..5) |ii| {
        const uv_path = try std.fmt.allocPrint(aa, "{s}uvs.csv", .{dir_paths[ii]});
        const uvs = try uvio.loadUVMap(aa, io, uv_path);

        var coords_dup = try MatSlice(f64).initAlloc(aa, sim_datas[ii].coords.mat.rows_num, sim_datas[ii].coords.mat.cols_num);
        @memcpy(coords_dup.elems, sim_datas[ii].coords.mat.elems);

        mesh_inputs[ii] = MeshInput{
            .mesh_type = mesh_types[ii],
            .coords = meshio.Coords.init(coords_dup.elems, coords_dup.rows_num),
            .connect = sim_datas[ii].connect,
            .disp = sim_datas[ii].field,
            .shader = .{ .tex_rgb_u8 = .{
                .uvs = uvs.array,
                .texture = texture,
                .interp_type = .cubic_lut_lerp,
                .bits = 8,
                .scaling = .none,
            } },
        };
    }

    // Bottom Row (5-9): Flat RGB Shading
    for (0..5) |ii| {
        const field = sim_datas[ii].field.?;
        const num_coords = sim_datas[ii].coords.mat.rows_num;
        var rgb_field_arr = try zraster.NDArray(f64).initFlat(aa, &[_]usize{ field.array.dims[0], num_coords, 3 });

        const coords = sim_datas[ii].coords;
        var min_x: f64 = std.math.inf(f64);
        var max_x: f64 = -std.math.inf(f64);
        for (0..num_coords) |nn| {
            const x_val = coords.x(nn);
            if (x_val < min_x) min_x = x_val;
            if (x_val > max_x) max_x = x_val;
        }
        const range_x = max_x - min_x;

        for (0..field.array.dims[0]) |tt| {
            for (0..num_coords) |nn| {
                const x_val = coords.x(nn);
                const t = if (range_x > 0) (x_val - min_x) / range_x else 0.5;

                var rr: f64 = 0;
                var gg: f64 = 0;
                var bb: f64 = 0;

                if (t < 0.5) {
                    const t_scaled = t * 2.0;
                    rr = 1.0 - t_scaled;
                    gg = t_scaled;
                    bb = 0.0;
                } else {
                    const t_scaled = (t - 0.5) * 2.0;
                    rr = 0.0;
                    gg = 1.0 - t_scaled;
                    bb = t_scaled;
                }

                rgb_field_arr.set(&[_]usize{ tt, nn, 0 }, rr);
                rgb_field_arr.set(&[_]usize{ tt, nn, 1 }, gg);
                rgb_field_arr.set(&[_]usize{ tt, nn, 2 }, bb);
            }
        }

        const rgb_field = meshio.Field{
            .array = rgb_field_arr,
            .array_mem = rgb_field_arr.elems,
        };

        var coords_dup = try MatSlice(f64).initAlloc(aa, sim_datas[ii].coords.mat.rows_num, sim_datas[ii].coords.mat.cols_num);
        @memcpy(coords_dup.elems, sim_datas[ii].coords.mat.elems);

        mesh_inputs[ii + 5] = MeshInput{
            .mesh_type = mesh_types[ii],
            .coords = meshio.Coords.init(coords_dup.elems, coords_dup.rows_num),
            .connect = sim_datas[ii].connect,
            .disp = sim_datas[ii].field,
            .shader = .{ .nodal = .{
                .field = rgb_field,
                .bits = 8,
                .scaling = .auto,
                .scale_over = .within_frames,
            } },
        };
    }

    mr.arrangeMeshSlice(mesh_inputs, .{ 0.15, 0.15, 0.0 }, .{ 5, 2, 1 });

    const pixel_num = [_]u32{ 1200, 800 };
    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);
    const fov_scale_factor: f64 = 1.1;

    const roi_pos = CameraOps.roiCentOverMeshes(mesh_inputs);
    const cam_pos = CameraOps.posFillFrameFromRotOverMeshes(
        mesh_inputs,
        pixel_num,
        pixel_size,
        focal_leng,
        rot,
        fov_scale_factor,
    );
    const camera = Camera.init(pixel_num, pixel_size, cam_pos, rot, roi_pos, focal_leng, 2);

    const config = zraster.RasterConfig{
        .save_opt = .disk,
        .save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .bmp, .bits = 8, .scaling = .auto, .channels = 3 },
        },
        .report = .full_stats,
    };

    std.debug.print("Rendering RGB Data to {s}/...\n", .{out_dir_root});
    _ = try zraster.rasterAllFrames(aa, io, &camera, mesh_inputs, config, out_dir);

    std.debug.print("Done.\n", .{});
}
