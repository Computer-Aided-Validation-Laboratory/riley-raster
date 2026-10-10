// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("../riley/zig/buildconfig.zig");
const camera = @import("../riley/zig/camera.zig");
const common = @import("../dev_support/tests.zig");
const fullcase_dist_frontend = @import("fullcase_dist_frontend.zig");
const gk = @import("../riley/zig/geometrykernels.zig");
const mo = @import("../riley/zig/meshpipeline.zig");
const orch = @import("../dev_support/orchestration.zig");
const policy = @import("../dev_support/testpolicy.zig");
const rastcfg = @import("../riley/zig/rasterconfig.zig");
const riley = @import("../riley/zig/riley.zig");
const tcfg = @import("../dev_support/testconfig.zig");

const F = buildconfig.F;
const CameraInput = camera.CameraInput;
const MeshInput = mo.MeshInput;
const Timestamp = std.Io.Clock.Timestamp;

pub fn runFullDistFrontendCaseTest(
    allocator: std.mem.Allocator,
    io: std.Io,
    prepared: *const orch.SingleMeshPrepared,
    mesh_type: gk.MeshType,
    dist_case: fullcase_dist_frontend.DistModelCase,
    case_name: []const u8,
    camera_shift_x: F,
    disp_active: bool,
    gold_dir_root: []const u8,
    config: rastcfg.RasterConfig,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const gold_dir = try std.fmt.allocPrint(
        aa,
        "{s}/{s}",
        .{ gold_dir_root, case_name },
    );

    var mesh = fullcase_dist_frontend.buildCheckerMeshInput(prepared, mesh_type);
    if (!disp_active) {
        mesh.disp = null;
    }
    const meshes = [_]MeshInput{mesh};

    var camera_input = fullcase_dist_frontend.buildCameraInput(
        prepared,
        dist_case.distort,
    );
    if (camera_shift_x != 0.0) {
        camera_input.pos_world.set(
            0,
            camera_input.pos_world.get(0) + camera_shift_x,
        );
    }

    var run_config = config;
    run_config.save_strategy = .memory;
    run_config.background_value = fullcase_dist_frontend.default_bg_value;

    const start_time = Timestamp.now(io, .awake);
    const result = try riley.raster(
        aa,
        io,
        &[_]CameraInput{camera_input},
        &meshes,
        run_config,
        null,
    );

    const render_result = result orelse return error.NoResult;
    defer aa.free(render_result.slice);

    const end_time = Timestamp.now(io, .awake);
    const duration_ms = @as(
        F,
        @floatFromInt(start_time.durationTo(end_time).raw.nanoseconds),
    ) / 1.0e6;

    const frames_num = if (render_result.dims.len == 5)
        render_result.dims[1]
    else
        render_result.dims[0];

    for (0..frames_num) |ff| {
        const gold_path = try common.findGoldPath(
            aa,
            io,
            gold_dir,
            0,
            ff,
            0,
            false,
        );

        common.compareNDArrayToGold(
            aa,
            io,
            &render_result,
            0,
            ff,
            0,
            1,
            gold_path,
            tcfg.FULL_GOLD_REL_TOL,
            tcfg.FULL_GOLD_ABS_TOL,
        ) catch |err| {
            const fail_dir = try std.fmt.allocPrint(
                aa,
                "full_dist_frontend/{s}",
                .{case_name},
            );
            try common.saveComparisonArtifactsFromResult(
                aa,
                io,
                common.default_fails_root,
                fail_dir,
                &render_result,
                0,
                ff,
                0,
                gold_path,
                1,
            );
            if (tcfg.TEST_CASE_VERBOSE) {
                std.debug.print(
                    "FAIL {s} frame {d} ({d:.2} ms)\n",
                    .{ case_name, ff, duration_ms },
                );
            }
            try common.recordGoldFailure(err);
        };
    }

    if (tcfg.TEST_CASE_VERBOSE) {
        std.debug.print(
            "PASS {s} ({d:.2} ms, {d} frames)\n",
            .{ case_name, duration_ms, frames_num },
        );
    }
}

