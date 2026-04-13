const std = @import("std");

const buildconfig = @import("buildconfig.zig");
const S = buildconfig.SimdWidth;
const VecSB = buildconfig.VecSB;
const VecSF = buildconfig.VecSF;

const common = @import("shaderkernels_common.zig");
const shaderops = @import("shaderops.zig");
const report = @import("report.zig");
const MatSlice = @import("matslice.zig").MatSlice;
const CoordSpace = @import("geometrykernels.zig").CoordSpace;

pub fn NodalKernel(comptime N: usize) type {
    return struct {
        pub inline fn shade(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext(N),
            interp: shaderops.InterpData(N),
            shader: *const shaderops.NodalPrepared,
            ctx_report: anytype,
            spx_image_scratch: *MatSlice(f64),
        ) void {
            common.shadeNodalScalarCommon(
                N,
                coord_space,
                ctx_shade,
                interp,
                shader,
                ctx_report,
                spx_image_scratch,
            );
        }

        pub inline fn shadeSIMD(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext(N),
            ctx_report: anytype,
            v_mask_active: VecSB,
            v_weights: [N]VecSF,
            v_nodes_inv_z: [N]VecSF,
            v_subpx_z: VecSF,
            shader: *const shaderops.NodalPrepared,
            spx_image_scratch: *MatSlice(f64),
        ) void {
            if (comptime @TypeOf(ctx_report).mode_tag == .full_stats) {
                if (shader.elem_normals != null) {
                    report.recordNormalSIMD(
                        N,
                        S,
                        ctx_report,
                        ctx_shade,
                        v_mask_active,
                        v_weights,
                    );
                }
            }

            if (comptime coord_space == CoordSpace.raster) {
                shaderops.fillNodalPerspSIMD(
                    N,
                    ctx_shade,
                    v_weights,
                    v_nodes_inv_z,
                    v_subpx_z,
                    shader,
                    spx_image_scratch,
                );
            } else if (comptime coord_space == CoordSpace.clip_px_leng) {
                shaderops.fillNodalClipSIMD(
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
            ctx_report: anytype,
            spx_image_scratch: *MatSlice(f64),
        ) void {
            common.shadeTexScalarCommon(
                N,
                TexT,
                channels,
                coord_space,
                ctx_shade,
                interp,
                shader,
                ctx_report,
                spx_image_scratch,
            );
        }

        pub inline fn shadeSIMD(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext(N),
            ctx_report: anytype,
            v_mask_active: VecSB,
            v_weights: [N]VecSF,
            v_nodes_inv_z: [N]VecSF,
            v_subpx_z: VecSF,
            shader: *const shaderops.TexPrepared(TexT, channels),
            spx_image_scratch: *MatSlice(f64),
        ) void {
            if (comptime @TypeOf(ctx_report).mode_tag == .full_stats) {
                if (shader.elem_normals != null) {
                    report.recordNormalSIMD(
                        N,
                        S,
                        ctx_report,
                        ctx_shade,
                        v_mask_active,
                        v_weights,
                    );
                }
            }

            if (comptime coord_space == CoordSpace.raster) {
                shaderops.fillTexPerspSIMD(
                    N,
                    TexT,
                    channels,
                    shader.interp_type,
                    ctx_shade,
                    v_mask_active,
                    v_weights,
                    v_nodes_inv_z,
                    v_subpx_z,
                    shader,
                    spx_image_scratch,
                );
            } else if (comptime coord_space == CoordSpace.clip_px_leng) {
                shaderops.fillTexClipSIMD(
                    N,
                    TexT,
                    channels,
                    shader.interp_type,
                    ctx_shade,
                    v_mask_active,
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
