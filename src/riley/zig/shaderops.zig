// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const shaderfunc = @import("shaderfunc.zig");
const shadertypes = @import("shadertypes.zig");
const cfg = @import("buildconfig.zig").config;
const shaderops_common = @import("shaderops_common.zig");
const shaderops_scalar = @import("shaderops_scalar.zig");
const shaderops_simd = @import("shaderops_simd.zig");

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

pub const concreteTexture = shadertypes.concreteTexture;
pub const normFuncShaderParams = shaderfunc.normFuncShaderParams;
pub const hasShader = shaderops_common.hasShader;
pub const selectShader = shaderops_common.selectShader;
pub const stageSource = shaderops_common.stageSource;
pub const identityRGB = shaderops_common.identityRGB;
pub const identityMulti = shaderops_common.identityMulti;
pub const monoToPipeSource = shaderops_common.monoToPipeSource;
pub const pipeSourceToMono = shaderops_common.pipeSourceToMono;
pub const identitySlots = @import("shaderpipe.zig").identitySlots;
pub const resolverIdentity = @import("shaderpipe.zig").resolverIdentity;
pub const identity_channels_1 = @import("shaderpipe.zig").identity_channels_1;
pub const identity_channels_3 = @import("shaderpipe.zig").identity_channels_3;
pub const identity_channels_8 = @import("shaderpipe.zig").identity_channels_8;

// --------------------------------------------------------------------------------------
// Public Entry-Point Func
// --------------------------------------------------------------------------------------

pub const fillNodalClipScal = shaderops_scalar.fillNodalClipScal;
pub const fillNodalPerspScal = shaderops_scalar.fillNodalPerspScal;
pub const fillTexClipScal = shaderops_scalar.fillTexClipScal;
pub const fillTexPerspScal = shaderops_scalar.fillTexPerspScal;
pub const fillFuncClipScal = shaderops_scalar.fillFuncClipScal;
pub const fillFuncPerspScal = shaderops_scalar.fillFuncPerspScal;
pub const fillNodalClip = fillNodalClipScal;
pub const fillNodalPersp = fillNodalPerspScal;
pub const fillTexClip = fillTexClipScal;
pub const fillTexPersp = fillTexPerspScal;
pub const fillFuncClip = fillFuncClipScal;
pub const fillFuncPersp = fillFuncPerspScal;
pub const fillNodalClipSIMD = shaderops_simd.fillNodalClipSIMD;
pub const ImageSink = shaderops_simd.ImageSink;
pub const VectorSink = shaderops_simd.VectorSink;
pub const fillNodalPerspSIMD = shaderops_simd.fillNodalPerspSIMD;
pub const fillTexClipSIMD = shaderops_simd.fillTexClipSIMD;
pub const fillTexPerspSIMD = shaderops_simd.fillTexPerspSIMD;
pub const fillFuncClipSIMD = shaderops_simd.fillFuncClipSIMD;
pub const fillFuncPerspSIMD = shaderops_simd.fillFuncPerspSIMD;
pub const evalFuncShaderGreyNormSIMD = shaderops_simd.evalFuncShaderGreyNormSIMD;
pub const evalFuncShaderRGBNormSIMD = shaderops_simd.evalFuncShaderRGBNormSIMD;
