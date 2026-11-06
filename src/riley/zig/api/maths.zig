// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------

// Public numerical primitives and mathematical utilities.

pub const F = @import("../buildconfig.zig").F;

pub const Vec2F = @import("../vecstack.zig").Vec2F;
pub const Vec3F = @import("../vecstack.zig").Vec3F;
pub const Vec2T = @import("../vecstack.zig").Vec2T;
pub const Vec3T = @import("../vecstack.zig").Vec3T;
pub const Vec2Ops = @import("../vecstack.zig").Vec2Ops;
pub const Vec3Ops = @import("../vecstack.zig").Vec3Ops;

pub const Mat22F = @import("../matstack.zig").Mat22F;
pub const Mat33F = @import("../matstack.zig").Mat33F;
pub const Mat44F = @import("../matstack.zig").Mat44F;
pub const MatSlice = @import("../matslice.zig").MatSlice;
pub const NDArray = @import("../ndarray.zig").NDArray;
pub const MappedNDArray = @import("../ndarray.zig").MappedNDArray;

pub const Rotation = @import("../rotation.zig").Rotation;
