// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const policy = @import("testpolicy.zig");

pub fn sharedRoot(comptime suite_name: []const u8) []const u8 {
    if (comptime std.mem.eql(u8, suite_name, "min")) {
        return policy.goldRoot(.min);
    }
    if (comptime std.mem.eql(u8, suite_name, "small")) {
        return policy.goldRoot(.small);
    }
    if (comptime std.mem.eql(u8, suite_name, "simple")) {
        return policy.goldRoot(.simple);
    }
    if (comptime std.mem.eql(u8, suite_name, "edge")) {
        return policy.goldRoot(.edge);
    }
    if (comptime std.mem.eql(u8, suite_name, "multimesh")) {
        return policy.goldRoot(.multimesh);
    }
    if (comptime std.mem.eql(u8, suite_name, "hull")) {
        return policy.goldRoot(.hull);
    }
    if (comptime std.mem.eql(u8, suite_name, "fullscreen")) {
        return policy.goldRoot(.fullscreen);
    }
    if (comptime std.mem.eql(u8, suite_name, "fullscreen_ssaa1")) {
        return policy.goldRoot(.fullscreen_ssaa1);
    }
    if (comptime std.mem.eql(u8, suite_name, "texfunc")) {
        return policy.goldRoot(.texfunc);
    }
    if (comptime std.mem.eql(u8, suite_name, "ssaa")) {
        return policy.goldRoot(.ssaa);
    }
    if (comptime std.mem.eql(u8, suite_name, "psf")) {
        return policy.goldRoot(.psf);
    }
    @compileError("Unknown shared gold suite: " ++ suite_name);
}

pub fn sphereRoot(comptime suite_name: []const u8) []const u8 {
    if (comptime std.mem.eql(u8, suite_name, "sphere2000")) {
        return policy.goldRoot(.sphere2000);
    }
    if (comptime std.mem.eql(u8, suite_name, "sphere2000_ssaa1")) {
        return policy.goldRoot(.sphere2000_ssaa1);
    }
    if (comptime std.mem.eql(u8, suite_name, "sphere2000zoom")) {
        return policy.goldRoot(.sphere2000zoom);
    }
    @compileError("Unknown sphere gold suite: " ++ suite_name);
}

pub fn sphereMulticameraRoot() []const u8 {
    return policy.goldRoot(.sphere200multicam);
}
