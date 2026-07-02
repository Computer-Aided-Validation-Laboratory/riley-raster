// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const cfg = @import("buildconfig.zig").config;
const common = @import("shaderops_common.zig");
const impl = if (cfg.simd == .on)
    @import("shaderops_simd.zig")
else
    @import("shaderops_scalar.zig");
const simd_impl = @import("shaderops_simd.zig");

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

pub const ScaleOver = common.ScaleOver;
pub const NormalType = common.NormalType;
pub const FuncCoordMode = common.FuncCoordMode;
pub const FuncShaderBuiltin = common.FuncShaderBuiltin;
pub const FuncShaderParams = common.FuncShaderParams;
pub const LocalShaderBuff = common.LocalShaderBuff;
pub const NodalInput = common.NodalInput;
pub const NodalPrepared = common.NodalPrepared;
pub const TexInput = common.TexInput;
pub const TexPrepared = common.TexPrepared;
pub const FuncInput = common.FuncInput;
pub const FuncPrepared = common.FuncPrepared;
pub const ShadeContext = common.ShadeContext;
pub const InterpData = common.InterpData;
pub const ShaderInput = common.ShaderInput;
pub const NodalStatic = common.NodalStatic;
pub const TexStatic = common.TexStatic;
pub const FuncStatic = common.FuncStatic;
pub const ShaderStatic = common.ShaderStatic;
pub const ShaderPrepared = common.ShaderPrepared;

// --------------------------------------------------------------------------------------
// Public Entry-Point Func
// --------------------------------------------------------------------------------------

pub const fillNodalClip = impl.fillNodalClip;
pub const fillNodalPersp = impl.fillNodalPersp;
pub const fillTexClip = impl.fillTexClip;
pub const fillTexPersp = impl.fillTexPersp;
pub const fillFuncClip = impl.fillFuncClip;
pub const fillFuncPersp = impl.fillFuncPersp;
pub const fillNodalClipSIMD = simd_impl.fillNodalClipSIMD;
pub const fillNodalPerspSIMD = simd_impl.fillNodalPerspSIMD;
pub const fillTexClipSIMD = simd_impl.fillTexClipSIMD;
pub const fillTexPerspSIMD = simd_impl.fillTexPerspSIMD;
pub const fillFuncClipSIMD = simd_impl.fillFuncClipSIMD;
pub const fillFuncPerspSIMD = simd_impl.fillFuncPerspSIMD;
