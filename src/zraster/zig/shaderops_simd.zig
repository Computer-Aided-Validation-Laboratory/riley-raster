const std = @import("std");
const ndarray = @import("ndarray.zig");
const MatSlice = @import("matslice.zig").MatSlice;
const texops = @import("textureops.zig");
const InterpType = texops.InterpType;
const common = @import("shaderops_common.zig");

const NDArray = ndarray.NDArray;

pub const ScaleOver = common.ScaleOver;
pub const NormalType = common.NormalType;
pub const MAX_FIELDS = common.MAX_FIELDS;
pub const FlatInput = common.FlatInput;
pub const FlatPrepared = common.FlatPrepared;
pub const TexInput = common.TexInput;
pub const TexPrepared = common.TexPrepared;
pub const LocalNodeBuffer = common.LocalNodeBuffer;
pub const ShadeContext = common.ShadeContext;
pub const InterpData = common.InterpData;
pub const ShaderInput = common.ShaderInput;
pub const ShaderPrepared = common.ShaderPrepared;

pub inline fn fillFlat(
    comptime N: usize,
    ctx_shade: ShadeContext(N),
    interp: InterpData(N),
    sh: *const FlatPrepared,
    spx_image_scratch: *MatSlice(f64),
) void {
    for (0..ctx_shade.actual_fields) |ff| {
        const vs = ctx_shade.local_buf.interpolate(ff, interp.weights);
        spx_image_scratch.elems[ff * spx_image_scratch.cols_num + ctx_shade.idx] =
            vs * sh.scale_mul + sh.scale_add;
    }
}

pub inline fn fillFlatPerspective(
    comptime N: usize,
    ctx_shade: ShadeContext(N),
    interp: InterpData(N),
    sh: *const FlatPrepared,
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
        spx_image_scratch.elems[ff * spx_image_scratch.cols_num + ctx_shade.idx] =
            final_val * sh.scale_mul + sh.scale_add;
    }
}

pub inline fn fillFlatSIMD(
    comptime N: usize,
    ctx_shade: ShadeContext(N),
    v_weights: [N]@Vector(8, f64),
    sh: *const FlatPrepared,
    spx_image_scratch: *MatSlice(f64),
) void {
    const v_mul: @Vector(8, f64) = @splat(sh.scale_mul);
    const v_add: @Vector(8, f64) = @splat(sh.scale_add);
    const px_stride = spx_image_scratch.cols_num;

    inline for (0..MAX_FIELDS) |ff| {
        if (ff >= ctx_shade.actual_fields) break;
        const base = ff * N;
        var v_vs: @Vector(8, f64) = @splat(0.0);
        inline for (0..N) |nn| {
            v_vs += v_weights[nn] * @as(@Vector(8, f64), @splat(ctx_shade.local_buf.data[base + nn]));
        }

        const v_final = v_vs * v_mul + v_add;
        const flat_idx = ff * px_stride + ctx_shade.idx;
        const ptr_out: *align(8) @Vector(8, f64) = @ptrCast(&spx_image_scratch.elems[flat_idx]);
        const v_old_val: @Vector(8, f64) = ptr_out.*;
        ptr_out.* = @select(f64, ctx_shade.v_mask.?, v_final, v_old_val);
    }
}

pub inline fn fillFlatPerspectiveSIMD(
    comptime N: usize,
    ctx_shade: ShadeContext(N),
    v_weights: [N]@Vector(8, f64),
    v_nodes_inv_z: [N]@Vector(8, f64),
    v_subpx_z: @Vector(8, f64),
    sh: *const FlatPrepared,
    spx_image_scratch: *MatSlice(f64),
) void {
    const v_mul: @Vector(8, f64) = @splat(sh.scale_mul);
    const v_add: @Vector(8, f64) = @splat(sh.scale_add);
    const px_stride = spx_image_scratch.cols_num;

    inline for (0..MAX_FIELDS) |ff| {
        if (ff >= ctx_shade.actual_fields) break;
        const base = ff * N;
        var v_vs: @Vector(8, f64) = @splat(0.0);
        inline for (0..N) |nn| {
            v_vs += v_weights[nn] * v_nodes_inv_z[nn] * @as(@Vector(8, f64), @splat(ctx_shade.local_buf.data[base + nn]));
        }

        const v_final = (v_vs * v_subpx_z) * v_mul + v_add;
        const flat_idx = ff * px_stride + ctx_shade.idx;
        const ptr_out: *align(8) @Vector(8, f64) = @ptrCast(&spx_image_scratch.elems[flat_idx]);
        const v_old_val: @Vector(8, f64) = ptr_out.*;
        ptr_out.* = @select(f64, ctx_shade.v_mask.?, v_final, v_old_val);
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
        spx_image_scratch.elems[ch * spx_image_scratch.cols_num + ctx_shade.idx] =
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
        spx_image_scratch.elems[ch * spx_image_scratch.cols_num + ctx_shade.idx] =
            sampled[ch] * sh.scale_mul + sh.scale_add;
    }
}

