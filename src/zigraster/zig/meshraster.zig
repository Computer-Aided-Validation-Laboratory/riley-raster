const std = @import("std");

const NDArray = @import("ndarray.zig").NDArray;

const meshio = @import("meshio.zig");
const Coords = meshio.Coords;
const Connect = meshio.Connect;
const Field = meshio.Field;
const SimData = meshio.SimData;

const texio = @import("textureio.zig");
const Texture = texio.Texture;


pub const FlatShader = struct {
    field: NDArray(f64),
};

pub const TexShader = struct {
    uvs: NDArray(f64),
    texture: Texture(u8,1),    
};

pub const FieldShader = union(enum) {
    flat: FlatShader,
    texture: TexShader,    
};

pub const MeshType = enum {
    lin_tri,
    quad_tri,
};

pub const MeshRaster = struct {
    mesh_type: MeshType,
    coords: NDArray(f64),
    disp: NDArray(f64),
    shader: FieldShader,  
};

pub fn initCoordArray(comptime T: type,
                     allocator: std.mem.Allocator,
                     dim0: usize, 
                     dim1: usize, 
                     dim2: usize) !NDArray(T) {
    var elem_arr_dims = [_]usize{dim0,dim1,dim2};
    const elem_arr_size: usize = dim0*dim1*dim2;
    const elem_arr_mem = try allocator.alloc(T, elem_arr_size);
    @memset(elem_arr_mem,0.0);
    const elem_arr = try NDArray(T).init(allocator, 
                                         elem_arr_mem, 
                                         elem_arr_dims[0..]);
    return elem_arr;
}


pub fn fillElemCoords(coords: *const Coords, 
                      connect: *const Connect,
                      elem_array: *NDArray(f64),
                      ) void {

    const dim_elem: usize = 0; 
    const dim_field: usize = 1;
    const dim_node: usize = 2;

    var elem_inds = [_]usize{0,0,0};

    for (0..elem_array.dims[dim_elem]) |ee| {
        elem_inds[dim_elem] = ee;
        const coord_inds: []usize = connect.getElem(ee);

        for (0..elem_array.dims[dim_node]) |nn| {
            elem_inds[dim_node] = nn;
                                
            elem_inds[dim_field] = 0;            
            elem_array.set(elem_inds[0..],coords.x(coord_inds[nn]));
            elem_inds[dim_field] = 1;            
            elem_array.set(elem_inds[0..],coords.y(coord_inds[nn]));
            elem_inds[dim_field] = 2;            
            elem_array.set(elem_inds[0..],coords.z(coord_inds[nn]));
            
        } 
    }    
}

pub fn initFieldArray(comptime T: type,
                     allocator: std.mem.Allocator,
                     dim0: usize, 
                     dim1: usize, 
                     dim2: usize,
                     dim3: usize) !NDArray(T) {
    var elem_arr_dims = [_]usize{dim0,dim1,dim2,dim3};
    const elem_arr_size: usize = dim0*dim1*dim2*dim3;
    const elem_arr_mem = try allocator.alloc(T, elem_arr_size);
    @memset(elem_arr_mem,0.0);
    const elem_arr = try NDArray(T).init(allocator, 
                                         elem_arr_mem, 
                                         elem_arr_dims[0..]);
    return elem_arr;
}

pub fn fillElemFields(connect: *const Connect,
                      field: *const Field,
                      field_array: *NDArray(f64),
                      ) void {

    const dim_time: usize = 0;
    const dim_elem: usize = 1; 
    const dim_field: usize = 2;
    const dim_node: usize = 3;

    var set_elem_inds = [_]usize{0,0,0,0}; // dims=(time,elem,field,node)
    var get_field_inds = [_]usize{0,0,0}; // dims=(time,coord,field)

    for (0..field_array.dims[dim_time]) |tt|{
        get_field_inds[0] = tt;
        set_elem_inds[dim_time] = tt;
        
        for (0..field_array.dims[dim_elem]) |ee| {
            set_elem_inds[dim_elem] = ee;
            const coord_inds: []usize = connect.getElem(ee);

            for (0..field_array.dims[dim_node]) |nn| {
                set_elem_inds[dim_node] = nn;
                get_field_inds[1] = coord_inds[nn];
                
                for (0..field_array.dims[dim_field]) |ff| {
                    get_field_inds[2] = ff;
                    const field_val: f64 = field.array.get(get_field_inds[0..]);

                    set_elem_inds[dim_field] = ff;
                    field_array.set(set_elem_inds[0..],field_val);    
                }
            } 
        }
    }    
}
pub fn transformCoords(allocator: std.mem.Allocator,
                       coords: *const Coords, 
                       connect: *const Connect,) !NDArray(f64) {


    // dims=(elems_num,coord[x,y,z],nodes_per_elem)
    var elem_coord_arr = try initCoordArray(f64,
                                           allocator,
                                           connect.elem_n,
                                           3,
                                           connect.nodes_per_elem);

    fillElemCoords(coords,connect,&elem_coord_arr);

    return elem_coord_arr;
}

pub fn transformField(allocator: std.mem.Allocator,
                      connect: *const Connect, 
                      field: *const Field) !NDArray(f64) {

    // dims=(times_num,elems_num,fields_num,nodes_per_elem) 
    var elem_field_arr = try initFieldArray(f64,
                                           allocator,
                                           field.getTimeN(), 
                                           connect.elem_n,
                                           field.getFieldsN(),
                                           connect.nodes_per_elem);

    fillElemFields(connect,field,&elem_field_arr);

    return elem_field_arr;
}

