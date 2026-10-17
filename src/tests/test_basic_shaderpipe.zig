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
            const path = try std.fmt.bufPrint(&path_buf, "{s}/{s}/cam0_frame{d}_field0.fimg", .{ policy.goldRoot(.basic), case_name, frame });
            try std.Io.Dir.cwd().deleteFile(io, path);
        }
    }
}

fn runCase(allocator: std.mem.Allocator, io: std.Io, generate_gold: bool) !void {
    const sample_tol: F = if (F == f32) 1e-5 else 1e-9;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();
    const prepared = try orch.prepareSingleMeshCase(aa, io, "distort_rot", .quad4, .{ 48, 48 }, 1.15, "data/edge");

    const stages = [_]shaderops.PipeStageInput{
        .{ .source = .{ .shader = .{ .func = .{
            .builtin = .checker,
            .params = .{ .coord_scale = .{ 4, 4 }, .settings = .{ .checker = .{} } },
            .bits = null,
            .scaling = .none,
        } }, .destination = .{ .kind = .channel, .index = 0 } } },
        .{ .source = .{ .shader = .{ .func = .{
            .builtin = .constant,
            .params = .{ .settings = .{ .constant = .{ .value = 0.25 } } },
            .bits = null,
            .scaling = .none,
        } }, .destination = .{ .kind = .channel, .index = 1 } } },
    };
    const sum_slots = [_]shaderpipe.Slot{
        .{ .kind = .channel, .index = 0 },
        .{ .kind = .channel, .index = 1 },
    };
    const pipes = [_]shaderops.PipeInput{.{
        .family = .mono,
        .stages = &stages,
        .resolver = .{ .sum = &sum_slots },
    }};
    const mesh = meshpipe.MeshInput{
        .mesh_type = .quad4,
        .coords = prepared.sim_data.coords,
        .connect = prepared.sim_data.connect,
        .disp = prepared.sim_data.field,
        .shader = .{ .pipes = &pipes },
    };
    const cam_in = camera.CameraInput{
        .pixels_num = prepared.camera.pixels_num,
        .pixels_size = prepared.camera.pixels_size,
        .pos_world = prepared.camera.pos_world,
        .rot_world = prepared.camera.rot_world,
        .roi_cent_world = prepared.camera.roi_cent_world,
        .focal_length = prepared.camera.focal_length,
        .sub_sample = 1,
        .pipe_request = .mono,
    };
    var config = tcfg.getRasterConfig(.testing);
    config.save_strategy = if (generate_gold) .both else .memory;
    config.background_value = 0;
    if (generate_gold) config.output.image_save_opts = &.{
        imageio.ImageSaveOpts{ .format = .fimg, .bits = null, .scaling = .none },
        imageio.ImageSaveOpts{ .format = .bmp, .bits = 8, .scaling = .auto },
    };
    const sum_gold_dir = try std.fmt.allocPrint(aa, "{s}/shaderpipe_sum_quad4", .{policy.goldRoot(.basic)});
    const ir_gold_dir = try std.fmt.allocPrint(aa, "{s}/shaderpipe_ir_quad4", .{policy.goldRoot(.basic)});
    const result = try riley.raster(aa, io, &.{cam_in}, &.{mesh}, config, if (generate_gold) sum_gold_dir else null);
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
        for ([_]usize{ 0, image.dims[1] - 1 }) |frame| {
            const gold = try common.findGoldPath(aa, io, sum_gold_dir, 0, frame, 0, false);
            try common.compareNDArrayToGold(aa, io, &image, 0, frame, 0, 1, gold, tcfg.REL_TOL, tcfg.ABS_TOL);
        }
    }

    // A temperature field and an independent emissivity producer feed the IR
    // resolver. Distinct nodal values make the physically resolved image vary.
    var temperature = try meshio.Field.initAlloc(aa, 1, prepared.sim_data.coords.mat.rows_num, 1);
    for (0..prepared.sim_data.coords.mat.rows_num) |node| {
        temperature.array.set(&.{ 0, node, 0 }, 290 + @as(F, @floatFromInt(node)) * 5);
    }
    const response: shaderpipe.BandResponse = .{
        .wavelengths_m = &.{ 8e-6, 9e-6, 10e-6, 11e-6, 12e-6 },
        .response = &.{ 0, 1, 1, 1, 0 },
    };
    const radiance = try response.prepareRadianceLookup(aa, 280, 340, 0.25);
    const speckle = try imageio.loadImage(u8, 1, aa, io, "texture/speck128_mono_u8.bmp", .bmp);
    const ir_stages = [_]shaderops.PipeStageInput{
        .{ .source = .{ .shader = .{ .nodal = .{
            .field = temperature,
            .bits = null,
            .scaling = .none,
        } }, .destination = .{ .kind = .field, .index = 0 } } },
        .{ .source = .{ .shader = .{ .tex_u8 = .{
            .uvs = prepared.uvs.array,
            .tex = speckle,
            .samp_cfg = .{ .sample = .linear, .mode = .direct },
            .bits = null,
            .scaling = .{ .fixed = .{ 0, 255 } },
        } }, .destination = .{ .kind = .channel, .index = 0 } } },
        .{ .grey_to_emissivity = .{
            .source = .{ .kind = .channel, .index = 0 },
            .destination = .{ .kind = .parameter, .index = 0 },
            .black = 0.95,
            .white = 0.55,
        } },
    };
    const ir_pipe = [_]shaderops.PipeInput{.{
        .family = .ir,
        .stages = &ir_stages,
        .resolver = .{ .greybody_band = .{
            .temperature = .{ .kind = .field, .index = 0 },
            .emissivity = .{ .kind = .parameter, .index = 0 },
            .radiance = radiance,
        } },
    }};
    var ir_mesh = mesh;
    ir_mesh.shader = .{ .pipes = &ir_pipe };
    var ir_cam = cam_in;
    ir_cam.pipe_request = .ir;
    const ir_result = try riley.raster(aa, io, &.{ir_cam}, &.{ir_mesh}, config, if (generate_gold) ir_gold_dir else null);
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
        for ([_]usize{ 0, ir_image.dims[1] - 1 }) |frame| {
            const gold = try common.findGoldPath(aa, io, ir_gold_dir, 0, frame, 0, false);
            try common.compareNDArrayToGold(aa, io, &ir_image, 0, frame, 0, 1, gold, tcfg.REL_TOL, tcfg.ABS_TOL);
        }
    }

    var invalid_camera = cam_in;
    invalid_camera.pipe_request = .rgb;
    var memory_config = config;
    memory_config.save_strategy = .memory;
    try std.testing.expectError(error.NoCompatibleShaderPipe, riley.raster(aa, io, &.{invalid_camera}, &.{mesh}, memory_config, null));
    const missing_slots = [_]shaderpipe.Slot{.{ .kind = .channel, .index = 4 }};
    const invalid_pipe = [_]shaderops.PipeInput{.{
        .family = .mono,
        .stages = &stages,
        .resolver = .{ .identity = &missing_slots },
    }};
    var invalid_mesh = mesh;
    invalid_mesh.shader = .{ .pipes = &invalid_pipe };
    try std.testing.expectError(error.InvalidShaderPipe, riley.raster(aa, io, &.{cam_in}, &.{invalid_mesh}, memory_config, null));

    // A mixed camera batch selects the matching pipe and pads unused channels.
    var channels = try meshio.Field.initAlloc(aa, 1, prepared.sim_data.coords.mat.rows_num, 4);
    for (0..prepared.sim_data.coords.mat.rows_num) |node| {
        for (0..4) |ch| channels.array.set(&.{ 0, node, ch }, @as(F, @floatFromInt(ch + 1)) * 0.1);
    }
    const rgb_stages = [_]shaderops.PipeStageInput{.{ .source = .{
        .shader = .{ .func_rgb = .{
            .builtin = .constant,
            .params = .{ .settings = .{ .constant = .{ .value_rgb = .{ 0.2, 0.5, 0.8 } } } },
            .bits = null,
            .scaling = .none,
        } },
        .destination = .{ .kind = .channel, .index = 0 },
    } }};
    const multi_stages = [_]shaderops.PipeStageInput{.{ .source = .{
        .shader = .{ .nodal = .{ .field = channels, .bits = null, .scaling = .none } },
        .destination = .{ .kind = .channel, .index = 0 },
    } }};
    const rgb_slots = [_]shaderpipe.Slot{
        .{ .kind = .channel, .index = 0 }, .{ .kind = .channel, .index = 1 },
        .{ .kind = .channel, .index = 2 },
    };
    const multi_slots = [_]shaderpipe.Slot{
        .{ .kind = .channel, .index = 0 }, .{ .kind = .channel, .index = 1 },
        .{ .kind = .channel, .index = 2 }, .{ .kind = .channel, .index = 3 },
    };
    const mixed_pipes = [_]shaderops.PipeInput{
        .{ .family = .rgb, .stages = &rgb_stages, .resolver = .{ .identity = &rgb_slots } },
        .{ .family = .{ .multichannel = 4 }, .stages = &multi_stages, .resolver = .{ .identity = &multi_slots } },
    };
    var mixed_mesh = mesh;
    mixed_mesh.disp = null;
    mixed_mesh.shader = .{ .pipes = &mixed_pipes };
    var rgb_cam = cam_in;
    rgb_cam.pipe_request = .rgb;
    var multi_cam = cam_in;
    multi_cam.pipe_request = .{ .multichannel = 4 };
    const mixed_result = try riley.raster(aa, io, &.{ rgb_cam, multi_cam }, &.{mixed_mesh}, memory_config, null);
    const mixed_image = mixed_result orelse return error.NoResult;
    defer aa.free(mixed_image.slice);
    try std.testing.expectEqual(@as(usize, 4), mixed_image.dims[2]);
    var found = false;
    for (0..mixed_image.dims[3]) |y| {
        for (0..mixed_image.dims[4]) |x| {
            if (mixed_image.get(&.{ 1, 0, 0, y, x }) < 0.099) continue;
            try std.testing.expectApproxEqAbs(@as(F, 0.2), mixed_image.get(&.{ 0, 0, 0, y, x }), sample_tol);
            try std.testing.expectApproxEqAbs(@as(F, 0.5), mixed_image.get(&.{ 0, 0, 1, y, x }), sample_tol);
            try std.testing.expectApproxEqAbs(@as(F, 0.8), mixed_image.get(&.{ 0, 0, 2, y, x }), sample_tol);
            try std.testing.expectEqual(@as(F, 0), mixed_image.get(&.{ 0, 0, 3, y, x }));
            try std.testing.expectApproxEqAbs(@as(F, 0.4), mixed_image.get(&.{ 1, 0, 3, y, x }), sample_tol);
            found = true;
            break;
        }
        if (found) break;
    }
    try std.testing.expect(found);

    const expr_stages = [_]shaderops.PipeStageInput{
        rgb_stages[0],
        .{ .source = .{
            .shader = .{ .func_rgb = .{
                .builtin = .constant,
                .params = .{ .settings = .{ .constant = .{ .value_rgb = .{ 0.1, 0.2, 0.3 } } } },
                .bits = null,
                .scaling = .none,
            } },
            .destination = .{ .kind = .parameter, .index = 0 },
        } },
        .{ .source = .{
            .shader = .{ .func = .{
                .builtin = .constant,
                .params = .{ .settings = .{ .constant = .{ .value = 2 } } },
                .bits = null,
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
    const expression_pipe = [_]shaderops.PipeInput{.{
        .family = .mono,
        .stages = &expr_stages,
        .resolver = .{ .expression = .{ .operations = &expression, .constants = &.{0.5} } },
    }};
    var expr_mesh = mixed_mesh;
    expr_mesh.shader = .{ .pipes = &expression_pipe };
    const expr_result = try riley.raster(aa, io, &.{cam_in}, &.{expr_mesh}, memory_config, null);
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
    for (0..front_coords.mat.rows_num) |node| {
        for (0..3) |axis| {
            const toward_camera = cam_in.pos_world.get(axis) - cam_in.roi_cent_world.get(axis);
            front_coords.mat.set(node, axis, front_coords.mat.get(node, axis) + toward_camera * 0.01);
        }
    }
    const front_rgb_pipe = [_]shaderops.PipeInput{mixed_pipes[0]};
    var front_rgb_mesh = mixed_mesh;
    front_rgb_mesh.coords = front_coords;
    front_rgb_mesh.shader = .{ .pipes = &front_rgb_pipe };
    var rear_mono_mesh = mesh;
    rear_mono_mesh.disp = null;
    const mixed_scene = [_]meshpipe.MeshInput{ front_rgb_mesh, rear_mono_mesh };
    const mixed_scene_result = try riley.raster(aa, io, &.{ cam_in, rgb_cam }, &mixed_scene, memory_config, null);
    const mixed_scene_image = mixed_scene_result orelse return error.NoResult;
    defer aa.free(mixed_scene_image.slice);
    const mono_only_result = try riley.raster(aa, io, &.{cam_in}, &.{rear_mono_mesh}, memory_config, null);
    const mono_only = mono_only_result orelse return error.NoResult;
    defer aa.free(mono_only.slice);
    const rgb_only_result = try riley.raster(aa, io, &.{rgb_cam}, &.{front_rgb_mesh}, memory_config, null);
    const rgb_only = rgb_only_result orelse return error.NoResult;
    defer aa.free(rgb_only.slice);
    for (0..mixed_scene_image.dims[3]) |y| for (0..mixed_scene_image.dims[4]) |x| {
        try std.testing.expectEqual(mono_only.get(&.{ 0, 0, 0, y, x }), mixed_scene_image.get(&.{ 0, 0, 0, y, x }));
        for (0..3) |ch| {
            try std.testing.expectEqual(rgb_only.get(&.{ 0, 0, ch, y, x }), mixed_scene_image.get(&.{ 1, 0, ch, y, x }));
        }
    };
}
