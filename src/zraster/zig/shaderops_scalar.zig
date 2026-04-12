const MatSlice = @import("matslice.zig").MatSlice;
const texops = @import("textureops.zig");
const InterpType = texops.InterpType;
const common = @import("shaderops_common.zig");

pub inline fn fillNodalClip(
    comptime N: usize,
    ctx_shade: common.ShadeContext(N),
    interp: common.InterpData(N),
    sh: *const common.NodalPrepared,
    spx_image_scratch: *MatSlice(f64),
) void {
    // Scalar scratch stores one sub-pixel contiguously as [field0, field1, ...].
    for (0..@as(usize, ctx_shade.actual_fields)) |ff| {
        const vs = ctx_shade.shader_buf.interpolate(ff, interp.weights);
        spx_image_scratch.slice[ctx_shade.scratch_idx * ctx_shade.fields_num + ff] =
            vs * sh.scale_mul + sh.scale_add;
    }
}

pub inline fn fillNodalPersp(
    comptime N: usize,
    ctx_shade: common.ShadeContext(N),
    interp: common.InterpData(N),
    sh: *const common.NodalPrepared,
    spx_image_scratch: *MatSlice(f64),
) void {
    // Scalar scratch stores one sub-pixel contiguously as [field0, field1, ...].
    for (0..@as(usize, ctx_shade.actual_fields)) |ff| {
        const base = ff * N;
        var vs: f64 = 0.0;
        inline for (0..N) |nn| {
            const inv_z = interp.nodes_inv_z[nn];
            vs += interp.weights[nn] * ctx_shade.shader_buf.data[base + nn] * inv_z;
        }

        const final_val = vs * interp.sub_pixel_z;
        spx_image_scratch.slice[ctx_shade.scratch_idx * ctx_shade.fields_num + ff] =
            final_val * sh.scale_mul + sh.scale_add;
    }
}

pub inline fn fillTexClip(
    comptime N: usize,
    comptime TexT: type,
    comptime channels: usize,
    interp_type: InterpType,
    ctx_shade: common.ShadeContext(N),
    interp: common.InterpData(N),
    sh: *const common.TexPrepared(TexT, channels),
    spx_image_scratch: *MatSlice(f64),
) void {
    var u_at: f64 = 0.0;
    var tex_v_at: f64 = 0.0;
    inline for (0..N) |nn| {
        u_at += interp.weights[nn] * ctx_shade.shader_buf.data[nn];
        tex_v_at += interp.weights[nn] * ctx_shade.shader_buf.data[N + nn];
    }

    const sampled = texops.sampleGeneric(
        channels,
        interp_type,
        sh.texture,
        u_at,
        tex_v_at,
    );
    // Scalar scratch stores one sub-pixel contiguously as [ch0, ch1, ...].
    inline for (0..channels) |ch| {
        spx_image_scratch.slice[ctx_shade.scratch_idx * ctx_shade.fields_num + ch] =
            sampled[ch] * sh.scale_mul + sh.scale_add;
    }
}

pub inline fn fillTexPersp(
    comptime N: usize,
    comptime TexT: type,
    comptime channels: usize,
    interp_type: InterpType,
    ctx_shade: common.ShadeContext(N),
    interp: common.InterpData(N),
    sh: *const common.TexPrepared(TexT, channels),
    spx_image_scratch: *MatSlice(f64),
) void {
    var u_at: f64 = 0.0;
    var tex_v_at: f64 = 0.0;
    inline for (0..N) |nn| {
        const inv_z = interp.nodes_inv_z[nn];
        u_at += interp.weights[nn] * ctx_shade.shader_buf.data[nn] * inv_z;
        tex_v_at += interp.weights[nn] * ctx_shade.shader_buf.data[N + nn] * inv_z;
    }

    const sampled = texops.sampleGeneric(
        channels,
        interp_type,
        sh.texture,
        u_at * interp.sub_pixel_z,
        tex_v_at * interp.sub_pixel_z,
    );
    // Scalar scratch stores one sub-pixel contiguously as [ch0, ch1, ...].
    inline for (0..channels) |ch| {
        spx_image_scratch.slice[ctx_shade.scratch_idx * ctx_shade.fields_num + ch] =
            sampled[ch] * sh.scale_mul + sh.scale_add;
    }
}