pub fn testOffscreenDistortedOn(
    allocator: std.mem.Allocator,
    io: std.Io,
    mesh_type: gk.MeshType,
    dist_case: fullcase_dist_frontend.DistModelCase,
    gold_dir_root: []const u8,
    config: rastcfg.RasterConfig,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const data_dir_root = "data/edge";
    const prepared = try orch.prepareSingleMeshCase(
        aa,
        io,
        "distort_rot",
        mesh_type,
        fullcase_dist_frontend.pixel_num_dist_frontend,
        fullcase_dist_frontend.fov_scale_dist_frontend,
        data_dir_root,
    );

    const roi_dist = prepared.camera.pos_world.get(2) -
        prepared.camera.roi_cent_world.get(2);
    const pixel_size = prepared.camera.pixels_size[0];
    const focal_len = prepared.camera.focal_length;
    const bounds = fullcase_dist_frontend.calcCoordsBounds(
        &prepared.sim_data.coords,
    );

    // Place mesh min_x at 128.5 px in pinhole space (strictly off screen)
    const target_cam_x = bounds.min_x - (64.5 * pixel_size * roi_dist / focal_len);
    const shift_x = target_cam_x - prepared.camera.pos_world.get(0);

    var mesh_input = fullcase_dist_frontend.buildCheckerMeshInput(&prepared, mesh_type);
    mesh_input.disp = null;

    var run_config = config;
    run_config.save_strategy = .memory;
    run_config.background_value = fullcase_dist_frontend.default_bg_value;

    const case_name = try fullcase_dist_frontend.formatOntoScreenCaseName(
        aa,
        mesh_type,
        dist_case.tag,
    );

    // 1. Compare rendered output against gold
    try runFullDistFrontendCaseTest(
        allocator,
        io,
        &prepared,
        mesh_type,
        dist_case,
        case_name,
        shift_x,
        false,
        gold_dir_root,
        config,
    );

    // 2. Direct assertions on output image
    var camera_input = fullcase_dist_frontend.buildCameraInput(
        &prepared,
        dist_case.distort,
    );
    camera_input.pos_world.set(0, target_cam_x);

    const result = try riley.raster(
        aa,
        io,
        &[_]CameraInput{camera_input},
        &[_]MeshInput{mesh_input},
        run_config,
        null,
    );
    const image = result orelse return error.NoResult;
    defer aa.free(image.slice);

    if (dist_case.distort == .none) {
        var all_bg = true;
        for (image.slice) |val| {
            if (@abs(val - fullcase_dist_frontend.default_bg_value) > 1e-4) {
                all_bg = false;
                break;
            }
        }
        try std.testing.expect(all_bg);
    } else {
        var has_non_bg = false;
        for (image.slice) |val| {
            if (@abs(val - fullcase_dist_frontend.default_bg_value) > 1e-4) {
                has_non_bg = true;
                break;
            }
        }
        try std.testing.expect(has_non_bg);
    }
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const config = tcfg.getRasterConfig(.testing);
    const gold_dir_root = policy.goldRoot(.full_dist_frontend);
    const data_dir_root = "data/edge";

    // Standard cases
    for (fullcase_dist_frontend.test_motions) |motion| {
        for (fullcase_dist_frontend.all_mesh_types) |mesh_type| {
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            const aa = arena.allocator();

            const prepared = try orch.prepareSingleMeshCase(
                aa,
                io,
                motion,
                mesh_type,
                fullcase_dist_frontend.pixel_num_dist_frontend,
                fullcase_dist_frontend.fov_scale_dist_frontend,
                data_dir_root,
            );

            for (fullcase_dist_frontend.dist_model_cases) |dist_case| {
                const case_name = try fullcase_dist_frontend.formatCaseName(
                    aa,
                    motion,
                    mesh_type,
                    dist_case.tag,
                );
                try runFullDistFrontendCaseTest(
                    allocator,
                    io,
                    &prepared,
                    mesh_type,
                    dist_case,
                    case_name,
                    0.0,
                    true,
                    gold_dir_root,
                    config,
                );
            }
        }
    }

    // Half off-screen cases (50% split)
    for (fullcase_dist_frontend.edge_mesh_types) |mesh_type| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const aa = arena.allocator();

        const prepared = try orch.prepareSingleMeshCase(
            aa,
            io,
            "distort_rot",
            mesh_type,
            fullcase_dist_frontend.pixel_num_dist_frontend,
            fullcase_dist_frontend.fov_scale_dist_frontend,
            data_dir_root,
        );

        const roi_dist = prepared.camera.pos_world.get(2) -
            prepared.camera.roi_cent_world.get(2);
        const pixel_size = prepared.camera.pixels_size[0];
        const focal_len = prepared.camera.focal_length;
        const half_sensor_px = @as(
            F,
            @floatFromInt(fullcase_dist_frontend.pixel_num_dist_frontend[0] / 2),
        );
        const half_sensor_world = half_sensor_px * pixel_size * roi_dist / focal_len;
        const shift_x = -half_sensor_world;

        for (fullcase_dist_frontend.dist_model_cases) |dist_case| {
            const case_name = try fullcase_dist_frontend.formatHalfOffCaseName(
                aa,
                mesh_type,
                dist_case.tag,
            );
            try runFullDistFrontendCaseTest(
                allocator,
                io,
                &prepared,
                mesh_type,
                dist_case,
                case_name,
                shift_x,
                true,
                gold_dir_root,
                config,
            );
        }
    }

    // Onto-screen cases (gold compare and assertion)
    for (fullcase_dist_frontend.edge_mesh_types) |mesh_type| {
        for (fullcase_dist_frontend.onto_screen_dist_cases) |dist_case| {
            try testOffscreenDistortedOn(
                allocator,
                io,
                mesh_type,
                dist_case,
                gold_dir_root,
                config,
            );
        }
    }
}
