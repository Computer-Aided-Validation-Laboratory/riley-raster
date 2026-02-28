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
// DISPATCH
// pub const ElementType = enum {
//     lin_tri,
// };
// 
// pub fn render(elem_type: ElementType, TODO) !void {
//     switch (elem_type) {
//         inline else => |tag| {
//             rasterFrame(elem_type, TODO);
//         }
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
    const N: usize = 3;        // Set to nodes per elem 
    const tile_size: u16 = 32; // Tile pixels
    const area_tol: f64 = 1e-9;
    
    //-----------------------------------------------------------------------------------------
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    //-----------------------------------------------------------------------------------------
    // **ELEMENT WISE PRE-TRANSFORM**
    time_start = std.Io.Clock.Timestamp.now(io, .awake); 

    const elems_num: usize = connect.elem_n;
    const nodes_per_elem: usize = connect.nodes_per_elem;
    const coords_num: usize = 3;
    const fields_num: usize = field.getFieldsN();

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

    // dims=(elems_num,coord[x,y,z],nodes_per_elem)
    const dim_elem: usize = 0; 
    const dim_field: usize = 1;
    const dim_node: usize = 2;

    // NOTE: both these functions can be joined as a single loop
    rops.fillElemCoords(coords,connect,dim_elem,dim_node,dim_field,&elem_coord_arr);
    rops.fillElemFields(connect,field,frame_ind,dim_elem,dim_node,dim_field,&elem_field_arr);

    time_end = std.Io.Clock.Timestamp.now(io, .awake);
    const time0_data_transform: f64 = @floatFromInt(
        time_start.durationTo(time_end).raw.nanoseconds);
    
    //-----------------------------------------------------------------------------------------
    // World to Raster Coords - SIMD
        
    time_start = std.Io.Clock.Timestamp.now(io, .awake);
    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        const coords_world: Vec3SIMD(N,f64) = try vsd.loadVec3SIMDFromElemArray(
            N,f64,&elem_coord_arr,ee);

        const coords_raster: Vec3SIMD(N,f64) = rops.worldToRasterSIMD(
            N,f64,coords_world,camera); 

        try vsd.saveVec3SIMDToElemArray(N,f64,&elem_coord_arr,ee,coords_raster);
    }
    time_end = std.Io.Clock.Timestamp.now(io, .awake);
    const time1_world_to_raster: f64 = @floatFromInt(
        time_start.durationTo(time_end).raw.nanoseconds);
        
    //-----------------------------------------------------------------------------------------
    // Extract Element Bounding Boxes
    time_start = std.Io.Clock.Timestamp.now(io, .awake);

    const elem_bboxes: []BBox = try arena_alloc.alloc(BBox,elems_num);
    var elems_in_image: usize = 0;

    // SWITCH HERE
    
    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        const coords_raster: Vec3OfSlices(f64) = try rops.loadVec3SlicesFromElemArray(
            N,f64,&elem_coord_arr,ee
        );

        // Width (X) on screen check and crop
        const x_max: f64 = std.mem.max(f64,coords_raster.x);
        const x_min: f64 = std.mem.min(f64,coords_raster.x);
        if ((x_min > @as(f64, @floatFromInt(camera.pixels_num[0] - 1))) or (x_max < 0.0)) {
            continue;
        }

        // Height (Y) on on screen check and crop
        const y_max: f64 = std.mem.max(f64,coords_raster.y);
        const y_min: f64 = std.mem.min(f64,coords_raster.y);
        if ((y_min > @as(f64, @floatFromInt(camera.pixels_num[1] - 1))) or (y_max < 0.0)) {
            continue;
        }

        // Backface culling, negative area = crop for linear triangles
        const elem_area: f64 = rops.edgeFun3Slices(0,1,2,coords_raster.x,coords_raster.y);
        
        if (elem_area < area_tol) {
            continue;
        }
        
        const x_min_i: u16 = rops.boundIndMin(u16,x_min);
        const x_max_i: u16 = rops.boundIndMax(u16,
                                              x_max, 
                                              @intCast(camera.pixels_num[0]));
        const y_min_i: u16 = rops.boundIndMin(u16,y_min);
        const y_max_i: u16 = rops.boundIndMax(u16,
                                              y_max, 
                                              @intCast(camera.pixels_num[1]));

        elem_bboxes[elems_in_image] = BBox{
            .elem_ind = ee,
            .x_min = x_min_i,
            .x_max = x_max_i,
            .y_min = y_min_i,
            .y_max = y_max_i,
        };
        elems_in_image += 1;
    }

    time_end = std.Io.Clock.Timestamp.now(io, .awake);
    const time2_elem_bboxes_crop: f64 = @floatFromInt(
        time_start.durationTo(time_end).raw.nanoseconds);

    //----------------------------------------------------------------------------------
    // Element Tile Overlap COUNT: Pass 1, How many element in each tile? 

    time_start = std.Io.Clock.Timestamp.now(io, .awake);
    
    const tiles_num_x: usize = try std.math.divCeil(usize,camera.pixels_num[0],tile_size);
    const tiles_num_y: usize = try std.math.divCeil(usize,camera.pixels_num[1],tile_size);
    const tiles_num: usize = tiles_num_x*tiles_num_y;    

    const tile_elem_counts: []usize = try arena_alloc.alloc(usize,tiles_num);
    @memset(tile_elem_counts,0);

    for (0..elems_in_image) |ee| {
        const tile_ind_min_x: u16 = elem_bboxes[ee].x_min / tile_size;
        const tile_ind_max_x: u16 = try std.math.divCeil(u16,elem_bboxes[ee].x_max,tile_size);
        const tile_ind_min_y: u16 = elem_bboxes[ee].y_min / tile_size;
        const tile_ind_max_y: u16 = try std.math.divCeil(u16,elem_bboxes[ee].y_max,tile_size);

        for (tile_ind_min_y..tile_ind_max_y) |ty| {
            const tile_row_offset: usize = ty * tiles_num_x;
            
            for (tile_ind_min_x..tile_ind_max_x) |tx| {
                const tile_ind_flat: usize = tile_row_offset + tx;

                tile_elem_counts[tile_ind_flat] += 1;
                
            }
        }
    }

    time_end = std.Io.Clock.Timestamp.now(io, .awake);
    const time3_elem_tile_overlap_count: f64 = @floatFromInt(
        time_start.durationTo(time_end).raw.nanoseconds);

    //-----------------------------------------------------------------------------------------
    // Element Tile Overlap, Pass 2: Store overlap bounding boxes for ACTIVE tiles only.
    // Coarse, bounding box overlap based raster. Assumes a sparse mesh with each element 
    // touching few tiles.

    time_start = std.Io.Clock.Timestamp.now(io, .awake);
    
    const screen_px_x = @as(u16,@intCast(camera.pixels_num[0]));
    const screen_px_y = @as(u16,@intCast(camera.pixels_num[1]));

    // Count the active tiles and work out the write offsets into the overlap boxes
    const tile_write_inds: []usize = try arena_alloc.alloc(usize,tiles_num); 
    var current_offset: usize = 0;
    var num_active_tiles: usize = 0;
    for (tile_elem_counts,0..) |cc,ii| {
        tile_write_inds[ii] = current_offset;
        current_offset += cc;
        if (cc > 0) {
            num_active_tiles += 1;            
        }
    }

    const overlap_total: usize = sliceops.sum(usize,tile_elem_counts);
    const overlap_bboxes: []BBox = try arena_alloc.alloc(BBox,overlap_total);

    // Main raster loop will only need to analyse active tiles
    const active_tiles: []ActiveTile = try arena_alloc.alloc(ActiveTile,num_active_tiles);

    var active_ind: usize = 0;
    for (tile_elem_counts,0..) |cc,ii| {
    
        if (cc > 0) {
            const tx = @as(u16, @intCast(ii % tiles_num_x));
            const ty = @as(u16, @intCast(ii / tiles_num_x));
        
            active_tiles[active_ind] = ActiveTile{
                .overlap_start = tile_write_inds[ii],
                .overlap_count = cc,
                .x_px_min = tx*tile_size,
                .y_px_min = ty*tile_size,
            };
            active_ind += 1;      
        }
    }

    // NOTE: only loops over elements in image so ee is not the element number for coord data
    // in the NDArray!    
    for (0..elems_in_image) |ee| {
        const tile_ind_min_x: u16 = elem_bboxes[ee].x_min / tile_size;
        const tile_ind_min_y: u16 = elem_bboxes[ee].y_min / tile_size;
        
        // No 'try' divCeil
        const tile_ind_max_x = @min(@as(u16, @intCast(tiles_num_x)),
            (elem_bboxes[ee].x_max + tile_size - 1) / tile_size);
          const tile_ind_max_y = @min(@as(u16, @intCast(tiles_num_y)),
            (elem_bboxes[ee].y_max + tile_size - 1) / tile_size);

        for (tile_ind_min_y..tile_ind_max_y) |ty| {
            const tile_row_offset: usize = ty * tiles_num_x;

            const tile_px_min_y: u16 = @as(u16,@intCast(ty*tile_size));
            const tile_px_max_y: u16 = @as(u16,@min(tile_px_min_y+tile_size,screen_px_y));

            const overlap_y_min = @max(elem_bboxes[ee].y_min, tile_px_min_y);
            const overlap_y_max = @min(elem_bboxes[ee].y_max, tile_px_max_y);

            for (tile_ind_min_x..tile_ind_max_x) |tx| {
                
                const tile_px_min_x: u16 = @as(u16,@intCast(tx*tile_size));
                const tile_px_max_x: u16 = @as(u16,@min(tile_px_min_x+tile_size,screen_px_x));

                const tile_ind_flat: usize = tile_row_offset + tx;
                const write_ind = tile_write_inds[tile_ind_flat]; 
                tile_write_inds[tile_ind_flat] += 1;

                overlap_bboxes[write_ind] = BBox{
                    .elem_ind = elem_bboxes[ee].elem_ind,
                    .x_min = @max(elem_bboxes[ee].x_min,tile_px_min_x),
                    .x_max = @min(elem_bboxes[ee].x_max,tile_px_max_x),
                    .y_min = overlap_y_min,
                    .y_max = overlap_y_max,
                };  
            }
        }
    }

    time_end = std.Io.Clock.Timestamp.now(io, .awake);
    const time4_elem_tile_overlap_store: f64 = @floatFromInt(
        time_start.durationTo(time_end).raw.nanoseconds);
    
    //-----------------------------------------------------------------------------------------
    // Raster Loop, pass 3: Loop over ACTIVE tiles and check corners
    time_start = std.Io.Clock.Timestamp.now(io, .awake);

    // SWITCH HERE

    try rlintri.rasterElems(
        N,
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
