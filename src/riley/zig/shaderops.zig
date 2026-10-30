// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const shadertypes = @import("shadertypes.zig");
const cfg = @import("buildconfig.zig").config;
const comm = @import("shaderops_common.zig");
const scal = @import("shaderops_scalar.zig");
const simd_impl = @import("shaderops_simd.zig");

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

pub const concreteTexture = shadertypes.concreteTexture;
pub const normFuncShaderParams = shadertypes.normFuncShaderParams;
pub const hasShader = comm.hasShader;
pub const selectShader = comm.selectShader;
pub const stageSource = comm.stageSource;
pub const identityRGB = comm.identityRGB;
pub const identityMulti = comm.identityMulti;
pub const monoToPipeSource = comm.monoToPipeSource;
pub const pipeSourceToMono = comm.pipeSourceToMono;
pub const identitySlots = @import("shaderpipe.zig").identitySlots;
pub const resolverIdentity = @import("shaderpipe.zig").resolverIdentity;
pub const identity_channels_1 = @import("shaderpipe.zig").identity_channels_1;
pub const identity_channels_3 = @import("shaderpipe.zig").identity_channels_3;
pub const identity_channels_8 = @import("shaderpipe.zig").identity_channels_8;

// --------------------------------------------------------------------------------------
// Public Entry-Point Func
// --------------------------------------------------------------------------------------

pub const fillNodalClipScal = scal.fillNodalClipScal;
pub const fillNodalPerspScal = scal.fillNodalPerspScal;
pub const fillTexClipScal = scal.fillTexClipScal;
pub const fillTexPerspScal = scal.fillTexPerspScal;
pub const fillFuncClipScal = scal.fillFuncClipScal;
pub const fillFuncPerspScal = scal.fillFuncPerspScal;
pub const fillNodalClip = fillNodalClipScal;
pub const fillNodalPersp = fillNodalPerspScal;
pub const fillTexClip = fillTexClipScal;
pub const fillTexPersp = fillTexPerspScal;
pub const fillFuncClip = fillFuncClipScal;
pub const fillFuncPersp = fillFuncPerspScal;
pub const fillNodalClipSIMD = simd_impl.fillNodalClipSIMD;
pub const ImageSink = simd_impl.ImageSink;
pub const VectorSink = simd_impl.VectorSink;
pub const fillNodalPerspSIMD = simd_impl.fillNodalPerspSIMD;
pub const fillTexClipSIMD = simd_impl.fillTexClipSIMD;
pub const fillTexPerspSIMD = simd_impl.fillTexPerspSIMD;
pub const fillFuncClipSIMD = simd_impl.fillFuncClipSIMD;
pub const fillFuncPerspSIMD = simd_impl.fillFuncPerspSIMD;
pub const evalFuncShaderGreyNormSIMD = simd_impl.evalFuncShaderGreyNormSIMD;
pub const evalFuncShaderRGBNormSIMD = simd_impl.evalFuncShaderRGBNormSIMD;
