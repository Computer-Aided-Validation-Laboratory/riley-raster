// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const default_runner = @import("default_test_runner");

// Zig tests use the runner as @import("root"). Expose Riley's build options
// there while retaining the toolchain's standard test execution and protocol.
pub const build_options = @import("build_options");
pub const main = default_runner.main;
pub const std_options = default_runner.std_options;
pub const fuzz = default_runner.fuzz;
