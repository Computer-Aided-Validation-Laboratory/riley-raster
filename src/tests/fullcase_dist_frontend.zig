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
const gk = @import("../riley/zig/geometrykernels.zig");
const meshio = @import("../riley/zig/meshio.zig");
const mo = @import("../riley/zig/meshpipeline.zig");
const orch = @import("../dev_support/orchestration.zig");
const shaderops = @import("../riley/zig/shaderops_common.zig");

const F = buildconfig.F;
const CameraInput = camera.CameraInput;
const MeshInput = mo.MeshInput;

pub const pixel_num_dist_frontend = [_]u32{ 128, 128 };
pub const sub_sample_dist_frontend: u32 = 2;
pub const fov_scale_dist_frontend: F = 1.0;
pub const default_bg_value: F = 127.5;

pub const DistModelCase = struct {
    tag: []const u8,
    distort: camera.DistortParams,
};

pub fn buildRadialPoly7Coeffs(k1: F, k2: F, k3: F) [72]F {
    var coeffs = [_]F{0} ** 72;
    // Degree 3 terms (total = 3):
    // (3,0) term 6, (1,2) term 8 -> u; (2,1) term 7, (0,3) term 9 -> v
    coeffs[2 * 6] = k1;
    coeffs[2 * 8] = k1;
    coeffs[2 * 7 + 1] = k1;
    coeffs[2 * 9 + 1] = k1;

    // Degree 5 terms (total = 5):
    // (5,0) 15, (3,2) 17, (1,4) 19 -> u; (4,1) 16, (2,3) 18, (0,5) 20 -> v
    coeffs[2 * 15] = k2;
    coeffs[2 * 17] = 2.0 * k2;
    coeffs[2 * 19] = k2;
    coeffs[2 * 16 + 1] = k2;
    coeffs[2 * 18 + 1] = 2.0 * k2;
    coeffs[2 * 20 + 1] = k2;

    // Degree 7 terms (total = 7):
    // (7,0) 28, (5,2) 30, (3,4) 32, (1,6) 34 -> u; (6,1) 29, (4,3) 31, (2,5) 33, (0,7) 35 -> v
    coeffs[2 * 28] = k3;
    coeffs[2 * 30] = 3.0 * k3;
    coeffs[2 * 32] = 3.0 * k3;
    coeffs[2 * 34] = k3;
    coeffs[2 * 29 + 1] = k3;
    coeffs[2 * 31 + 1] = 3.0 * k3;
    coeffs[2 * 33 + 1] = 3.0 * k3;
    coeffs[2 * 35 + 1] = k3;

    return coeffs;
}

pub const poly7_barrel_coeffs = buildRadialPoly7Coeffs(-5000.0, 2.0e7, 0.0);
pub const poly7_pincushion_coeffs = buildRadialPoly7Coeffs(
    4500.0,
    2.0e7,
    5.0e10,
);
pub const poly7_combo_barrel_coeffs = buildRadialPoly7Coeffs(
    -2500.0,
    1.0e7,
    0.0,
);
pub const poly7_combo_pincushion_coeffs = buildRadialPoly7Coeffs(
    2200.0,
    1.0e7,
    3.0e10,
);

pub const dist_model_cases = [_]DistModelCase{
    .{
        .tag = "bc_barrel",
        .distort = .{
            .brown_con = .{
                .k1 = -5000.0,
                .k2 = 2.0e7,
            },
        },
    },
    .{
        .tag = "bc_pincushion",
        .distort = .{
            .brown_con = .{
                .k1 = 4500.0,
                .k2 = 2.0e7,
            },
        },
    },
    .{
        .tag = "bcext_barrel",
        .distort = .{
            .brown_con_ext = .{
                .k1 = -5000.0,
                .k2 = 2.0e7,
                .k4 = 500.0,
            },
        },
    },
    .{
        .tag = "bcext_pincushion",
        .distort = .{
            .brown_con_ext = .{
                .k1 = 4500.0,
                .k2 = 2.0e7,
                .k4 = 500.0,
            },
        },
    },
    .{
        .tag = "poly7_barrel",
        .distort = .{
            .poly = .{
                .degree = 7,
                .mode = .displacement,
                .coeffs = &poly7_barrel_coeffs,
            },
        },
    },
    .{
        .tag = "poly7_pincushion",
        .distort = .{
            .poly = .{
                .degree = 7,
                .mode = .displacement,
                .coeffs = &poly7_pincushion_coeffs,
            },
        },
    },
    .{
        .tag = "bc_poly7_barrel",
        .distort = .{
            .brown_con_poly = .{
                .brown_con = .{ .k1 = -2500.0, .k2 = 1.0e7 },
                .poly = .{
                    .degree = 7,
                    .mode = .displacement,
                    .coeffs = &poly7_combo_barrel_coeffs,
                },
            },
        },
    },
    .{
        .tag = "bc_poly7_pincushion",
        .distort = .{
            .brown_con_poly = .{
                .brown_con = .{ .k1 = 2200.0, .k2 = 1.0e7 },
                .poly = .{
                    .degree = 7,
                    .mode = .displacement,
                    .coeffs = &poly7_combo_pincushion_coeffs,
                },
            },
        },
    },
};

