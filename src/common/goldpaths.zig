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

const cfg = buildconfig.config;
const F = buildconfig.F;

pub fn sharedRoot(comptime suite_name: []const u8) []const u8 {
    return if (F == f64)
        std.fmt.comptimePrint("gold/{s}", .{suite_name})
    else
        std.fmt.comptimePrint("gold/{s}_f32", .{suite_name});
}

pub fn sphereRoot(comptime suite_name: []const u8) []const u8 {
    if (F == f64) {
        return if (cfg.simd == .on)
            std.fmt.comptimePrint("gold/{s}-simd", .{suite_name})
        else
            std.fmt.comptimePrint("gold/{s}", .{suite_name});
    }

    return std.fmt.comptimePrint("gold/{s}_f32_{s}", .{
        suite_name,
        if (cfg.simd == .on) "simd" else "scalar",
    });
}

pub fn sphereMulticameraRoot() []const u8 {
    if (F == f64) {
        return if (cfg.simd == .on)
            "gold/sphere200multicam-simd"
        else
            "gold/sphere200multicam";
    }

    return std.fmt.comptimePrint("gold/sphere200multicam_f32_{s}", .{
        if (cfg.simd == .on) "simd" else "scalar",
    });
}
