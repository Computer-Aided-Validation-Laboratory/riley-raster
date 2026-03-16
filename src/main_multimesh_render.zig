const std = @import("std");
const print = std.debug.print;

const MatSlice = @import("zigraster/zig/matslice.zig").MatSlice;
const meshio = @import("zigraster/zig/meshio.zig");
const SimData = meshio.SimData;

const mr = @import("zigraster/zig/meshraster.zig");
const MeshType = mr.MeshType;
const MeshRaster = mr.MeshRaster;
const MeshTransform = mr.MeshTransform;

const Camera = @import("zigraster/zig/camera.zig").Camera;
const CameraOps = @import("zigraster/zig/camera.zig").CameraOps;
const Rotation = @import("zigraster/zig/rotation.zig").Rotation;

const specraster = @import("zigraster/zig/specraster.zig");
const RasterConfig = specraster.RasterConfig;

const iio = @import("zigraster/zig/imageio.zig");
const uvio = @import("zigraster/zig/uvio.zig");

pub fn main() !void {
    const print_break = "--------------------------------------------------------------------------------";
    print("{s}\nMulti-Mesh Mixed Shader Test (Flat & Texture)\n{s}\n", 
        .{ print_break, print_break });    

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

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

    const mesh_types = [_]MeshType{
        .tri3,
        .tri6,
        .quad4ibi,
        .quad8,
        .quad9,
    };

    // 1. Load SimData and Global Texture
    print("Loading simulation data and texture...\n", .{});
    const sim_datas = try meshio.loadMultiSimData(aa, io, &dir_paths, .{});
    const texture = try iio.loadImage(aa, io, "texture/speckle-simple.tiff", .tiff, u8, 1);

    // 2. Construct 10 MeshRasters (Row 1: Flat, Row 2: Texture)
    var mesh_rasters = try aa.alloc(MeshRaster, 10);
    
    // Top Row (0-4): Flat Shading
    for (0..5) |ii| {
        // Duplicate coords to ensure independent translation
        var coords_dup = try MatSlice(f64).initAlloc(
            aa, sim_datas[ii].coords.mat.rows_num, sim_datas[ii].coords.mat.cols_num
        );
        @memcpy(coords_dup.elems, sim_datas[ii].coords.mat.elems);

        mesh_rasters[ii] = MeshRaster{
            .mesh_type = mesh_types[ii],
            .coords = meshio.Coords.init(coords_dup.elems, coords_dup.rows_num),
            .connect = sim_datas[ii].connect,
            .disp = sim_datas[ii].field,
            .shader = .{ .flat = .{
                .field = sim_datas[ii].field.?,
                .bits = 8,
                .scaling = .auto,
                .scale_over = .within_frames,
            }},
        };
    }

    // Bottom Row (5-9): Texture Shading
    for (0..5) |ii| {
        const uv_path = try std.fmt.allocPrint(aa, "{s}uvs.csv", .{dir_paths[ii]});
        const uvs = try uvio.loadUVMap(aa, io, uv_path);
        
        // Duplicate coords to ensure independent translation
        var coords_dup = try MatSlice(f64).initAlloc(
            aa, sim_datas[ii].coords.mat.rows_num, sim_datas[ii].coords.mat.cols_num
        );
        @memcpy(coords_dup.elems, sim_datas[ii].coords.mat.elems);

        mesh_rasters[ii + 5] = MeshRaster{
            .mesh_type = mesh_types[ii],
            .coords = meshio.Coords.init(coords_dup.elems, coords_dup.rows_num),
            .connect = sim_datas[ii].connect,
            .disp = sim_datas[ii].field,
            .shader = .{ .tex_u8 = .{
                .uvs = uvs.array,
                .texture = texture,
                .interp_type = .cubic_lut_lerp,
                .bits = 8,
                .scaling = .none,
            }},
        };
    }

    // 3. Arrange in a 5x2 grid
    // grid_dims are {cols, rows, layers}
    print("Arranging meshes in a 5x2 grid...\n", .{});
    mr.arrangeMeshSlice(mesh_rasters, .{ 0.15, 0.15, 0.0 }, .{ 5, 2, 1 });

    // 4. Setup Camera
    const pixel_num = [_]u32{ 1600, 800 };
    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);
    const fov_scale_factor: f64 = 1.2;
    const subsample: u8 = 2;

    const roi_pos = CameraOps.roiCentOverMeshes(mesh_rasters);
    const cam_pos = CameraOps.posFillFrameFromRotOverMeshes(
        mesh_rasters, pixel_num, pixel_size, focal_leng, rot, fov_scale_factor
    );

    const camera = Camera.init(pixel_num, pixel_size, cam_pos, rot, roi_pos, focal_leng, subsample);

    // 5. Output Setup
    const out_dir_name = "out-multimesh";
    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, out_dir_name, .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    var out_dir = try cwd.openDir(io, out_dir_name, .{});
    defer out_dir.close(io);

    const config = RasterConfig{
        .save_opt = .disk,
        .save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .bmp, .bits = 8, .scaling = .auto },
            .{ .format = .csv, .bits = null, .scaling = .none },
        },
        .tile_size = 32,
        .report = .perf,
        .perf_opts = .{
            .formats = &[_]iio.ImageSaveOpts{
                .{ .format = .bmp, .bits = 8, .scaling = .auto },
            },
            .save_iteration_map = true,
            .save_depth_map = true,
        },
    };

    // 6. Render
    print("Rendering scene with {d} meshes...\n", .{mesh_rasters.len});
    const time_start = std.Io.Clock.Timestamp.now(io, .awake);
    _ = try specraster.rasterAllFrames(aa, io, &camera, mesh_rasters, config, out_dir);
    const time_end = std.Io.Clock.Timestamp.now(io, .awake);

    const total_time_ms = @as(f64, 
        @floatFromInt(time_start.durationTo(time_end).raw.nanoseconds)) / 1e6;
    print("\nTotal scene rendering time: {d:.3} ms\n", .{total_time_ms});
    print("{s}\nDone.\n{s}\n", .{print_break, print_break});
}
