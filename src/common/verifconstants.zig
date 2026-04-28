// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const cam = @import("../zraster/zig/camera.zig");
const gk = @import("../zraster/zig/geometrykernels.zig");
const rotation = @import("../zraster/zig/rotation.zig");
const vecstack = @import("../zraster/zig/vecstack.zig");

pub const output_dir_name = "verif-a-solver";

pub const CameraCase = struct {
    name: []const u8,
    input: cam.CameraInput,
};

pub fn ElementCase(comptime N: usize) type {
    return struct {
        name: []const u8,
        node_x: [N]f64,
        node_y: [N]f64,
        node_z: [N]f64,
    };
}

fn baseCameraInput(distortion: cam.DistortionModel) cam.CameraInput {
    return .{
        .pixels_num = .{ 800, 600 },
        .pixels_size = .{ 1.0, 1.0 },
        .pos_world = .{ .slice = .{ 0.0, 0.0, 0.0 } },
        .rot_world = rotation.Rotation.init(0.0, 0.0, 0.0),
        .roi_cent_world = .{ .slice = .{ 0.0, 0.0, -1000.0 } },
        .focal_length = 1200.0,
        .sub_sample = 1,
        .distortion = distortion,
    };
}

pub const camera_cases = [_]CameraCase{
    .{
        .name = "ideal",
        .input = baseCameraInput(.none),
    },
    .{
        .name = "brown_conrady",
        .input = baseCameraInput(.{
            .brown_conrady = .{
                .k1 = -8.0e-3,
                .k2 = 1.0e-4,
                .k3 = -1.0e-6,
                .p1 = 2.5e-4,
                .p2 = -1.5e-4,
            },
        }),
    },
    .{
        .name = "brown_conrady_ext",
        .input = baseCameraInput(.{
            .brown_conrady_ext = .{
                .k1 = -8.0e-3,
                .k2 = 1.0e-4,
                .k3 = -1.0e-6,
                .k4 = 2.0e-3,
                .k5 = -5.0e-5,
                .k6 = 1.0e-6,
                .p1 = 2.5e-4,
                .p2 = -1.5e-4,
            },
        }),
    },
};

pub const tri3_cases = [_]ElementCase(3){
    .{
        .name = "regular",
        .node_x = .{ -120.0, 120.0, -10.0 },
        .node_y = .{ -90.0, -80.0, 130.0 },
        .node_z = .{ -1000.0, -1000.0, -1000.0 },
    },
    .{
        .name = "skewed",
        .node_x = .{ -150.0, 90.0, 25.0 },
        .node_y = .{ -95.0, -55.0, 120.0 },
        .node_z = .{ -980.0, -1040.0, -960.0 },
    },
    .{
        .name = "near_degenerate",
        .node_x = .{ -120.0, 120.0, -100.0 },
        .node_y = .{ -70.0, -68.0, 14.0 },
        .node_z = .{ -1000.0, -1005.0, -998.0 },
    },
};

pub const tri6_cases = [_]ElementCase(6){
    .{
        .name = "convex_regular",
        .node_x = .{ -120.0, 120.0, -10.0, 0.0, 80.0, -95.0 },
        .node_y = .{ -90.0, -80.0, 130.0, -118.0, 52.0, 42.0 },
        .node_z = .{ -1000.0, -1000.0, -1000.0, -1000.0, -1000.0, -1000.0 },
    },
    .{
        .name = "concave_regular",
        .node_x = .{ -120.0, 120.0, -10.0, 0.0, 28.0, -42.0 },
        .node_y = .{ -90.0, -80.0, 130.0, -38.0, 6.0, 10.0 },
        .node_z = .{ -1000.0, -1000.0, -1000.0, -1000.0, -1000.0, -1000.0 },
    },
    .{
        .name = "convex_distorted",
        .node_x = .{ -155.0, 88.0, 35.0, -18.0, 95.0, -122.0 },
        .node_y = .{ -108.0, -42.0, 118.0, -120.0, 55.0, 26.0 },
        .node_z = .{ -975.0, -1035.0, -940.0, -990.0, -970.0, -955.0 },
    },
    .{
        .name = "concave_distorted",
        .node_x = .{ -155.0, 88.0, 35.0, -8.0, 48.0, -55.0 },
        .node_y = .{ -108.0, -42.0, 118.0, -26.0, -6.0, -4.0 },
        .node_z = .{ -975.0, -1035.0, -940.0, -990.0, -970.0, -955.0 },
    },
    .{
        .name = "near_degenerate_convex",
        .node_x = .{ -110.0, 125.0, -92.0, 10.0, 52.0, -112.0 },
        .node_y = .{ -75.0, -72.0, 22.0, -92.0, 4.0, 28.0 },
        .node_z = .{ -1002.0, -995.0, -988.0, -999.0, -992.0, -990.0 },
    },
};

pub const quad4_cases = [_]ElementCase(4){
    .{
        .name = "regular",
        .node_x = .{ -130.0, 125.0, 120.0, -125.0 },
        .node_y = .{ -95.0, -90.0, 90.0, 95.0 },
        .node_z = .{ -1000.0, -1000.0, -1000.0, -1000.0 },
    },
    .{
        .name = "skewed",
        .node_x = .{ -155.0, 82.0, 148.0, -95.0 },
        .node_y = .{ -108.0, -55.0, 102.0, 126.0 },
        .node_z = .{ -980.0, -1040.0, -955.0, -1015.0 },
    },
    .{
        .name = "near_degenerate",
        .node_x = .{ -145.0, 150.0, 132.0, -130.0 },
        .node_y = .{ -38.0, -35.0, 36.0, 39.0 },
        .node_z = .{ -1000.0, -995.0, -990.0, -998.0 },
    },
};

