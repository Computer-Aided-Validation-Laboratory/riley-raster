const ndarray = @import("ndarray.zig");
const MatSlice = @import("matslice.zig").MatSlice;
const texops = @import("textureops.zig");
const InterpType = texops.InterpType;
const common = @import("shaderops_common.zig");

const NDArray = ndarray.NDArray;

pub const ScaleOver = common.ScaleOver;
pub const NormalType = common.NormalType;
pub const MAX_FIELDS = common.MAX_FIELDS;
pub const NodalInput = common.NodalInput;
pub const NodalPrepared = common.NodalPrepared;
pub const TexInput = common.TexInput;
pub const TexPrepared = common.TexPrepared;
pub const LocalNodeBuffer = common.LocalNodeBuffer;
pub const ShadeContext = common.ShadeContext;
pub const InterpData = common.InterpData;
pub const ShaderInput = common.ShaderInput;
pub const ShaderPrepared = common.ShaderPrepared;

pub inline fn fillNodal(
    comptime N: usize,
    ctx_shade: ShadeContext(N),
    interp: InterpData(N),
    sh: *const NodalPrepared,
    spx_image_scratch: *MatSlice(f64),
) void {
    for (0..ctx_shade.actual_fields) |ff| {
        const vs = ctx_shade.local_buf.interpolate(ff, interp.weights);
        spx_image_scratch.elems[ctx_shade.idx * ctx_shade.fields_num + ff] =
            vs * sh.scale_mul + sh.scale_add;
    }
}

pub inline fn fillNodalPerspective(
    comptime N: usize,
    ctx_shade: ShadeContext(N),
    interp: InterpData(N),
    sh: *const NodalPrepared,
    spx_image_scratch: *MatSlice(f64),
) void {
    for (0..ctx_shade.actual_fields) |ff| {
        const base = ff * N;
        var vs: f64 = 0.0;
        inline for (0..N) |nn| {
            const inv_z = interp.nodes_inv_z[nn];
            vs += interp.weights[nn] * ctx_shade.local_buf.data[base + nn] * inv_z;
        }

        const final_val = vs * interp.sub_pixel_z;
        spx_image_scratch.elems[ctx_shade.idx * ctx_shade.fields_num + ff] =
            final_val * sh.scale_mul + sh.scale_add;
    }
}

pub inline fn fillTex(
    comptime N: usize,
    comptime TexT: type,
    comptime channels: usize,
    interp_type: InterpType,
    ctx_shade: ShadeContext(N),
    interp: InterpData(N),
    sh: *const TexPrepared(TexT, channels),
    spx_image_scratch: *MatSlice(f64),
) void {
    var u_at: f64 = 0.0;
    var v_at: f64 = 0.0;
    inline for (0..N) |nn| {
        u_at += interp.weights[nn] * ctx_shade.local_buf.data[nn];
        v_at += interp.weights[nn] * ctx_shade.local_buf.data[N + nn];
    }

    const sampled = texops.sampleGeneric(
        channels,
        interp_type,
        sh.texture,
        u_at,
        v_at,
    );
    inline for (0..channels) |ch| {
        spx_image_scratch.elems[ctx_shade.idx * ctx_shade.fields_num + ch] =
            sampled[ch] * sh.scale_mul + sh.scale_add;
    }
}

pub inline fn fillTexPerspective(
    comptime N: usize,
    comptime TexT: type,
    comptime channels: usize,
    interp_type: InterpType,
    ctx_shade: ShadeContext(N),
    interp: InterpData(N),
    sh: *const TexPrepared(TexT, channels),
    spx_image_scratch: *MatSlice(f64),
) void {
    var u_at: f64 = 0.0;
    var v_at: f64 = 0.0;
    inline for (0..N) |nn| {
        const inv_z = interp.nodes_inv_z[nn];
        u_at += interp.weights[nn] * ctx_shade.local_buf.data[nn] * inv_z;
        v_at += interp.weights[nn] * ctx_shade.local_buf.data[N + nn] * inv_z;
    }

    const sampled = texops.sampleGeneric(
        channels,
        interp_type,
        sh.texture,
        u_at * interp.sub_pixel_z,
        v_at * interp.sub_pixel_z,
    );
    inline for (0..channels) |ch| {
        spx_image_scratch.elems[ctx_shade.idx * ctx_shade.fields_num + ch] =
            sampled[ch] * sh.scale_mul + sh.scale_add;
    }
}
