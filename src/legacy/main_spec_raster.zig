const std = @import("std");
const print = std.debug.print;
const time = std.time;

const meshio = @import("zraster/zig/meshio.zig");
const Coords = meshio.Coords;
const Connect = meshio.Connect;
const Field = meshio.Field;
const SimData = meshio.SimData;

const mr = @import("zraster/zig/meshraster.zig");
const MeshType = mr.MeshType;
const MeshInput = mr.MeshInput;
const NodalInput = mr.NodalInput;
const TexInput = mr.TexInput;

const VecStack = @import("zraster/zig/vecstack.zig");
const MatStack = @import("zraster/zig/matstack.zig");

const Rotation = @import("zraster/zig/rotation.zig").Rotation;
const Vec3f = VecStack.Vec3f;
const Mat44f = MatStack.Mat44f;
const Mat44Ops = MatStack.Mat44Ops;

const matslice = @import("zraster/zig/matslice.zig");
const MatSlice = matslice.MatSlice;
const MatSliceOps = matslice.MatSliceOps;

const ndarray = @import("zraster/zig/ndarray.zig");
const NDArray = ndarray.NDArray;

const Camera = @import("zraster/zig/camera.zig").Camera;
const CameraOps = @import("zraster/zig/camera.zig").CameraOps;

const iio = @import("zraster/zig/imageio.zig");
const zraster = @import("zraster/zig/zraster.zig");
const RasterConfig = zraster.RasterConfig;

pub fn main() !void {
    const print_break = [_]u8{'-'} ** 80;
    print("{s}\nZig Software rasteriser\n{s}\n", .{ print_break, print_break });

    //=========================================================================
    // IO
    var single_thread_io: std.Io.Threaded = .init_single_threaded;
    const io = single_thread_io.io();

    var time_start = std.Io.Clock.Timestamp.now(io, .awake);
    var time_end = std.Io.Clock.Timestamp.now(io, .awake);

    //==========================================================================
    // MEMORY ALLOCATORS
    const page_alloc = std.heap.page_allocator;

    var render_arena = std.heap.ArenaAllocator.init(page_alloc);
    defer render_arena.deinit();
    const render_alloc = render_arena.allocator();

    //==========================================================================
    // SETUP: load simulation data from file
    //const path_data = "data/cylinder/";
    //const path_data = "data/block/";

    const path_data = "data-simple/tri3_fullscreen/";
    const mesh_type: MeshType = .tri3;

    //const path_data = "data-simple/tri6_fullscreen/";
    //const mesh_type: MeshType = .tri6;

    const frame_idx: usize = 1;

    const path_coords = path_data ++ "coords.csv";
    const path_connect = path_data ++ "connectivity.csv";

    const path_fields = [_][]const u8{
        path_data ++ "field_disp_x.csv",
        path_data ++ "field_disp_y.csv",
        path_data ++ "field_disp_z.csv",
    };

    const sim_data: SimData = try meshio.loadSimData(page_alloc, io, path_coords, path_connect, path_fields[0..], null);

    //--------------------------------------------------------------------------
    // CHECK FIELD LOADED CORRECTLY
    const field_coord_n = sim_data.field.?.getCoordN();
    const field_time_n = sim_data.field.?.getTimeN();
    const field_fields_n = sim_data.field.?.getFieldsN();

    print("\nfield: time_n = {d}\n", .{field_time_n});
    print("field: coord_n = {d}\n", .{field_coord_n});
    print("field: fields_n = {d}\n\n", .{field_fields_n});

    //=========================================================================================
    // Build Camera
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

    //=========================================================================================
    // Mesh Data Transformation
    const elem_coords = try mr.prepareCoords(page_alloc, &sim_data.coords, &sim_data.connect);
    const elem_disp = try mr.prepareField(page_alloc, &sim_data.connect, &sim_data.field.?);
    const elem_field = try mr.prepareField(page_alloc, &sim_data.connect, &sim_data.field.?);
    const elem_shader = NodalInput{ .field = elem_field };

    var mesh_input = MeshInput{
        .mesh_type = mesh_type,
        .coords = elem_coords,
        .disp = elem_disp,
        .shader = .{ .nodal = elem_shader },
    };

    //=========================================================================================
    // Raster Config
    const config = RasterConfig{
        .threads_within_image = 0,
        .threads_over_images = 0,
        .save_opt = .none,
        .save_formats = &[_]iio.ImageFormat{.csv},
    };

    //=========================================================================================
    // Raster One Frame
    print("{s}\nRastering Image\n{s}\n", .{ print_break, print_break });

    var images_dims = [_]usize{ sim_data.field.?.getFieldsN(), camera.pixels_num[1], camera.pixels_num[0] };
    var images_arr = try NDArray(f64).initFlat(render_alloc, images_dims[0..]);
    @memset(images_arr.elems, 0.0);

    try zraster.rasterOneFrame(
        mesh_type,
        page_alloc,
        io,
        &camera,
        frame_idx,
        config.tile_size,
        config.threads_within_image,
        &mesh_input.shader,
        &mesh_input.coords,
        &images_arr,
    );

    const image_max = std.mem.max(f64, images_arr.elems);
    const image_min = std.mem.min(f64, images_arr.elems);
    print("Image: [max, min] = [{d:.6}, {d:.6}]\n", .{ image_max, image_min });
    print("{s}\n", .{print_break});

    //======================================================================
    // 6. Save image to disk
    // const cwd = std.fs.cwd();
    const cwd: std.Io.Dir = std.Io.Dir.cwd();

    const dir_name = "out-bench-spec-raster";
    var name_buff: [1024]u8 = undefined;

    cwd.createDir(io, dir_name, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // Path exists do nothing
        else => return err, // Propagate any other error
    };

    var out_dir: std.Io.Dir = try cwd.openDir(io, dir_name, .{});
    defer out_dir.close(io);

    print("Saving output images to: {s}\n", .{dir_name});

    var image_slice_inds = [_]usize{ 0, 0, 0 };

    for (0..sim_data.field.?.getFieldsN()) |ff| {
        image_slice_inds[0] = ff;
        // Grab a matrix slice of the field images
        const image_slice = images_arr.getSlice(image_slice_inds[0..], 0);
        const image_mat = MatSlice(f64).init(image_slice, camera.pixels_num[1], camera.pixels_num[0]);

        time_start = std.Io.Clock.Timestamp.now(io, .awake);

        const file_name = try std.fmt.bufPrint(
            name_buff[0..],
            "spec_field{d}_frame{d}",
            .{ ff, frame_idx },
        );
        try iio.saveImage(io, out_dir, file_name, &image_mat, .bmp, 8);
        try iio.saveImage(io, out_dir, file_name, &image_mat, .csv, 8);

        time_end = std.Io.Clock.Timestamp.now(io, .awake);

        const time_save_image: f64 = @floatFromInt(time_start.durationTo(time_end).raw.nanoseconds);
        print("Field {d} image save time = {d:.3} ms\n", .{
            ff,
            time_save_image / time.ns_per_ms,
        });
    }
} // main, end
