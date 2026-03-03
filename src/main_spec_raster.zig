const std = @import("std");
const print = std.debug.print;
const time = std.time;

const meshio = @import("zigraster/zig/meshio.zig");
const Coords = meshio.Coords;
const Connect = meshio.Connect;
const Field = meshio.Field;
const SimData = meshio.SimData;

const mr = @import("zigraster/zig/meshraster.zig");
const MeshType = mr.MeshType;
const MeshRaster = mr.MeshRaster; 
const FlatShader = mr.FlatShader;
const TexShader = mr.TexShader;

const VecStack = @import("zigraster/zig/vecstack.zig");
const MatStack = @import("zigraster/zig/matstack.zig");

const Rotation = @import("zigraster/zig/rotation.zig").Rotation;
const Vec3f = VecStack.Vec3f;
const Mat44f = MatStack.Mat44f;
const Mat44Ops = MatStack.Mat44Ops;

const matslice = @import("zigraster/zig/matslice.zig");
const MatSlice = matslice.MatSlice;
const MatSliceOps = matslice.MatSliceOps;

const ndarray = @import("zigraster/zig/ndarray.zig");
const NDArray = ndarray.NDArray;

const Camera = @import("zigraster/zig/camera.zig").Camera;
const CameraOps = @import("zigraster/zig/camera.zig").CameraOps;

