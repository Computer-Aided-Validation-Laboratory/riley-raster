// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
// --------------------------------------------------------------------------------------
const root = @import("root");

// Check requested options independently of buildconfig; plain zig test uses defaults.
const requested = if (@hasDecl(root, "build_options"))
    @import("build_options")
else
    struct {
        pub const enable_all_evaluators = false;
        pub const speckle_mask_samples_per_cell = 12;
    };

pub const enable_all_evaluators = requested.enable_all_evaluators;
pub const speckle_mask_samples_per_cell: comptime_int =
    requested.speckle_mask_samples_per_cell;