pub const quad8_cases = [_]ElementCase(8){
    .{
        .name = "convex_regular",
        .node_x = .{ -130.0, 125.0, 120.0, -125.0, 0.0, 155.0, -2.0, -160.0 },
        .node_y = .{ -95.0, -90.0, 90.0, 95.0, -132.0, 0.0, 132.0, 4.0 },
        .node_z = .{ -1000.0, -1000.0, -1000.0, -1000.0, -1000.0, -1000.0, -1000.0, -1000.0 },
    },
    .{
        .name = "concave_regular",
        .node_x = .{ -130.0, 125.0, 120.0, -125.0, 0.0, 118.0, -2.0, -116.0 },
        .node_y = .{ -95.0, -90.0, 90.0, 95.0, -44.0, 0.0, 42.0, 4.0 },
        .node_z = .{ -1000.0, -1000.0, -1000.0, -1000.0, -1000.0, -1000.0, -1000.0, -1000.0 },
    },
    .{
        .name = "convex_distorted",
        .node_x = .{ -160.0, 88.0, 142.0, -92.0, -16.0, 160.0, 6.0, -150.0 },
        .node_y = .{ -110.0, -50.0, 108.0, 128.0, -136.0, 8.0, 145.0, 12.0 },
        .node_z = .{ -972.0, -1042.0, -948.0, -1016.0, -990.0, -970.0, -955.0, -985.0 },
    },
    .{
        .name = "concave_distorted",
        .node_x = .{ -160.0, 88.0, 142.0, -92.0, -12.0, 116.0, 8.0, -112.0 },
        .node_y = .{ -110.0, -50.0, 108.0, 128.0, -32.0, 4.0, 52.0, 8.0 },
        .node_z = .{ -972.0, -1042.0, -948.0, -1016.0, -990.0, -970.0, -955.0, -985.0 },
    },
    .{
        .name = "near_degenerate_convex",
        .node_x = .{ -150.0, 155.0, 132.0, -128.0, 0.0, 154.0, 2.0, -150.0 },
        .node_y = .{ -36.0, -34.0, 41.0, 43.0, -62.0, 5.0, 72.0, 8.0 },
        .node_z = .{ -1002.0, -996.0, -990.0, -998.0, -998.0, -993.0, -991.0, -996.0 },
    },
};

pub const quad9_cases = [_]ElementCase(9){
    .{
        .name = "convex_regular",
        .node_x = .{ -130.0, 125.0, 120.0, -125.0, 0.0, 155.0, -2.0, -160.0, 3.0 },
        .node_y = .{ -95.0, -90.0, 90.0, 95.0, -132.0, 0.0, 132.0, 4.0, 0.0 },
        .node_z = .{ -1000.0, -1000.0, -1000.0, -1000.0, -1000.0, -1000.0, -1000.0, -1000.0, -1000.0 },
    },
    .{
        .name = "concave_regular",
        .node_x = .{ -130.0, 125.0, 120.0, -125.0, 0.0, 118.0, -2.0, -116.0, 3.0 },
        .node_y = .{ -95.0, -90.0, 90.0, 95.0, -44.0, 0.0, 42.0, 4.0, 0.0 },
        .node_z = .{ -1000.0, -1000.0, -1000.0, -1000.0, -1000.0, -1000.0, -1000.0, -1000.0, -1000.0 },
    },
    .{
        .name = "convex_distorted",
        .node_x = .{ -160.0, 88.0, 142.0, -92.0, -16.0, 160.0, 6.0, -150.0, 12.0 },
        .node_y = .{ -110.0, -50.0, 108.0, 128.0, -136.0, 8.0, 145.0, 12.0, 18.0 },
        .node_z = .{ -972.0, -1042.0, -948.0, -1016.0, -990.0, -970.0, -955.0, -985.0, -978.0 },
    },
    .{
        .name = "concave_distorted",
        .node_x = .{ -160.0, 88.0, 142.0, -92.0, -12.0, 116.0, 8.0, -112.0, 10.0 },
        .node_y = .{ -110.0, -50.0, 108.0, 128.0, -32.0, 4.0, 52.0, 8.0, 10.0 },
        .node_z = .{ -972.0, -1042.0, -948.0, -1016.0, -990.0, -970.0, -955.0, -985.0, -978.0 },
    },
    .{
        .name = "near_degenerate_convex",
        .node_x = .{ -150.0, 155.0, 132.0, -128.0, 0.0, 154.0, 2.0, -150.0, 2.0 },
        .node_y = .{ -36.0, -34.0, 41.0, 43.0, -62.0, 5.0, 72.0, 8.0, 6.0 },
        .node_z = .{ -1002.0, -996.0, -990.0, -998.0, -998.0, -993.0, -991.0, -996.0, -994.0 },
    },
};

pub fn getCases(
    comptime mesh_type: gk.MeshType,
) []const ElementCase(mesh_type.getNodesNum()) {
    return switch (mesh_type) {
        .tri3 => tri3_cases[0..],
        .tri6 => tri6_cases[0..],
        .quad4ibi => quad4_cases[0..],
        .quad4newton => quad4_cases[0..],
        .quad8 => quad8_cases[0..],
        .quad9 => quad9_cases[0..],
    };
}
