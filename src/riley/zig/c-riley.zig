// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const riley = @import("api.zig");
const maths = riley.maths;
const ops = riley.ops;
const dataio = riley.dataio;
const F = maths.F;

// --------------------------------------------------------------------------
// Public C ABI Contract
//
// The public Riley C ABI is fixed to the production Riley build:
// - precision: f64
// - SIMD: on
//
// This keeps the exported ABI stable for C, Cython and Python callers.
// If you need alternate precision or SIMD experiments, use the native Zig
// entry points rather than this public C interface.
// --------------------------------------------------------------------------
comptime {
    if (F != f64) @compileError("The public Riley C ABI must be built with f64.");
}

const error_buf_len: usize = 512;
const default_image_save_opts = [_]dataio.ImageSaveOpts{
    .{
        .format = .bmp,
        .file_bits = 8,
        .scaling = .none,
    },
};

var last_error_buf: [error_buf_len]u8 = [_]u8{0} ** error_buf_len;

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

pub const CVec2U32 = extern struct {
    x: u32,
    y: u32,
};

pub const CVec2F64 = extern struct {
    x: F,
    y: F,
};

pub const CVec3F64 = extern struct {
    x: F,
    y: F,
    z: F,
};

pub const CArray2DF64 = extern struct {
    elems: [*c]const F,
    rows_num: usize,
    cols_num: usize,
};

pub const CArray2DUsize = extern struct {
    elems: [*c]const usize,
    rows_num: usize,
    cols_num: usize,
};

pub const CArray3DF64 = extern struct {
    elems: [*c]const F,
    dim0: usize,
    dim1: usize,
    dim2: usize,
};

pub const CArray3DU8 = extern struct {
    elems: [*c]const u8,
    dim0: usize,
    dim1: usize,
    dim2: usize,
};

pub const CArray3DU16 = extern struct {
    elems: [*c]const u16,
    dim0: usize,
    dim1: usize,
    dim2: usize,
};

pub const CDims5Usize = extern struct {
    dim0: usize,
    dim1: usize,
    dim2: usize,
    dim3: usize,
    dim4: usize,
};

pub const CImageBuffF64 = extern struct {
    elems: [*c]F,
    dims: CDims5Usize,
};

pub const CDistort = extern struct {
    distort_model: u32,
    distort_k1: F,
    distort_k2: F,
    distort_k3: F,
    distort_k4: F,
    distort_k5: F,
    distort_k6: F,
    distort_p1: F,
    distort_p2: F,
    distort_s1: F,
    distort_s2: F,
    distort_s3: F,
    distort_s4: F,
    distort_tau_x: F,
    distort_tau_y: F,
    distort_poly_degree: u32,
    distort_poly_mode: u32,
    distort_poly_coeffs: [*c]const F,
    distort_poly_coeffs_len: usize,
};

pub const CPSF = extern struct {
    psf_type: u32,
    psf_sigma_x: F,
    psf_sigma_y: F,
    psf_theta: F,
    psf_supp_rad: F,
    psf_separable: u32,
};

pub const CImageSaveOpts = extern struct {
    format: u32,
    file_bits: c_int,
    adc_bits: c_int,
    scaling_tag: u32,
    scaling_min: F,
    scaling_max: F,
    packing: u32,
};

pub const CCameraInput = extern struct {
    pixels_num: CVec2U32,
    pixels_size: CVec2F64,
    pos_world: CVec3F64,
    rot_world: CVec3F64,
    roi_cent_world: CVec3F64,
    focal_length: F,
    sub_sample: u32,
    background_value: F,
    distort: CDistort,
    psf: CPSF,
    coord_sys: u32,
    subpixel_center_map: u32,
    render_format_tag: u32,
    render_channels: u32,
    output_files: [*c]const CImageSaveOpts,
    output_files_len: usize,
};

pub const CFuncShaderParams = extern struct {
    coord_scale: [2]F,
    coord_offset: [2]F,
    constant_value: F,
    constant_value_rgb: [3]F,
    linear_coeff: [3]F,
    linear_coeff_rgb: [3][3]F,
    quadratic_coeff: [6]F,
    quadratic_coeff_rgb: [3][6]F,
    wave_num_scalar: [2]F,
    wave_num_rgb: [3]F,
    sinusoidal_bias: F,
    sinusoidal_amp: [2]F,
    sinusoidal_bias_rgb: [3]F,
    sinusoidal_amp_rgb: [3]F,
    checker_level: [2]F,
    checker_smooth_frequency: F,
    lambertian_coeff: [2]F,
    lambertian_coeff_rgb: [3][2]F,
    eggbox_mean: F,
    eggbox_contrast: F,
    eggbox_pitch: [2]F,
    eggbox_phase: [2]F,
};

pub const CFuncChannel = extern struct {
    builtin: u32,
    params: CFuncShaderParams,
    output_gain: F,
    output_offset: F,
    scaling_tag: u32,
    scaling_min: F,
    scaling_max: F,
};

pub const CTextureData = extern union {
    f: CArray3DF64,
    u8: CArray3DU8,
    u16: CArray3DU16,
};

pub const CTextureInput = extern struct {
    uvs: CArray2DF64,
    data: CTextureData,
    storage: u32,
    sample: u32,
    sample_mode: u32,
};

pub const CNodalInput = extern struct {
    field: CArray3DF64,
    scale_over: u32,
};

pub const CFunctionInput = extern struct {
    uvs: CArray2DF64,
    builtin: u32,
    coord_mode: u32,
    params: CFuncShaderParams,
    channels: [*c]const CFuncChannel,
    channels_len: usize,
};

pub const CShaderPayload = extern union {
    texture: CTextureInput,
    nodal: CNodalInput,
    func: CFunctionInput,
};

pub const CShaderInput = extern struct {
    shader_tag: u32,
    output_gain: F,
    output_offset: F,
    scaling_tag: u32,
    scaling_min: F,
    scaling_max: F,
    value: CShaderPayload,
};

pub const CRegister = extern struct { kind: u32, index: u32 };
pub const CResolverOp = extern struct {
    tag: u32,
    register_ref: CRegister,
    lower: F,
    upper: F,
};
pub const CLookup = extern struct {
    first: F,
    step: F,
    values: [*c]const F,
    values_len: usize,
};
pub const CResolver = extern struct {
    tag: u32,
    registers: [*c]const CRegister,
    registers_len: usize,
    weights: [*c]const F,
    weights_len: usize,
    factor: CRegister,
    temperature: CRegister,
    emissivity: CRegister,
    ambient: F,
    gain: F,
    lookup: CLookup,
    operations: [*c]const CResolverOp,
    operations_len: usize,
};
pub const CPipeStage = extern struct {
    tag: u32,
    shader: [*c]const CShaderInput,
    register_source: CRegister,
    register_dest: CRegister,
    lower: F,
    upper: F,
    black: F,
    white: F,
    register_source_b: CRegister,
    alpha_register: CRegister,
    alpha: F,
    alpha_from_register: u32,
    gain: F,
    offset: F,
    components: u32,
    lookup: CLookup,
};
pub const CPipe = extern struct {
    stages: [*c]const CPipeStage,
    stages_len: usize,
    resolver: CResolver,
    constants: [*c]const F,
    constants_len: usize,
};

pub const CShaderExecution = extern union {
    direct: CShaderInput,
    pipe: CPipe,
};

pub const CShaderEntry = extern struct {
    format_tag: u32,
    execution_tag: u32,
    value: CShaderExecution,
};

pub const CMeshInput = extern struct {
    mesh_type: u32,
    normal_type: u32,
    coords: CArray2DF64,
    connect: CArray2DUsize,
    disp: CArray3DF64,
    shaders: [*c]const CShaderEntry,
    shaders_len: usize,
};

pub const CRasterConfig = extern struct {
    render_mode: u32,
    parallel_mode: u32,
    thread_count: u16,
    save_strategy: u32,
    oneroot_hull_mode: u32,
    oneroot_newton_seed_mode: u32,
    oneroot_newton_seed_reuse: u32,
    oneroot_edge_fun_mode: u32,
    multiroot_mode: u32,
    multiroot_edge_fun_mode: u32,
    validate_input: u32,
    report_perf: u32,
    report_console: u8,
    tile_size_min: u16,
    tile_size_max: u16,
    disk_save_overlap: u8,
    tile_size_override: u16,
    global_subpx_tile_size_min: u16,
    global_subpx_tile_size_max: u16,
    global_subpx_tile_size_override: u16,
    global_subpx_stripe_size_min: u16,
    global_subpx_stripe_size_max: u16,
    global_subpx_stripe_size_override: u16,
    raster_halo_px_override: u16,
    save_frame_buff_count: usize,
    buffer_mode: u32,
    output_name_format: ?[*:0]const u8,
    edge_spacing_px: F,
};

fn clearLastError() void {
    @memset(last_error_buf[0..], 0);
}

fn setLastErrorSlice(msg: []const u8) void {
    clearLastError();
    const copy_len = @min(msg.len, error_buf_len - 1);
    @memcpy(last_error_buf[0..copy_len], msg[0..copy_len]);
}

fn setLastError(err: anyerror) void {
    var msg_buf: [error_buf_len]u8 = undefined;
    const msg = std.fmt.bufPrint(
        msg_buf[0..],
        "{s}",
        .{@errorName(err)},
    ) catch @errorName(err);
    setLastErrorSlice(msg);
}

pub export fn rileyGetLastError(
    out_buf: [*c]u8,
    out_buf_len: usize,
) usize {
    if (out_buf == null or out_buf_len == 0) {
        return 0;
    }

    const msg_len = std.mem.indexOfScalar(
        u8,
        last_error_buf[0..],
        0,
    ) orelse last_error_buf.len;
    const copy_len = @min(msg_len, out_buf_len - 1);
    @memcpy(out_buf[0..copy_len], last_error_buf[0..copy_len]);
    out_buf[copy_len] = 0;
    return copy_len;
}

fn cVec3ToVec3(in_vec: CVec3F64) maths.Vec3F {
    return maths.Vec3F.initSlice(&.{ in_vec.x, in_vec.y, in_vec.z });
}

fn vec3ToCVec3(in_vec: maths.Vec3F) CVec3F64 {
    return .{
        .x = in_vec.get(0),
        .y = in_vec.get(1),
        .z = in_vec.get(2),
    };
}

fn dimsToArray(in_dims: CDims5Usize) [5]usize {
    return .{
        in_dims.dim0,
        in_dims.dim1,
        in_dims.dim2,
        in_dims.dim3,
        in_dims.dim4,
    };
}

fn dimsFromArray(in_dims: [5]usize) CDims5Usize {
    return .{
        .dim0 = in_dims[0],
        .dim1 = in_dims[1],
        .dim2 = in_dims[2],
        .dim3 = in_dims[3],
        .dim4 = in_dims[4],
    };
}

fn array3ToDims(in_array: anytype) [3]usize {
    return .{
        in_array.dim0,
        in_array.dim1,
        in_array.dim2,
    };
}

