// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const cfg = @import("buildconfig.zig").config;
const common_impl = @import("textureops_common.zig");
const simd_impl = @import("textureops_simd.zig");
const impl = if (cfg.simd == .on) simd_impl else common_impl;

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

pub const TextureSample = common_impl.TextureSample;
pub const TextureSampleMode = common_impl.TextureSampleMode;
pub const TextureSampleConfig = common_impl.TextureSampleConfig;
pub const texelToFloat = common_impl.texelToFloat;
pub const Texture = impl.Texture;

// --------------------------------------------------------------------------------------
// Public Entry-Point Functions
// --------------------------------------------------------------------------------------

pub const sampleScalar = impl.sampleScalar;
pub const sampleGreyscale = impl.sampleGreyscale;

pub const sampleOneLane = simd_impl.sampleOneLane;
pub const sampleWide = simd_impl.sampleWide;
pub const sampleLanes = simd_impl.sampleLanes;
pub const sampleLanesTri3 = simd_impl.sampleLanesTri3;
