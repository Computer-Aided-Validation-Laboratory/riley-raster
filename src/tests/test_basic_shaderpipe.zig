const std = @import("std");
const camera = @import("../riley/zig/camera.zig");
const meshpipe = @import("../riley/zig/meshpipeline.zig");
const shaderops = @import("../riley/zig/shaderops.zig");
const shaderpipe = @import("../riley/zig/shaderpipe.zig");
const riley = @import("../riley/zig/riley.zig");
const orch = @import("../dev_support/orchestration.zig");
const tcfg = @import("../dev_support/testconfig.zig");
const F = @import("../riley/zig/buildconfig.zig").F;
const meshio = @import("../riley/zig/meshio.zig");
const policy = @import("../dev_support/testpolicy.zig");
const common = @import("../dev_support/tests.zig");
const imageio = @import("../riley/zig/imageio.zig");
const texops = @import("../riley/zig/textureops.zig");
const ndarray = @import("../riley/zig/ndarray.zig");

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    try runCase(allocator, io, false);
}

pub fn generateGold(allocator: std.mem.Allocator, io: std.Io) !void {
    try runCase(allocator, io, true);
    // Keep only the two floating-point comparison frames selected above.
    // BMP previews remain local and ignored by Git.
    inline for (.{ "shaderpipe_sum_quad4", "shaderpipe_ir_quad4" }) |case_name| {
        for (1..12) |frame| {
            var path_buf: [256]u8 = undefined;
            const path = try std.fmt.bufPrint(
                &path_buf,
                "{s}/{s}/cam0_frame{d}_field0.fimg",
                .{ policy.goldRoot(.basic), case_name, frame },
            );
            try std.Io.Dir.cwd().deleteFile(io, path);
        }
    }
}