fn cConstSlice(
    comptime T: type,
    ptr: [*c]const T,
    len: usize,
) ![]const T {
    if (ptr == null and len > 0) {
        return error.NullPointer;
    }
    return ptr[0..len];
}

fn cMutSlice(
    comptime T: type,
    ptr: [*c]T,
    len: usize,
) ![]T {
    if (ptr == null and len > 0) {
        return error.NullPointer;
    }
    return ptr[0..len];
}

fn meshTypeFromC(mesh_type: u32) !riley.MeshType {
    return switch (mesh_type) {
        @intFromEnum(riley.MeshType.tri3) => .tri3,
        @intFromEnum(riley.MeshType.tri3opt) => .tri3opt,
        @intFromEnum(riley.MeshType.tri6) => .tri6,
        @intFromEnum(riley.MeshType.quad4) => .quad4,
        @intFromEnum(riley.MeshType.quad8) => .quad8,
        @intFromEnum(riley.MeshType.quad9) => .quad9,
        else => error.InvalidMeshType,
    };
}

fn renderModeFromC(render_mode: u32) !riley.RenderMode {
    return switch (render_mode) {
        @intFromEnum(riley.RenderMode.in_order) => .in_order,
        @intFromEnum(riley.RenderMode.offline) => .offline,
        else => error.InvalidRenderMode,
    };
}

fn saveStrategyFromC(save_strategy: u32) !riley.SaveStrategy {
    return switch (save_strategy) {
        @intFromEnum(riley.SaveStrategy.disk) => .disk,
        @intFromEnum(riley.SaveStrategy.memory) => .memory,
        @intFromEnum(riley.SaveStrategy.both) => .both,
        @intFromEnum(riley.SaveStrategy.none) => .none,
        else => error.InvalidSaveStrategy,
    };
}

fn reportModeFromC(report_mode: u32) !riley.ReportMode {
    return switch (report_mode) {
        0 => .off,
        1 => .bench,
        else => error.InvalidReportMode,
    };
}

fn bufferModeFromC(buffer_mode: u32) !riley.BufferMode {
    return switch (buffer_mode) {
        @intFromEnum(riley.BufferMode.tile_local) => .tile_local,
        @intFromEnum(riley.BufferMode.global_subpx_full) => .global_subpx_full,
        @intFromEnum(riley.BufferMode.global_subpx_stripe) => .global_subpx_stripe,
        else => error.InvalidBufferMode,
    };
}

fn subpxCenterMapFromC(subpx_map: u32) !riley.SubPixelCenterMap {
    return switch (subpx_map) {
        @intFromEnum(riley.SubPixelCenterMap.full_in_mem) => .full_in_mem,
        @intFromEnum(riley.SubPixelCenterMap.per_tile) => .per_tile,
        else => error.InvalidSubPixelCenterMap,
    };
}

fn hullModeFromC(hull_mode: u32) !riley.HullMode {
    return switch (hull_mode) {
        @intFromEnum(riley.HullMode.on_no_fallback) => .on_no_fallback,
        @intFromEnum(riley.HullMode.on_convex_fallback) => .on_convex_fallback,
        else => error.InvalidHullMode,
    };
}

fn newtonSeedModeFromC(
    seed_mode: u32,
) !riley.NewtonSeedMode {
    return switch (seed_mode) {
        @intFromEnum(riley.NewtonSeedMode.centroid) => .centroid,
        @intFromEnum(riley.NewtonSeedMode.hull) => .hull,
        else => error.InvalidNewtonSeedMode,
    };
}

fn newtonSeedReuseFromC(
    seed_reuse: u32,
) !riley.NewtonSeedReuse {
    return switch (seed_reuse) {
        @intFromEnum(riley.NewtonSeedReuse.off) => .off,
        @intFromEnum(riley.NewtonSeedReuse.last_conv) => .last_conv,
        else => error.InvalidNewtonSeedReuse,
    };
}

fn multirootModeFromC(
    mode: u32,
) !riley.MultirootSolverMode {
    return switch (mode) {
        @intFromEnum(riley.MultirootSolverMode.fast) => .fast,
        @intFromEnum(riley.MultirootSolverMode.robust) => .robust,
        else => error.InvalidMultirootSolverMode,
    };
}

fn edgeFunModeFromC(
    mode: u32,
) !riley.EdgeFunMode {
    return switch (mode) {
        @intFromEnum(riley.EdgeFunMode.on_the_fly) => .on_the_fly,
        @intFromEnum(riley.EdgeFunMode.pre_calc) => .pre_calc,
        else => error.InvalidEdgeFunMode,
    };
}

fn validateInputFromC(
    validate_input: u32,
) !riley.ValidateInput {
    return switch (validate_input) {
        @intFromEnum(riley.ValidateInput.off) => .off,
        @intFromEnum(riley.ValidateInput.fast) => .fast,
        @intFromEnum(riley.ValidateInput.full) => .full,
        else => error.InvalidValidateInputMode,
    };
}

fn coordSysFromC(coord_sys: u32) !riley.CameraCoordSys {
    return switch (coord_sys) {
        @intFromEnum(riley.CameraCoordSys.opengl) => .opengl,
        @intFromEnum(riley.CameraCoordSys.opencv) => .opencv,
        else => error.InvalidCoordSys,
    };
}

fn imageFormatFromC(format_tag: u32) !dataio.ImageFormat {
    return switch (format_tag) {
        0 => .csv,
        1 => .fimg,
        2 => .ppm,
        3 => .bmp,
        4 => .tiff,
        else => error.InvalidImageFormat,
    };
}

fn psfSeparableFromC(sep_tag: u32) !riley.SeparablePSF {
    return switch (sep_tag) {
        0 => .no,
        1 => .yes,
        else => error.InvalidSeparablePSF,
    };
}

fn psfFromC(in_camera: *const CPSF) !riley.PointSpreadFunc {
    return switch (in_camera.psf_type) {
        0 => .{ .pixel_box = .{} },
        1 => .{ .gaussian = .{
            .sigma_px = in_camera.psf_sigma_x,
            .supp_rad_px = in_camera.psf_supp_rad,
            .separable = try psfSeparableFromC(in_camera.psf_separable),
        } },
        2 => .{ .anisotropic_gaussian = .{
            .sigma_x_px = in_camera.psf_sigma_x,
            .sigma_y_px = in_camera.psf_sigma_y,
            .theta_rad = in_camera.psf_theta,
            .supp_rad_px = in_camera.psf_supp_rad,
            .separable = try psfSeparableFromC(in_camera.psf_separable),
        } },
        else => error.InvalidPsfType,
    };
}

fn distortFromC(in_camera: *const CDistort) !riley.DistortParams {
    var poly = riley.PolyMap{};
    if (in_camera.distort_model >= 3 and in_camera.distort_model <= 5) {
        const degree = std.math.cast(u8, in_camera.distort_poly_degree) orelse
            return error.InvalidPolyDegree;
        const mode: riley.PolyMode = switch (in_camera.distort_poly_mode) {
            0 => .coordinate,
            1 => .displacement,
            else => return error.InvalidPolyMode,
        };
        if (degree < 1 or degree > 7) return error.InvalidPolyDegree;
        if (in_camera.distort_poly_coeffs_len != 2 * ((@as(usize, degree) + 1) * (@as(usize, degree) + 2) / 2))
            return error.InvalidPolyCoeffCount;
        if (in_camera.distort_poly_coeffs == null) return error.NullPointer;
        poly = try riley.PolyMap.init(
            degree,
            mode,
            in_camera.distort_poly_coeffs[0..in_camera.distort_poly_coeffs_len],
        );
    }

    return switch (in_camera.distort_model) {
        0 => .none,
        1 => .{ .brown_con = .{
            .k1 = in_camera.distort_k1,
            .k2 = in_camera.distort_k2,
            .k3 = in_camera.distort_k3,
            .p1 = in_camera.distort_p1,
            .p2 = in_camera.distort_p2,
        } },
        2 => .{ .brown_con_ext = .{
            .k1 = in_camera.distort_k1,
            .k2 = in_camera.distort_k2,
            .k3 = in_camera.distort_k3,
            .k4 = in_camera.distort_k4,
            .k5 = in_camera.distort_k5,
            .k6 = in_camera.distort_k6,
            .p1 = in_camera.distort_p1,
            .p2 = in_camera.distort_p2,
            .s1 = in_camera.distort_s1,
            .s2 = in_camera.distort_s2,
            .s3 = in_camera.distort_s3,
            .s4 = in_camera.distort_s4,
            .tau_x = in_camera.distort_tau_x,
            .tau_y = in_camera.distort_tau_y,
        } },
        3 => .{ .poly = poly },
        4 => .{ .brown_con_poly = .{
            .brown_con = .{
                .k1 = in_camera.distort_k1,
                .k2 = in_camera.distort_k2,
                .k3 = in_camera.distort_k3,
                .p1 = in_camera.distort_p1,
                .p2 = in_camera.distort_p2,
            },
            .poly = poly,
        } },
        5 => .{ .brown_con_ext_poly = .{
            .brown_con_ext = .{
                .k1 = in_camera.distort_k1,
                .k2 = in_camera.distort_k2,
                .k3 = in_camera.distort_k3,
                .k4 = in_camera.distort_k4,
                .k5 = in_camera.distort_k5,
                .k6 = in_camera.distort_k6,
                .p1 = in_camera.distort_p1,
                .p2 = in_camera.distort_p2,
                .s1 = in_camera.distort_s1,
                .s2 = in_camera.distort_s2,
                .s3 = in_camera.distort_s3,
                .s4 = in_camera.distort_s4,
                .tau_x = in_camera.distort_tau_x,
                .tau_y = in_camera.distort_tau_y,
            },
            .poly = poly,
        } },
        else => error.InvalidDistortModel,
    };
}

fn texSampleFromC(sample: u32) !riley.TexSamp {
    const mitchell = riley.TexSamp.cubic_mitchell_netravali;
    return switch (sample) {
        @intFromEnum(riley.TexSamp.nearest) => .nearest,
        @intFromEnum(riley.TexSamp.linear) => .linear,
        @intFromEnum(riley.TexSamp.cubic_catmull_rom) => .cubic_catmull_rom,
        @intFromEnum(mitchell) => .cubic_mitchell_netravali,
        @intFromEnum(riley.TexSamp.lanczos3) => .lanczos3,
        @intFromEnum(riley.TexSamp.cubic_bspline) => .cubic_bspline,
        @intFromEnum(riley.TexSamp.quintic_bspline) => .quintic_bspline,
        @intFromEnum(riley.TexSamp.lanczos2) => .lanczos2,
        else => error.InvalidTexSample,
    };
}

fn texSampleModeFromC(
    sample_mode: u32,
) !riley.TexSampMode {
    return switch (sample_mode) {
        @intFromEnum(riley.TexSampMode.direct) => .direct,
        @intFromEnum(riley.TexSampMode.lut) => .lut,
        @intFromEnum(riley.TexSampMode.lut_lerp) => .lut_lerp,
        else => error.InvalidTexSampleMode,
    };
}

