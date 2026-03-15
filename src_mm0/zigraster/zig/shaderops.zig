const std = @import("std");
const NDArray = @import("ndarray.zig").NDArray;
const MatSlice = @import("matslice.zig").MatSlice;
const iio = @import("imageio.zig");
const Texture = iio.Texture;
const texops = @import("textureops.zig");
const InterpType = texops.InterpType;

const meshio = @import("meshio.zig");
const Field = meshio.Field;

pub const FlatShader = struct {
    field: Field,
    bits: ?u8 = null,
};

pub const TexShader = struct {
    uvs: NDArray(f64),
    texture: Texture(u8, 1),
    interp_type: InterpType = .cubic_lut_lerp,
};

pub const Shader = union(enum) {
    flat: FlatShader,
    texture: TexShader,
};

pub inline fn fillFlat(
    comptime N: usize,
    frame_ind: usize,
    elem_ind: usize,
    actual_fields: usize,
    fields_num: usize,
    weights: [N]f64,
    sh: *const FlatShader,
    idx: usize,
    spx_image_scratch: *MatSlice(f64),
) void {
    const e_stride = sh.field.array.strides[1];
    const f_stride = sh.field.array.strides[2];
    const f_off = frame_ind * sh.field.array.strides[0] + elem_ind * e_stride;

    for (0..actual_fields) |ff| {
        const ff_off = f_off + ff * f_stride;
        var vs: f64 = 0.0;
        inline for (0..N) |nn| {
            vs += weights[nn] * sh.field.array.elems[ff_off + nn];
        }
        spx_image_scratch.elems[idx * fields_num + ff] = vs;
    }
}

pub inline fn fillFlatPerspective(
    comptime N: usize,
    frame_ind: usize,
    elem_ind: usize,
    actual_fields: usize,
    fields_num: usize,
    weights: [N]f64,
    nodes_inv_z: [N]f64,
    spx_z: f64,
    sh: *const FlatShader,
    idx: usize,
    spx_image_scratch: *MatSlice(f64),
) void {
    const e_stride = sh.field.array.strides[1];
    const f_stride = sh.field.array.strides[2];
    const f_off = frame_ind * sh.field.array.strides[0] + elem_ind * e_stride;

    for (0..actual_fields) |ff| {
        const ff_off = f_off + ff * f_stride;
        var vs: f64 = 0.0;
        inline for (0..N) |nn| {
            vs += weights[nn] * sh.field.array.elems[ff_off + nn] * nodes_inv_z[nn];
        }
        
        const final_val = vs * spx_z;
        if (final_val != 0.0) {
             // std.debug.print("fillFlatPersp: non-zero write! final={d:.6}\n", .{final_val});
        }

        spx_image_scratch.elems[idx * fields_num + ff] = final_val;
    }
}

pub inline fn fillTex(
    comptime N: usize,
    comptime interp_type: InterpType,
    elem_ind: usize,
    weights: [N]f64,
    sh: *const TexShader,
    idx: usize,
    spx_image_scratch: *MatSlice(f64),
) void {
    const e_stride = sh.uvs.strides[0];
    const c_stride = sh.uvs.strides[1];
    const uv_off = elem_ind * e_stride;

    var u_at: f64 = 0.0;
    var v_at: f64 = 0.0;
    inline for (0..N) |nn| {
        u_at += weights[nn] * sh.uvs.elems[uv_off + nn];
        v_at += weights[nn] * sh.uvs.elems[uv_off + c_stride + nn];
    }

    spx_image_scratch.elems[idx] = texops.sampleGreyscale(
        interp_type,
        sh.texture,
        u_at,
        v_at,
    );
}

pub inline fn fillTexPerspective(
    comptime N: usize,
    comptime interp_type: InterpType,
    elem_ind: usize,
    weights: [N]f64,
    nodes_inv_z: [N]f64,
    spx_z: f64,
    sh: *const TexShader,
    idx: usize,
    spx_image_scratch: *MatSlice(f64),
) void {
    const e_stride = sh.uvs.strides[0];
    const c_stride = sh.uvs.strides[1];
    const uv_off = elem_ind * e_stride;

    var u_at: f64 = 0.0;
    var v_at: f64 = 0.0;
    inline for (0..N) |nn| {
        const inv_z = nodes_inv_z[nn];
        u_at += weights[nn] * sh.uvs.elems[uv_off + nn] * inv_z;
        v_at += weights[nn] * sh.uvs.elems[uv_off + c_stride + nn] * inv_z;
    }

    spx_image_scratch.elems[idx] = texops.sampleGreyscale(
        interp_type,
        sh.texture,
        u_at * spx_z,
        v_at * spx_z,
    );
}
