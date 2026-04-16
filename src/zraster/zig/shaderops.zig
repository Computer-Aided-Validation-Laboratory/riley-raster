// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const cfg = @import("buildconfig.zig").config;
const common = @import("shaderops_common.zig");
const impl = if (cfg.simd == .on)
    @import("shaderops_simd.zig")
else
    @import("shaderops_scalar.zig");
const simd_impl = @import("shaderops_simd.zig");

pub const ScaleOver = common.ScaleOver;
pub const NormalType = common.NormalType;
pub const LocalShaderBuffer = common.LocalShaderBuffer;
pub const NodalInput = common.NodalInput;
pub const NodalPrepared = common.NodalPrepared;
pub const TexInput = common.TexInput;
pub const TexPrepared = common.TexPrepared;
pub const ShadeContext = common.ShadeContext;
pub const InterpData = common.InterpData;
pub const ShaderInput = common.ShaderInput;
pub const ShaderPrepared = common.ShaderPrepared;
pub const fillNodalClip = impl.fillNodalClip;
pub const fillNodalPersp = impl.fillNodalPersp;
pub const fillTexClip = impl.fillTexClip;
pub const fillTexPersp = impl.fillTexPersp;
pub const fillTexClipRuntime = impl.fillTexClipRuntime;
pub const fillTexPerspRuntime = impl.fillTexPerspRuntime;
pub const fillNodalClipSIMD = simd_impl.fillNodalClipSIMD;
pub const fillNodalPerspSIMD = simd_impl.fillNodalPerspSIMD;
pub const fillTexClipSIMD = simd_impl.fillTexClipSIMD;
pub const fillTexPerspSIMD = simd_impl.fillTexPerspSIMD;
pub const fillTexClipSIMDRuntime = simd_impl.fillTexClipSIMDRuntime;
pub const fillTexPerspSIMDRuntime = simd_impl.fillTexPerspSIMDRuntime;