fn scaleOverFromC(scale_over: u32) !riley.ScaleOver {
    return switch (scale_over) {
        @intFromEnum(riley.ScaleOver.within_frames) => .within_frames,
        @intFromEnum(riley.ScaleOver.over_frames) => .over_frames,
        else => error.InvalidScaleOver,
    };
}

fn funcShaderBuiltinFromC(
    func_shader_builtin: u32,
) !riley.FuncShaderBuiltin {
    const lambertian = riley.FuncShaderBuiltin.lambertian_normal_z;
    const eggbox = riley.FuncShaderBuiltin.eggbox;
    return switch (func_shader_builtin) {
        @intFromEnum(riley.FuncShaderBuiltin.constant) => .constant,
        @intFromEnum(riley.FuncShaderBuiltin.linear) => .linear,
        @intFromEnum(riley.FuncShaderBuiltin.quadratic) => .quadratic,
        @intFromEnum(riley.FuncShaderBuiltin.sinusoidal) => .sinusoidal,
        @intFromEnum(riley.FuncShaderBuiltin.sinusoidal_approx) => .sinusoidal_approx,
        @intFromEnum(riley.FuncShaderBuiltin.checker) => .checker,
        @intFromEnum(riley.FuncShaderBuiltin.checker_smooth) => .checker_smooth,
        @intFromEnum(lambertian) => .lambertian_normal_z,
        @intFromEnum(eggbox) => .eggbox,
        else => error.InvalidFuncShaderBuiltin,
    };
}

fn funcCoordModeFromC(
    coord_mode: u32,
) !riley.FuncCoordMode {
    return switch (coord_mode) {
        @intFromEnum(riley.FuncCoordMode.uv) => .uv,
        @intFromEnum(riley.FuncCoordMode.para) => .para,
        @intFromEnum(riley.FuncCoordMode.world_reference) => .world_reference,
        @intFromEnum(riley.FuncCoordMode.world_deformed) => .world_deformed,
        else => error.InvalidFuncCoordMode,
    };
}

fn normalTypeFromC(normal_type: u32) !riley.NormalType {
    return switch (normal_type) {
        @intFromEnum(riley.NormalType.none) => .none,
        @intFromEnum(riley.NormalType.exact) => .exact,
        @intFromEnum(riley.NormalType.avg) => .avg,
        else => error.InvalidNormalType,
    };
}

fn funcShaderParamsFromC(
    builtin: riley.FuncShaderBuiltin,
    in_params: CFuncShaderParams,
) riley.FuncShaderParams {
    return .{
        .coord_scale = .{
            in_params.coord_scale[0],
            in_params.coord_scale[1],
        },
        .coord_offset = .{
            in_params.coord_offset[0],
            in_params.coord_offset[1],
        },
        .settings = switch (builtin) {
            .constant => .{
                .constant = .{
                    .value = in_params.constant_value,
                    .value_rgb = .{
                        in_params.constant_value_rgb[0],
                        in_params.constant_value_rgb[1],
                        in_params.constant_value_rgb[2],
                    },
                },
            },
            .linear => .{
                .linear = .{
                    .coeffs = .{
                        in_params.linear_coeff[0],
                        in_params.linear_coeff[1],
                        in_params.linear_coeff[2],
                    },
                    .coeffs_rgb = .{
                        .{
                            in_params.linear_coeff_rgb[0][0],
                            in_params.linear_coeff_rgb[0][1],
                            in_params.linear_coeff_rgb[0][2],
                        },
                        .{
                            in_params.linear_coeff_rgb[1][0],
                            in_params.linear_coeff_rgb[1][1],
                            in_params.linear_coeff_rgb[1][2],
                        },
                        .{
                            in_params.linear_coeff_rgb[2][0],
                            in_params.linear_coeff_rgb[2][1],
                            in_params.linear_coeff_rgb[2][2],
                        },
                    },
                },
            },
            .quadratic => .{
                .quadratic = .{
                    .coeffs = .{
                        in_params.quadratic_coeff[0],
                        in_params.quadratic_coeff[1],
                        in_params.quadratic_coeff[2],
                        in_params.quadratic_coeff[3],
                        in_params.quadratic_coeff[4],
                        in_params.quadratic_coeff[5],
                    },
                    .coeffs_rgb = .{
                        .{
                            in_params.quadratic_coeff_rgb[0][0],
                            in_params.quadratic_coeff_rgb[0][1],
                            in_params.quadratic_coeff_rgb[0][2],
                            in_params.quadratic_coeff_rgb[0][3],
                            in_params.quadratic_coeff_rgb[0][4],
                            in_params.quadratic_coeff_rgb[0][5],
                        },
                        .{
                            in_params.quadratic_coeff_rgb[1][0],
                            in_params.quadratic_coeff_rgb[1][1],
                            in_params.quadratic_coeff_rgb[1][2],
                            in_params.quadratic_coeff_rgb[1][3],
                            in_params.quadratic_coeff_rgb[1][4],
                            in_params.quadratic_coeff_rgb[1][5],
                        },
                        .{
                            in_params.quadratic_coeff_rgb[2][0],
                            in_params.quadratic_coeff_rgb[2][1],
                            in_params.quadratic_coeff_rgb[2][2],
                            in_params.quadratic_coeff_rgb[2][3],
                            in_params.quadratic_coeff_rgb[2][4],
                            in_params.quadratic_coeff_rgb[2][5],
                        },
                    },
                },
            },
            .sinusoidal => .{
                .sinusoidal = .{
                    .wave_num_scalar = .{
                        in_params.wave_num_scalar[0],
                        in_params.wave_num_scalar[1],
                    },
                    .wave_num_rgb = .{
                        in_params.wave_num_rgb[0],
                        in_params.wave_num_rgb[1],
                        in_params.wave_num_rgb[2],
                    },
                    .bias = in_params.sinusoidal_bias,
                    .amplitudes = .{
                        in_params.sinusoidal_amp[0],
                        in_params.sinusoidal_amp[1],
                    },
                    .bias_rgb = .{
                        in_params.sinusoidal_bias_rgb[0],
                        in_params.sinusoidal_bias_rgb[1],
                        in_params.sinusoidal_bias_rgb[2],
                    },
                    .amplitudes_rgb = .{
                        in_params.sinusoidal_amp_rgb[0],
                        in_params.sinusoidal_amp_rgb[1],
                        in_params.sinusoidal_amp_rgb[2],
                    },
                },
            },
            .sinusoidal_approx => .{
                .sinusoidal_approx = .{
                    .wave_num_scalar = .{
                        in_params.wave_num_scalar[0],
                        in_params.wave_num_scalar[1],
                    },
                    .wave_num_rgb = .{
                        in_params.wave_num_rgb[0],
                        in_params.wave_num_rgb[1],
                        in_params.wave_num_rgb[2],
                    },
                    .bias = in_params.sinusoidal_bias,
                    .amplitudes = .{
                        in_params.sinusoidal_amp[0],
                        in_params.sinusoidal_amp[1],
                    },
                    .bias_rgb = .{
                        in_params.sinusoidal_bias_rgb[0],
                        in_params.sinusoidal_bias_rgb[1],
                        in_params.sinusoidal_bias_rgb[2],
                    },
                    .amplitudes_rgb = .{
                        in_params.sinusoidal_amp_rgb[0],
                        in_params.sinusoidal_amp_rgb[1],
                        in_params.sinusoidal_amp_rgb[2],
                    },
                },
            },
            .checker => .{
                .checker = .{
                    .levels = .{
                        in_params.checker_level[0],
                        in_params.checker_level[1],
                    },
                },
            },
            .checker_smooth => .{
                .checker_smooth = .{
                    .frequency = in_params.checker_smooth_frequency,
                },
            },
            .lambertian_normal_z => .{
                .lambertian_normal_z = .{
                    .coeffs = .{
                        in_params.lambertian_coeff[0],
                        in_params.lambertian_coeff[1],
                    },
                    .coeffs_rgb = .{
                        .{
                            in_params.lambertian_coeff_rgb[0][0],
                            in_params.lambertian_coeff_rgb[0][1],
                        },
                        .{
                            in_params.lambertian_coeff_rgb[1][0],
                            in_params.lambertian_coeff_rgb[1][1],
                        },
                        .{
                            in_params.lambertian_coeff_rgb[2][0],
                            in_params.lambertian_coeff_rgb[2][1],
                        },
                    },
                },
            },
            .eggbox => .{
                .eggbox = .{
                    .mean = in_params.eggbox_mean,
                    .contrast = in_params.eggbox_contrast,
                    .pitch = .{
                        in_params.eggbox_pitch[0],
                        in_params.eggbox_pitch[1],
                    },
                    .phase = .{
                        in_params.eggbox_phase[0],
                        in_params.eggbox_phase[1],
                    },
                },
            },
        },
    };
}

fn bitsFromC(bits: c_int) !?u8 {
    if (bits < 0) {
        return null;
    }
    if (bits > std.math.maxInt(u8)) {
        return error.InvalidBits;
    }
    return @intCast(bits);
}

fn scaleStrategyFromC(
    scaling_tag: u32,
    scaling_min: F,
    scaling_max: F,
) !riley.ScaleStrategy {
    return switch (scaling_tag) {
        0 => .none,
        1 => .auto,
        2 => .{ .fixed = .{ scaling_min, scaling_max } },
        3 => .{ .frac = .{ scaling_min, scaling_max } },
        else => error.InvalidScaleStrategy,
    };
}

fn buildCoordsFromC(in_coords: *const CArray2DF64) !riley.Coords {
    if (in_coords.cols_num != 3 or in_coords.rows_num == 0) {
        return error.InvalidCoordsShape;
    }
    const coords_slice = try cConstSlice(
        F,
        in_coords.elems,
        in_coords.rows_num * in_coords.cols_num,
    );
    return riley.Coords.init(
        @constCast(coords_slice),
        in_coords.rows_num,
    );
}

fn buildConnectFromC(
    in_connect: *const CArray2DUsize,
) !riley.Connect {
    const connect_slice = try cConstSlice(
        usize,
        in_connect.elems,
        in_connect.rows_num * in_connect.cols_num,
    );
    return riley.Connect.init(
        @constCast(connect_slice),
        in_connect.rows_num,
        in_connect.cols_num,
    );
}

fn buildArray2DF64(
    allocator: std.mem.Allocator,
    in_array: *const CArray2DF64,
    cols_num_expected: ?usize,
) !maths.NDArray(F) {
    if (cols_num_expected) |expected_cols_num| {
        if (in_array.cols_num != expected_cols_num) {
            return error.InvalidArray2DShape;
        }
    }
    const slice_in = try cConstSlice(
        F,
        in_array.elems,
        in_array.rows_num * in_array.cols_num,
    );
    var dims = [_]usize{
        in_array.rows_num,
        in_array.cols_num,
    };
    return try maths.NDArray(F).init(
        allocator,
        @constCast(slice_in),
        dims[0..],
    );
}

