const ndarray = @import("ndarray.zig");
const NDArray = ndarray.NDArray;
const MappedNDArray = ndarray.MappedNDArray;
const iio = @import("imageio.zig");
const Texture = iio.Texture;
const texops = @import("textureops.zig");
const InterpType = texops.InterpType;
const meshio = @import("meshio.zig");
const Field = meshio.Field;
const imageops = @import("imageops.zig");
const buildconfig = @import("buildconfig.zig");
const cfg = buildconfig.config;
const S = cfg.simd_vector_width;

pub const ScaleOver = enum { within_frames, over_frames };
pub const NormalType = enum { none, exact, averaged };

pub fn LocalNodeBuffer(comptime N: usize) type {
    return struct {
        data: [cfg.max_nodal_fields * N]f64 = undefined,
        normals: [3 * N]f64 = undefined,
        actual_fields: usize = 0,
        has_normals: bool = false,

        const Self = @This();

        pub inline fn load(
            self: *Self,
            array: NDArray(f64),
            start_idx: usize,
            fields_num: usize,
        ) void {
            self.actual_fields = fields_num;
            const count = fields_num * N;
            @memcpy(self.data[0..count], array.elems[start_idx .. start_idx + count]);
        }

        pub inline fn loadNormals(
            self: *Self,
            array: NDArray(f64),
            start_idx: usize,
        ) void {
            self.has_normals = true;
            const count = 3 * N;
            @memcpy(self.normals[0..count], array.elems[start_idx .. start_idx + count]);
        }

        pub inline fn interpolate(
            self: *const Self,
            field_idx: usize,
            weights: [N]f64,
        ) f64 {
            const base = field_idx * N;
            var sum: f64 = 0.0;
            inline for (0..N) |nn| {
                sum += weights[nn] * self.data[base + nn];
            }
            return sum;
        }

        pub inline fn interpolateNormal(
            self: *const Self,
            weights: [N]f64,
        ) [3]f64 {
            var norm = [3]f64{ 0.0, 0.0, 0.0 };
            inline for (0..N) |nn| {
                norm[0] += weights[nn] * self.normals[0 * N + nn];
                norm[1] += weights[nn] * self.normals[1 * N + nn];
                norm[2] += weights[nn] * self.normals[2 * N + nn];
            }
            return norm;
        }
    };
}

pub const NodalInput = struct {
    field: Field,
    bits: ?u8 = 8,
    scaling: imageops.ScaleStrategy = .none,
    scale_over: ScaleOver = .over_frames,
    normal_type: NormalType = .none,
};

pub const NodalPrepared = struct {
    elem_field: NDArray(f64),
    bits: ?u8 = 8,
    scaling: imageops.ScaleStrategy = .none,
    scale_over: ScaleOver = .over_frames,
    scale_mul: f64 = 1.0,
    scale_add: f64 = 0.0,
    normal_type: NormalType = .none,
    elem_normals: ?MappedNDArray(f64) = null,
};

pub fn TexInput(comptime T: type, comptime channels: usize) type {
    return struct {
        uvs: NDArray(f64),
        texture: Texture(T, channels),
        interp_type: InterpType = .cubic_lut_lerp,
        bits: ?u8 = 8,
        scaling: imageops.ScaleStrategy = .none,
        normal_type: NormalType = .none,
    };
}

pub fn TexPrepared(comptime T: type, comptime channels: usize) type {
    return struct {
        elem_uvs: NDArray(f64),
        texture: Texture(T, channels),
        interp_type: InterpType = .cubic_lut_lerp,
        bits: ?u8 = 8,
        scaling: imageops.ScaleStrategy = .none,
        scale_mul: f64 = 1.0,
        scale_add: f64 = 0.0,
        normal_type: NormalType = .none,
        elem_normals: ?MappedNDArray(f64) = null,
    };
}

pub fn ShadeContext(comptime N: usize) type {
    return struct {
        frame_index: usize,
        elem_index: usize,
        fields_num: usize,
        actual_fields: usize,
        idx: usize,
        global_subx: usize,
        global_suby: usize,
        local_buf: *const LocalNodeBuffer(N),
        v_mask: ?@Vector(S, bool) = null,
    };
}

pub fn InterpData(comptime N: usize) type {
    return struct {
        weights: [N]f64,
        nodes_inv_z: [N]f64,
        sub_pixel_z: f64,
    };
}

pub const ShaderInput = union(enum) {
    nodal: NodalInput,
    tex_u8: TexInput(u8, 1),
    tex_u16: TexInput(u16, 1),
    tex_rgb_u8: TexInput(u8, 3),
    tex_rgb_u16: TexInput(u16, 3),
};

pub const ShaderPrepared = union(enum) {
    nodal: NodalPrepared,
    tex_u8: TexPrepared(u8, 1),
    tex_u16: TexPrepared(u16, 1),
    tex_rgb_u8: TexPrepared(u8, 3),
    tex_rgb_u16: TexPrepared(u16, 3),
};
