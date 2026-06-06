// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const common = @import("common/stereoplate_test_common.zig");

pub fn main(init: std.process.Init) !void {
    var out_dir = try std.Io.Dir.cwd().openDir(init.io, common.out_dir_test0, .{});
    defer out_dir.close(init.io);

    const stereo_pair = try common.cameraio.loadStereoPair(
        init.gpa,
        init.io,
        out_dir,
        "stereo_data.csv",
    );
    std.debug.print("Rendering stereoplate test1 to {s}/...\n", .{common.out_dir_test1});
    try common.renderStereoPlate(init.gpa, init.io, stereo_pair, common.out_dir_test1);

    const max_abs = try common.compareStereoOutputs(
        init.gpa,
        init.io,
        common.out_dir_test0,
        common.out_dir_test1,
        common.out_dir_diff,
    );
    std.debug.print("test0/test1 max abs diff = {d:.16}\n", .{max_abs});
    if (max_abs > 0.0) return error.NonZeroDifference;
}