fn buildArray3DF64(
    allocator: std.mem.Allocator,
    in_array: *const CArray3DF64,
) !maths.NDArray(F) {
    const dims = array3ToDims(in_array.*);
    const elems_num = dims[0] * dims[1] * dims[2];
    const slice_in = try cConstSlice(
        F,
        in_array.elems,
        elems_num,
    );
    var dims_mut = dims;
    return try maths.NDArray(F).init(
        allocator,
        @constCast(slice_in),
        dims_mut[0..],
    );
}

fn buildTexArray(
    comptime T: type,
    allocator: std.mem.Allocator,
    in_array: anytype,
    channels_num: usize,
) !maths.NDArray(T) {
    const dims = array3ToDims(in_array.*);
    if (dims[0] != channels_num or dims[1] == 0 or dims[2] == 0) {
        return error.InvalidTexShape;
    }
    const elems_num = dims[0] * dims[1] * dims[2];
    const slice_in = try cConstSlice(T, in_array.elems, elems_num);
    var dims_mut = dims;
    return try maths.NDArray(T).init(allocator, @constCast(slice_in), dims_mut[0..]);
}

fn buildOptionalFieldFromC(
    allocator: std.mem.Allocator,
    in_array: *const CArray3DF64,
) !struct {
    field: ?riley.Field,
    array: ?maths.NDArray(F),
} {
    const dims = array3ToDims(in_array.*);
    if (dims[0] == 0 or dims[1] == 0 or dims[2] == 0) {
        return .{
            .field = null,
            .array = null,
        };
    }
    const array = try buildArray3DF64(allocator, in_array);
    return .{
        .field = .{
            .array = array,
            .array_mem = array.slice,
        },
        .array = array,
    };
}

fn buildCameraInput(
    allocator: std.mem.Allocator,
    in_camera: *const CCameraInput,
) !riley.CameraInput {
    const render_format: riley.RenderFormat = switch (in_camera.render_format_tag) {
        0 => .mono,
        1 => .rgb,
        2 => .ir,
        3 => .{
            .multifield = if (in_camera.render_channels >= 1 and
                in_camera.render_channels <= riley.max_channels)
                @intCast(in_camera.render_channels)
            else
                return error.InvalidRenderChannels,
        },
        else => return error.InvalidRenderFormat,
    };

    var output_files: []const dataio.ImageSaveOpts = &default_image_save_opts;
    if (in_camera.output_files_len > 0) {
        const c_files = try cConstSlice(
            CImageSaveOpts,
            in_camera.output_files,
            in_camera.output_files_len,
        );
        const files = try allocator.alloc(dataio.ImageSaveOpts, c_files.len);
        for (c_files, files) |c_opt, *opt| {
            opt.* = .{
                .format = try imageFormatFromC(c_opt.format),
                .file_bits = try bitsFromC(c_opt.file_bits),
                .adc_bits = try bitsFromC(c_opt.adc_bits),
                .scaling = try scaleStrategyFromC(
                    c_opt.scaling_tag,
                    c_opt.scaling_min,
                    c_opt.scaling_max,
                ),
                .packing = switch (c_opt.packing) {
                    0 => .spread,
                    1 => .lower,
                    2 => .upper,
                    else => return error.InvalidCodePacking,
                },
            };
        }
        output_files = files;
    }

    return .{
        .pixels_num = .{
            in_camera.pixels_num.x,
            in_camera.pixels_num.y,
        },
        .pixels_size = .{
            in_camera.pixels_size.x,
            in_camera.pixels_size.y,
        },
        .pos_world = cVec3ToVec3(in_camera.pos_world),
        .rot_world = maths.Rotation.init(
            in_camera.rot_world.x,
            in_camera.rot_world.y,
            in_camera.rot_world.z,
        ),
        .roi_cent_world = cVec3ToVec3(in_camera.roi_cent_world),
        .focal_length = in_camera.focal_length,
        .sub_sample = in_camera.sub_sample,
        .background_value = in_camera.background_value,
        .distort = try distortFromC(&in_camera.distort),
        .psf = try psfFromC(&in_camera.psf),
        .coord_sys = try coordSysFromC(in_camera.coord_sys),
        .render_format = render_format,
        .output_files = output_files,
        .subpixel_center_map = try subpxCenterMapFromC(
            in_camera.subpixel_center_map,
        ),
    };
}

fn pipeRegisterFromC(in_slot: CRegister) !riley.Register {
    if (in_slot.index >= riley.max_registers) return error.InvalidPipeRegister;
    return .{
        .kind = switch (in_slot.kind) {
            0 => .channel,
            1 => .field,
            2 => .parameter,
            3 => .constant,
            else => return error.InvalidPipeRegister,
        },
        .index = @intCast(in_slot.index),
    };
}

fn pipeRegistersFromC(
    allocator: std.mem.Allocator,
    registers: [*c]const CRegister,
    count: usize,
) ![]riley.Register {
    const input = try cConstSlice(CRegister, registers, count);
    const output = try allocator.alloc(riley.Register, count);
    for (input, output) |register_ref, *dest| {
        dest.* = try pipeRegisterFromC(register_ref);
    }
    return output;
}

fn lookupFromC(input: CLookup) !riley.LookupTable {
    return .{
        .first = input.first,
        .step = input.step,
        .values = try cConstSlice(F, input.values, input.values_len),
    };
}

fn resolverFromC(
    allocator: std.mem.Allocator,
    input: CResolver,
    constants: []const F,
) !riley.ResolverInput {
    const registers = try pipeRegistersFromC(allocator, input.registers, input.registers_len);
    return switch (input.tag) {
        0 => .{ .identity = registers },
        1 => .{ .sum = registers },
        2 => .{ .modulate = .{
            .register_sources = registers,
            .factor = try pipeRegisterFromC(input.factor),
            .ambient = input.ambient,
            .gain = input.gain,
        } },
        3 => .{ .weighted_sum = .{
            .register_sources = registers,
            .weights = try cConstSlice(F, input.weights, input.weights_len),
        } },
        4 => .{ .greybody_bolometric = .{
            .temperature = try pipeRegisterFromC(input.temperature),
            .emissivity = try pipeRegisterFromC(input.emissivity),
        } },
        5 => .{ .greybody_band = .{
            .temperature = try pipeRegisterFromC(input.temperature),
            .emissivity = try pipeRegisterFromC(input.emissivity),
            .radiance = try lookupFromC(input.lookup),
        } },
        7 => .{ .greybody_band_apparent_c = .{
            .temperature = try pipeRegisterFromC(input.temperature),
            .emissivity = try pipeRegisterFromC(input.emissivity),
            .radiance = try lookupFromC(input.lookup),
            .ambient_k = input.ambient,
        } },
        6 => blk: {
            const input_ops = try cConstSlice(
                CResolverOp,
                input.operations,
                input.operations_len,
            );
            const operations = try allocator.alloc(riley.ResolverOp, input_ops.len);
            for (input_ops, operations) |op, *dest| {
                dest.* = switch (op.tag) {
                    0 => .{ .load = try pipeRegisterFromC(op.register_ref) },
                    1 => .add,
                    2 => .subtract,
                    3 => .multiply,
                    4 => .divide,
                    5 => .power4,
                    6 => .clamp01,
                    7 => .{ .clamp = .{ .lower = op.lower, .upper = op.upper } },
                    8 => if (op.register_ref.index < 1)
                        .{ .lut = 0 }
                    else
                        return error.InvalidPipeOperation,
                    9 => if (op.register_ref.index < riley.max_channels)
                        .{ .store = @intCast(op.register_ref.index) }
                    else
                        return error.InvalidPipeOperation,
                    else => return error.InvalidPipeOperation,
                };
            }
            const lookups = if (input.lookup.values_len > 0)
                try allocator.dupe(
                    riley.LookupTable,
                    &.{try lookupFromC(input.lookup)},
                )
            else
                &.{};
            break :blk .{ .expression = .{
                .operations = operations,
                .constants = constants,
                .lookups = lookups,
            } };
        },
        else => error.InvalidPipeResolver,
    };
}

