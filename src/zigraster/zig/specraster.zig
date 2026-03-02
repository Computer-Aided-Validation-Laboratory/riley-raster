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

const rlintri = @import("rasterlintri.zig");


//---------------------------------------------------------------------------------------------
// DISPATCH: dynamics to static using comptime
// pub const ElementType = enum {
//     lin_tri,
//     quad_tri,
//     lin_quad,
//     quad_quad, 
// };
// 
// pub fn render(elem_type: ElementType, DATA) !void {
//     switch (elem_type) {
//         inline else => |tag| {
//             raster(elem_type, DATA);
//         },
//     }
// }
// 
// pub fn raster(comptime elem_type: ElementType, DATA) !void {
//     switch (elem_type) {
//         .lin_tri => {
//             rasterLinTri(DATA);
//         },
//         .quad_tri => {
//             rasterQuadTri(DATA);    
//         },
//         .lin_quad => {
//             rasterLinQuad(DATA);    
//         },
//         .quad_quad => {
//             rasterQuadQuad(DATA);    
//         },
//     }
// }
//---------------------------------------------------------------------------------------------

pub fn rasterFrame(allocator: std.mem.Allocator, 
                   io: std.Io,
                   frame_ind: usize, 
                   coords: *const Coords, 
                   connect: *const Connect, 
                   field: *const Field, 
                   camera: *const Camera, 
                   image_out_arr: *NDArray(f64),
                   ) !void {

    const raster_start = std.Io.Clock.Timestamp.now(io, .awake);
    var time_start = std.Io.Clock.Timestamp.now(io, .awake);
    var time_end = std.Io.Clock.Timestamp.now(io, .awake);

    //-----------------------------------------------------------------------------------------
    // CONSTANTS

    // NODES PER ELEM
    const N: usize = 3;        // Set to nodes per elem 

    // MESH DIMS
    const elems_num: usize = connect.elem_n;
    const nodes_per_elem: usize = connect.nodes_per_elem;
    const coords_num: usize = 3;
    const fields_num: usize = field.getFieldsN();

    // dims=(elems_num,coord[x,y,z],nodes_per_elem)
    const dim_elem: usize = 0; 
    const dim_field: usize = 1;
    const dim_node: usize = 2;

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
    // 0. Element Data Pre-Transform
    time_start = std.Io.Clock.Timestamp.now(io, .awake); 

    // dims=(elems_num,coord[x,y,z],nodes_per_elem)
    var elem_coord_arr = try rops.initElemArray(f64,
                                            arena_alloc,
                                            elems_num,
                                            coords_num,
                                            nodes_per_elem);
    // dims=(elems_num,fields_num,nodes_per_elem) 
    var elem_field_arr = try rops.initElemArray(f64,
                                            arena_alloc,
                                            elems_num,
                                            fields_num,
                                            nodes_per_elem);

    

    // NOTE: both these functions can be joined as a single loop
    rops.fillElemCoords(coords,connect,dim_elem,dim_node,dim_field,&elem_coord_arr);
    rops.fillElemFields(connect,field,frame_ind,dim_elem,dim_node,dim_field,&elem_field_arr);

    time_end = std.Io.Clock.Timestamp.now(io, .awake);
    const time0_data_transform: f64 = @floatFromInt(
        time_start.durationTo(time_end).raw.nanoseconds);

    
    //-----------------------------------------------------------------------------------------
    // Tilin Raster Step 1: World to Camera/Raster Coords - SIMD
        
    time_start = std.Io.Clock.Timestamp.now(io, .awake);
    
    try rops.transformElemsToRasterSIMD(N,f64,camera,dim_elem,&elem_coord_arr);
    
    time_end = std.Io.Clock.Timestamp.now(io, .awake);
    const time1_world_to_raster: f64 = @floatFromInt(
        time_start.durationTo(time_end).raw.nanoseconds);
        
    //-----------------------------------------------------------------------------------------
    // Tiling Raster Step 2: Calculate Element Bounding Boxes
    time_start = std.Io.Clock.Timestamp.now(io, .awake);

    const elem_bboxes: []BBox = try arena_alloc.alloc(BBox,elems_num);

    // SWITCH HERE over ElementType
    const elems_in_image = try rlintri.countElemsCalcBBoxes(camera,
                                                            dim_elem,
                                                            &elem_coord_arr,
                                                            elem_bboxes);

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

    // SWITCH HERE over ElementType
    try rlintri.rasterElems(
        arena_alloc,
        camera,
        tile_size,
        active_tiles,
        overlap_bboxes,
        &elem_coord_arr,
        &elem_field_arr,
        image_out_arr,
    );

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
    const mega_tris_per_sec: f64 = 1.0e3 * @as(f64, @floatFromInt(connect.elem_n)) 
        / time_raster_all;

    const conv_units: f64 = 1.0/1.0e6;
    const print_break = [_]u8{'='} ** 80;
    print("\n{s}\nSoftware Raster Times\n{s}\n", .{ print_break, print_break });
    print("Data transform          = {d:.6} ms\n",.{time0_data_transform*conv_units});
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

    