fn runCase(allocator: std.mem.Allocator, io: std.Io, generate_gold: bool) !void {
    const sample_tol: F = if (F == f32) 1e-5 else 1e-9;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();
    const prepared = try orch.prepareSingleMeshCase(
        aa,
        io,
        "distort_rot",
        .quad4,
        .{ 48, 48 },
        1.15,
        "data/edge",
    );

    const stages = [_]shaderops.ShaderPipeStageInput{
        .{ .source = .{ .shader = .{ .func = .{
            .builtin = .checker,
            .params = .{ .coord_scale = .{ 4, 4 }, .settings = .{ .checker = .{} } },

            .scaling = .none,
        } }, .destination = .{ .kind = .channel, .index = 0 } } },
        .{ .source = .{ .shader = .{ .func = .{
            .builtin = .constant,
            .params = .{ .settings = .{ .constant = .{ .value = 0.25 } } },

            .scaling = .none,
        } }, .destination = .{ .kind = .channel, .index = 1 } } },
    };
    const sum_slots = [_]shaderpipe.Slot{
        .{ .kind = .channel, .index = 0 },
        .{ .kind = .channel, .index = 1 },
    };
    const pipes = [_]shaderops.ShaderPipeInput{.{
        .stages = &stages,
        .resolver = .{ .sum = &sum_slots },
    }};
    const mesh = meshpipe.MeshInput{
        .mesh_type = .quad4,
        .coords = prepared.sim_data.coords,
        .connect = prepared.sim_data.connect,
        .disp = prepared.sim_data.field,
        .shaders = .{ .mono = .{ .pipe = pipes[0] } },
    };
    const cam_in = camera.CameraInput{
        .pixels_num = prepared.camera.pixels_num,
        .pixels_size = prepared.camera.pixels_size,
        .pos_world = prepared.camera.pos_world,
        .rot_world = prepared.camera.rot_world,
        .roi_cent_world = prepared.camera.roi_cent_world,
        .focal_length = prepared.camera.focal_length,
        .sub_sample = 1,
        .render_format = .mono,
    };
    var config = tcfg.getRasterConfig(.testing);
    config.save_strategy = if (generate_gold) .both else .memory;
    config.background_value = 0;

    const generic_stages = [_]shaderops.ShaderPipeStageInput{
        .{ .source = .{ .shader = .{ .func_rgb = .{
            .builtin = .constant,
            .params = .{ .settings = .{ .constant = .{
                .value_rgb = .{ 0.3, 0.4, 0 },
            } } },

            .scaling = .none,
        } }, .destination = .{ .kind = .field, .index = 0 } } },
        .{ .normalise = .{ .source = .{ .kind = .field, .index = 0 }, .destination = .{ .kind = .channel, .index = 0 }, .components = 3 } },
        .{ .affine_map = .{ .source = .{ .kind = .channel, .index = 0 }, .destination = .{ .kind = .field, .index = 3 }, .gain = 2, .offset = 0.1 } },
        .{ .lut_map = .{ .source = .{ .kind = .field, .index = 3 }, .destination = .{ .kind = .field, .index = 4 }, .lookup = .{ .first = 0, .step = 1, .values = &.{ 0, 10, 20 } } } },
        .{ .blend = .{ .a = .{ .kind = .field, .index = 4 }, .b = .{ .kind = .channel, .index = 1 }, .destination = .{ .kind = .channel, .index = 3 }, .alpha = .{ .slot = .{ .kind = .channel, .index = 0 } } } },
    };
    const generic_result_slot = [_]shaderpipe.Slot{.{ .kind = .channel, .index = 3 }};
    var generic_mesh = mesh;
    generic_mesh.shaders = .{ .mono = .{ .pipe = .{
        .stages = &generic_stages,
        .resolver = .{ .identity = &generic_result_slot },
    } } };
    var generic_config = config;
    generic_config.save_strategy = .memory;
    const generic_result = try riley.raster(
        aa,
        io,
        &.{cam_in},
        &.{generic_mesh},
        generic_config,
        null,
    );
    const generic_image = generic_result orelse return error.NoResult;
    defer aa.free(generic_image.slice);
    var generic_foreground: usize = 0;
    for (generic_image.slice) |value| {
        if (value != 0) {
            generic_foreground += 1;
            try std.testing.expectApproxEqAbs(@as(F, 5.68), value, sample_tol);
        }
    }
    try std.testing.expect(generic_foreground > 0);

    // A nodal source with fewer frames than the mesh displacement must use
    // the selected frame, then hold its final field frame just like a direct
    // nodal shader. This compares the complete scalar/SIMD raster result.
    var timed_field = try meshio.Field.initAlloc(
        aa,
        3,
        prepared.sim_data.coords.mat.rows_num,
        1,
    );
    for (0..3) |ff| {
        for (0..prepared.sim_data.coords.mat.rows_num) |nn| {
            timed_field.array.set(
                &.{ ff, nn, 0 },
                @as(F, @floatFromInt(ff + 1)) * 0.2,
            );
        }
    }
    const zero_disp = try meshio.Field.initAlloc(
        aa,
        4,
        prepared.sim_data.coords.mat.rows_num,
        3,
    );
    @memset(zero_disp.array.slice, 0);
    const nodal_shader: shaderops.ShaderDirectInput = .{ .nodal = .{
        .field = timed_field,

        .scaling = .none,
    } };
    var direct_mesh = mesh;
    direct_mesh.disp = zero_disp;
    direct_mesh.shaders = .{ .mono = .{ .direct = nodal_shader } };
    var direct_cam = cam_in;
    direct_cam.render_format = .mono;
    var parity_config = config;
    parity_config.save_strategy = .memory;
    const direct_result = try riley.raster(
        aa,
        io,
        &.{direct_cam},
        &.{direct_mesh},
        parity_config,
        null,
    );
    const direct_image = direct_result orelse return error.NoResult;
    defer aa.free(direct_image.slice);
    const parity_stage = [_]shaderops.ShaderPipeStageInput{.{ .source = .{
        .shader = nodal_shader,
        .destination = .{ .kind = .channel, .index = 0 },
    } }};
    const parity_slots = [_]shaderpipe.Slot{.{ .kind = .channel, .index = 0 }};
    const parity_pipe = [_]shaderops.ShaderPipeInput{.{
        .stages = &parity_stage,
        .resolver = .{ .identity = &parity_slots },
    }};
    var pipe_mesh = direct_mesh;
    pipe_mesh.shaders = .{ .mono = .{ .pipe = parity_pipe[0] } };
    const pipe_result = try riley.raster(
        aa,
        io,
        &.{cam_in},
        &.{pipe_mesh},
        parity_config,
        null,
    );
    const pipe_image = pipe_result orelse return error.NoResult;
    defer aa.free(pipe_image.slice);
    try std.testing.expectEqual(@as(usize, 4), pipe_image.dims[1]);
    for (direct_image.slice, pipe_image.slice) |expected, actual| {
        try std.testing.expectApproxEqAbs(expected, actual, sample_tol);
    }
    var frame_max: [4]F = @splat(0);
    for (0..4) |ff| {
        for (0..direct_image.dims[3]) |yy| {
            for (0..direct_image.dims[4]) |xx| {
                const px = direct_image.get(&.{ 0, ff, 0, yy, xx });
                frame_max[ff] = @max(frame_max[ff], px);
            }
        }
    }
    try std.testing.expect(frame_max[0] > 0);
    try std.testing.expectApproxEqAbs(frame_max[0] * 2, frame_max[1], sample_tol);
    try std.testing.expectApproxEqAbs(frame_max[0] * 3, frame_max[2], sample_tol);
    try std.testing.expectApproxEqAbs(frame_max[2], frame_max[3], sample_tol);

    const function_channels = [_]shaderops.FuncChannel{
        .{ .builtin = .constant, .params = .{ .settings = .{ .constant = .{ .value = 0.2 } } } },
        .{ .builtin = .constant, .params = .{ .settings = .{ .constant = .{ .value = 0.3 } } }, .output_gain = 2, .output_offset = 0.1 },
        .{ .builtin = .linear, .params = .{ .settings = .{ .linear = .{ .coeffs = .{ 0.4, 0, 0 } } } } },
        .{ .builtin = .eggbox, .params = .{ .settings = .{ .eggbox = .{ .mean = 0.5, .contrast = 0 } } } },
    };
    const function_shader: shaderops.ShaderDirectInput = .{ .func_multi = .{
        .channels = &function_channels,
    } };
    var multifield_cam = cam_in;
    multifield_cam.render_format = .{ .multifield = 4 };
    var function_mesh = direct_mesh;
    function_mesh.shaders = .{ .multifield = .{ .direct = function_shader } };
    const function_result = (try riley.raster(
        aa,
        io,
        &.{multifield_cam},
        &.{function_mesh},
        parity_config,
        null,
    )) orelse return error.NoResult;
    defer aa.free(function_result.slice);
    const function_stages = [_]shaderops.ShaderPipeStageInput{.{ .source = .{
        .shader = function_shader,
        .destination = .{ .kind = .channel, .index = 0 },
    } }};
    const function_slots = [_]shaderpipe.Slot{
        .{ .kind = .channel, .index = 0 },
        .{ .kind = .channel, .index = 1 },
        .{ .kind = .channel, .index = 2 },
        .{ .kind = .channel, .index = 3 },
    };
    var function_pipe_mesh = function_mesh;
    function_pipe_mesh.shaders = .{ .multifield = .{ .pipe = .{
        .stages = &function_stages,
        .resolver = .{ .identity = &function_slots },
    } } };
    const function_pipe_result = (try riley.raster(
        aa,
        io,
        &.{multifield_cam},
        &.{function_pipe_mesh},
        parity_config,
        null,
    )) orelse return error.NoResult;
    defer aa.free(function_pipe_result.slice);
    for (function_result.slice, function_pipe_result.slice) |direct_value, pipe_value| {
        try std.testing.expectApproxEqAbs(direct_value, pipe_value, sample_tol);
    }
    try std.testing.expectEqual(@as(usize, 4), function_result.dims[2]);
    var function_foreground: usize = 0;
    for (0..function_result.dims[3]) |yy| {
        for (0..function_result.dims[4]) |xx| {
            const first = function_result.get(&.{ 0, 0, 0, yy, xx });
            if (first > 0.199) {
                function_foreground += 1;
                try std.testing.expectApproxEqAbs(@as(F, 0.2), first, sample_tol);
                try std.testing.expectApproxEqAbs(@as(F, 0.7), function_result.get(&.{ 0, 0, 1, yy, xx }), sample_tol);
                try std.testing.expectApproxEqAbs(@as(F, 0.4), function_result.get(&.{ 0, 0, 2, yy, xx }), sample_tol);
                try std.testing.expectApproxEqAbs(@as(F, 0.5), function_result.get(&.{ 0, 0, 3, yy, xx }), sample_tol);
            }
        }
    }
    try std.testing.expect(function_foreground > 0);

    var multifield_tex = try texops.Tex(F, 4).init(aa, 2, 2);
    for (0..4) |ch| {
        for (0..2) |row| {
            for (0..2) |col| {
                multifield_tex.setVal(ch, row, col, @as(F, @floatFromInt(ch + 1)) * 0.1);
            }
        }
    }
    const texture_uvs = try ndarray.NDArray(F).initFlat(
        aa,
        &.{ prepared.sim_data.coords.mat.rows_num, 2 },
    );
    @memset(texture_uvs.slice, 0.5);
    const texture_shader: shaderops.ShaderDirectInput = .{ .tex_multi_f = .{
        .uvs = texture_uvs,
        .tex = .{ .array = multifield_tex.array, .rows_num = multifield_tex.rows_num, .cols_num = multifield_tex.cols_num },
        .samp_cfg = .{ .sample = .nearest },
        .output_gain = 2,
        .output_offset = 0.05,
    } };
    var texture_mesh = direct_mesh;
    texture_mesh.shaders = .{ .multifield = .{ .direct = texture_shader } };
    const texture_result = (try riley.raster(
        aa,
        io,
        &.{multifield_cam},
        &.{texture_mesh},
        parity_config,
        null,
    )) orelse return error.NoResult;
    defer aa.free(texture_result.slice);
    var texture_foreground: usize = 0;
    for (0..texture_result.dims[3]) |yy| {
        for (0..texture_result.dims[4]) |xx| {
            const first = texture_result.get(&.{ 0, 0, 0, yy, xx });
            if (first > 0.249) {
                texture_foreground += 1;
                for (0..4) |ch| {
                    const expected = @as(F, @floatFromInt(ch + 1)) * 0.2 + 0.05;
                    try std.testing.expectApproxEqAbs(
                        expected,
                        texture_result.get(&.{ 0, 0, ch, yy, xx }),
                        sample_tol,
                    );
                }
            }
        }
    }
    try std.testing.expect(texture_foreground > 0);

    // The public texture input accepts the channel cap and integer storage.
    // Integer texels are converted during static preparation for this path.
    var eight_tex = try texops.Tex(u8, 8).init(aa, 2, 2);
    for (0..8) |ch| {
        for (0..2) |row| {
            for (0..2) |col| eight_tex.setVal(ch, row, col, @intCast(ch + 1));
        }
    }
    var eight_camera = cam_in;
    eight_camera.render_format = .{ .multifield = 8 };
    var eight_mesh = direct_mesh;
    eight_mesh.shaders = .{ .multifield = .{ .direct = .{ .tex_multi_u8 = .{
        .uvs = texture_uvs,
        .tex = .{ .array = eight_tex.array, .rows_num = eight_tex.rows_num, .cols_num = eight_tex.cols_num },
        .samp_cfg = .{ .sample = .nearest },
    } } } };
    const eight_result = (try riley.raster(
        aa,
        io,
        &.{eight_camera},
        &.{eight_mesh},
        parity_config,
        null,
    )) orelse return error.NoResult;
    defer aa.free(eight_result.slice);
    try std.testing.expectEqual(@as(usize, 8), eight_result.dims[2]);
    var eight_foreground: usize = 0;
    for (0..eight_result.dims[3]) |yy| {
        for (0..eight_result.dims[4]) |xx| {
            if (eight_result.get(&.{ 0, 0, 0, yy, xx }) > 0.5) {
                eight_foreground += 1;
                for (0..8) |ch| {
                    try std.testing.expectApproxEqAbs(
                        @as(F, @floatFromInt(ch + 1)),
                        eight_result.get(&.{ 0, 0, ch, yy, xx }),
                        sample_tol,
                    );
                }
            }
        }
    }
    try std.testing.expect(eight_foreground > 0);

    var format_mesh = direct_mesh;
    format_mesh.shaders = .{
        .mono = .{ .direct = nodal_shader },
        .multifield = .{ .direct = function_shader },
    };
    const format_result = (try riley.raster(
        aa,
        io,
        &.{ cam_in, multifield_cam },
        &.{format_mesh},
        parity_config,
        null,
    )) orelse return error.NoResult;
    defer aa.free(format_result.slice);
    try std.testing.expectEqual(@as(usize, 2), format_result.dims[0]);
    try std.testing.expectEqual(@as(usize, 4), format_result.dims[2]);
    for (1..4) |ch| {
        for (0..format_result.dims[3]) |yy| {
            for (0..format_result.dims[4]) |xx| {
                const padding = format_result.get(&.{ 0, 0, ch, yy, xx });
                if (padding != 0) {
                    std.debug.print("mono padding channel {d} at {d},{d}: {e}\n", .{ ch, yy, xx, padding });
                    return error.InvalidCameraPadding;
                }
            }
        }
    }
    try std.testing.expectApproxEqAbs(
        function_result.get(&.{ 0, 0, 1, 24, 24 }),
        format_result.get(&.{ 1, 0, 1, 24, 24 }),
        sample_tol,
    );

    try runSharedWorldGeometryCase(aa, io, mesh, cam_in, parity_config, sample_tol);

    const sum_gold_dir = try std.fmt.allocPrint(
        aa,
        "{s}/shaderpipe_sum_quad4",
        .{policy.goldRoot(.basic)},
    );
    const ir_gold_dir = try std.fmt.allocPrint(
        aa,
        "{s}/shaderpipe_ir_quad4",
        .{policy.goldRoot(.basic)},
    );
    const result = try riley.raster(
        aa,
        io,
        &.{cam_in},
        &.{mesh},
        config,
        if (generate_gold) sum_gold_dir else null,
    );
    const image = result orelse return error.NoResult;
    defer aa.free(image.slice);
    var min: F = std.math.inf(F);
    var max: F = -std.math.inf(F);
    var dark_count: usize = 0;
    var light_count: usize = 0;
    for (image.slice) |pixel| {
        min = @min(min, pixel);
        max = @max(max, pixel);
        if (pixel > 0.15 and pixel < 0.4) dark_count += 1;
        if (pixel > 1.1) light_count += 1;
    }
    try std.testing.expect(max > 0.9);
    try std.testing.expect(min < 0.1);
    try std.testing.expect(dark_count > 0);
    try std.testing.expect(light_count > 0);
    if (!generate_gold) {
        for ([_]usize{ 0, image.dims[1] - 1 }) |ff| {
            const gold = try common.findGoldPath(aa, io, sum_gold_dir, 0, ff, 0, false);
            try common.compareNDArrayToGold(
                aa,
                io,
                &image,
                0,
                ff,
                0,
                1,
                gold,
                tcfg.REL_TOL,
                tcfg.ABS_TOL,
            );
        }
    }

    // A temperature field and an independent emissivity producer feed the IR
    // resolver. Distinct nodal values make the physically resolved image vary.
    var temperature = try meshio.Field.initAlloc(
        aa,
        1,
        prepared.sim_data.coords.mat.rows_num,
        1,
    );
    for (0..prepared.sim_data.coords.mat.rows_num) |nn| {
        temperature.array.set(&.{ 0, nn, 0 }, 290 + @as(F, @floatFromInt(nn)) * 5);
    }
    const response: shaderpipe.BandResponse = .{
        .wavelengths_m = &.{ 8e-6, 9e-6, 10e-6, 11e-6, 12e-6 },
        .response = &.{ 0, 1, 1, 1, 0 },
    };
    const radiance = try response.prepareRadianceLookup(aa, 280, 340, 0.25);
    const speckle = try imageio.loadImage(u8, 1, aa, io, "texture/speck128_mono_u8.bmp", .bmp);
    const ir_stages = [_]shaderops.ShaderPipeStageInput{
        .{ .source = .{ .shader = .{ .nodal = .{
            .field = temperature,

            .scaling = .none,
        } }, .destination = .{ .kind = .field, .index = 0 } } },
        .{ .source = .{ .shader = .{ .tex_u8 = .{
            .uvs = prepared.uvs.array,
            .tex = speckle,
            .samp_cfg = .{ .sample = .linear, .mode = .direct },

            .scaling = .{ .fixed = .{ 0, 255 } },
        } }, .destination = .{ .kind = .channel, .index = 0 } } },
        .{ .grey_to_emissivity = .{
            .source = .{ .kind = .channel, .index = 0 },
            .destination = .{ .kind = .parameter, .index = 0 },
            .black = 0.95,
            .white = 0.55,
        } },
    };
    const ir_pipe = [_]shaderops.ShaderPipeInput{.{
        .stages = &ir_stages,
        .resolver = .{ .greybody_band = .{
            .temperature = .{ .kind = .field, .index = 0 },
            .emissivity = .{ .kind = .parameter, .index = 0 },
            .radiance = radiance,
        } },
    }};
    var ir_mesh = mesh;
    ir_mesh.shaders = .{ .ir = .{ .pipe = ir_pipe[0] } };
    var ir_cam = cam_in;
    ir_cam.render_format = .ir;
    const ir_result = try riley.raster(
        aa,
        io,
        &.{ir_cam},
        &.{ir_mesh},
        config,
        if (generate_gold) ir_gold_dir else null,
    );
    const ir_image = ir_result orelse return error.NoResult;
    defer aa.free(ir_image.slice);
    var ir_min: F = std.math.inf(F);
    var ir_max: F = -std.math.inf(F);
    for (ir_image.slice) |pixel| {
        if (pixel <= 0) continue;
        ir_min = @min(ir_min, pixel);
        ir_max = @max(ir_max, pixel);
    }
    try std.testing.expect(ir_min > radiance.sample(280) * 0.5);
    try std.testing.expect(ir_max < radiance.sample(340));
    try std.testing.expect(ir_max > ir_min * 1.01);
    if (!generate_gold) {
        for ([_]usize{ 0, ir_image.dims[1] - 1 }) |ff| {
            const gold = try common.findGoldPath(aa, io, ir_gold_dir, 0, ff, 0, false);
            try common.compareNDArrayToGold(
                aa,
                io,
                &ir_image,
                0,
                ff,
                0,
                1,
                gold,
                tcfg.REL_TOL,
                tcfg.ABS_TOL,
            );
        }
    }

    var invalid_camera = cam_in;
    invalid_camera.render_format = .rgb;
    var memory_config = config;
    memory_config.save_strategy = .memory;
    try std.testing.expectError(
        error.NoCompatibleShader,
        riley.raster(aa, io, &.{invalid_camera}, &.{mesh}, memory_config, null),
    );
    const missing_slots = [_]shaderpipe.Slot{.{ .kind = .channel, .index = 4 }};
    const invalid_pipe = [_]shaderops.ShaderPipeInput{.{
        .stages = &stages,
        .resolver = .{ .identity = &missing_slots },
    }};
    var invalid_mesh = mesh;
    invalid_mesh.shaders = .{ .mono = .{ .pipe = invalid_pipe[0] } };
    try std.testing.expectError(
        error.InvalidShaderPipe,
        riley.raster(aa, io, &.{cam_in}, &.{invalid_mesh}, memory_config, null),
    );

    // The fixed local buffer is indexed by total stage position, including
    // transforms. A source at the final valid position must load correctly.
    var max_stages: [8]shaderops.ShaderPipeStageInput = undefined;
    max_stages[0] = parity_stage[0];
    for (1..7) |ss| max_stages[ss] = .{ .clamp = .{
        .source = .{ .kind = .channel, .index = @intCast(ss - 1) },
        .destination = .{ .kind = .channel, .index = @intCast(ss) },
        .lower = 0,
        .upper = 1,
    } };
    max_stages[7] = .{ .source = .{
        .shader = nodal_shader,
        .destination = .{ .kind = .channel, .index = 7 },
    } };
    const last_slot = [_]shaderpipe.Slot{.{ .kind = .channel, .index = 7 }};
    const max_pipe = [_]shaderops.ShaderPipeInput{.{
        .stages = &max_stages,
        .resolver = .{ .identity = &last_slot },
    }};
    var max_mesh = direct_mesh;
    max_mesh.shaders = .{ .mono = .{ .pipe = max_pipe[0] } };
    const max_result = try riley.raster(
        aa,
        io,
        &.{cam_in},
        &.{max_mesh},
        parity_config,
        null,
    );
    const max_image = max_result orelse return error.NoResult;
    defer aa.free(max_image.slice);
    for (direct_image.slice, max_image.slice) |expected, actual| {
        try std.testing.expectApproxEqAbs(expected, actual, sample_tol);
    }
    var too_many_stages: [9]shaderops.ShaderPipeStageInput = undefined;
    @memcpy(too_many_stages[0..8], max_stages[0..]);
    too_many_stages[8] = .{ .clamp = .{
        .source = .{ .kind = .channel, .index = 7 },
        .destination = .{ .kind = .channel, .index = 8 },
        .lower = 0,
        .upper = 1,
    } };
    const overflow_pipe = [_]shaderops.ShaderPipeInput{.{
        .stages = &too_many_stages,
        .resolver = .{ .identity = &last_slot },
    }};
    max_mesh.shaders = .{ .mono = .{ .pipe = overflow_pipe[0] } };
    try std.testing.expectError(
        error.InvalidShaderPipe,
        riley.raster(aa, io, &.{cam_in}, &.{max_mesh}, parity_config, null),
    );

    // A mixed camera batch selects the matching pipe and pads unused channels.
    var channels = try meshio.Field.initAlloc(
        aa,
        1,
        prepared.sim_data.coords.mat.rows_num,
        4,
    );
    for (0..prepared.sim_data.coords.mat.rows_num) |nn| {
        for (0..4) |cc| {
            channels.array.set(
                &.{ 0, nn, cc },
                @as(F, @floatFromInt(cc + 1)) * 0.1,
            );
        }
    }
    const rgb_stages = [_]shaderops.ShaderPipeStageInput{.{ .source = .{
        .shader = .{ .func_rgb = .{
            .builtin = .constant,
            .params = .{ .settings = .{ .constant = .{ .value_rgb = .{ 0.2, 0.5, 0.8 } } } },

            .scaling = .none,
        } },
        .destination = .{ .kind = .channel, .index = 0 },
    } }};
    const multi_stages = [_]shaderops.ShaderPipeStageInput{.{ .source = .{
        .shader = .{ .nodal = .{ .field = channels, .scaling = .none } },
        .destination = .{ .kind = .channel, .index = 0 },
    } }};
    const rgb_slots = [_]shaderpipe.Slot{
        .{ .kind = .channel, .index = 0 }, .{ .kind = .channel, .index = 1 },
        .{ .kind = .channel, .index = 2 },
    };
    const invalid_rgb_stages = [_]shaderops.ShaderPipeStageInput{.{ .source = .{
        .shader = rgb_stages[0].source.shader,
        .destination = .{ .kind = .channel, .index = 255 },
    } }};
    const invalid_rgb_pipe = [_]shaderops.ShaderPipeInput{.{
        .stages = &invalid_rgb_stages,
        .resolver = .{ .identity = &rgb_slots },
    }};
    var invalid_rgb_mesh = mesh;
    invalid_rgb_mesh.shaders = .{ .rgb = .{ .pipe = invalid_rgb_pipe[0] } };
    var invalid_rgb_cam = cam_in;
    invalid_rgb_cam.render_format = .rgb;
    try std.testing.expectError(
        error.InvalidShaderPipe,
        riley.raster(
            aa,
            io,
            &.{invalid_rgb_cam},
            &.{invalid_rgb_mesh},
            memory_config,
            null,
        ),
    );
    const multi_slots = [_]shaderpipe.Slot{
        .{ .kind = .channel, .index = 0 }, .{ .kind = .channel, .index = 1 },
        .{ .kind = .channel, .index = 2 }, .{ .kind = .channel, .index = 3 },
    };
    const mixed_pipes = [_]shaderops.ShaderPipeInput{
        .{ .stages = &rgb_stages, .resolver = .{ .identity = &rgb_slots } },
        .{ .stages = &multi_stages, .resolver = .{ .identity = &multi_slots } },
    };
    var mixed_mesh = mesh;
    mixed_mesh.disp = null;
    mixed_mesh.shaders = .{ .rgb = .{ .pipe = mixed_pipes[0] }, .multifield = .{ .pipe = mixed_pipes[1] } };
    var rgb_cam = cam_in;
    rgb_cam.render_format = .rgb;
    var multi_cam = cam_in;
    multi_cam.render_format = .{ .multifield = 4 };
    const mixed_result = try riley.raster(
        aa,
        io,
        &.{ rgb_cam, multi_cam },
        &.{mixed_mesh},
        memory_config,
        null,
    );
    const mixed_image = mixed_result orelse return error.NoResult;
    defer aa.free(mixed_image.slice);
    try std.testing.expectEqual(@as(usize, 4), mixed_image.dims[2]);
    var found = false;
    for (0..mixed_image.dims[3]) |yy| {
        for (0..mixed_image.dims[4]) |xx| {
            if (mixed_image.get(&.{ 1, 0, 0, yy, xx }) < 0.099) continue;
            try std.testing.expectApproxEqAbs(
                @as(F, 0.2),
                mixed_image.get(&.{ 0, 0, 0, yy, xx }),
                sample_tol,
            );
            try std.testing.expectApproxEqAbs(
                @as(F, 0.5),
                mixed_image.get(&.{ 0, 0, 1, yy, xx }),
                sample_tol,
            );
            try std.testing.expectApproxEqAbs(
                @as(F, 0.8),
                mixed_image.get(&.{ 0, 0, 2, yy, xx }),
                sample_tol,
            );
            try std.testing.expectEqual(
                @as(F, 0),
                mixed_image.get(&.{ 0, 0, 3, yy, xx }),
            );
            try std.testing.expectApproxEqAbs(
                @as(F, 0.4),
                mixed_image.get(&.{ 1, 0, 3, yy, xx }),
                sample_tol,
            );
            found = true;
            break;
        }
        if (found) break;
    }
    try std.testing.expect(found);

    const unused_field = try meshio.Field.initAlloc(
        aa,
        6,
        prepared.sim_data.coords.mat.rows_num,
        4,
    );
    @memset(unused_field.array.slice, 0.1);
    const unused_stages = [_]shaderops.ShaderPipeStageInput{.{ .source = .{
        .shader = .{ .nodal = .{ .field = unused_field, .scaling = .none } },
        .destination = .{ .kind = .channel, .index = 0 },
    } }};
    var direct_with_unused = direct_mesh;
    direct_with_unused.shaders.multifield = .{ .pipe = .{
        .stages = &unused_stages,
        .resolver = .{ .identity = &multi_slots },
    } };
    const direct_only = (try riley.raster(
        aa,
        io,
        &.{direct_cam},
        &.{direct_with_unused},
        memory_config,
        null,
    )) orelse return error.NoResult;
    defer aa.free(direct_only.slice);
    try std.testing.expectEqual(@as(usize, 4), direct_only.dims[1]);
    try std.testing.expectEqual(@as(usize, 1), direct_only.dims[2]);

    var invalid_multi_cam = multi_cam;
    invalid_multi_cam.render_format = .{ .multifield = 9 };
    try std.testing.expectError(
        error.InvalidRenderFormatChannels,
        riley.raster(
            aa,
            io,
            &.{invalid_multi_cam},
            &.{mixed_mesh},
            memory_config,
            null,
        ),
    );

    // One geometry and one displacement history can serve direct stereo and
    // an independent IR pipe in a single camera batch.
    var multimodal_mesh = direct_mesh;
    multimodal_mesh.shaders.ir = .{ .pipe = parity_pipe[0] };
    const multimodal = (try riley.raster(
        aa,
        io,
        &.{ direct_cam, ir_cam, direct_cam },
        &.{multimodal_mesh},
        parity_config,
        null,
    )) orelse return error.NoResult;
    defer aa.free(multimodal.slice);
    for (0..multimodal.dims[1]) |ff| {
        for (0..multimodal.dims[3]) |yy| {
            for (0..multimodal.dims[4]) |xx| {
                const expected = direct_image.get(&.{ 0, ff, 0, yy, xx });
                try std.testing.expectApproxEqAbs(
                    expected,
                    multimodal.get(&.{ 0, ff, 0, yy, xx }),
                    sample_tol,
                );
                try std.testing.expectApproxEqAbs(
                    expected,
                    multimodal.get(&.{ 1, ff, 0, yy, xx }),
                    sample_tol,
                );
                try std.testing.expectApproxEqAbs(
                    expected,
                    multimodal.get(&.{ 2, ff, 0, yy, xx }),
                    sample_tol,
                );
            }
        }
    }

    const expr_stages = [_]shaderops.ShaderPipeStageInput{
        rgb_stages[0],
        .{ .source = .{
            .shader = .{ .func_rgb = .{
                .builtin = .constant,
                .params = .{ .settings = .{ .constant = .{
                    .value_rgb = .{ 0.1, 0.2, 0.3 },
                } } },

                .scaling = .none,
            } },
            .destination = .{ .kind = .parameter, .index = 0 },
        } },
        .{ .source = .{
            .shader = .{ .func = .{
                .builtin = .constant,
                .params = .{ .settings = .{ .constant = .{ .value = 2 } } },

                .scaling = .none,
            } },
            .destination = .{ .kind = .field, .index = 0 },
        } },
    };
    const expression = [_]shaderpipe.Op{
        .{ .load = .{ .kind = .channel, .index = 0 } },
        .{ .load = .{ .kind = .parameter, .index = 0 } },
        .multiply,
        .{ .load = .{ .kind = .channel, .index = 1 } },
        .{ .load = .{ .kind = .parameter, .index = 1 } },
        .multiply,
        .add,
        .{ .load = .{ .kind = .channel, .index = 2 } },
        .{ .load = .{ .kind = .parameter, .index = 2 } },
        .multiply,
        .add,
        .{ .load = .{ .kind = .field, .index = 0 } },
        .multiply,
        .{ .load = .{ .kind = .constant, .index = 0 } },
        .multiply,
        .{ .store = 0 },
    };
    const expression_pipe = [_]shaderops.ShaderPipeInput{.{
        .stages = &expr_stages,
        .resolver = .{ .expression = .{
            .operations = &expression,
            .constants = &.{0.5},
        } },
    }};
    var expr_mesh = mixed_mesh;
    expr_mesh.shaders = .{ .mono = .{ .pipe = expression_pipe[0] } };
    const expr_result = try riley.raster(
        aa,
        io,
        &.{cam_in},
        &.{expr_mesh},
        memory_config,
        null,
    );
    const expr_image = expr_result orelse return error.NoResult;
    defer aa.free(expr_image.slice);
    var expr_found = false;
    for (expr_image.slice) |pixel| {
        if (pixel < 0.35) continue;
        try std.testing.expectApproxEqAbs(@as(F, 0.36), pixel, sample_tol);
        expr_found = true;
    }
    try std.testing.expect(expr_found);

    // The incompatible foreground mesh must be absent from mono depth and
    // geometry preparation; each mixed-camera image matches its isolated scene.
    var front_coords = try meshio.Coords.initAlloc(aa, prepared.sim_data.coords.mat.rows_num);
    @memcpy(front_coords.mem, prepared.sim_data.coords.mem);
    for (0..front_coords.mat.rows_num) |nn| {
        for (0..3) |axis| {
            const toward_camera =
                cam_in.pos_world.get(axis) - cam_in.roi_cent_world.get(axis);
            const offset = toward_camera * 0.01;
            const cur_val = front_coords.mat.get(nn, axis);
            front_coords.mat.set(nn, axis, cur_val + offset);
        }
    }
    const front_rgb_pipe = [_]shaderops.ShaderPipeInput{mixed_pipes[0]};
    var front_rgb_mesh = mixed_mesh;
    front_rgb_mesh.coords = front_coords;
    front_rgb_mesh.shaders = .{ .rgb = .{ .pipe = front_rgb_pipe[0] } };
    var rear_mono_mesh = mesh;
    rear_mono_mesh.disp = null;
    const mixed_scene = [_]meshpipe.MeshInput{ front_rgb_mesh, rear_mono_mesh };
    const mixed_scene_result = try riley.raster(
        aa,
        io,
        &.{ cam_in, rgb_cam },
        &mixed_scene,
        memory_config,
        null,
    );
    const mixed_scene_image = mixed_scene_result orelse return error.NoResult;
    defer aa.free(mixed_scene_image.slice);
    const mono_only_result = try riley.raster(
        aa,
        io,
        &.{cam_in},
        &.{rear_mono_mesh},
        memory_config,
        null,
    );
    const mono_only = mono_only_result orelse return error.NoResult;
    defer aa.free(mono_only.slice);
    const rgb_only_result = try riley.raster(
        aa,
        io,
        &.{rgb_cam},
        &.{front_rgb_mesh},
        memory_config,
        null,
    );
    const rgb_only = rgb_only_result orelse return error.NoResult;
    defer aa.free(rgb_only.slice);
    for (0..mixed_scene_image.dims[3]) |yy| {
        for (0..mixed_scene_image.dims[4]) |xx| {
            try std.testing.expectEqual(
                mono_only.get(&.{ 0, 0, 0, yy, xx }),
                mixed_scene_image.get(&.{ 0, 0, 0, yy, xx }),
            );
            for (0..3) |cc| {
                try std.testing.expectEqual(
                    rgb_only.get(&.{ 0, 0, cc, yy, xx }),
                    mixed_scene_image.get(&.{ 1, 0, cc, yy, xx }),
                );
            }
        }
    }

    // A selected mesh at scene index 1 must retain its own global nodal
    // scaling after the incompatible mesh at index 0 is filtered out.
    var scaled_direct_mesh = direct_mesh;
    scaled_direct_mesh.shaders = .{ .mono = .{ .direct = .{ .nodal = .{
        .field = timed_field,

        .scaling = .{ .fixed = .{ 0, 0.8 } },
    } } } };
    const scaled_only_result = try riley.raster(
        aa,
        io,
        &.{direct_cam},
        &.{scaled_direct_mesh},
        memory_config,
        null,
    );
    const scaled_only = scaled_only_result orelse return error.NoResult;
    defer aa.free(scaled_only.slice);

    const selected_scene = [_]meshpipe.MeshInput{ front_rgb_mesh, scaled_direct_mesh };
    for ([_]riley.RenderMode{ .offline, .in_order }) |mode| {
        var selected_config = memory_config;
        selected_config.render_mode = mode;
        const selected_result = try riley.raster(
            aa,
            io,
            &.{ rgb_cam, direct_cam, direct_cam },
            &selected_scene,
            selected_config,
            null,
        );
        const selected_image = selected_result orelse return error.NoResult;
        defer aa.free(selected_image.slice);
        try std.testing.expectEqual(@as(usize, 4), selected_image.dims[1]);
        for (0..2) |camera_offset| {
            for (0..4) |frame_idx| {
                for (0..selected_image.dims[3]) |yy| {
                    for (0..selected_image.dims[4]) |xx| {
                        try std.testing.expectEqual(
                            scaled_only.get(&.{ 0, frame_idx, 0, yy, xx }),
                            selected_image.get(&.{ camera_offset + 1, frame_idx, 0, yy, xx }),
                        );
                    }
                }
            }
        }
    }
}