fn buildShaderDirectInput(
    allocator: std.mem.Allocator,
    in_shader: *const CShaderInput,
) !riley.PipeSourceInput {
    const scaling = try scaleStrategyFromC(
        in_shader.scaling_tag,
        in_shader.scaling_min,
        in_shader.scaling_max,
    );

    switch (in_shader.shader_tag) {
        0 => {
            if (in_shader.value.texture.storage > 2) return error.InvalidTextureStorage;
            if (in_shader.value.texture.uvs.cols_num != 2) {
                return error.InvalidUVShape;
            }

            var uvs_array = try buildArray2DF64(
                allocator,
                &in_shader.value.texture.uvs,
                2,
            );
            errdefer uvs_array.deinit(allocator);

            const samp_cfg = riley.TexSampConfig{
                .sample = try texSampleFromC(in_shader.value.texture.sample),
                .mode = try texSampleModeFromC(in_shader.value.texture.sample_mode),
            };
            if (!samp_cfg.isValid()) {
                return error.InvalidTexSampleConfig;
            }

            if (in_shader.value.texture.storage == 1) {
                var tex_array = try buildTexArray(
                    u16,
                    allocator,
                    &in_shader.value.texture.data.u16,
                    1,
                );
                errdefer tex_array.deinit(allocator);
                return .{ .tex_u16 = .{
                    .uvs = uvs_array,
                    .tex = riley.TexDataFix(u16, 1){
                        .array = tex_array,
                        .rows_num = in_shader.value.texture.data.u16.dim1,
                        .cols_num = in_shader.value.texture.data.u16.dim2,
                    },
                    .samp_cfg = samp_cfg,
                    .output_gain = in_shader.output_gain,
                    .output_offset = in_shader.output_offset,
                    .scaling = scaling,
                } };
            } else if (in_shader.value.texture.storage == 2) {
                var tex_array = try buildTexArray(F, allocator, &in_shader.value.texture.data.f, 1);
                errdefer tex_array.deinit(allocator);
                return .{ .tex_f = .{
                    .uvs = uvs_array,
                    .tex = riley.TexDataFix(F, 1){
                        .array = tex_array,
                        .rows_num = in_shader.value.texture.data.f.dim1,
                        .cols_num = in_shader.value.texture.data.f.dim2,
                    },
                    .samp_cfg = samp_cfg,
                    .output_gain = in_shader.output_gain,
                    .output_offset = in_shader.output_offset,
                    .scaling = scaling,
                } };
            } else {
                var tex_array = try buildTexArray(
                    u8,
                    allocator,
                    &in_shader.value.texture.data.u8,
                    1,
                );
                errdefer tex_array.deinit(allocator);
                return .{ .tex_u8 = .{
                    .uvs = uvs_array,
                    .tex = riley.TexDataFix(u8, 1){
                        .array = tex_array,
                        .rows_num = in_shader.value.texture.data.u8.dim1,
                        .cols_num = in_shader.value.texture.data.u8.dim2,
                    },
                    .samp_cfg = samp_cfg,
                    .output_gain = in_shader.output_gain,
                    .output_offset = in_shader.output_offset,
                    .scaling = scaling,
                } };
            }
        },
        1 => {
            if (in_shader.value.texture.storage > 2) return error.InvalidTextureStorage;
            if (in_shader.value.texture.uvs.cols_num != 2) {
                return error.InvalidUVShape;
            }

            var uvs_array = try buildArray2DF64(
                allocator,
                &in_shader.value.texture.uvs,
                2,
            );
            errdefer uvs_array.deinit(allocator);

            const samp_cfg = riley.TexSampConfig{
                .sample = try texSampleFromC(in_shader.value.texture.sample),
                .mode = try texSampleModeFromC(in_shader.value.texture.sample_mode),
            };
            if (!samp_cfg.isValid()) {
                return error.InvalidTexSampleConfig;
            }

            if (in_shader.value.texture.storage == 1) {
                var tex_array = try buildTexArray(
                    u16,
                    allocator,
                    &in_shader.value.texture.data.u16,
                    3,
                );
                errdefer tex_array.deinit(allocator);
                return .{ .tex_rgb_u16 = .{
                    .uvs = uvs_array,
                    .tex = riley.TexDataFix(u16, 3){
                        .array = tex_array,
                        .rows_num = in_shader.value.texture.data.u16.dim1,
                        .cols_num = in_shader.value.texture.data.u16.dim2,
                    },
                    .samp_cfg = samp_cfg,
                    .output_gain = in_shader.output_gain,
                    .output_offset = in_shader.output_offset,
                    .scaling = scaling,
                } };
            } else if (in_shader.value.texture.storage == 2) {
                var tex_array = try buildTexArray(F, allocator, &in_shader.value.texture.data.f, 3);
                errdefer tex_array.deinit(allocator);
                return .{ .tex_rgb_f = .{
                    .uvs = uvs_array,
                    .tex = riley.TexDataFix(F, 3){
                        .array = tex_array,
                        .rows_num = in_shader.value.texture.data.f.dim1,
                        .cols_num = in_shader.value.texture.data.f.dim2,
                    },
                    .samp_cfg = samp_cfg,
                    .output_gain = in_shader.output_gain,
                    .output_offset = in_shader.output_offset,
                    .scaling = scaling,
                } };
            } else {
                var tex_array = try buildTexArray(
                    u8,
                    allocator,
                    &in_shader.value.texture.data.u8,
                    3,
                );
                errdefer tex_array.deinit(allocator);
                return .{ .tex_rgb_u8 = .{
                    .uvs = uvs_array,
                    .tex = riley.TexDataFix(u8, 3){
                        .array = tex_array,
                        .rows_num = in_shader.value.texture.data.u8.dim1,
                        .cols_num = in_shader.value.texture.data.u8.dim2,
                    },
                    .samp_cfg = samp_cfg,
                    .output_gain = in_shader.output_gain,
                    .output_offset = in_shader.output_offset,
                    .scaling = scaling,
                } };
            }
        },
        2, 5 => {
            const nodal_built = try buildOptionalFieldFromC(
                allocator,
                &in_shader.value.nodal.field,
            );
            if (nodal_built.field == null or nodal_built.array == null) {
                return error.MissingNodalField;
            }
            if (in_shader.shader_tag == 5 and nodal_built.field.?.getFieldsN() != 3) {
                return error.InvalidNodalRgbFieldCount;
            }
            return .{ .nodal = .{
                .field = nodal_built.field.?,
                .output_gain = in_shader.output_gain,
                .output_offset = in_shader.output_offset,
                .scaling = scaling,
                .scale_over = try scaleOverFromC(in_shader.value.nodal.scale_over),
            } };
        },
        3 => {
            var uvs_array_opt: ?maths.NDArray(F) = null;
            if (in_shader.value.func.uvs.rows_num > 0 and in_shader.value.func.uvs.cols_num > 0) {
                uvs_array_opt = try buildArray2DF64(
                    allocator,
                    &in_shader.value.func.uvs,
                    2,
                );
            }
            errdefer if (uvs_array_opt) |*uvs_array| {
                uvs_array.deinit(allocator);
            };

            const builtin = try funcShaderBuiltinFromC(
                in_shader.value.func.builtin,
            );
            return .{ .func = .{
                .uvs = uvs_array_opt,
                .coord_mode = try funcCoordModeFromC(
                    in_shader.value.func.coord_mode,
                ),
                .builtin = builtin,
                .params = funcShaderParamsFromC(
                    builtin,
                    in_shader.value.func.params,
                ),
                .output_gain = in_shader.output_gain,
                .output_offset = in_shader.output_offset,
                .scaling = scaling,
            } };
        },
        4 => {
            var uvs_array_opt: ?maths.NDArray(F) = null;
            if (in_shader.value.func.uvs.rows_num > 0 and in_shader.value.func.uvs.cols_num > 0) {
                uvs_array_opt = try buildArray2DF64(
                    allocator,
                    &in_shader.value.func.uvs,
                    2,
                );
            }
            errdefer if (uvs_array_opt) |*uvs_array| {
                uvs_array.deinit(allocator);
            };

            const builtin = try funcShaderBuiltinFromC(
                in_shader.value.func.builtin,
            );
            return .{ .func_rgb = .{
                .uvs = uvs_array_opt,
                .coord_mode = try funcCoordModeFromC(
                    in_shader.value.func.coord_mode,
                ),
                .builtin = builtin,
                .params = funcShaderParamsFromC(
                    builtin,
                    in_shader.value.func.params,
                ),
                .output_gain = in_shader.output_gain,
                .output_offset = in_shader.output_offset,
                .scaling = scaling,
            } };
        },
        6 => {
            if (in_shader.value.func.channels_len < 1 or
                in_shader.value.func.channels_len > riley.max_channels)
                return error.InvalidFuncChannelCount;
            const inputs = try cConstSlice(CFuncChannel, in_shader.value.func.channels, in_shader.value.func.channels_len);
            const channels = try allocator.alloc(riley.FuncChannel, inputs.len);
            errdefer allocator.free(channels);
            for (inputs, channels) |input, *channel| {
                const builtin = try funcShaderBuiltinFromC(input.builtin);
                channel.* = .{
                    .builtin = builtin,
                    .params = funcShaderParamsFromC(builtin, input.params),
                    .output_gain = input.output_gain,
                    .output_offset = input.output_offset,
                    .scaling = try scaleStrategyFromC(input.scaling_tag, input.scaling_min, input.scaling_max),
                };
            }
            var uvs: ?maths.NDArray(F) = null;
            if (in_shader.value.func.uvs.rows_num > 0 and in_shader.value.func.uvs.cols_num > 0) {
                uvs = try buildArray2DF64(allocator, &in_shader.value.func.uvs, 2);
            }
            errdefer if (uvs) |*array| array.deinit(allocator);
            return .{ .func_multi = .{
                .uvs = uvs,
                .coord_mode = try funcCoordModeFromC(in_shader.value.func.coord_mode),
                .channels = channels,
            } };
        },
        7 => {
            const texture = in_shader.value.texture;
            const uvs = try buildArray2DF64(allocator, &texture.uvs, 2);
            const sampling: riley.TexSampConfig = .{
                .sample = try texSampleFromC(texture.sample),
                .mode = try texSampleModeFromC(texture.sample_mode),
            };
            if (!sampling.isValid()) return error.InvalidTexSampleConfig;
            switch (texture.storage) {
                0 => {
                    const data = texture.data.u8;
                    if (data.dim0 < 2 or data.dim0 > riley.max_channels) return error.InvalidTexShape;
                    return .{ .tex_multi_u8 = .{
                        .uvs = uvs,
                        .tex = .{ .array = try buildTexArray(u8, allocator, &data, data.dim0), .rows_num = data.dim1, .cols_num = data.dim2 },
                        .samp_cfg = sampling,
                        .output_gain = in_shader.output_gain,
                        .output_offset = in_shader.output_offset,
                        .scaling = scaling,
                    } };
                },
                1 => {
                    const data = texture.data.u16;
                    if (data.dim0 < 2 or data.dim0 > riley.max_channels) return error.InvalidTexShape;
                    return .{ .tex_multi_u16 = .{
                        .uvs = uvs,
                        .tex = .{ .array = try buildTexArray(u16, allocator, &data, data.dim0), .rows_num = data.dim1, .cols_num = data.dim2 },
                        .samp_cfg = sampling,
                        .output_gain = in_shader.output_gain,
                        .output_offset = in_shader.output_offset,
                        .scaling = scaling,
                    } };
                },
                2 => {
                    const data = texture.data.f;
                    if (data.dim0 < 2 or data.dim0 > riley.max_channels) return error.InvalidTexShape;
                    return .{ .tex_multi_f = .{
                        .uvs = uvs,
                        .tex = .{ .array = try buildTexArray(F, allocator, &data, data.dim0), .rows_num = data.dim1, .cols_num = data.dim2 },
                        .samp_cfg = sampling,
                        .output_gain = in_shader.output_gain,
                        .output_offset = in_shader.output_offset,
                        .scaling = scaling,
                    } };
                },
                else => return error.InvalidTextureStorage,
            }
        },
        else => return error.InvalidShaderTag,
    }
}

fn pipeSourceToMono(source: riley.PipeSourceInput) !riley.ShaderMonoInput {
    return switch (source) {
        .tex_u8 => |tex_shader| .{ .tex_u8 = tex_shader },
        .tex_u16 => |tex_shader| .{ .tex_u16 = tex_shader },
        .tex_f => |tex_shader| .{ .tex_f = tex_shader },
        .nodal => |nodal_shader| blk: {
            if (nodal_shader.field.getFieldsN() != 1) return error.UnsuppedImageModeFieldCount;
            break :blk .{ .nodal = nodal_shader };
        },
        .func => |func_shader| .{ .func = func_shader },
        .func_rgb, .func_multi => return error.UnsuppedImageModeFieldCount,
        else => return error.UnsuppedImageModeFieldCount,
    };
}

