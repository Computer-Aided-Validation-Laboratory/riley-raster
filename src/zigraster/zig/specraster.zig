const std = @import("std");
const print = std.debug.print;
const time = std.time;

const vecstack = @import("vecstack.zig");
const Vec3T = @import("vecstack.zig").Vec3T;
const Vec3SliceOps = @import("vecstack.zig").Vec3SliceOps;

const Mat44Ops = @import("matstack.zig").Mat44Ops;

const VecSlice = @import("vecslice.zig").VecSlice;
const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;

const sliceops = @import("sliceops.zig");

const vsd = @import("vecsimd.zig");
const Vec3SIMD = vsd.Vec3SIMD;

const Coords = @import("meshio.zig").Coords;
const Connect = @import("meshio.zig").Connect;
const Field = @import("meshio.zig").Field;

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
const tri6 = @import("tri6.zig");

const iops = @import("imageops.zig");
const ImageFormat = iops.ImageFormat;

pub const SaveOption = enum {
    disk,
    memory,
    both,
    none,
};

pub const RasterConfig = struct {
    threads_within_image: usize = 0,
    threads_over_image: usize = 0,
    save_opt: SaveOption = .disk,
    save_formats: []const ImageFormat = &[_]ImageFormat{.tiff},
    add_displacements: bool = false,
    tile_size: u16 = 32,
};


// Modifies coords by transforming them in-place
pub fn rasterOneFrame(mesh_type: MeshType,
                      allocator: std.mem.Allocator, 
                      io: std.Io,
                      frame_ind: usize,
                      camera: *const Camera, 
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
                                       frame_ind,
                                       camera,
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
                  frame_ind: usize,
                  camera: *const Camera, 
                  shader: anytype, 
                  coords: *NDArray(f64),
                  image_out_arr: *NDArray(f64),
                  ) !void {    
    
    const raster_start = std.Io.Clock.Timestamp.now(io, .awake);
    var time_start = std.Io.Clock.Timestamp.now(io, .awake);
    var time_end = std.Io.Clock.Timestamp.now(io, .awake);

    //-----------------------------------------------------------------------------------------
    // CONSTANTS
    const ShaderType = @TypeOf(shader);

    // MESH DIMS
    const dim_elem: usize = 0; 
    const elems_num: usize = coords.dims[dim_elem];
    
    // PIXELS
    const screen_px_x = @as(u16,@intCast(camera.pixels_num[0]));
    const screen_px_y = @as(u16,@intCast(camera.pixels_num[1]));

    // TILES
    const tile_size: u16 = 32; // Tile pixels
    const tiles_num_x: usize = try std.math.divCeil(usize,camera.pixels_num[0],tile_size);
    const tiles_num_y: usize = try std.math.divCeil(usize,camera.pixels_num[1],tile_size);
    const tiles_num: usize = tiles_num_x*tiles_num_y;

    //-----------------------------------------------------------------------------------------
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();
    
    //-----------------------------------------------------------------------------------------
    // Tiling Raster Step 1: World to Camera/Raster Coords - SIMD
    time_start = std.Io.Clock.Timestamp.now(io, .awake);

    if (comptime mesh_type == .tri3) {
        try tri3.transformElemsToRasterSIMD(3, f64, camera, dim_elem, coords);
    } else if (comptime mesh_type == .tri6) {
        try tri6.transformElemsToCamSIMD(6, f64, camera, dim_elem, coords);
    }
    
    time_end = std.Io.Clock.Timestamp.now(io, .awake);
    const time1_world_to_raster: f64 = @floatFromInt(
        time_start.durationTo(time_end).raw.nanoseconds);
        
    //-----------------------------------------------------------------------------------------
    // Tiling Raster Step 2: Calculate Element Bounding Boxes
    time_start = std.Io.Clock.Timestamp.now(io, .awake);

    const elem_bboxes: []BBox = try arena_alloc.alloc(BBox,elems_num);
    var elems_in_image: usize = 0;
    
    if (comptime mesh_type == .tri3) {
        elems_in_image = try tri3.countElemsCalcBBoxes(camera,
                                                        dim_elem,
                                                        coords,
                                                        elem_bboxes);
    } else if (comptime mesh_type == .tri6) {
        elems_in_image = try tri6.countElemsCalcBBoxes(camera,
                                                        dim_elem,
                                                        coords,
                                                        elem_bboxes);
    }
    
    time_end = std.Io.Clock.Timestamp.now(io, .awake);
    const time2_elem_bboxes_crop: f64 = @floatFromInt(
        time_start.durationTo(time_end).raw.nanoseconds);

    //-----------------------------------------------------------------------------------------
    // Tiling Raster Step 3: Element Tile Overlap - COUNT only  
    time_start = std.Io.Clock.Timestamp.now(io, .awake);        

    const tile_elem_counts: []usize = try arena_alloc.alloc(usize,tiles_num);
    @memset(tile_elem_counts,0);
    const tile_write_inds: []usize = try arena_alloc.alloc(usize,tiles_num); 

    const num_active_tiles = try rops.elemTileOverlapCount(tile_size,
                                                           tiles_num_x,
                                                           elems_in_image,
                                                           elem_bboxes,
                                                           tile_elem_counts,
                                                           tile_write_inds);

    time_end = std.Io.Clock.Timestamp.now(io, .awake);
    const time3_elem_tile_overlap_count: f64 = @floatFromInt(
        time_start.durationTo(time_end).raw.nanoseconds);
        
    //-----------------------------------------------------------------------------------------
    // Tiling Raster Step 4: Element Tile Overlap Store overlap boxes for ACTIVE tiles
    // Coarse, bounding box overlap based raster. Assumes a sparse mesh with each element 
    // touching few tiles.

    time_start = std.Io.Clock.Timestamp.now(io, .awake);
    
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
                         
    time_end = std.Io.Clock.Timestamp.now(io, .awake);
    const time4_elem_tile_overlap_store: f64 = @floatFromInt(
        time_start.durationTo(time_end).raw.nanoseconds);
    
    //-----------------------------------------------------------------------------------------
    // Tiling Raster Step 5: Main Raster Loop
    time_start = std.Io.Clock.Timestamp.now(io, .awake);

    if (comptime mesh_type == .tri3) {
        if (comptime ShaderType == FlatShader) {
            try tri3.rasterElemsFlat(arena_alloc,
                                      camera,
                                      frame_ind,
                                      tile_size,
                                      active_tiles,
                                      overlap_bboxes,
                                      coords,
                                      &shader.field,
                                      image_out_arr,);
        } else {
            print("No texture shading yet!",.{});
        }        
    } else if (comptime mesh_type == .tri6) {
        if (comptime ShaderType == FlatShader) { 
           try tri6.rasterElemsFlat(arena_alloc,
                                     camera,
                                     frame_ind,
                                     tile_size,
                                     active_tiles,
                                     overlap_bboxes,
                                     coords,
                                     &shader.field,
                                     image_out_arr,);
        } else {
            print("No texture shading yet!",.{});
        } 
    }
    
    time_end = std.Io.Clock.Timestamp.now(io, .awake);
    const time5_raster_loop: f64 = @floatFromInt(
        time_start.durationTo(time_end).raw.nanoseconds);

    //-----------------------------------------------------------------------------------------
    const raster_end = std.Io.Clock.Timestamp.now(io, .awake);
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
