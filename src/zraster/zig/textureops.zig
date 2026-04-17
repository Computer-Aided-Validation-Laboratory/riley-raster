// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const cfg = @import("buildconfig.zig").config;
const common_impl = @import("textureops_common.zig");
const simd_impl = @import("textureops_simd.zig");
const impl = if (cfg.simd == .on) simd_impl else common_impl;

pub const TextureSample = common_impl.TextureSample;
pub const TextureSampleMode = common_impl.TextureSampleMode;
pub const TextureSampleConfig = common_impl.TextureSampleConfig;
pub const Texture = impl.Texture;
pub const sampleScalar = impl.sampleScalar;
pub const sampleScalarRuntime = common_impl.sampleScalarRuntime;
pub const sampleGreyscale = impl.sampleGreyscale;
pub const sampleGreyscaleRuntime = common_impl.sampleGreyscaleRuntime;

// Scalar/Single Lane helper
pub const sampleOneLane = simd_impl.sampleOneLane;
pub const sampleOneLaneRuntime = simd_impl.sampleOneLaneRuntime;

// Strategy 1: Wide (Parallel over pixels)
pub const sampleWide = simd_impl.sampleWide;
pub const sampleWideRuntime = simd_impl.sampleWideRuntime;

// Strategy 2: Lanes (Serial over pixels, SIMD math)
pub const sampleLanes = simd_impl.sampleLanes;
pub const sampleLanesRuntime = simd_impl.sampleLanesRuntime;
pub const sampleLanesTri3 = simd_impl.sampleLanesTri3;
pub const sampleLanesTri3Runtime = simd_impl.sampleLanesTri3Runtime;
