// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------

// Public API entry point for `@import("riley")`.

const shaderfunc = @import("../shaderfunc.zig");
pub const dataio = @import("dataio.zig");
pub const maths = @import("maths.zig");
pub const ops = @import("ops.zig");

// --------------------------------------------------------------------------------------
// Rendering
// --------------------------------------------------------------------------------------

pub const raster = @import("../riley.zig").raster;
pub const rasterInto = @import("../riley.zig").rasterInto;
pub const calcAllFramesImageDims = @import("../riley.zig").calcAllFramesImageDims;

// --------------------------------------------------------------------------------------
// Mesh Types
// --------------------------------------------------------------------------------------

pub const MeshInput = @import("../meshtypes.zig").MeshInput;
pub const MeshType = @import("../geometrykernels.zig").MeshType;
pub const NormalType = @import("../normals.zig").NormalType;
pub const Coords = @import("../meshtypes.zig").Coords;
pub const Connect = @import("../meshtypes.zig").Connect;
pub const Field = @import("../fieldtypes.zig").Field;

// --------------------------------------------------------------------------------------
// Camera Types
// --------------------------------------------------------------------------------------

pub const CameraInput = @import("../cameratypes.zig").CameraInput;
pub const StereoPairInput = @import("../cameratypes.zig").StereoPairInput;
pub const CameraCoordSys = @import("../cameratypes.zig").CameraCoordSys;
pub const SubPixelCenterMap = @import("../cameratypes.zig").SubPixelCenterMap;
pub const FOVScaling = @import("../cameratypes.zig").FOVScaling;
pub const FrameFitMode = @import("../cameratypes.zig").FrameFitMode;
pub const OrbitCam = @import("../cameratypes.zig").OrbitCam;
pub const StereoPairPosRot = @import("../cameratypes.zig").StereoPairPosRot;
pub const CameraPlaneMetrics = @import("../cameratypes.zig").CameraPlaneMetrics;

// --------------------------------------------------------------------------------------
// Camera Models
// --------------------------------------------------------------------------------------

pub const BrownConParams = @import("../cameramodels.zig").BrownConParams;
pub const BrownConExtParams = @import("../cameramodels.zig").BrownConExtParams;
pub const BrownConPoly = @import("../cameramodels.zig").BrownConPoly;
pub const BrownConExtPolyParams = @import("../cameramodels.zig").BrownConExtPolyParams;
pub const PolyMap = @import("../cameramodels.zig").PolyMap;
pub const PolyMode = @import("../cameramodels.zig").PolyMode;
pub const DistortParams = @import("../cameramodels.zig").DistortParams;
pub const PointSpreadFunc = @import("../cameramodels.zig").PointSpreadFunc;
pub const SeparablePSF = @import("../cameramodels.zig").SeparablePSF;
pub const PixelBoxPSF = @import("../cameramodels.zig").PixelBoxPSF;
pub const GaussianPSF = @import("../cameramodels.zig").GaussianPSF;
pub const AnisotropicGaussianPSF = @import("../cameramodels.zig").AnisotropicGaussianPSF;

// --------------------------------------------------------------------------------------
// Shader Types
// --------------------------------------------------------------------------------------

pub const MeshShaderSetInput = @import("../shadertypes.zig").MeshShaderSetInput;
pub const ShaderMonoInput = @import("../shadertypes.zig").ShaderMonoInput;
pub const ShaderPipeInput = @import("../shadertypes.zig").ShaderPipeInput;
pub const ShaderPipeStageInput = @import("../shadertypes.zig").ShaderPipeStageInput;
pub const PipeSourceInput = @import("../shadertypes.zig").PipeSourceInput;
pub const NodalInput = @import("../shadertypes.zig").NodalInput;
pub const FuncInput = @import("../shadertypes.zig").FuncInput;
pub const FuncMultiInput = @import("../shadertypes.zig").FuncMultiInput;
pub const TexInput = @import("../shadertypes.zig").TexInput;
pub const RenderFormat = @import("../shadertypes.zig").RenderFormat;
pub const ScaleOver = @import("../shadertypes.zig").ScaleOver;
pub const FuncShaderBuiltin = shaderfunc.FuncShaderBuiltin;
pub const FuncShaderParams = shaderfunc.FuncShaderParams;

// --------------------------------------------------------------------------------------
// Shader Pipe
// --------------------------------------------------------------------------------------

pub const SlotKind = @import("../shaderpipe.zig").SlotKind;
pub const Slot = @import("../shaderpipe.zig").Slot;
pub const Op = @import("../shaderpipe.zig").Op;
pub const BandResponse = @import("../shaderpipe.zig").BandResponse;
pub const Resolver = @import("../shaderpipe.zig").Resolver;

// --------------------------------------------------------------------------------------
// Texture Types
// --------------------------------------------------------------------------------------

pub const TexSamp = @import("../texturetypes.zig").TexSamp;
pub const TexSampMode = @import("../texturetypes.zig").TexSampMode;
pub const TexSampConfig = @import("../texturetypes.zig").TexSampConfig;
pub const TexDataFix = @import("../texturetypes.zig").TexDataFix;
pub const TexDataDyn = @import("../texturetypes.zig").TexDataDyn;

// --------------------------------------------------------------------------------------
// Configuration
// --------------------------------------------------------------------------------------

pub const RasterConfig = @import("../rasterconfig.zig").RasterConfig;
pub const ParallelConfig = @import("../rasterconfig.zig").ParallelConfig;
pub const OutputConfig = @import("../rasterconfig.zig").OutputConfig;
pub const AdvancedConfig = @import("../rasterconfig.zig").AdvancedConfig;
pub const RasterTuning = @import("../rasterconfig.zig").RasterTuning;
pub const DistortionTuning = @import("../rasterconfig.zig").DistortionTuning;
pub const SolverTuning = @import("../rasterconfig.zig").SolverTuning;
pub const SolverTuningOneRoot = @import("../rasterconfig.zig").SolverTuningOneRoot;
pub const SolverTuningMultiroot = @import("../rasterconfig.zig").SolverTuningMultiroot;
pub const MultirootSolverMode = @import("../rasterconfig.zig").MultirootSolverMode;
pub const BufferMode = @import("../rasterconfig.zig").BufferMode;
pub const SaveStrategy = @import("../rasterconfig.zig").SaveStrategy;
pub const RenderMode = @import("../rasterconfig.zig").RenderMode;
pub const ReportMode = @import("../rasterconfig.zig").ReportMode;
pub const ValidateInput = @import("../rasterconfig.zig").ValidateInput;

// Input types used by scene builders and language adapters.
pub const ScaleStrategy = @import("../imageops.zig").ScaleStrategy;
pub const FuncCoordMode = shaderfunc.FuncCoordMode;
pub const FuncChannel = @import("../shadertypes.zig").FuncChannel;
pub const Lookup = @import("../shaderpipe.zig").Lookup;
pub const HullMode = @import("../rasterconfig.zig").HullMode;
pub const EdgeFunMode = @import("../rasterconfig.zig").EdgeFunMode;
pub const NewtonSeedMode = @import("../rasterconfig.zig").NewtonSeedMode;
pub const NewtonSeedReuse = @import("../rasterconfig.zig").NewtonSeedReuse;

pub const max_channels = @import("../shaderpipe.zig").max_channels;
pub const max_slots = @import("../shaderpipe.zig").max_slots;
