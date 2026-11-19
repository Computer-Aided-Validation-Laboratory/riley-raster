// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

pub const dev_support = struct {
    pub const diag_badjac = @import("dev_support/diag_badjac.zig");
};

pub fn main(init: std.process.Init) !void {
    return dev_support.diag_badjac.main(init);
}
