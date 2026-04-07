const std = @import("std");
const shaderops = @import("shaderops.zig");
const report = @import("report.zig");
const texops = @import("textureops.zig");
const MatSlice = @import("matslice.zig").MatSlice;
const InterpType = texops.InterpType;
const common = @import("shaderkernels_common.zig");
const CoordSpace = common.CoordSpace;

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

            if (shader.elem_normals != null) {
                const normal = ctx_shade.shader_buf.interpolateNormal(interp.weights);
                if (comptime @TypeOf(ctx_perf).mode_tag == .full_stats) {
                    report.maybeRecordNormal(
                        ctx_perf,
                        ctx_shade.global_subx,
                        ctx_shade.global_suby,
                        normal,
                    );
                }
            }

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
    };
}

pub fn TexKernel(
    comptime N: usize,
    comptime T: type,
    comptime channels: usize,
) type {
    return struct {
        pub inline fn shade(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext(N),
            interp: shaderops.InterpData(N),
            shader: *const shaderops.TexPrepared(T, channels),
            ctx_perf: anytype,
            spx_image_scratch: *MatSlice(f64),
        ) void {
            common.recordDepth(
                ctx_perf,
                ctx_shade.global_subx,
                ctx_shade.global_suby,
                interp.sub_pixel_z,
            );

            if (shader.elem_normals != null) {
                const normal = ctx_shade.shader_buf.interpolateNormal(interp.weights);
                if (comptime @TypeOf(ctx_perf).mode_tag == .full_stats) {
                    report.maybeRecordNormal(
                        ctx_perf,
                        ctx_shade.global_subx,
                        ctx_shade.global_suby,
                        normal,
                    );
                }
            }
            if (comptime coord_space == CoordSpace.clip_px_leng) {
                shaderops.fillTex(
                    N,
                    T,
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
                    T,
                    channels,
                    shader.interp_type,
                    ctx_shade,
                    interp,
                    shader,
                    spx_image_scratch,
                );
            }
        }
    };
}
