const std = @import("std");
const buildconfig = @import("buildconfig.zig");
pub const shaderops = @import("shaderops.zig");
const texops = @import("textureops.zig");
const MatSlice = @import("matslice.zig").MatSlice;
const InterpType = texops.InterpType;
const common = @import("shaderkernels_common.zig");
const CoordSpace = common.CoordSpace;
const S = buildconfig.config.simd_vector_width;

pub fn NodalKernel(comptime N: usize) type {
    return struct {
        pub inline fn shade(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext(N),
            interp: shaderops.InterpData(N),
            shader: *const shaderops.NodalPrepared,
            ctx_perf: anytype,
            spx_image_scratch: *MatSlice(f64),
        ) void {
            common.recordDepth(
                ctx_perf,
                ctx_shade.global_subx,
                ctx_shade.global_suby,
                interp.sub_pixel_z,
            );

            if (comptime coord_space == CoordSpace.clip_px_leng) {
                shaderops.fillNodal(N, ctx_shade, interp, shader, spx_image_scratch);
            } else {
                shaderops.fillNodalPerspective(
                    N,
                    ctx_shade,
                    interp,
                    shader,
                    spx_image_scratch,
                );
            }
        }

        pub inline fn shadeSIMD(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext(N),
            v_mask: @Vector(S, bool),
            v_weights: [N]@Vector(S, f64),
            v_nodes_inv_z: [N]@Vector(S, f64),
            v_subpx_z: @Vector(S, f64),
            shader: *const shaderops.NodalPrepared,
            spx_image_scratch: *MatSlice(f64),
        ) void {
            _ = v_mask;
            if (comptime coord_space == CoordSpace.raster) {
                shaderops.fillNodalPerspectiveSIMD(
                    N,
                    ctx_shade,
                    v_weights,
                    v_nodes_inv_z,
                    v_subpx_z,
                    shader,
                    spx_image_scratch,
                );
            } else if (comptime coord_space == CoordSpace.clip_px_leng) {
                shaderops.fillNodalSIMD(
                    N,
                    ctx_shade,
                    v_weights,
                    shader,
                    spx_image_scratch,
                );
            } else {
                @panic("shadeSIMD not implemented for this coord_space");
            }
        }
    };
}

pub fn TexKernel(
    comptime N: usize,
    comptime TexT: type,
    comptime channels: usize,
) type {
    return struct {
        pub inline fn shade(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext(N),
            interp: shaderops.InterpData(N),
            shader: *const shaderops.TexPrepared(TexT, channels),
            ctx_perf: anytype,
            spx_image_scratch: *MatSlice(f64),
        ) void {
            common.recordDepth(
                ctx_perf,
                ctx_shade.global_subx,
                ctx_shade.global_suby,
                interp.sub_pixel_z,
            );
            if (comptime coord_space == CoordSpace.clip_px_leng) {
                shaderops.fillTex(
                    N,
                    TexT,
                    channels,
                    shader.interp_type,
                    ctx_shade,
                    interp,
                    shader,
                    spx_image_scratch,
                );
            } else {
                shaderops.fillTexPerspective(
                    N,
                    TexT,
                    channels,
                    shader.interp_type,
                    ctx_shade,
                    interp,
                    shader,
                    spx_image_scratch,
                );
            }
        }

        pub inline fn shadeSIMD(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext(N),
            v_mask: @Vector(S, bool),
            v_weights: [N]@Vector(S, f64),
            v_nodes_inv_z: [N]@Vector(S, f64),
            v_subpx_z: @Vector(S, f64),
            shader: *const shaderops.TexPrepared(TexT, channels),
            spx_image_scratch: *MatSlice(f64),
        ) void {
            if (comptime coord_space == CoordSpace.raster) {
                if (comptime N == 3) {
                    shaderops.fillTexPerspectiveSIMDTri3(
                        N,
                        TexT,
                        channels,
                        shader.interp_type,
                        ctx_shade,
                        v_mask,
                        v_weights,
                        v_nodes_inv_z,
                        v_subpx_z,
                        shader,
                        spx_image_scratch,
                    );
                } else {
                    shaderops.fillTexPerspectiveSIMD(
                        N,
                        TexT,
                        channels,
                        shader.interp_type,
                        ctx_shade,
                        v_mask,
                        v_weights,
                        v_nodes_inv_z,
                        v_subpx_z,
                        shader,
                        spx_image_scratch,
                    );
                }
            } else if (comptime coord_space == CoordSpace.clip_px_leng) {
                shaderops.fillTexSIMD(
                    N,
                    TexT,
                    channels,
                    shader.interp_type,
                    ctx_shade,
                    v_mask,
                    v_weights,
                    shader,
                    spx_image_scratch,
                );
            } else {
                @panic("shadeSIMD not implemented for this coord_space");
            }
        }
    };
}