const iops = @import("zigraster/zig/imageops.zig");
const specraster = @import("zigraster/zig/specraster.zig");

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
    //const path_data = "data/quad_tri_def/";
    //const path_data = "data/fill_lin_tri/";
    //const path_data = "data/fill_quad_tri/";

    const path_data = "data/lin_tri/";
    const mesh_type: MeshType = .lin_tri;

    // const path_data = "data/quad_tri_def/";
    // const mesh_type: MeshType = .quad_tri;

    const frame_ind: usize = 1;
    
    const path_coords = path_data ++ "coords.csv";
    const path_connect = path_data ++ "connectivity.csv";

    const path_fields = [_][]const u8{ 
        path_data ++ "field_disp_x.csv",
        path_data ++ "field_disp_y.csv",
        path_data ++ "field_disp_z.csv",
    };

    const sim_data: SimData = try meshio.load_sim_data(page_alloc,
                                                       io,
                                                       path_coords,
                                                       path_connect,
                                                       path_fields[0..]); 

    //--------------------------------------------------------------------------
    // CHECK FIELD LOADED CORRECTLY
    const field_coord_n = sim_data.field.getCoordN();
    const field_time_n = sim_data.field.getTimeN();
    const field_fields_n = sim_data.field.getFieldsN();
    
    print("\nfield: time_n = {d}\n",.{field_time_n});
    print("field: coord_n = {d}\n",.{field_coord_n});
    print("field: fields_n = {d}\n\n",.{field_fields_n});
        
    //=========================================================================================
    // Build Camera
    const pixel_num = [_]u32{1000,1000};
    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const alpha_z: f64 = std.math.degreesToRadians(0.0);
    const beta_y: f64 = std.math.degreesToRadians(0.0);
    const gamma_x: f64 = std.math.degreesToRadians(0.0);
    const cam_rot = Rotation.init(alpha_z, beta_y, gamma_x);
    const fov_scale_factor: f64 = 1.01;
    const subsample: u8 = 2;
    
    print("{s}\n", .{print_break});
    const roi_pos = CameraOps.roi_cent_from_coords(&sim_data.coords);
    
    print("\nROI center position:\n", .{});
    roi_pos.vecPrint();
    
    const cam_pos = CameraOps.pos_fill_frame_from_rot(&sim_data.coords, 
                                                      pixel_num, 
                                                      pixel_size, 
                                                      focal_leng, 
                                                      cam_rot, 
                                                      fov_scale_factor);
    
    print("\nCamera position:\n", .{});
    cam_pos.vecPrint();
    
    const camera = Camera.init(pixel_num, 
                               pixel_size, 
                               cam_pos, 
                               cam_rot, 
                               roi_pos, 
                               focal_leng, 
                               subsample);
    
    print("\nWorld to camera matrix:\n", .{});
    camera.world_to_cam_mat.matPrint();
    

    //=========================================================================================
    // Mesh Data Transformation

    const elem_coords = try mr.transformCoords(page_alloc,&sim_data.coords,&sim_data.connect);
    const elem_disp = try mr.transformField(page_alloc,&sim_data.connect,&sim_data.field);
    const elem_field = try mr.transformField(page_alloc,&sim_data.connect,&sim_data.field);
    const elem_shader = FlatShader{ .field=elem_field }; 

    var mesh_raster = MeshRaster{
        .mesh_type = mesh_type,
        .coords = elem_coords,
        .disp = elem_disp,
        .shader = .{ .flat = elem_shader},
    };

    //=========================================================================================
    // Raster One Frame
    print("{s}\nRastering Image\n{s}\n", .{print_break,print_break});
    const num_fields = sim_data.field.getFieldsN();
    
    const images_mem = try render_alloc.alloc(f64, 
                                              num_fields
                                              * camera.pixels_num[1]
                                              * camera.pixels_num[0]);
    @memset(images_mem,0.0);
    
    var images_dims = [_]usize{num_fields,
                        	   camera.pixels_num[1],
                        	   camera.pixels_num[0]};
    var images_arr = try NDArray(f64).init(render_alloc,
                                           images_mem,
                                           images_dims[0..]);
    
    time_start = std.Io.Clock.Timestamp.now(io, .awake);

    // Creates own arena for temporary render buffers which should be 
    // cleared after rendering a frame.
    try specraster.rasterOneFrame(mesh_type,
                                  page_alloc,
                                  io, 
                                  frame_ind, 
                                  &camera,
                                  &mesh_raster.coords,
                                  &mesh_raster.shader, 
                                  &images_arr);
                           
    time_end = std.Io.Clock.Timestamp.now(io, .awake);
    // const time_raster: f64 = @floatFromInt(time_start.durationTo(time_end).raw.nanoseconds);
    // print("Raster time = {d:.3}ms\n", .{time_raster / time.ns_per_ms});
    
    // Print diagnostics to console to see if there is an image
    const image_max = std.mem.max(f64, images_arr.elems);
    const image_min = std.mem.min(f64, images_arr.elems);
    print("Image: [max, min] = [{d:.6}, {d:.6}]\n", .{ image_max, image_min });
    print("{s}\n", .{print_break});

    //======================================================================
    // 6. Save image to disk
    // const cwd = std.fs.cwd();
    const cwd: std.Io.Dir = std.Io.Dir.cwd();
        
    const dir_name = "out-spec-raster";
    var name_buff: [1024]u8 = undefined;
    
    cwd.createDir(io, dir_name, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // Path exists do nothing
        else => return err, // Propagate any other error
    };
    
    var out_dir: std.Io.Dir = try cwd.openDir(io, dir_name, .{});
    defer out_dir.close(io);
    
    print("Saving output images to: {s}\n", .{dir_name});
    
    var image_slice_inds = [_]usize{0,0,0};
            
    for (0..num_fields) |ff|{
        image_slice_inds[0] = ff;
        // Grab a matrix slice of the field images
        const image_slice = images_arr.getSlice(image_slice_inds[0..],0); 
        const image_mat = MatSlice(f64).init(image_slice,
                                             camera.pixels_num[1],
                                             camera.pixels_num[0]);
        
        time_start = std.Io.Clock.Timestamp.now(io, .awake);
        
        const file_name = try std.fmt.bufPrint(name_buff[0..], 
                                                   "spec_field{d}_frame{d}", 
                                                   .{ff,frame_ind});        
        try iops.saveImage(io, out_dir, file_name, &image_mat, .bmp, 8);
        try iops.saveImage(io, out_dir, file_name, &image_mat, .csv, 8);

        time_end = std.Io.Clock.Timestamp.now(io, .awake);
    
        const time_save_image: f64 = @floatFromInt(
            time_start.durationTo(time_end).raw.nanoseconds
        );
        print("Field {d} image save time = {d:.3} ms\n", 
              .{ff,time_save_image / time.ns_per_ms,});
    }        
} // main, end
