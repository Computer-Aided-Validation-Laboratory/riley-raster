// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------

// Public load/save operations for meshes, UVs, images, cameras and calibration data.

const meshio = @import("../meshio.zig");
const uvio = @import("../uvio.zig");
const imageio = @import("../imageio.zig");
const cameraio = @import("../cameraio.zig");
const csvio = @import("../csvio.zig");

// --------------------------------------------------------------------------------------
// Mesh Data
// --------------------------------------------------------------------------------------

pub const SimDataFiles = meshio.SimDataFiles;
pub const SimData = meshio.SimData;
pub const loadSimData = meshio.loadSimData;
pub const loadMultiSimData = meshio.loadMultiSimData;
pub const parseCoords = meshio.parseCoords;
pub const parseConnect = meshio.parseConnect;
pub const parseField = meshio.parseField;
pub const getFieldTimeN = meshio.getFieldTimeN;

// --------------------------------------------------------------------------------------
// UV Data
// --------------------------------------------------------------------------------------

pub const UVMap = uvio.UVMap;
pub const loadUVs = uvio.loadUVs;
pub const loadUVMap = uvio.loadUVMap;

// --------------------------------------------------------------------------------------
// Images
// --------------------------------------------------------------------------------------

pub const ImageFormat = imageio.ImageFormat;
pub const ImageSaveOpts = imageio.ImageSaveOpts;
pub const CodePacking = imageio.CodePacking;
pub const loadImage = imageio.loadImage;
pub const saveImage = imageio.saveImage;
pub const saveMatAsImage = imageio.saveMatAsImage;
pub const saveImages = imageio.saveImages;
pub const formatFrameFieldBaseName = imageio.formatFrameFieldBaseName;
pub const validateOutputNameFormat = imageio.validateOutputNameFormat;
pub const savePPM = imageio.savePPM;
pub const loadPPM = imageio.loadPPM;
pub const loadCSV = imageio.loadCSV;
pub const loadFIMG = imageio.loadFIMG;
pub const loadBMP = imageio.loadBMP;
pub const loadTIFF = imageio.loadTIFF;

// --------------------------------------------------------------------------------------
// Cameras
// --------------------------------------------------------------------------------------

pub const saveCamera = cameraio.saveCamera;
pub const LoadedCamera = cameraio.LoadedCamera;
pub const saveStereoPair = cameraio.saveStereoPair;
pub const LoadedStereoPair = cameraio.LoadedStereoPair;

// --------------------------------------------------------------------------------------
// CSV
// --------------------------------------------------------------------------------------

pub const readCsvToList = csvio.readCsvToList;
pub const freeCsvLines = csvio.freeCsvLines;
pub const countCsvCols = csvio.countCsvCols;
pub const hasPackedChannels = csvio.hasPackedChannels;
pub const loadScalarCsv2D = csvio.loadScalarCsv2D;
pub const loadScalarCsv2DFromLines = csvio.loadScalarCsv2DFromLines;
pub const loadPackedCsv2D = csvio.loadPackedCsv2D;
pub const loadPackedCsv2DFromLines = csvio.loadPackedCsv2DFromLines;
pub const saveScalarGridCSV = csvio.saveScalarGridCSV;
pub const savePackedGridCSV = csvio.savePackedGridCSV;
