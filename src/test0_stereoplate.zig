// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const common = @import("common/stereoplate_test_common.zig");

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const aa = arena.allocator();

    var sim_data = try common.loadPlateSimData(aa, init.io);
    defer sim_data.deinit(aa);

    const stereo_pair = common.buildAutoStereoPair(&sim_data.coords);
    std.debug.print("Rendering stereoplate test0 to {s}/...\n", .{common.out_dir_test0});
    try common.renderStereoPlate(init.gpa, init.io, stereo_pair, common.out_dir_test0);
}
