const std = @import("std");
const print = std.debug.print;
const Timestamp = std.Io.Clock.Timestamp;

const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;

const sliceops = @import("sliceops.zig");

const Camera = @import("camera.zig").Camera;

const rops = @import("rasterops.zig");
const BBox = rops.BBox;
const ActiveTile = rops.ActiveTile;
const Vec3OfSlices = rops.Vec3OfSlices;

const meshraster = @import("meshraster.zig");
const MeshType = meshraster.MeshType;
const MeshRaster = meshraster.MeshRaster;
const FlatShader = meshraster.FlatShader;
const TexShader = meshraster.TexShader;
const FieldShader = meshraster.FieldShader;

const tri3 = @import("tri3.zig");
const tri3opt = @import("tri3opt.zig");
const tri6 = @import("tri6.zig");
const quad4ibi = @import("quad4ibi.zig");
const quad4newton = @import("quad4newton.zig");
const quad8 = @import("quad8.zig");
const quad9 = @import("quad9.zig");

const iops = @import("imageops.zig");
const ImageFormat = iops.ImageFormat;

pub const SaveOption = enum {
    disk,
    memory,
    both,
    none,
};

pub const RasterConfig = struct {
    threads_within_image: u16 = 0,
    threads_over_images: u16 = 0,
    save_opt: SaveOption = .disk,
    save_formats: []const ImageFormat = &[_]ImageFormat{.tiff},
    tile_size: u16 = 32,
};

fn applyDispToMesh(outer_alloc: std.mem.Allocator,
                   tt: usize,
                   coords: *const NDArray(f64),
                   disp: *const NDArray(f64)) !NDArray(f64) {

    var coords_disp = try NDArray(f64).initFlat(outer_alloc, coords.dims);
    @memcpy(coords_disp.elems, coords.elems); // dest, source

    const disp_frame_mem = disp.getSlice(&[_]usize{ tt, 0, 0, 0 }, 0);
    var disp_frame = try NDArray(f64).init(outer_alloc, disp_frame_mem, disp.dims[1..]);
    coords_disp.addInPlace(&disp_frame);
    
    return coords_disp;
}


pub fn rasterAllFrames(outer_alloc: std.mem.Allocator,
                       io: std.Io,
                       camera: *const Camera,
                       mesh_raster: *const MeshRaster,
                       config: RasterConfig,
                       out_dir: ?std.Io.Dir,
                       ) !?NDArray(f64) {

    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    var num_time: usize = 1;
    if (mesh_raster.disp) |d| {
        num_time = d.dims[0];
    } else if (mesh_raster.shader == .flat) {
        num_time = mesh_raster.shader.flat.field.dims[0];
    }
    
    const num_fields = switch (mesh_raster.shader) {
        .flat => |f| f.field.dims[2],
        .texture => 1,
    };
    
    // Optional image buffer for returning all rendered frames to user in memory
    var images_arr: ?NDArray(f64) = null;
    if (config.save_opt == .memory or config.save_opt == .both) {
        const dims = [_]usize{
            num_time,
            num_fields,
            camera.pixels_num[1],
            camera.pixels_num[0],
        };
        // If we are returning this put it on the outer allocator
        images_arr = try NDArray(f64).initFlat(outer_alloc, dims[0..]);
    }
    
    // Main render loop over frames    
    for (0..num_time) |tt| {
        _ = arena.reset(.free_all);

        // Allocate some temporary coords for this frame that we can transform in place
        var coords_transform: NDArray(f64) = undefined;
        if (mesh_raster.disp) |disp| {
            coords_transform = try applyDispToMesh(arena_alloc,tt,&mesh_raster.coords,&disp);
        } else {
            coords_transform = try NDArray(f64).initFlat(arena_alloc,mesh_raster.coords.dims);
            @memcpy(coords_transform.elems,mesh_raster.coords.elems); // dest, source    
        }

        // Prepare the image buffer to render into for the current frame
        var frame_arr: NDArray(f64) = undefined;
        if (images_arr) |*ima| {
            // If we are returning to the user we wrap a slice of image_arr we return 
            const stride = ima.strides[0];
            const mem = ima.elems[tt * stride .. (tt + 1) * stride];
            frame_arr = try NDArray(f64).init(arena_alloc, mem, ima.dims[1..]);
        } else {
            // If we are not returning to user we alloc on our arena
            const dims = [_]usize{ num_fields, camera.pixels_num[1], camera.pixels_num[0] };
            frame_arr = try NDArray(f64).initFlat(arena_alloc, dims[0..]);
        }
        @memset(frame_arr.elems, 0.0);

        try rasterOneFrame(mesh_raster.mesh_type,
                           arena_alloc,
                           io, 
                           camera,
                           tt,
                           config.tile_size,
                           config.threads_within_image,                           
                           &mesh_raster.shader,
                           &coords_transform,
                           &frame_arr);

        if (config.save_opt == .disk or config.save_opt == .both) {
            if (out_dir) |save_dir| {
                var name_buff: [1024]u8 = undefined;
                
                for (0..num_fields) |ff| {
                    const file_name = try std.fmt.bufPrint(
                        name_buff[0..],
                        "frame_{d}_field_{d}",
                        .{ tt, ff },
                    );

                    const save_slice = frame_arr.getSlice(&[_]usize{ ff, 0, 0 }, 0);
                    const save_mat = MatSlice(f64).init(save_slice, 
                                                        camera.pixels_num[1], 
                                                        camera.pixels_num[0]);

                    const bits: u8 = switch (mesh_raster.shader) {
                        .flat => |f| @intCast(f.bits orelse 8),
                        .texture => 8,
                    };

                    for (config.save_formats) |format| {
                        try iops.saveImage(io, save_dir, file_name, &save_mat, format, bits);
                    }
                }
            }
        }


    } // End render loop
    
    return images_arr;
}