pub inline fn fillTexSIMD(
    comptime N: usize,
    comptime TexT: type,
    comptime channels: usize,
    interp_type: InterpType,
    ctx_shade: ShadeContext(N),
    v_mask: @Vector(8, bool),
    v_weights: [N]@Vector(8, f64),
    sh: *const TexPrepared(TexT, channels),
    spx_image_scratch: *MatSlice(f64),
) void {
    var v_u_at: @Vector(8, f64) = @splat(0.0);
    var v_v_at: @Vector(8, f64) = @splat(0.0);
    inline for (0..N) |nn| {
        v_u_at += v_weights[nn] * @as(@Vector(8, f64), @splat(ctx_shade.local_buf.data[nn]));
        v_v_at += v_weights[nn] * @as(@Vector(8, f64), @splat(ctx_shade.local_buf.data[N + nn]));
    }

    const px_stride = spx_image_scratch.cols_num;
    const mask_arr: [8]bool = v_mask;
    const u_at_arr: [8]f64 = v_u_at;
    const v_at_arr: [8]f64 = v_v_at;

    for (0..8) |ii| {
        if (mask_arr[ii]) {
            const sampled = texops.sampleGeneric(
                channels,
                interp_type,
                sh.texture,
                u_at_arr[ii],
                v_at_arr[ii],
            );

            inline for (0..channels) |ch| {
                spx_image_scratch.elems[ch * px_stride + ctx_shade.idx + ii] = sampled[ch] * sh.scale_mul + sh.scale_add;
            }
        }
    }
}

pub inline fn fillTexPerspectiveSIMD(
    comptime N: usize,
    comptime TexT: type,
    comptime channels: usize,
    interp_type: InterpType,
    ctx_shade: ShadeContext(N),
    v_mask: @Vector(8, bool),
    v_weights: [N]@Vector(8, f64),
    v_nodes_inv_z: [N]@Vector(8, f64),
    v_subpx_z: @Vector(8, f64),
    sh: *const TexPrepared(TexT, channels),
    spx_image_scratch: *MatSlice(f64),
) void {
    const v_mul: @Vector(8, f64) = @splat(sh.scale_mul);
    const v_add: @Vector(8, f64) = @splat(sh.scale_add);
    const px_stride = spx_image_scratch.cols_num;

    // SIMD UV Interpolation
    var v_u_at: @Vector(8, f64) = @splat(0.0);
    var v_v_at: @Vector(8, f64) = @splat(0.0);
    inline for (0..N) |nn| {
        const v_inv_z = v_nodes_inv_z[nn];
        v_u_at += v_weights[nn] * @as(@Vector(8, f64), @splat(ctx_shade.local_buf.data[nn])) * v_inv_z;
        v_v_at += v_weights[nn] * @as(@Vector(8, f64), @splat(ctx_shade.local_buf.data[N + nn])) * v_inv_z;
    }

    v_u_at *= v_subpx_z;
    v_v_at *= v_subpx_z;

    const sampled_vecs = texops.sampleGenericHybrid(
        channels,
        interp_type,
        v_mask,
        sh.texture,
        v_u_at,
        v_v_at,
    );

    inline for (0..channels) |ch| {
        const v_final = sampled_vecs[ch] * v_mul + v_add;
        const flat_idx = ch * px_stride + ctx_shade.idx;
        const ptr_out: *align(8) @Vector(8, f64) = @ptrCast(&spx_image_scratch.elems[flat_idx]);
        const v_old_val: @Vector(8, f64) = ptr_out.*;
        ptr_out.* = @select(f64, v_mask, v_final, v_old_val);
    }
}

pub inline fn fillTexPerspectiveSIMDTri3(
    comptime N: usize,
    comptime TexT: type,
    comptime channels: usize,
    interp_type: InterpType,
    ctx_shade: ShadeContext(N),
    v_mask: @Vector(8, bool),
    v_weights: [N]@Vector(8, f64),
    v_nodes_inv_z: [N]@Vector(8, f64),
    v_subpx_z: @Vector(8, f64),
    sh: *const TexPrepared(TexT, channels),
    spx_image_scratch: *MatSlice(f64),
) void {
    const v_mul: @Vector(8, f64) = @splat(sh.scale_mul);
    const v_add: @Vector(8, f64) = @splat(sh.scale_add);
    const px_stride = spx_image_scratch.cols_num;

    var v_u_at: @Vector(8, f64) = @splat(0.0);
    var v_v_at: @Vector(8, f64) = @splat(0.0);
    inline for (0..N) |nn| {
        const v_inv_z = v_nodes_inv_z[nn];
        v_u_at += v_weights[nn] * @as(@Vector(8, f64), @splat(ctx_shade.local_buf.data[nn])) * v_inv_z;
        v_v_at += v_weights[nn] * @as(@Vector(8, f64), @splat(ctx_shade.local_buf.data[N + nn])) * v_inv_z;
    }

    v_u_at *= v_subpx_z;
    v_v_at *= v_subpx_z;

    const sampled_vecs = texops.sampleGenericHybridTri3Local(
        channels,
        interp_type,
        v_mask,
        sh.texture,
        v_u_at,
        v_v_at,
    );

    inline for (0..channels) |ch| {
        const v_final = sampled_vecs[ch] * v_mul + v_add;
        const flat_idx = ch * px_stride + ctx_shade.idx;
        const ptr_out: *align(8) @Vector(8, f64) = @ptrCast(&spx_image_scratch.elems[flat_idx]);
        const v_old_val: @Vector(8, f64) = ptr_out.*;
        ptr_out.* = @select(f64, v_mask, v_final, v_old_val);
    }
}