pub const onto_screen_dist_cases = [_]DistModelCase{
    .{ .tag = "dist_none", .distort = .none },
    dist_model_cases[0], // bc_barrel
    dist_model_cases[2], // bcext_barrel
    dist_model_cases[4], // poly7_barrel
    dist_model_cases[6], // bc_poly7_barrel
};

pub const all_mesh_types = [_]gk.MeshType{
    .tri3,
    .tri6,
    .quad4,
    .quad8,
    .quad9,
};

pub const edge_mesh_types = [_]gk.MeshType{
    .tri3,
    .tri6,
};

pub const test_motions = [_][]const u8{
    "distort_rot",
    "distort_shear",
};

pub fn formatCaseName(
    allocator: std.mem.Allocator,
    motion: []const u8,
    mesh_type: gk.MeshType,
    dist_tag: []const u8,
) ![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        "dist_frontend_{s}_{s}_{s}",
        .{ motion, @tagName(mesh_type), dist_tag },
    );
}

pub fn formatHalfOffCaseName(
    allocator: std.mem.Allocator,
    mesh_type: gk.MeshType,
    dist_tag: []const u8,
) ![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        "dist_frontend_halfoff_{s}_{s}",
        .{ @tagName(mesh_type), dist_tag },
    );
}

pub fn formatOntoScreenCaseName(
    allocator: std.mem.Allocator,
    mesh_type: gk.MeshType,
    dist_tag: []const u8,
) ![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        "dist_frontend_ontoscreen_{s}_{s}",
        .{ @tagName(mesh_type), dist_tag },
    );
}

pub fn buildCheckerMeshInput(
    prepared: *const orch.SingleMeshPrepared,
    mesh_type: gk.MeshType,
) MeshInput {
    const shader_params = shaderops.FuncShaderParams{
        .coord_scale = .{ 4.0, 4.0 },
        .settings = .{ .checker = .{} },
    };
    return MeshInput{
        .mesh_type = mesh_type,
        .coords = prepared.sim_data.coords,
        .connect = prepared.sim_data.connect,
        .disp = prepared.sim_data.field,
        .shader = .{
            .func = .{
                .uvs = null,
                .coord_mode = .para,
                .builtin = .checker,
                .params = shader_params,
                .bits = 8,
                .scaling = .auto,
                .normal_type = .none,
            },
        },
    };
}

pub fn buildCameraInput(
    prepared: *const orch.SingleMeshPrepared,
    distort: camera.DistortParams,
) CameraInput {
    return CameraInput{
        .pixels_num = prepared.camera.pixels_num,
        .pixels_size = prepared.camera.pixels_size,
        .pos_world = prepared.camera.pos_world,
        .rot_world = prepared.camera.rot_world,
        .roi_cent_world = prepared.camera.roi_cent_world,
        .focal_length = prepared.camera.focal_length,
        .sub_sample = sub_sample_dist_frontend,
        .distort = distort,
    };
}

pub fn calcCoordsBounds(coords: *const meshio.Coords) struct {
    min_x: F,
    max_x: F,
    min_y: F,
    max_y: F,
} {
    var min_x: F = coords.x(0);
    var max_x: F = coords.x(0);
    var min_y: F = coords.y(0);
    var max_y: F = coords.y(0);
    for (1..coords.mat.rows_num) |nn| {
        const px = coords.x(nn);
        const py = coords.y(nn);
        if (px < min_x) min_x = px;
        if (px > max_x) max_x = px;
        if (py < min_y) min_y = py;
        if (py > max_y) max_y = py;
    }
    return .{
        .min_x = min_x,
        .max_x = max_x,
        .min_y = min_y,
        .max_y = max_y,
    };
}