// Modifies coords by transforming them in-place
pub fn rasterOneFrame(mesh_type: MeshType,
                      allocator: std.mem.Allocator, 
                      io: std.Io,
                      camera: *const Camera,
                      frame_ind: usize,
                      tile_size: u16,
                      threads: u16,                        
                      shader: *const FieldShader,
                      coords: *NDArray(f64),
                      image_out_arr: *NDArray(f64),
                      ) !void {    
    
    // Use inline switch to force comptime dispatch for every combination of
    // MeshType and Shader variant.
    switch (mesh_type) {
        inline else => |mesh_tag| {
            switch (shader.*) {
                inline else => |shader_val| {
                    try rasterInternal(mesh_tag,
                                       allocator,
                                       io,
                                       camera,
                                       frame_ind,
                                       tile_size,
                                       threads,
                                       shader_val,
                                       coords, 
                                       image_out_arr);
                }
            }
        }
    }
}

fn rasterInternal(comptime mesh_type: MeshType,
                  allocator: std.mem.Allocator, 
                  io: std.Io,
                  camera: *const Camera, 
                  frame_ind: usize,
                  tile_size: u16,
                  threads: u16,
                  shader: anytype, 
                  coords: *NDArray(f64),
                  image_out_arr: *NDArray(f64),
                  ) !void {    
                  
    // TODO: add threading for the raster hot loop
    _ = threads;
    
    const raster_start = Timestamp.now(io, .awake);
    var time_start = Timestamp.now(io, .awake);
    var time_end = Timestamp.now(io, .awake);

    //-----------------------------------------------------------------------------------------
    // Types and Namespaces

    const MeshFun = switch (mesh_type) {
        .tri3 => tri3,
        .tri3opt => tri3opt,
        .tri6 => tri6,
        .quad4ibi => quad4ibi,
        .quad4newton => quad4newton,
        .quad8 => quad8,
        .quad9 => quad9,
        //else => unreachable,
    };

    const N: usize = switch (mesh_type) {
        .tri3, .tri3opt => 3,
        .tri6 => 6,
        .quad4ibi, .quad4newton => 4,
        .quad8 => 8,
        .quad9 => 9,
        //else => unreachable,
    };

    //-----------------------------------------------------------------------------------------
    // CONSTANTS    
    // MESH DIMS
    const dim_elem: usize = 0; 
    const elems_num: usize = coords.dims[dim_elem];
    
    // PIXELS
    const screen_px_x = @as(u16,@intCast(camera.pixels_num[0]));
    const screen_px_y = @as(u16,@intCast(camera.pixels_num[1]));

    // TILES
    const tiles_num_x: usize = try std.math.divCeil(usize,camera.pixels_num[0],tile_size);
    const tiles_num_y: usize = try std.math.divCeil(usize,camera.pixels_num[1],tile_size);
    const tiles_num: usize = tiles_num_x*tiles_num_y;

    //-----------------------------------------------------------------------------------------
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();
    
    //-----------------------------------------------------------------------------------------
    // Tiling Raster Step 1: World to Camera/Raster Coords - SIMD
    time_start = Timestamp.now(io, .awake);

    if (comptime mesh_type == .tri3 or mesh_type == .tri3opt) {
        try rops.transformElemsRasterSIMD(N, f64, camera, dim_elem, coords);
    } else {
        try rops.transformElemsCamSIMD(N, f64, camera, dim_elem, coords);
    }
    
    time_end = Timestamp.now(io, .awake);
    const time1_world_to_raster: f64 = @floatFromInt(
        time_start.durationTo(time_end).raw.nanoseconds);
        
    //-----------------------------------------------------------------------------------------
    // Tiling Raster Step 2: Calculate Element Bounding Boxes
    time_start = Timestamp.now(io, .awake);

    const elem_bboxes: []BBox = try arena_alloc.alloc(BBox,elems_num);
    
    const elems_in_image = if (comptime mesh_type == .tri3 or mesh_type == .tri3opt)
        try rops.countElemsCalcBBoxesTri3(camera, dim_elem, coords, elem_bboxes)
    else
        try rops.countElemsCalcBBoxes(N, camera, dim_elem, coords, elem_bboxes);
    
    time_end = Timestamp.now(io, .awake);
    const time2_elem_bboxes_crop: f64 = @floatFromInt(
        time_start.durationTo(time_end).raw.nanoseconds);

    //-----------------------------------------------------------------------------------------
    // Tiling Raster Step 3: Element Tile Overlap - COUNT only  
    time_start = Timestamp.now(io, .awake);        

    const tile_elem_counts: []usize = try arena_alloc.alloc(usize,tiles_num);
    @memset(tile_elem_counts,0);
    const tile_write_inds: []usize = try arena_alloc.alloc(usize,tiles_num); 

    const num_active_tiles = try rops.elemTileOverlapCount(tile_size,
                                                           tiles_num_x,
                                                           elems_in_image,
                                                           elem_bboxes,
                                                           tile_elem_counts,
                                                           tile_write_inds);

    time_end = Timestamp.now(io, .awake);
    const time3_elem_tile_overlap_count: f64 = @floatFromInt(
        time_start.durationTo(time_end).raw.nanoseconds);
        
    //-----------------------------------------------------------------------------------------
    // Tiling Raster Step 4: Element Tile Overlap Store overlap boxes for ACTIVE tiles
    // Coarse, bounding box overlap based raster. Assumes a sparse mesh with each element 
    // touching few tiles.

    time_start = Timestamp.now(io, .awake);
    
    const overlap_total: usize = sliceops.sum(usize,tile_elem_counts);
    const overlap_bboxes: []BBox = try arena_alloc.alloc(BBox,overlap_total);
    const active_tiles: []ActiveTile = try arena_alloc.alloc(ActiveTile,num_active_tiles);

    rops.storeActiveTiles(tile_size,
                          tiles_num_x,
                          tiles_num_y,
                          screen_px_x,
                          screen_px_y,
                          elems_in_image,
                          elem_bboxes,
                          tile_elem_counts,
                          tile_write_inds,
                          overlap_bboxes,
                          active_tiles);
                         
    time_end = Timestamp.now(io, .awake);
    const time4_elem_tile_overlap_store: f64 = @floatFromInt(
        time_start.durationTo(time_end).raw.nanoseconds);
    
    //-----------------------------------------------------------------------------------------
    // Tiling Raster Step 5: Main Raster Loop
    time_start = Timestamp.now(io, .awake);

    try MeshFun.rasterElems(arena_alloc, 
                            camera, 
                            frame_ind,
                            tile_size,
                            active_tiles,
                            overlap_bboxes,
                            coords,
                            &shader,
                            image_out_arr,);
                                    
    time_end = Timestamp.now(io, .awake);
    const time5_raster_loop: f64 = @floatFromInt(
        time_start.durationTo(time_end).raw.nanoseconds);

    //-----------------------------------------------------------------------------------------
    const raster_end = Timestamp.now(io, .awake);
    const time_raster_all: f64 = @floatFromInt(
        raster_start.durationTo(raster_end).raw.nanoseconds);

    var total_px: f64 = @as(f64,@floatFromInt(camera.pixels_num[0]*camera.pixels_num[1]));
    const sub_samp_f: f64 = @as(f64, @floatFromInt(camera.sub_sample));
    total_px = total_px*sub_samp_f*sub_samp_f;
    // conv ns->s *1e9, conv to million ops-> /1e6 = *1e3  
    const mega_ops_per_sec: f64 = 1.0e3 * total_px/time_raster_all; // time in ns
    const mega_tris_per_sec: f64 = 1.0e3 * @as(f64, @floatFromInt(elems_num)) 
        / time_raster_all;

    const conv_units: f64 = 1.0/1.0e6;
    const print_break = [_]u8{'='} ** 80;
    print("\n{s}\nSoftware Raster Times\n{s}\n", .{ print_break, print_break });
    print("World to raster         = {d:.6} ms\n",.{time1_world_to_raster*conv_units});
    print("Elem bbox crop          = {d:.6} ms\n",.{time2_elem_bboxes_crop*conv_units});
    print("Elem tile overlap count = {d:.6} ms\n",.{time3_elem_tile_overlap_count*conv_units});
    print("Elem tile overlap store = {d:.6} ms\n",.{time4_elem_tile_overlap_store*conv_units});
    print("Raster loop time        = {d:.6} ms\n",.{time5_raster_loop*conv_units});
    print("{s}\nTOTAL RASTER TIME  = {d:.3} ms\n",.{print_break,time_raster_all*conv_units});
    print("{s}\n",.{print_break});
    print("Total Ops   = {d}\n",.{total_px});
    print("MOps/second = {d:.2}\n",.{mega_ops_per_sec});
    print("MTri/second = {d:.2}\n",.{mega_tris_per_sec});
    print("{s}\n",.{print_break});
}
