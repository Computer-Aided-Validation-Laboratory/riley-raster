const std = @import("std");
const zraster = @import("zigraster/zig/zraster.zig");
const meshio = @import("zigraster/zig/meshio.zig");
const iio = @import("zigraster/zig/imageio.zig");
const uvio = @import("zigraster/zig/uvio.zig");
const Camera = @import("zigraster/zig/camera.zig").Camera;
const CameraOps = @import("zigraster/zig/camera.zig").CameraOps;
const Rotation = @import("zigraster/zig/camera.zig").Rotation;
const MeshRaster = @import("zigraster/zig/meshraster.zig").MeshRaster;
const mr = @import("zigraster/zig/meshraster.zig");
const MatSlice = @import("zigraster/zig/matslice.zig").MatSlice;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const out_dir_root = "out-rgb";
    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, out_dir_root, .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    var out_dir = try cwd.openDir(io, out_dir_root, .{});
    defer out_dir.close(io);

    var arena = std.heap.ArenaAllocator.init(allocator);
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
    const texture = try iio.loadImage(
        aa, io, "texture/speckle_rgb.bmp", .bmp, u8, 3
    );

    var mesh_rasters = try aa.alloc(MeshRaster, 10);

    // Top Row (0-4): Flat RGB Shading
    // We create 3 fields for R, G, B
    for (0..5) |ii| {
        const field = sim_datas[ii].field.?;
        // Create an NDArray with 3 fields instead of 1
        // Layout must be (time, coord, field)
        // We MUST use the number of coordinates, not the number of field entries if they differ
        const num_coords = sim_datas[ii].coords.mat.rows_num;
        var rgb_field_arr = try zraster.NDArray(f64).initFlat(
            aa, &[_]usize{ field.array.dims[0], num_coords, 3 }
        );
        
        // Fill fields with some RGB patterns
        for (0..field.array.dims[0]) |tt| {
            for (0..field.array.dims[1]) |nn| {
                const val = field.array.get(&[_]usize{ tt, nn, 0 });
                rgb_field_arr.set(&[_]usize{ tt, nn, 0 }, val); // Red
                rgb_field_arr.set(&[_]usize{ tt, nn, 1 }, 1.0 - val); // Green
                rgb_field_arr.set(&[_]usize{ tt, nn, 2 }, val * val); // Blue
            }
        }

        const rgb_field = meshio.Field{ 
            .array = rgb_field_arr,
            .array_mem = rgb_field_arr.elems,
        };

        mesh_rasters[ii] = MeshRaster{
            .mesh_type = mesh_types[ii],
            .coords = sim_datas[ii].coords,
            .connect = sim_datas[ii].connect,
            .disp = sim_datas[ii].field,
            .shader = .{ .flat = .{
                .field = rgb_field,
                .bits = 8,
                .scaling = .auto,
                .scale_over = .within_frames,
            } },
        };
    }

    // Bottom Row (5-9): Texture RGB Shading
    for (0..5) |ii| {
        const uv_path = try std.fmt.allocPrint(aa, "{s}uvs.csv", .{dir_paths[ii]});
        const uvs = try uvio.loadUVMap(aa, io, uv_path);

        mesh_rasters[ii + 5] = MeshRaster{
            .mesh_type = mesh_types[ii],
            .coords = sim_datas[ii].coords,
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

    mr.arrangeMeshSlice(mesh_rasters, .{ 0.15, 0.15, 0.0 }, .{ 5, 2, 1 });

    const pixel_num = [_]u32{ 1200, 800 };
    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);
    const fov_scale_factor: f64 = 1.1;

    const roi_pos = CameraOps.roiCentOverMeshes(mesh_rasters);
    const cam_pos = CameraOps.posFillFrameFromRotOverMeshes(
        mesh_rasters, pixel_num, pixel_size, focal_leng, rot, fov_scale_factor,
    );
    const camera = Camera.init(
        pixel_num, pixel_size, cam_pos, rot, roi_pos, focal_leng, 2
    );

    const config = zraster.RasterConfig{
        .save_opt = .disk,
        .save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .bmp, .bits = 8, .scaling = .auto, .channels = 3 },
        },
        .tile_size = 32,
        .report = .perf,
    };

    std.debug.print("Rendering RGB Data to {s}/...\n", .{out_dir_root});
    _ = try zraster.rasterAllFrames(aa, io, &camera, mesh_rasters, config, out_dir);

    std.debug.print("Done.\n", .{});
}
