const std = @import("std");

pub const NDArray = @import("ndarray.zig").NDArray;

const meshio = @import("meshio.zig");
const Coords = meshio.Coords;
const Connect = meshio.Connect;
const Field = meshio.Field;

const uvio = @import("uvio.zig");
const UVMap = uvio.UVMap;

const shaderops = @import("shaderops.zig");
pub const FlatShader = shaderops.FlatShader;
pub const TexShader = shaderops.TexShader;
pub const FieldShader = shaderops.FieldShader;

pub const MeshType = enum {
    tri3,
    tri3opt,
    tri6,
    quad4ibi,
    quad4newton,
    quad8,
    quad9,
};

pub const MeshRaster = struct {
    mesh_type: MeshType,
    coords: NDArray(f64),
    disp: ?NDArray(f64),
    shader: FieldShader,
};

pub fn transformCoords(
    allocator: std.mem.Allocator,
    coords: *const Coords,
    connect: *const Connect,
) !NDArray(f64) {
    // dims=(elems_num,coord[x,y,z],nodes_per_elem)
    const coord_dims = [_]usize{ connect.elem_n, 3, connect.nodes_per_elem };
    var elem_coord_arr = try NDArray(f64).initFlat(allocator, coord_dims[0..]);
    @memset(elem_coord_arr.elems, 0.0);

    const dim_elem: usize = 0;
    const dim_field: usize = 1;
    const dim_node: usize = 2;

    var elem_inds = [_]usize{ 0, 0, 0 };

    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        elem_inds[dim_elem] = ee;
        const coord_inds: []usize = connect.getElem(ee);

        for (0..elem_coord_arr.dims[dim_node]) |nn| {
            elem_inds[dim_node] = nn;

            elem_inds[dim_field] = 0;
            elem_coord_arr.set(elem_inds[0..], coords.x(coord_inds[nn]));
            elem_inds[dim_field] = 1;
            elem_coord_arr.set(elem_inds[0..], coords.y(coord_inds[nn]));
            elem_inds[dim_field] = 2;
            elem_coord_arr.set(elem_inds[0..], coords.z(coord_inds[nn]));
        }
    }

    return elem_coord_arr;
}

pub fn transformField(
    allocator: std.mem.Allocator,
    connect: *const Connect,
    field: *const Field,
) !NDArray(f64) {
    // dims=(times_num,elems_num,fields_num,nodes_per_elem)
    const field_dims = [_]usize{
        field.getTimeN(),
        connect.elem_n,
        field.getFieldsN(),
        connect.nodes_per_elem,
    };
    var elem_field_arr = try NDArray(f64).initFlat(allocator, field_dims[0..]);
    @memset(elem_field_arr.elems, 0.0);

    const dim_time: usize = 0;
    const dim_elem: usize = 1;
    const dim_field: usize = 2;
    const dim_node: usize = 3;

    var set_elem_inds = [_]usize{ 0, 0, 0, 0 }; // dims=(time,elem,field,node)
    var get_field_inds = [_]usize{ 0, 0, 0 }; // dims=(time,coord,field)

    for (0..elem_field_arr.dims[dim_time]) |tt| {
        get_field_inds[0] = tt;
        set_elem_inds[dim_time] = tt;

        for (0..elem_field_arr.dims[dim_elem]) |ee| {
            set_elem_inds[dim_elem] = ee;
            const coord_inds: []usize = connect.getElem(ee);

            for (0..elem_field_arr.dims[dim_node]) |nn| {
                set_elem_inds[dim_node] = nn;
                get_field_inds[1] = coord_inds[nn];

                for (0..elem_field_arr.dims[dim_field]) |ff| {
                    get_field_inds[2] = ff;
                    const field_val: f64 = field.array.get(get_field_inds[0..]);

                    set_elem_inds[dim_field] = ff;
                    elem_field_arr.set(set_elem_inds[0..], field_val);
                }
            }
        }
    }

    return elem_field_arr;
}

pub fn transformUVs(
    allocator: std.mem.Allocator,
    uvs: *const UVMap,
    connect: *const Connect,
) !NDArray(f64) {
    const elems_num = connect.elem_n;
    const nodes_per_elem = connect.nodes_per_elem;
    var elem_uv_arr = try NDArray(f64).initFlat(
        allocator,
        &[_]usize{ elems_num, 2, nodes_per_elem },
    );
    @memset(elem_uv_arr.elems, 0.0);

    for (0..elems_num) |ee| {
        const coord_inds = connect.getElem(ee);
        for (0..nodes_per_elem) |nn| {
            for (0..2) |uu| {
                const val = uvs.array.get(&[_]usize{ coord_inds[nn], uu });
                elem_uv_arr.set(&[_]usize{ ee, uu, nn }, val);
            }
        }
    }

    return elem_uv_arr;
}