fn buildPipeInput(allocator: std.mem.Allocator, pipe: *const CPipe) !riley.ShaderPipeInput {
    const input_stages = try cConstSlice(CPipeStage, pipe.stages, pipe.stages_len);
    const stages = try allocator.alloc(riley.ShaderPipeStageInput, input_stages.len);
    for (input_stages, stages) |input_stage, *stage| {
        stage.* = switch (input_stage.tag) {
            0 => .{ .shader = .{
                .shader = if (input_stage.shader != null)
                    try buildShaderDirectInput(allocator, input_stage.shader)
                else
                    return error.NullPointer,
                .register_dest = try pipeRegisterFromC(input_stage.register_dest),
            } },
            1 => .{ .grey_to_emissivity = .{
                .register_source = try pipeRegisterFromC(input_stage.register_source),
                .register_dest = try pipeRegisterFromC(input_stage.register_dest),
                .greylevel_at_black = input_stage.lower,
                .greylevel_at_white = input_stage.upper,
                .emissivity_at_black = input_stage.black,
                .emissivity_at_white = input_stage.white,
            } },
            2 => .{ .clamp = .{
                .register_source = try pipeRegisterFromC(input_stage.register_source),
                .register_dest = try pipeRegisterFromC(input_stage.register_dest),
                .lower = input_stage.lower,
                .upper = input_stage.upper,
            } },
            3 => .{ .affine_map = .{
                .register_source = try pipeRegisterFromC(input_stage.register_source),
                .register_dest = try pipeRegisterFromC(input_stage.register_dest),
                .gain = input_stage.gain,
                .offset = input_stage.offset,
            } },
            4 => .{ .lut_map = .{
                .register_source = try pipeRegisterFromC(input_stage.register_source),
                .register_dest = try pipeRegisterFromC(input_stage.register_dest),
                .lookup = try lookupFromC(input_stage.lookup),
            } },
            5 => .{ .blend = .{
                .a = try pipeRegisterFromC(input_stage.register_source),
                .b = try pipeRegisterFromC(input_stage.register_source_b),
                .register_dest = try pipeRegisterFromC(input_stage.register_dest),
                .alpha = if (input_stage.alpha_from_register != 0)
                    .{ .register = try pipeRegisterFromC(input_stage.alpha_register) }
                else
                    .{ .fixed = input_stage.alpha },
            } },
            6 => .{ .normalise = .{
                .register_source = try pipeRegisterFromC(input_stage.register_source),
                .register_dest = try pipeRegisterFromC(input_stage.register_dest),
                .components = std.math.cast(u8, input_stage.components) orelse return error.InvalidPipeStage,
            } },
            else => return error.InvalidPipeStage,
        };
    }
    const constants = try cConstSlice(F, pipe.constants, pipe.constants_len);
    return .{
        .stages = stages,
        .resolver = try resolverFromC(allocator, pipe.resolver, constants),
        .constants = constants,
    };
}

fn buildMeshInput(allocator: std.mem.Allocator, in_mesh: *const CMeshInput) !riley.MeshInput {
    const mesh_type = try meshTypeFromC(in_mesh.mesh_type);
    if (in_mesh.connect.cols_num != mesh_type.getNodesNum()) return error.InvalidConnectShape;
    const disp = try buildOptionalFieldFromC(allocator, &in_mesh.disp);
    var mesh: riley.MeshInput = .{
        .mesh_type = mesh_type,
        .normal_type = try normalTypeFromC(in_mesh.normal_type),
        .coords = try buildCoordsFromC(&in_mesh.coords),
        .connect = try buildConnectFromC(&in_mesh.connect),
        .disp = disp.field,
        .shaders = .{},
    };
    if (in_mesh.shaders_len == 0 or in_mesh.shaders_len > 4) return error.InvalidShaderCount;
    const entries = try cConstSlice(CShaderEntry, in_mesh.shaders, in_mesh.shaders_len);
    for (entries) |*entry| {
        var direct: ?riley.ShaderMonoInput = null;
        var pipe: ?riley.ShaderPipeInput = null;
        switch (entry.execution_tag) {
            0 => direct = try pipeSourceToMono(try buildShaderDirectInput(allocator, &entry.value.direct)),
            1 => pipe = try buildPipeInput(allocator, &entry.value.pipe),
            else => return error.InvalidExecutionTag,
        }
        switch (entry.format_tag) {
            0 => {
                if (mesh.shaders.mono_direct != null or mesh.shaders.mono_pipe != null) return error.DuplicateRole;
                mesh.shaders.mono_direct = direct;
                mesh.shaders.mono_pipe = pipe;
            },
            1 => {
                if (mesh.shaders.rgb_pipe != null) return error.DuplicateRole;
                mesh.shaders.rgb_pipe = pipe orelse return error.InvalidExecutionTag;
            },
            2 => {
                if (mesh.shaders.ir_direct != null or mesh.shaders.ir_pipe != null) return error.DuplicateRole;
                mesh.shaders.ir_direct = direct;
                mesh.shaders.ir_pipe = pipe;
            },
            3 => {
                if (mesh.shaders.multifield_pipe != null) return error.DuplicateRole;
                mesh.shaders.multifield_pipe = pipe orelse return error.InvalidExecutionTag;
            },
            else => return error.InvalidRenderFormatTag,
        }
    }
    return mesh;
}

fn buildCameraInputSlice(
    allocator: std.mem.Allocator,
    in_cameras: [*c]const CCameraInput,
    cameras_len: usize,
) ![]riley.CameraInput {
    const cameras_slice = try cConstSlice(
        CCameraInput,
        in_cameras,
        cameras_len,
    );
    const cameras_out = try allocator.alloc(riley.CameraInput, cameras_len);
    for (cameras_slice, 0..) |camera_in, nn| {
        cameras_out[nn] = try buildCameraInput(allocator, &camera_in);
    }
    return cameras_out;
}

fn buildMeshInputSlice(allocator: std.mem.Allocator, in_meshes: [*c]const CMeshInput, count: usize) ![]riley.MeshInput {
    const inputs = try cConstSlice(CMeshInput, in_meshes, count);
    const meshes = try allocator.alloc(riley.MeshInput, count);
    for (inputs, meshes) |*input, *mesh| mesh.* = try buildMeshInput(allocator, input);
    return meshes;
}

fn buildRasterConfig(
    in_config: *const CRasterConfig,
) !riley.RasterConfig {
    var config = riley.RasterConfig{};
    config.render_mode = try renderModeFromC(in_config.render_mode);
    config.parallel = switch (in_config.parallel_mode) {
        0 => .auto,
        1 => .serial,
        2 => if (in_config.thread_count > 0)
            .{ .threads = in_config.thread_count }
        else
            return error.InvalidThreadCount,
        else => return error.InvalidParallelMode,
    };
    config.save_strategy = try saveStrategyFromC(in_config.save_strategy);
    config.advanced.solver.oneroot.hull_mode = try hullModeFromC(
        in_config.oneroot_hull_mode,
    );
    config.advanced.solver.oneroot.newton_seed_mode = try newtonSeedModeFromC(
        in_config.oneroot_newton_seed_mode,
    );
    config.advanced.solver.oneroot.newton_seed_reuse = try newtonSeedReuseFromC(
        in_config.oneroot_newton_seed_reuse,
    );
    config.advanced.solver.oneroot.edge_fun_mode = try edgeFunModeFromC(
        in_config.oneroot_edge_fun_mode,
    );
    config.advanced.solver.multiroot.mode = try multirootModeFromC(
        in_config.multiroot_mode,
    );
    config.advanced.solver.multiroot.edge_fun_mode = try edgeFunModeFromC(
        in_config.multiroot_edge_fun_mode,
    );
    config.validation = try validateInputFromC(
        in_config.validate_input,
    );
    config.report_perf = try reportModeFromC(in_config.report_perf);
    config.report_console = in_config.report_console != 0;
    config.advanced.raster.buffer_mode = try bufferModeFromC(in_config.buffer_mode);
    config.advanced.distortion.edge_spacing_px = in_config.edge_spacing_px;
    config.advanced.raster.tile_size_min = if (in_config.tile_size_min == 0)
        config.advanced.raster.tile_size_min
    else
        in_config.tile_size_min;
    config.advanced.raster.tile_size_max = if (in_config.tile_size_max == 0)
        config.advanced.raster.tile_size_max
    else
        in_config.tile_size_max;
    config.output.disk_save_overlap = in_config.disk_save_overlap != 0;
    config.advanced.raster.tile_size_override = if (in_config.tile_size_override == 0)
        null
    else
        in_config.tile_size_override;
    config.advanced.raster.global_subpx_tile_size_min =
        if (in_config.global_subpx_tile_size_min == 0)
            config.advanced.raster.global_subpx_tile_size_min
        else
            in_config.global_subpx_tile_size_min;
    config.advanced.raster.global_subpx_tile_size_max =
        if (in_config.global_subpx_tile_size_max == 0)
            config.advanced.raster.global_subpx_tile_size_max
        else
            in_config.global_subpx_tile_size_max;
    config.advanced.raster.global_subpx_tile_size_override =
        if (in_config.global_subpx_tile_size_override == 0)
            null
        else
            in_config.global_subpx_tile_size_override;
    config.advanced.raster.global_subpx_stripe_size_min =
        if (in_config.global_subpx_stripe_size_min == 0)
            config.advanced.raster.global_subpx_stripe_size_min
        else
            in_config.global_subpx_stripe_size_min;
    config.advanced.raster.global_subpx_stripe_size_max =
        if (in_config.global_subpx_stripe_size_max == 0)
            config.advanced.raster.global_subpx_stripe_size_max
        else
            in_config.global_subpx_stripe_size_max;
    config.advanced.raster.global_subpx_stripe_size_override =
        if (in_config.global_subpx_stripe_size_override == 0)
            null
        else
            in_config.global_subpx_stripe_size_override;
    config.advanced.raster.raster_halo_px_override =
        if (in_config.raster_halo_px_override == 0)
            null
        else
            in_config.raster_halo_px_override;
    if (in_config.save_frame_buff_count != 0) {
        config.output.save_frame_buff_count = in_config.save_frame_buff_count;
    }

    if (in_config.output_name_format) |format| {
        config.output_name_format = std.mem.span(format);
    }

    return config;
}

fn buildImageBuff(
    allocator: std.mem.Allocator,
    in_buff: *const CImageBuffF64,
) !maths.NDArray(F) {
    const dims = dimsToArray(in_buff.dims);
    var elems_num: usize = 1;
    for (dims) |dim| {
        elems_num *= dim;
    }
    const image_slice = try cMutSlice(
        F,
        in_buff.elems,
        elems_num,
    );
    return try maths.NDArray(F).init(
        allocator,
        image_slice,
        dims[0..],
    );
}

fn initThreadedIo(
    gpa: std.mem.Allocator,
    total_threads: u16,
) std.Io.Threaded {
    const threads = @max(@as(u16, 1), total_threads);
    const limit: std.Io.Limit = if (threads <= 1)
        .nothing
    else
        .limited(threads - 1);

    return std.Io.Threaded.init(gpa, .{
        .argv0 = .empty,
        .environ = .empty,
        .async_limit = limit,
        .concurrent_limit = limit,
    });
}

