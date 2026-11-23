// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
// --------------------------------------------------------------------------------------

// Gold-independent native units and in-memory integration tests. Imported entry points
// bring their core dependencies' tests; C ABI tests remain in the fixed-contract suite.
test {
    _ = @import("riley/zig/riley.zig");
    _ = @import("test_poly.zig");
    _ = @import("testproceduralspeckles.zig");
    _ = @import("dev_support/tests.zig");
    _ = @import("dev_support/testsuites.zig");
    _ = @import("dev_support/benchargs.zig");
    _ = @import("bench_speckle_evaluators.zig");
}
