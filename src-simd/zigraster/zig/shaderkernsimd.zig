const std = @import("std");
pub const shaderops = @import("shaderops.zig");
pub const shaderopssimd = @import("shaderopssimd.zig");
const texops = @import("textureops.zig");
const MatSlice = @import("matslice.zig").MatSlice;
const FeatureConfig = @import("featureconfig.zig").FeatureConfig;
const L = FeatureConfig.simd_lane_width;

const geomkerns = if (FeatureConfig.simd)
    @import("geomkernsimd.zig")
else
    @import("geometrykernels.zig");
const CoordSpace = geomkerns.CoordSpace;

pub fn FlatKernelSIMD(comptime N: usize) type {
    return struct {
        pub inline fn shade(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext(N),
            interp: shaderops.InterpData(N),
            shader: *const shaderops.FlatPrepared,
            ctx_perf: anytype,
            spx_image_scratch: *MatSlice(f64),
        ) void {
            if (@TypeOf(ctx_perf).mode == .perf) {
                ctx_perf.recordDepth(
                    ctx_shade.global_subx, ctx_shade.global_suby, 1.0 / interp.sub_pixel_z,
                );
            }
            if (comptime coord_space == CoordSpace.clip_px_leng) {
                shaderops.fillFlat(N, ctx_shade, interp, shader, spx_image_scratch);
            } else {
                shaderops.fillFlatPerspective(N, ctx_shade, interp, shader, spx_image_scratch);
            }
        }

        pub inline fn shadeSIMD(
            comptime coord_space: CoordSpace,
            mask: @Vector(L, bool),
            ctx_shade: shaderopssimd.ShadeContextSIMD(N),
            interp: shaderopssimd.InterpDataSIMD(N),
            shader: *const shaderops.FlatPrepared,
            ctx_perf: anytype,
            spx_image_scratch: *MatSlice(f64),
        ) void {
            _ = ctx_perf;
            for (0..ctx_shade.actual_fields) |ff| {
                const base = ff * N;
                var vs: @Vector(L, f64) = @splat(0.0);
                if (comptime coord_space == CoordSpace.clip_px_leng) {
                    inline for (0..N) |nn| {
                        vs += interp.weights[nn] * @as(@Vector(L, f64), @splat(ctx_shade.local_buf.data[base + nn]));
                    }
                } else {
                    inline for (0..N) |nn| {
                        const inv_z_vec: @Vector(L, f64) = @splat(interp.nodes_inv_z[nn]);
                        const val_vec: @Vector(L, f64) = @splat(ctx_shade.local_buf.data[base + nn]);
                        vs += interp.weights[nn] * val_vec * inv_z_vec;
                    }
                    vs *= interp.sub_pixel_z;
                }
                const final_val = vs * @as(@Vector(L, f64), @splat(shader.scale_mul)) + 
                                  @as(@Vector(L, f64), @splat(shader.scale_add));
                inline for (0..L) |ll| {
                    if (mask[ll]) {
                        spx_image_scratch.elems[(ctx_shade.idx + ll) * ctx_shade.fields_num + ff] = final_val[ll];
                    }
                }
            }
        }
    };
}

