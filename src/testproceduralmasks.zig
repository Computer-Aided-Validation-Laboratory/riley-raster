// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("riley/zig/buildconfig.zig");
const expected_config = @import("tests/expected_speckle_config.zig");

test "speckle build options reach the mask test root" {
    try std.testing.expectEqual(
        expected_config.enable_all_evaluators,
        buildconfig.enable_all_evaluators,
    );
    try std.testing.expectEqual(
        expected_config.speckle_mask_samples_per_cell,
        buildconfig.speckle_mask_samples_per_cell,
    );
}

test {
    _ = @import("dev_support/proceduraldemo.zig");
    _ = @import("riley/zig/speckleops.zig");
    _ = @import("riley/zig/shaderops_common.zig");
    _ = @import("riley/zig/shaderops_scalar.zig");
    _ = @import("riley/zig/shaderops_simd.zig");
}
