// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const textureops_common = @import("textureops_common.zig");
const textureops_simd = @import("textureops_simd.zig");

// --------------------------------------------------------------------------------------
// Public Entry-Point Func
// --------------------------------------------------------------------------------------

pub const lanczos2Coeff = textureops_common.lanczos2Coeff;
pub const texelToFloat = textureops_common.texelToFloat;

pub const sampScal = textureops_common.sampScal;
pub const sampGrey = textureops_common.sampGrey;
pub const sampOneLane = textureops_simd.sampOneLane;
pub const sampWide = textureops_simd.sampWide;
pub const sampLanes = textureops_simd.sampLanes;
pub const sampLanesTri3 = textureops_simd.sampLanesTri3;
pub const sampleScal = sampScal;
pub const sampleGreyscale = sampGrey;
pub const sampleOneLane = sampOneLane;
pub const sampleWide = sampWide;
pub const sampleLanes = sampLanes;
pub const sampleLanesTri3 = sampLanesTri3;
