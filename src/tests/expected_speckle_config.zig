// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
// --------------------------------------------------------------------------------------
const root = @import("root");
const buildoptions = @import("../riley/zig/buildoptions.zig");

// Check requested options independently of buildconfig; plain zig test uses defaults.
const requested = if (@hasDecl(root, "build_options"))
    @import("build_options").values
else
    buildoptions.Options{};

pub const enable_all_evaluators = requested.enable_all_evaluators;
pub const speckle_mask_samples_per_cell: comptime_int =
    @backingInt(requested.speckle_mask_resolution);
