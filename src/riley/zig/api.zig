// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------

// Public module root. Zig resolves a module path from the root source directory, so
// this file lives beside the implementation and forwards the explicit public surface
// assembled in api/core.zig.

const core = @import("api/core.zig");

pub const dataio = core.dataio;
pub const maths = core.maths;
pub const ops = core.ops;
pub const raster = core.raster;
pub const rasterInto = core.rasterInto;
pub const calcAllFramesImageDims = core.calcAllFramesImageDims;
pub const MeshInput = core.MeshInput;
pub const MeshType = core.MeshType;
pub const NormalType = core.NormalType;
pub const Coords = core.Coords;
pub const Connect = core.Connect;
pub const Field = core.Field;
pub const CameraInput = core.CameraInput;
pub const StereoPairInput = core.StereoPairInput;
pub const CameraCoordSys = core.CameraCoordSys;
pub const SubPixelCenterMap = core.SubPixelCenterMap;
pub const FOVScaling = core.FOVScaling;
pub const FrameFitMode = core.FrameFitMode;
pub const OrbitCam = core.OrbitCam;
pub const StereoPairPosRot = core.StereoPairPosRot;
pub const CameraPlaneMetrics = core.CameraPlaneMetrics;
pub const BrownConParams = core.BrownConParams;
pub const BrownConExtParams = core.BrownConExtParams;
pub const BrownConPoly = core.BrownConPoly;
pub const BrownConExtPolyParams = core.BrownConExtPolyParams;
pub const PolyMap = core.PolyMap;
pub const PolyMode = core.PolyMode;
pub const DistortParams = core.DistortParams;
pub const PointSpreadFunc = core.PointSpreadFunc;
pub const SeparablePSF = core.SeparablePSF;
pub const PixelBoxPSF = core.PixelBoxPSF;
pub const GaussianPSF = core.GaussianPSF;
pub const AnisotropicGaussianPSF = core.AnisotropicGaussianPSF;
pub const MeshShaderSetInput = core.MeshShaderSetInput;
pub const ShaderMonoInput = core.ShaderMonoInput;
pub const ShaderPipeInput = core.ShaderPipeInput;
pub const ShaderPipeStageInput = core.ShaderPipeStageInput;
pub const PipeSourceInput = core.PipeSourceInput;
pub const NodalInput = core.NodalInput;
pub const FuncInput = core.FuncInput;
pub const FuncMultiInput = core.FuncMultiInput;
pub const TexInput = core.TexInput;
pub const RenderFormat = core.RenderFormat;
pub const ScaleOver = core.ScaleOver;
pub const FuncShaderBuiltin = core.FuncShaderBuiltin;
pub const FuncShaderParams = core.FuncShaderParams;
pub const RegisterKind = core.RegisterKind;
pub const Register = core.Register;
pub const ResolverOp = core.ResolverOp;
pub const SpectralBandResponse = core.SpectralBandResponse;
pub const Resolver = core.Resolver;
pub const TexSamp = core.TexSamp;
pub const TexSampMode = core.TexSampMode;
pub const TexSampConfig = core.TexSampConfig;
pub const TexDataFix = core.TexDataFix;
pub const TexDataDyn = core.TexDataDyn;
pub const RasterConfig = core.RasterConfig;
pub const ParallelConfig = core.ParallelConfig;
pub const OutputConfig = core.OutputConfig;
pub const AdvancedConfig = core.AdvancedConfig;
pub const RasterTuning = core.RasterTuning;
pub const DistortionTuning = core.DistortionTuning;
pub const SolverTuning = core.SolverTuning;
pub const SolverTuningOneRoot = core.SolverTuningOneRoot;
pub const SolverTuningMultiroot = core.SolverTuningMultiroot;
pub const MultirootSolverMode = core.MultirootSolverMode;
pub const BufferMode = core.BufferMode;
pub const SaveStrategy = core.SaveStrategy;
pub const RenderMode = core.RenderMode;
pub const ReportMode = core.ReportMode;
pub const ValidateInput = core.ValidateInput;
pub const ScaleStrategy = core.ScaleStrategy;
pub const FuncCoordMode = core.FuncCoordMode;
pub const FuncChannel = core.FuncChannel;
pub const LookupTable = core.LookupTable;
pub const HullMode = core.HullMode;
pub const EdgeFunMode = core.EdgeFunMode;
pub const NewtonSeedMode = core.NewtonSeedMode;
pub const NewtonSeedReuse = core.NewtonSeedReuse;
pub const max_channels = core.max_channels;
pub const max_registers = core.max_registers;
