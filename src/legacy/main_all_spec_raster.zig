const std = @import("std");
const print = std.debug.print;
const Timestamp = std.Io.Clock.Timestamp;

const meshio = @import("zraster/zig/meshio.zig");
const Coords = meshio.Coords;
const Connect = meshio.Connect;
const Field = meshio.Field;
const SimData = meshio.SimData;

const mr = @import("zraster/zig/meshraster.zig");
const MeshType = mr.MeshType;
const MeshInput = mr.MeshInput;
const FlatInput = mr.FlatInput;
const TexInput = mr.TexInput;

const ndarray = @import("zraster/zig/ndarray.zig");
const NDArray = ndarray.NDArray;

const Rotation = @import("zraster/zig/rotation.zig").Rotation;
const Camera = @import("zraster/zig/camera.zig").Camera;
const CameraOps = @import("zraster/zig/camera.zig").CameraOps;

const iio = @import("zraster/zig/imageio.zig");

const zraster = @import("zraster/zig/zraster.zig");
const RasterConfig = zraster.RasterConfig;

const uvio = @import("zraster/zig/uvio.zig");

const ShaderMode = enum { flat, texture };

//=============================================================================================
const shader_mode: ShaderMode = .texture;
const report_perf: bool = true; // Set to true to enable performance diagnostics
//=============================================================================================

pub fn main() !void {
    const print_break = [_]u8{'-'} ** 80;
    print("{s}\nZig Software Rasteriser\n{s}\n", .{ print_break, print_break });

    //-----------------------------------------------------------------------------------------
    // Memory allocators and io
    const page_alloc = std.heap.page_allocator;

    var single_thread_io: std.Io.Threaded = .init_single_threaded;
    const io = single_thread_io.io();

    var time_start = std.Io.Clock.Timestamp.now(io, .awake);
    var time_end = std.Io.Clock.Timestamp.now(io, .awake);

    //-----------------------------------------------------------------------------------------
    // Input constants
    // const path_data = "data-simple/tri3_single/"
    // const path_data = "data-simple/tri3_fullscreen/";
    // const mesh_type: MeshType = .tri3;

    //const path_data = "data-simple/tri6_single/";
    //const path_data = "data-simple/tri6_fullscreen/";
    const path_data = "data-simple/tri6_twoelems/";
    const mesh_type: MeshType = .tri6;

    //const path_data = "data-simple/tri3_fullscreen/";
    //const mesh_type: MeshType = .tri3opt;

    const out_dir_name = "out-bench-zraster";

    //-----------------------------------------------------------------------------------------
    // Simulation input mesh
    const path_coords = path_data ++ "coords.csv";
    const path_connect = path_data ++ "connectivity.csv";

    const path_fields = [_][]const u8{
        path_data ++ "field_disp_x.csv",
        path_data ++ "field_disp_y.csv",
        path_data ++ "field_disp_z.csv",
    };

    const sim_data: SimData = try meshio.loadSimData(page_alloc, io, path_coords, path_connect, path_fields[0..], null);

    const field_coord_n = sim_data.field.?.getCoordN();
    const field_time_n = sim_data.field.?.getTimeN();
    const field_fields_n = sim_data.field.?.getFieldsN();

    print("\nfield: time_n = {d}\n", .{field_time_n});
    print("field: coord_n = {d}\n", .{field_coord_n});
    print("field: fields_n = {d}\n\n", .{field_fields_n});

    //-----------------------------------------------------------------------------------------
    // Camera setup
    const pixel_num = [_]u32{ 1200, 800 };
    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const alpha_z: f64 = std.math.degreesToRadians(0.0);
    const beta_y: f64 = std.math.degreesToRadians(0.0);
    const gamma_x: f64 = std.math.degreesToRadians(0.0);
    const cam_rot = Rotation.init(alpha_z, beta_y, gamma_x);
    const fov_scale_factor: f64 = 1.0;
    const subsample: u8 = 2;

    print("{s}\n", .{print_break});
    const roi_pos = CameraOps.roiCentFromCoords(&sim_data.coords);

    print("\nROI center position:\n", .{});
    roi_pos.vecPrint();

    const cam_pos = CameraOps.posFillFrameFromRot(&sim_data.coords, pixel_num, pixel_size, focal_leng, cam_rot, fov_scale_factor);

    print("\nCamera position:\n", .{});
    cam_pos.vecPrint();

    const camera = Camera.init(pixel_num, pixel_size, cam_pos, cam_rot, roi_pos, focal_leng, subsample);

    print("\nWorld to camera matrix:\n", .{});
    camera.world_to_cam_mat.matPrint();

    //-----------------------------------------------------------------------------------------
    // Mesh Data Transformation

    var mesh_input = MeshInput{
        .mesh_type = mesh_type,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = sim_data.disp,
        .shader = undefined,
    };

    if (comptime shader_mode == .flat) {
        mesh_input.shader = .{ .flat = .{
            .field = sim_data.field.?,
            .bits = 8,
        } };
    } else {
        const path_uvs = path_data ++ "uvs.csv";
        const path_tex = "texture/speckle-simple.tiff";

        const uvs = try uvio.loadUVMap(page_alloc, io, path_uvs);
        const texture = try iio.loadImage(page_alloc, io, path_tex, .tiff, u8, 1);

        mesh_input.shader = .{ .tex_u8 = .{
            .uvs = uvs,
            .texture = texture,
            .interp_type = .cubic_lut_lerp,
        } };
    }

    //-----------------------------------------------------------------------------------------
    // Raster Config
    const config = RasterConfig{
        .threads_within_image = 0,
        .threads_over_images = 0,
        .save_opt = .disk,
        .save_formats = &[_]iio.ImageFormat{ .csv, .bmp },
        .report = if (report_perf) .perf else .off,
        .perf_opts = .{}, // init to defaults
    };

    //-----------------------------------------------------------------------------------------
    // Output directory
    const cwd: std.Io.Dir = std.Io.Dir.cwd();

    cwd.createDir(io, out_dir_name, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    var out_dir: std.Io.Dir = try cwd.openDir(io, out_dir_name, .{});
    defer out_dir.close(io);

    //-----------------------------------------------------------------------------------------
    // Raster frames
    print("{s}\nRastering Images\n{s}\n", .{ print_break, print_break });

    time_start = Timestamp.now(io, .awake);

    const images_out = try zraster.rasterAllFrames(page_alloc, io, &camera, &mesh_input, config, out_dir);

    _ = images_out;

    time_end = Timestamp.now(io, .awake);
    const end_to_end_time: f64 = @floatFromInt(time_start.durationTo(time_end).raw.nanoseconds);

    const conv_units: f64 = 1.0 / 1.0e6;
    print("{s}\nEnd to end time: {d:.3} ms\n{s}\n", .{ print_break, end_to_end_time * conv_units, print_break });
}
