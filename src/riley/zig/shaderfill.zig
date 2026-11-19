// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const shaderfill_scalar = @import("shaderfill_scalar.zig");
const shaderfill_simd = @import("shaderfill_simd.zig");

pub const fillNodalClipScal = shaderfill_scalar.fillNodalClipScal;
pub const fillNodalPerspScal = shaderfill_scalar.fillNodalPerspScal;
pub const fillTexClipScal = shaderfill_scalar.fillTexClipScal;
pub const fillTexPerspScal = shaderfill_scalar.fillTexPerspScal;
pub const fillFuncClipScal = shaderfill_scalar.fillFuncClipScal;
pub const fillFuncPerspScal = shaderfill_scalar.fillFuncPerspScal;
pub const fillNodalClip = fillNodalClipScal;
pub const fillNodalPersp = fillNodalPerspScal;
pub const fillTexClip = fillTexClipScal;
pub const fillTexPersp = fillTexPerspScal;
pub const fillFuncClip = fillFuncClipScal;
pub const fillFuncPersp = fillFuncPerspScal;
pub const fillNodalClipSIMD = shaderfill_simd.fillNodalClipSIMD;
pub const ImageSink = shaderfill_simd.ImageSink;
pub const VectorSink = shaderfill_simd.VectorSink;
pub const fillNodalPerspSIMD = shaderfill_simd.fillNodalPerspSIMD;
pub const fillTexClipSIMD = shaderfill_simd.fillTexClipSIMD;
pub const fillTexPerspSIMD = shaderfill_simd.fillTexPerspSIMD;
pub const fillFuncClipSIMD = shaderfill_simd.fillFuncClipSIMD;
pub const fillFuncPerspSIMD = shaderfill_simd.fillFuncPerspSIMD;
pub const evalFuncShaderGreyNormSIMD = shaderfill_simd.evalFuncShaderGreyNormSIMD;
pub const evalFuncShaderRGBNormSIMD = shaderfill_simd.evalFuncShaderRGBNormSIMD;
