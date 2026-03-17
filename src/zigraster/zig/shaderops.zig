const std = @import("std");
const NDArray = @import("ndarray.zig").NDArray;
const MatSlice = @import("matslice.zig").MatSlice;
const iio = @import("imageio.zig");
const Texture = iio.Texture;
const texops = @import("textureops.zig");
const InterpType = texops.InterpType;

const meshio = @import("meshio.zig");
const Field = meshio.Field;

const imageops = @import("imageops.zig");
pub const ScaleOver = enum { within_frames, over_frames };

pub const MAX_FIELDS = 8;

pub fn LocalNodeBuffer(comptime N: usize) type {
    return struct {
        data: [MAX_FIELDS * N]f64 = undefined,
        actual_fields: usize = 0,

        const Self = @This();

        pub inline fn load(
            self: *Self, 
            array: NDArray(f64), 
            start_idx: usize, 
            fields_num: usize
        ) void {
            self.actual_fields = fields_num;
            const count = fields_num * N;
            @memcpy(self.data[0..count], array.elems[start_idx .. start_idx + count]);
        }

        pub inline fn interpolate(
            self: *const Self, 
            field_idx: usize, 
            weights: [N]f64
        ) f64 {
            const base = field_idx * N;
            var sum: f64 = 0.0;
            inline for (0..N) |nn| {
                sum += weights[nn] * self.data[base + nn];
            }
            return sum;
        }
    };
}

pub const FlatShader = struct {
    field: Field,
    bits: ?u8 = 8,
    scaling: imageops.ScaleStrategy = .none,
    scale_over: ScaleOver = .over_frames,
};

pub fn TexShader(comptime T: type, comptime channels: usize) type {
    return struct {
        uvs: NDArray(f64),
        texture: Texture(T, channels),
        interp_type: InterpType = .cubic_lut_lerp,
        bits: ?u8 = 8,
        scaling: imageops.ScaleStrategy = .none,
        scale_mul: f64 = 1.0,
        scale_add: f64 = 0.0,
    };
}

pub fn ShadeContext(comptime N: usize) type {
    return struct {
        frame_index: usize,
        elem_index: usize,
        fields_num: usize,
        actual_fields: usize,
        idx: usize,
        spx_image_scratch: *MatSlice(f64),
        global_subx: usize,
        global_suby: usize,
        local_buf: *const LocalNodeBuffer(N),
    };
}

pub fn InterpData(comptime N: usize) type {
    return struct {
        weights: [N]f64,
        nodes_inv_z: [N]f64,
        sub_pixel_z: f64,
    };
}

pub const Shader = union(enum) {
    flat: FlatShader,
    tex_u8: TexShader(u8, 1),
    tex_u16: TexShader(u16, 1),
    tex_rgb_u8: TexShader(u8, 3),
    tex_rgb_u16: TexShader(u16, 3),
};

pub inline fn fillFlat(
    comptime N: usize,
    ctx: ShadeContext(N),
    interp: InterpData(N),
) void {
    for (0..ctx.actual_fields) |ff| {
        const vs = ctx.local_buf.interpolate(ff, interp.weights);
        ctx.spx_image_scratch.elems[ctx.idx * ctx.fields_num + ff] = vs;
    }
}

pub inline fn fillFlatPerspective(
    comptime N: usize,
    ctx: ShadeContext(N),
    interp: InterpData(N),
) void {
    for (0..ctx.actual_fields) |ff| {
        const base = ff * N;
        var vs: f64 = 0.0;
        inline for (0..N) |nn| {
            const inv_z = interp.nodes_inv_z[nn];
            vs += interp.weights[nn] * ctx.local_buf.data[base + nn] * inv_z;
        }
        
        const final_val = vs * interp.sub_pixel_z;
        ctx.spx_image_scratch.elems[ctx.idx * ctx.fields_num + ff] = final_val;
    }
}

pub inline fn fillTex(
    comptime N: usize,
    comptime TexT: type,
    comptime channels: usize,
    interp_type: InterpType,
    ctx: ShadeContext(N),
    interp: InterpData(N),
    sh: *const TexShader(TexT, channels),
) void {
    var u_at: f64 = 0.0;
    var v_at: f64 = 0.0;
    inline for (0..N) |nn| {
        u_at += interp.weights[nn] * ctx.local_buf.data[nn];
        v_at += interp.weights[nn] * ctx.local_buf.data[N + nn];
    }

    const sampled = texops.sampleGeneric(
        channels,
        interp_type,
        sh.texture,
        u_at,
        v_at,
    );
    inline for (0..channels) |ch| {
        ctx.spx_image_scratch.elems[ctx.idx * ctx.fields_num + ch] = 
            sampled[ch] * sh.scale_mul + sh.scale_add;
    }
}

pub inline fn fillTexPerspective(
    comptime N: usize,
    comptime TexT: type,
    comptime channels: usize,
    interp_type: InterpType,
    ctx: ShadeContext(N),
    interp: InterpData(N),
    sh: *const TexShader(TexT, channels),
) void {
    var u_at: f64 = 0.0;
    var v_at: f64 = 0.0;
    inline for (0..N) |nn| {
        const inv_z = interp.nodes_inv_z[nn];
        u_at += interp.weights[nn] * ctx.local_buf.data[nn] * inv_z;
        v_at += interp.weights[nn] * ctx.local_buf.data[N + nn] * inv_z;
    }

    const sampled = texops.sampleGeneric(
        channels,
        interp_type,
        sh.texture,
        u_at * interp.sub_pixel_z,
        v_at * interp.sub_pixel_z,
    );
    inline for (0..channels) |ch| {
        ctx.spx_image_scratch.elems[ctx.idx * ctx.fields_num + ch] = 
            sampled[ch] * sh.scale_mul + sh.scale_add;
    }
}
