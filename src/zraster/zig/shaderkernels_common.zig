const shaderops = @import("shaderops.zig");
const MatSlice = @import("matslice.zig").MatSlice;
const texops = @import("textureops.zig");
const InterpType = texops.InterpType;
const CoordSpace = @import("geometrykernels.zig").CoordSpace;

pub inline fn shadeNodalScalarCommon(
    comptime N: usize,
    comptime coord_space: CoordSpace,
    ctx_shade: shaderops.ShadeContext(N),
    interp: shaderops.InterpData(N),
    shader: *const shaderops.NodalPrepared,
    ctx_report: anytype,
    spx_image_scratch: *MatSlice(f64),
) void {
    if (comptime @TypeOf(ctx_report).mode_tag == .full_stats) {
        ctx_report.recordDepth(
            ctx_shade.global_subx,
            ctx_shade.global_suby,
            1.0 / interp.sub_pixel_z,
        );
    }

    if (shader.elem_normals != null) {
        const normal = ctx_shade.shader_buf.interpolateNormal(interp.weights);
        if (comptime @TypeOf(ctx_report).mode_tag == .full_stats) {
            ctx_report.recordNormal(
                ctx_shade.global_subx,
                ctx_shade.global_suby,
                normal[0],
                normal[1],
                normal[2],
            );
        }
    }

    if (comptime coord_space == CoordSpace.clip_px_leng) {
        shaderops.fillNodalClip(
            N,
            ctx_shade,
            interp,
            shader,
            spx_image_scratch,
        );
    } else {
        shaderops.fillNodalPersp(
            N,
            ctx_shade,
            interp,
            shader,
            spx_image_scratch,
        );
    }
}

pub inline fn shadeTexScalarCommon(
    comptime N: usize,
    comptime TexT: type,
    comptime channels: usize,
    comptime coord_space: CoordSpace,
    ctx_shade: shaderops.ShadeContext(N),
    interp: shaderops.InterpData(N),
    shader: *const shaderops.TexPrepared(TexT, channels),
    ctx_report: anytype,
    spx_image_scratch: *MatSlice(f64),
) void {
    if (comptime @TypeOf(ctx_report).mode_tag == .full_stats) {
        ctx_report.recordDepth(
            ctx_shade.global_subx,
            ctx_shade.global_suby,
            1.0 / interp.sub_pixel_z,
        );
    }

    if (shader.elem_normals != null) {
        const normal = ctx_shade.shader_buf.interpolateNormal(interp.weights);
        if (comptime @TypeOf(ctx_report).mode_tag == .full_stats) {
            ctx_report.recordNormal(
                ctx_shade.global_subx,
                ctx_shade.global_suby,
                normal[0],
                normal[1],
                normal[2],
            );
        }
    }

    if (comptime coord_space == CoordSpace.clip_px_leng) {
        shaderops.fillTexClip(
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
        shaderops.fillTexPersp(
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