fn cameraInputToC(in_camera: riley.CameraInput) CCameraInput {
    var out_camera = CCameraInput{
        .pixels_num = .{
            .x = in_camera.pixels_num[0],
            .y = in_camera.pixels_num[1],
        },
        .pixels_size = .{
            .x = in_camera.pixels_size[0],
            .y = in_camera.pixels_size[1],
        },
        .pos_world = vec3ToCVec3(in_camera.pos_world),
        .rot_world = .{
            .x = in_camera.rot_world.alpha_z,
            .y = in_camera.rot_world.beta_y,
            .z = in_camera.rot_world.gamma_x,
        },
        .roi_cent_world = vec3ToCVec3(in_camera.roi_cent_world),
        .focal_length = in_camera.focal_length,
        .sub_sample = in_camera.sub_sample,
        .background_value = in_camera.background_value,
        .render_format_tag = switch (in_camera.render_format) {
            .mono => 0,
            .rgb => 1,
            .ir => 2,
            .multifield => 3,
        },
        .render_channels = switch (in_camera.render_format) {
            .mono, .ir => 1,
            .rgb => 3,
            .multifield => |channels_num| channels_num,
        },
        .output_files = null,
        .output_files_len = 0,
        .distort = .{
            .distort_model = 0,
            .distort_k1 = 0.0,
            .distort_k2 = 0.0,
            .distort_k3 = 0.0,
            .distort_k4 = 0.0,
            .distort_k5 = 0.0,
            .distort_k6 = 0.0,
            .distort_p1 = 0.0,
            .distort_p2 = 0.0,
            .distort_s1 = 0.0,
            .distort_s2 = 0.0,
            .distort_s3 = 0.0,
            .distort_s4 = 0.0,
            .distort_tau_x = 0.0,
            .distort_tau_y = 0.0,
            .distort_poly_degree = 0,
            .distort_poly_mode = 1,
            .distort_poly_coeffs = null,
            .distort_poly_coeffs_len = 0,
        },
        .psf = .{
            .psf_type = 0,
            .psf_sigma_x = 0.0,
            .psf_sigma_y = 0.0,
            .psf_theta = 0.0,
            .psf_supp_rad = 0.0,
            .psf_separable = 1,
        },
        .coord_sys = @intFromEnum(in_camera.coord_sys),
        .subpixel_center_map = @intFromEnum(in_camera.subpixel_center_map),
    };

    switch (in_camera.distort) {
        .none => {},
        .brown_con => |model| {
            out_camera.distort.distort_model = 1;
            out_camera.distort.distort_k1 = model.k1;
            out_camera.distort.distort_k2 = model.k2;
            out_camera.distort.distort_k3 = model.k3;
            out_camera.distort.distort_p1 = model.p1;
            out_camera.distort.distort_p2 = model.p2;
        },
        .brown_con_ext => |model| {
            out_camera.distort.distort_model = 2;
            out_camera.distort.distort_k1 = model.k1;
            out_camera.distort.distort_k2 = model.k2;
            out_camera.distort.distort_k3 = model.k3;
            out_camera.distort.distort_k4 = model.k4;
            out_camera.distort.distort_k5 = model.k5;
            out_camera.distort.distort_k6 = model.k6;
            out_camera.distort.distort_p1 = model.p1;
            out_camera.distort.distort_p2 = model.p2;
            out_camera.distort.distort_s1 = model.s1;
            out_camera.distort.distort_s2 = model.s2;
            out_camera.distort.distort_s3 = model.s3;
            out_camera.distort.distort_s4 = model.s4;
            out_camera.distort.distort_tau_x = model.tau_x;
            out_camera.distort.distort_tau_y = model.tau_y;
        },
        .poly => |poly| {
            out_camera.distort.distort_model = 3;
            out_camera.distort.distort_poly_degree = poly.degree;
            out_camera.distort.distort_poly_mode = @intFromEnum(poly.mode);
            out_camera.distort.distort_poly_coeffs = poly.coeffs.ptr;
            out_camera.distort.distort_poly_coeffs_len = poly.coeffs.len;
        },
        .brown_con_poly => |chain| {
            out_camera.distort.distort_model = 4;
            out_camera.distort.distort_k1 = chain.brown_con.k1;
            out_camera.distort.distort_k2 = chain.brown_con.k2;
            out_camera.distort.distort_k3 = chain.brown_con.k3;
            out_camera.distort.distort_p1 = chain.brown_con.p1;
            out_camera.distort.distort_p2 = chain.brown_con.p2;
            out_camera.distort.distort_poly_degree = chain.poly.degree;
            out_camera.distort.distort_poly_mode = @intFromEnum(chain.poly.mode);
            out_camera.distort.distort_poly_coeffs = chain.poly.coeffs.ptr;
            out_camera.distort.distort_poly_coeffs_len = chain.poly.coeffs.len;
        },
        .brown_con_ext_poly => |chain| {
            out_camera.distort.distort_model = 5;
            out_camera.distort.distort_k1 = chain.brown_con_ext.k1;
            out_camera.distort.distort_k2 = chain.brown_con_ext.k2;
            out_camera.distort.distort_k3 = chain.brown_con_ext.k3;
            out_camera.distort.distort_k4 = chain.brown_con_ext.k4;
            out_camera.distort.distort_k5 = chain.brown_con_ext.k5;
            out_camera.distort.distort_k6 = chain.brown_con_ext.k6;
            out_camera.distort.distort_p1 = chain.brown_con_ext.p1;
            out_camera.distort.distort_p2 = chain.brown_con_ext.p2;
            out_camera.distort.distort_s1 = chain.brown_con_ext.s1;
            out_camera.distort.distort_s2 = chain.brown_con_ext.s2;
            out_camera.distort.distort_s3 = chain.brown_con_ext.s3;
            out_camera.distort.distort_s4 = chain.brown_con_ext.s4;
            out_camera.distort.distort_tau_x = chain.brown_con_ext.tau_x;
            out_camera.distort.distort_tau_y = chain.brown_con_ext.tau_y;
            out_camera.distort.distort_poly_degree = chain.poly.degree;
            out_camera.distort.distort_poly_mode = @intFromEnum(chain.poly.mode);
            out_camera.distort.distort_poly_coeffs = chain.poly.coeffs.ptr;
            out_camera.distort.distort_poly_coeffs_len = chain.poly.coeffs.len;
        },
    }

    switch (in_camera.psf) {
        .pixel_box => {
            out_camera.psf.psf_type = 0;
            out_camera.psf.psf_separable = 1;
        },
        .gaussian => |g| {
            out_camera.psf.psf_type = 1;
            out_camera.psf.psf_sigma_x = g.sigma_px;
            out_camera.psf.psf_supp_rad = g.supp_rad_px;
            out_camera.psf.psf_separable = if (g.separable == .yes)
                @as(u32, 1)
            else
                @as(u32, 0);
        },
        .anisotropic_gaussian => |ag| {
            out_camera.psf.psf_type = 2;
            out_camera.psf.psf_sigma_x = ag.sigma_x_px;
            out_camera.psf.psf_sigma_y = ag.sigma_y_px;
            out_camera.psf.psf_theta = ag.theta_rad;
            out_camera.psf.psf_supp_rad = ag.supp_rad_px;
            out_camera.psf.psf_separable = if (ag.separable == .yes)
                @as(u32, 1)
            else
                @as(u32, 0);
        },
    }
    return out_camera;
}

fn rasterSceneInternal(
    allocator: std.mem.Allocator,
    in_meshes: [*c]const CMeshInput,
    meshes_len: usize,
    in_cameras: [*c]const CCameraInput,
    cameras_len: usize,
    in_config: *const CRasterConfig,
    out_dir_path: ?[*:0]const u8,
    out_image: ?*CImageBuffF64,
) !void {
    const mesh_inputs = try buildMeshInputSlice(
        allocator,
        in_meshes,
        meshes_len,
    );

    const camera_inputs = try buildCameraInputSlice(
        allocator,
        in_cameras,
        cameras_len,
    );
    defer allocator.free(camera_inputs);

    const raster_config = try buildRasterConfig(in_config);

    var image_arr_opt: ?maths.NDArray(F) = null;
    if (out_image) |image_buff| {
        image_arr_opt = try buildImageBuff(allocator, image_buff);
    }
    defer if (image_arr_opt) |*image_arr| {
        image_arr.deinit(allocator);
    };

    const outer_alloc = std.heap.smp_allocator;
    var threaded_io = std.Io.Threaded.init(outer_alloc, .{
        .argv0 = .empty,
        .environ = .empty,
        .async_limit = .nothing,
        .concurrent_limit = .nothing,
    });
    defer threaded_io.deinit();
    const io = threaded_io.io();

    const out_dir_path_slice = if (out_dir_path) |path|
        std.mem.span(path)
    else
        null;

    try riley.rasterInto(
        outer_alloc,
        io,
        camera_inputs,
        mesh_inputs,
        raster_config,
        out_dir_path_slice,
        if (image_arr_opt) |*image_arr| image_arr else null,
    );
}

pub export fn rileyRoiCentFromCoords(
    in_coords: *const CArray2DF64,
    out_cent: *CVec3F64,
) c_int {
    clearLastError();

    const coords = buildCoordsFromC(in_coords) catch |err| {
        setLastError(err);
        return 1;
    };
    const roi_cent = ops.boundsCenter(&coords);
    out_cent.* = vec3ToCVec3(roi_cent);
    return 0;
}

const GeometryInput = struct { coords: riley.Coords };

fn buildGeometry(allocator: std.mem.Allocator, inputs: [*c]const CArray2DF64, count: usize) ![]GeometryInput {
    if (count == 0) return error.EmptyGeometry;
    const coords = try cConstSlice(CArray2DF64, inputs, count);
    const geometry = try allocator.alloc(GeometryInput, count);
    for (coords, geometry) |*input, *item| item.coords = try buildCoordsFromC(input);
    return geometry;
}

pub export fn rileyRoiCentOverMeshes(in_coords: [*c]const CArray2DF64, coords_len: usize, out_cent: *CVec3F64) c_int {
    clearLastError();
    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const geometry = buildGeometry(arena.allocator(), in_coords, coords_len) catch |err| {
        setLastError(err);
        return 1;
    };
    out_cent.* = vec3ToCVec3(ops.boundsCenterOverMeshes(geometry));
    return 0;
}

pub export fn rileyPosFrameCoords(
    in_coords: *const CArray2DF64,
    pixels_num: CVec2U32,
    pixels_size: CVec2F64,
    focal_length: F,
    rot_world: CVec3F64,
    fov_scale: F,
    fit_mode: u32,
    target: [*c]const CVec3F64,
    out_pos: *CVec3F64,
) c_int {
    clearLastError();
    const geometry = buildCoordsFromC(in_coords) catch |err| {
        setLastError(err);
        return 1;
    };
    const fit: riley.FrameFitMode = switch (fit_mode) {
        0 => .contain,
        1 => .cover,
        2 => .horizontal,
        3 => .vertical,
        else => {
            setLastError(error.InvalidFrameFitMode);
            return 1;
        },
    };
    const rot = maths.Rotation.init(rot_world.x, rot_world.y, rot_world.z);
    const pixels = [2]u32{ pixels_num.x, pixels_num.y };
    const pitch = [2]F{ pixels_size.x, pixels_size.y };
    const pos = if (target != null)
        ops.posFrameCoordsTarg(&geometry, cVec3ToVec3(target[0]), pixels, pitch, focal_length, rot, fov_scale, fit)
    else
        ops.posFrameCoords(&geometry, pixels, pitch, focal_length, rot, fov_scale, fit);
    out_pos.* = vec3ToCVec3(pos);
    return 0;
}

