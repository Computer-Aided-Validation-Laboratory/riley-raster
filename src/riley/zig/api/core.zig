// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------

// Public API entry point for `@import("riley")`.

pub const dataio = @import("dataio.zig");
pub const maths = @import("maths.zig");
pub const ops = @import("ops.zig");

// --------------------------------------------------------------------------------------
// Rendering
// --------------------------------------------------------------------------------------

pub const raster = @import("../riley.zig").raster;
pub const rasterInto = @import("../riley.zig").rasterInto;
pub const rasterAdvanced = @import("../riley.zig").rasterAdvanced;
pub const rasterAdvancedInto = @import("../riley.zig").rasterAdvancedInto;
pub const calcAllFramesImageDims = @import("../riley.zig").calcAllFramesImageDims;
pub const getThreadedIo = @import("../riley.zig").getThreadedIo;
pub const RasterAdvancedOptions = @import("../riley.zig").RasterAdvancedOptions;
pub const RenderGroup = @import("../riley.zig").RenderGroup;
pub const ManagedRenderGroups = @import("../riley.zig").ManagedRenderGroups;
pub const FrameBenchCapture = @import("../report.zig").FrameBenchCapture;

// --------------------------------------------------------------------------------------
// Mesh Types
// --------------------------------------------------------------------------------------

pub const MeshInput = @import("../meshtypes.zig").MeshInput;
pub const MeshStatic = @import("../meshtypes.zig").MeshStatic;
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

pub const BrownCon = @import("../cameramodels.zig").BrownCon;
pub const BrownConExt = @import("../cameramodels.zig").BrownConExt;
pub const BrownConParams = @import("../cameramodels.zig").BrownConParams;
pub const BrownConExtParams = @import("../cameramodels.zig").BrownConExtParams;
pub const BrownConPoly = @import("../cameramodels.zig").BrownConPoly;
pub const BrownConExtPoly = @import("../cameramodels.zig").BrownConExtPoly;
pub const BrownConExtPolyParams = @import("../cameramodels.zig").BrownConExtPolyParams;
pub const PolyMap = @import("../cameramodels.zig").PolyMap;
pub const PolyMode = @import("../cameramodels.zig").PolyMode;
pub const DistortParams = @import("../cameramodels.zig").DistortParams;
pub const DistortModel = @import("../cameramodels.zig").DistortModel;
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
pub const FuncShaderBuiltin = @import("../shadertypes.zig").FuncShaderBuiltin;
pub const FuncShaderParams = @import("../shadertypes.zig").FuncShaderParams;

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

pub const TexSamp = @import("../textureops.zig").TexSamp;
pub const TexSampMode = @import("../textureops.zig").TexSampMode;
pub const TexSampConfig = @import("../textureops.zig").TexSampConfig;
pub const TexDataFix = @import("../textureops.zig").TexDataFix;
pub const TexDataDyn = @import("../textureops.zig").TexDataDyn;

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
pub const GeometrySchedulingMode = @import("../rasterconfig.zig").GeometrySchedulingMode;