pub fn NormalKernelSIMD(comptime N: usize) type {
    return struct {
        pub inline fn shade(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext(N),
            interp: shaderops.InterpData(N),
            shader: anytype,
            ctx_perf: anytype,
            spx_image_scratch: *MatSlice(f64),
        ) void {
            _ = shader;
            _ = coord_space;
            if (@TypeOf(ctx_perf).mode == .perf) {
                ctx_perf.recordDepth(
                    ctx_shade.global_subx, ctx_shade.global_suby, 1.0 / interp.sub_pixel_z,
                );
            }
            const n = ctx_shade.local_buf.interpolateNormal(interp.weights);
            spx_image_scratch.elems[ctx_shade.idx * ctx_shade.fields_num + 0] = n[0] * 0.5 + 0.5;
            spx_image_scratch.elems[ctx_shade.idx * ctx_shade.fields_num + 1] = n[1] * 0.5 + 0.5;
            spx_image_scratch.elems[ctx_shade.idx * ctx_shade.fields_num + 2] = n[2] * 0.5 + 0.5;
        }

        pub inline fn shadeSIMD(
            comptime coord_space: CoordSpace,
            mask: @Vector(L, bool),
            ctx_shade: shaderopssimd.ShadeContextSIMD(N),
            interp: shaderopssimd.InterpDataSIMD(N),
            shader: anytype,
            ctx_perf: anytype,
            spx_image_scratch: *MatSlice(f64),
        ) void {
            _ = shader; _ = coord_space; _ = ctx_perf;
            var nx: @Vector(L, f64) = @splat(0.0);
            var ny: @Vector(L, f64) = @splat(0.0);
            var nz: @Vector(L, f64) = @splat(0.0);
            inline for (0..N) |nn| {
                const nx_node: @Vector(L, f64) = @splat(ctx_shade.local_buf.normals[0 * N + nn]);
                const ny_node: @Vector(L, f64) = @splat(ctx_shade.local_buf.normals[1 * N + nn]);
                const nz_node: @Vector(L, f64) = @splat(ctx_shade.local_buf.normals[2 * N + nn]);
                nx += interp.weights[nn] * nx_node;
                ny += interp.weights[nn] * ny_node;
                nz += interp.weights[nn] * nz_node;
            }
            inline for (0..L) |ll| {
                if (mask[ll]) {
                    const base = (ctx_shade.idx + ll) * ctx_shade.fields_num;
                    spx_image_scratch.elems[base + 0] = nx[ll] * 0.5 + 0.5;
                    spx_image_scratch.elems[base + 1] = ny[ll] * 0.5 + 0.5;
                    spx_image_scratch.elems[base + 2] = nz[ll] * 0.5 + 0.5;
                }
            }
        }
    };
}

pub fn TexKernelSIMD(comptime N: usize, comptime T: type, comptime channels: usize) type {
    return struct {
        pub inline fn shade(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext(N),
            interp: shaderops.InterpData(N),
            shader: *const shaderops.TexPrepared(T, channels),
            ctx_perf: anytype,
            spx_image_scratch: *MatSlice(f64),
        ) void {
            if (@TypeOf(ctx_perf).mode == .perf) {
                ctx_perf.recordDepth(
                    ctx_shade.global_subx, ctx_shade.global_suby, 1.0 / interp.sub_pixel_z,
                );
            }
            if (comptime coord_space == CoordSpace.clip_px_leng) {
                shaderops.fillTex(N, T, channels, shader.interp_type, ctx_shade, interp, shader, spx_image_scratch);
            } else {
                shaderops.fillTexPerspective(N, T, channels, shader.interp_type, ctx_shade, interp, shader, spx_image_scratch);
            }
        }

        pub inline fn shadeSIMD(
            comptime coord_space: CoordSpace,
            mask: @Vector(L, bool),
            ctx_shade: shaderopssimd.ShadeContextSIMD(N),
            interp: shaderopssimd.InterpDataSIMD(N),
            shader: *const shaderops.TexPrepared(T, channels),
            ctx_perf: anytype,
            spx_image_scratch: *MatSlice(f64),
        ) void {
            _ = ctx_perf;
            var u_at: @Vector(L, f64) = @splat(0.0);
            var v_at: @Vector(L, f64) = @splat(0.0);
            if (comptime coord_space == CoordSpace.clip_px_leng) {
                inline for (0..N) |nn| {
                    const u_n: @Vector(L, f64) = @splat(ctx_shade.local_buf.data[nn]);
                    const v_n: @Vector(L, f64) = @splat(ctx_shade.local_buf.data[N + nn]);
                    u_at += interp.weights[nn] * u_n;
                    v_at += interp.weights[nn] * v_n;
                }
            } else {
                inline for (0..N) |nn| {
                    const inv_z: @Vector(L, f64) = @splat(interp.nodes_inv_z[nn]);
                    const u_n: @Vector(L, f64) = @splat(ctx_shade.local_buf.data[nn]);
                    const v_n: @Vector(L, f64) = @splat(ctx_shade.local_buf.data[N + nn]);
                    u_at += interp.weights[nn] * u_n * inv_z;
                    v_at += interp.weights[nn] * v_n * inv_z;
                }
                u_at *= interp.sub_pixel_z;
                v_at *= interp.sub_pixel_z;
            }
            inline for (0..L) |ll| {
                if (mask[ll]) {
                    const sampled = texops.sampleGeneric(channels, shader.interp_type, shader.texture, u_at[ll], v_at[ll]);
                    inline for (0..channels) |ch| {
                        spx_image_scratch.elems[(ctx_shade.idx + ll) * ctx_shade.fields_num + ch] = sampled[ch] * shader.scale_mul + shader.scale_add;
                    }
                }
            }
        }
    };
}