pub export fn rileyPosFrameMeshes(
    in_coords: [*c]const CArray2DF64,
    coords_len: usize,
    pixels_num: CVec2U32,
    pixels_size: CVec2F64,
    focal_length: F,
    rot_world: CVec3F64,
    fov_scale: F,
    fit_mode: u32,
    target: [*c]const CVec3F64,
    out_pos: *CVec3F64,
) c_int {
    clearLastError();
    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const geometry = buildGeometry(arena.allocator(), in_coords, coords_len) catch |err| {
        setLastError(err);
        return 1;
    };
    const fit: riley.FrameFitMode = switch (fit_mode) {
        0 => .contain,
        1 => .cover,
        2 => .horizontal,
        3 => .vertical,
        else => {
            setLastError(error.InvalidFrameFitMode);
            return 1;
        },
    };
    const rot = maths.Rotation.init(rot_world.x, rot_world.y, rot_world.z);
    const pixels = [2]u32{ pixels_num.x, pixels_num.y };
    const pitch = [2]F{ pixels_size.x, pixels_size.y };
    const pos = if (target != null)
        ops.posFrameMeshesTarg(geometry, cVec3ToVec3(target[0]), pixels, pitch, focal_length, rot, fov_scale, fit)
    else
        ops.posFrameMeshes(geometry, pixels, pitch, focal_length, rot, fov_scale, fit);
    out_pos.* = vec3ToCVec3(pos);
    return 0;
}

pub export fn rileyCoverageToFovScale(coverage: F) F {
    return ops.coverageToFovScale(coverage);
}

pub export fn rileyFovScaleToCoverage(fov_scale: F) F {
    return ops.fovScaleToCoverage(fov_scale);
}

pub export fn rileyPosOrbitCam(
    targ_world: CVec3F64,
    azimuth_rad: F,
    elevation_rad: F,
    dist: F,
    out_pos: *CVec3F64,
    out_rot: *CVec3F64,
) c_int {
    clearLastError();
    const targ = cVec3ToVec3(targ_world);
    const orbit = ops.posOrbitCam(
        targ,
        azimuth_rad,
        elevation_rad,
        dist,
    );
    out_pos.* = vec3ToCVec3(orbit.pos);
    out_rot.* = .{
        .x = orbit.rot.alpha_z,
        .y = orbit.rot.beta_y,
        .z = orbit.rot.gamma_x,
    };
    return 0;
}

pub export fn rileyPosStereoPair(
    targ_world: CVec3F64,
    dist: F,
    stereo_angle_rad: F,
    baseline_angle_rad: F,
    out_cam0_pos: *CVec3F64,
    out_cam0_rot: *CVec3F64,
    out_cam1_pos: *CVec3F64,
    out_cam1_rot: *CVec3F64,
) c_int {
    clearLastError();
    const targ = cVec3ToVec3(targ_world);
    const stereo = ops.posStereoPair(
        targ,
        dist,
        stereo_angle_rad,
        baseline_angle_rad,
    );
    out_cam0_pos.* = vec3ToCVec3(stereo.cam0_pos);
    out_cam0_rot.* = .{
        .x = stereo.cam0_rot.alpha_z,
        .y = stereo.cam0_rot.beta_y,
        .z = stereo.cam0_rot.gamma_x,
    };
    out_cam1_pos.* = vec3ToCVec3(stereo.cam1_pos);
    out_cam1_rot.* = .{
        .x = stereo.cam1_rot.alpha_z,
        .y = stereo.cam1_rot.beta_y,
        .z = stereo.cam1_rot.gamma_x,
    };
    return 0;
}

pub export fn rileyCalcPixelResolution(
    in_camera: *const CCameraInput,
    targ_world: CVec3F64,
    out_res: *F,
) c_int {
    clearLastError();
    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const cam_input = buildCameraInput(arena.allocator(), in_camera) catch |err| {
        setLastError(err);
        return 1;
    };
    const targ = cVec3ToVec3(targ_world);
    out_res.* = ops.calcPixelResolution(cam_input, targ);
    return 0;
}

pub export fn rileyCalcOutputDimsScene(
    in_meshes: [*c]const CMeshInput,
    meshes_len: usize,
    in_cameras: [*c]const CCameraInput,
    cameras_len: usize,
    in_config: *const CRasterConfig,
    out_dims: *CDims5Usize,
) c_int {
    clearLastError();

    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const mesh_inputs = buildMeshInputSlice(
        aa,
        in_meshes,
        meshes_len,
    ) catch |err| {
        setLastError(err);
        return 1;
    };

    const camera_inputs = buildCameraInputSlice(
        aa,
        in_cameras,
        cameras_len,
    ) catch |err| {
        setLastError(err);
        return 1;
    };

    const raster_config = buildRasterConfig(in_config) catch |err| {
        setLastError(err);
        return 1;
    };

    const dims = riley.calcAllFramesImageDims(
        camera_inputs,
        mesh_inputs,
        raster_config,
    ) catch |err| {
        setLastError(err);
        return 1;
    };
    out_dims.* = dimsFromArray(dims);
    return 0;
}

pub export fn rileySaveCamera(
    out_dir_path: [*:0]const u8,
    file_name: [*:0]const u8,
    camera_idx: usize,
    camera_in: *const CCameraInput,
) c_int {
    clearLastError();

    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();

    const camera = buildCameraInput(arena.allocator(), camera_in) catch |err| {
        setLastError(err);
        return 1;
    };

    var threaded_io = initThreadedIo(std.heap.smp_allocator, 1);
    defer threaded_io.deinit();
    const io = threaded_io.io();
    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, std.mem.span(out_dir_path), .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            setLastError(err);
            return 1;
        }
    };

    var out_dir = cwd.openDir(
        io,
        std.mem.span(out_dir_path),
        .{},
    ) catch |err| {
        setLastError(err);
        return 1;
    };
    defer out_dir.close(io);

    dataio.saveCamera(
        io,
        out_dir,
        std.mem.span(file_name),
        camera_idx,
        camera,
    ) catch |err| {
        setLastError(err);
        return 1;
    };
    return 0;
}

/// Null buffer with zero capacity queries metadata/count without returning
/// a borrowed pointer.
fn copyLoadedCamera(
    camera_input: riley.CameraInput,
    coeffs: [*c]F,
    capacity: usize,
    out: *CCameraInput,
) !void {
    var result = cameraInputToC(camera_input);
    const count = result.distort.distort_poly_coeffs_len;
    if (coeffs == null and capacity == 0) {
        result.distort.distort_poly_coeffs = null;
        out.* = result;
        return;
    }
    if (capacity < count) return error.InsufficientPolyCapacity;
    if (count > 0) {
        if (coeffs == null) return error.NullPointer;
        @memcpy(coeffs[0..count], result.distort.distort_poly_coeffs[0..count]);
    }
    result.distort.distort_poly_coeffs = if (count == 0) null else coeffs;
    out.* = result;
}

pub export fn rileyLoadCamera(
    dir_path: [*:0]const u8,
    file_name: [*:0]const u8,
    coeffs: [*c]F,
    coeffs_capacity: usize,
    camera_out: *CCameraInput,
) c_int {
    clearLastError();

    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();

    var threaded_io = initThreadedIo(std.heap.smp_allocator, 1);
    defer threaded_io.deinit();
    const io = threaded_io.io();
    const cwd = std.Io.Dir.cwd();

    var dir = cwd.openDir(
        io,
        std.mem.span(dir_path),
        .{},
    ) catch |err| {
        setLastError(err);
        return 1;
    };
    defer dir.close(io);

    const loaded = dataio.LoadedCamera.init(
        arena.allocator(),
        io,
        dir,
        std.mem.span(file_name),
    ) catch |err| {
        setLastError(err);
        return 1;
    };
    defer loaded.deinit(arena.allocator());
    copyLoadedCamera(loaded.camera_input, coeffs, coeffs_capacity, camera_out) catch |err| {
        setLastError(err);
        return 1;
    };
    return 0;
}

pub export fn rileySaveStereoPair(
    out_dir_path: [*:0]const u8,
    stereo_file_name: [*:0]const u8,
    cam0_in: *const CCameraInput,
    cam1_in: *const CCameraInput,
) c_int {
    clearLastError();

    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const cam0 = buildCameraInput(aa, cam0_in) catch |err| {
        setLastError(err);
        return 1;
    };
    const cam1 = buildCameraInput(aa, cam1_in) catch |err| {
        setLastError(err);
        return 1;
    };

    var threaded_io = initThreadedIo(std.heap.smp_allocator, 1);
    defer threaded_io.deinit();
    const io = threaded_io.io();
    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, std.mem.span(out_dir_path), .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            setLastError(err);
            return 1;
        }
    };

    var out_dir = cwd.openDir(
        io,
        std.mem.span(out_dir_path),
        .{},
    ) catch |err| {
        setLastError(err);
        return 1;
    };
    defer out_dir.close(io);

    dataio.saveStereoPair(
        io,
        out_dir,
        std.mem.span(stereo_file_name),
        .{ .cameras = .{ cam0, cam1 } },
    ) catch |err| {
        setLastError(err);
        return 1;
    };
    return 0;
}

pub export fn rileyLoadStereoPair(
    dir_path: [*:0]const u8,
    stereo_file_name: [*:0]const u8,
    cam0_coeffs: [*c]F,
    cam0_capacity: usize,
    cam1_coeffs: [*c]F,
    cam1_capacity: usize,
    cam0_out: *CCameraInput,
    cam1_out: *CCameraInput,
) c_int {
    clearLastError();

    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    var threaded_io = initThreadedIo(std.heap.smp_allocator, 1);
    defer threaded_io.deinit();
    const io = threaded_io.io();
    const cwd = std.Io.Dir.cwd();

    var dir = cwd.openDir(
        io,
        std.mem.span(dir_path),
        .{},
    ) catch |err| {
        setLastError(err);
        return 1;
    };
    defer dir.close(io);

    const loaded = dataio.LoadedStereoPair.init(
        aa,
        io,
        dir,
        std.mem.span(stereo_file_name),
    ) catch |err| {
        setLastError(err);
        return 1;
    };
    defer loaded.deinit(aa);
    copyLoadedCamera(
        loaded.stereo_pair.cameras[0],
        cam0_coeffs,
        cam0_capacity,
        cam0_out,
    ) catch |err| {
        setLastError(err);
        return 1;
    };
    copyLoadedCamera(
        loaded.stereo_pair.cameras[1],
        cam1_coeffs,
        cam1_capacity,
        cam1_out,
    ) catch |err| {
        setLastError(err);
        return 1;
    };
    return 0;
}

pub export fn rileyRaster(
    in_meshes: [*c]const CMeshInput,
    meshes_len: usize,
    in_cameras: [*c]const CCameraInput,
    cameras_len: usize,
    in_config: *const CRasterConfig,
    out_dir_path: ?[*:0]const u8,
    out_image: ?*CImageBuffF64,
) c_int {
    clearLastError();

    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();

    rasterSceneInternal(
        arena.allocator(),
        in_meshes,
        meshes_len,
        in_cameras,
        cameras_len,
        in_config,
        out_dir_path,
        out_image,
    ) catch |err| {
        setLastError(err);
        return 1;
    };

    return 0;
}