fn runSharedWorldGeometryCase(
    allocator: std.mem.Allocator,
    io: std.Io,
    mesh: meshpipe.MeshInput,
    camera_mono: camera.CameraInput,
    config: riley.RasterConfig,
    tolerance: F,
) !void {
    const ref_shader: shaderops.ShaderDirectInput = .{ .func = .{
        .coord_mode = .world_reference,
        .builtin = .linear,
        .params = .{ .settings = .{ .linear = .{ .coeffs = .{ 0.5, 20, -10 } } } },

        .scaling = .none,
    } };
    const def_shader: shaderops.ShaderDirectInput = .{ .func = .{
        .coord_mode = .world_deformed,
        .builtin = .linear,
        .params = .{ .settings = .{ .linear = .{ .coeffs = .{ 0.25, -10, 20 } } } },

        .scaling = .none,
    } };
    var direct_camera = camera_mono;
    direct_camera.render_format = .mono;
    var direct_mesh = mesh;
    direct_mesh.shaders = .{ .mono = .{ .direct = ref_shader } };
    const ref_result = try riley.raster(
        allocator,
        io,
        &.{direct_camera},
        &.{direct_mesh},
        config,
        null,
    );
    const ref_image = ref_result orelse return error.NoResult;
    defer allocator.free(ref_image.slice);
    direct_mesh.shaders = .{ .mono = .{ .direct = def_shader } };
    const def_result = try riley.raster(
        allocator,
        io,
        &.{direct_camera},
        &.{direct_mesh},
        config,
        null,
    );
    const def_image = def_result orelse return error.NoResult;
    defer allocator.free(def_image.slice);

    const stages = [_]shaderops.ShaderPipeStageInput{
        .{ .source = .{ .shader = ref_shader, .destination = .{ .kind = .channel, .index = 0 } } },
        .{ .source = .{ .shader = ref_shader, .destination = .{ .kind = .channel, .index = 1 } } },
        .{ .source = .{ .shader = def_shader, .destination = .{ .kind = .channel, .index = 2 } } },
    };
    const slots = [_]shaderpipe.Slot{
        .{ .kind = .channel, .index = 0 },
        .{ .kind = .channel, .index = 1 },
        .{ .kind = .channel, .index = 2 },
    };
    var pipe_mesh = mesh;
    pipe_mesh.shaders = .{ .mono = .{ .pipe = .{
        .stages = &stages,
        .resolver = .{ .sum = &slots },
    } } };
    const pipe_result = try riley.raster(
        allocator,
        io,
        &.{camera_mono},
        &.{pipe_mesh},
        config,
        null,
    );
    const pipe_image = pipe_result orelse return error.NoResult;
    defer allocator.free(pipe_image.slice);
    var varied_pixels: usize = 0;
    for (ref_image.slice, def_image.slice, pipe_image.slice) |ref, def, actual| {
        try std.testing.expectApproxEqAbs(2 * ref + def, actual, tolerance);
        if (@abs(ref - def) > 0.01) varied_pixels += 1;
    }
    try std.testing.expect(varied_pixels > 0);
}
