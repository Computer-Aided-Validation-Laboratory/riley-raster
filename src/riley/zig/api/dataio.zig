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

// --------------------------------------------------------------------------------------
// Mesh Data
// --------------------------------------------------------------------------------------

pub const SimDataFiles = meshio.SimDataFiles;
pub const SimData = meshio.SimData;
pub const loadSimData = meshio.loadSimData;
pub const loadMultiSimData = meshio.loadMultiSimData;

// --------------------------------------------------------------------------------------
// UV Data
// --------------------------------------------------------------------------------------

pub const UVMap = uvio.UVMap;
pub const loadUVMap = uvio.loadUVMap;

// --------------------------------------------------------------------------------------
// Images
// --------------------------------------------------------------------------------------

pub const ImageFormat = imageio.ImageFormat;
pub const ImageSaveOpts = imageio.ImageSaveOpts;
pub const CodePacking = imageio.CodePacking;
pub const loadImage = imageio.loadImage;
pub const saveImage = imageio.saveImage;
pub const saveTextureCSV = imageio.saveTextureCSV;
pub const loadFIMG = imageio.loadFIMG;

// --------------------------------------------------------------------------------------
// Cameras
// --------------------------------------------------------------------------------------

pub const saveCamera = cameraio.saveCamera;
pub const LoadedCamera = cameraio.LoadedCamera;
pub const saveStereoPair = cameraio.saveStereoPair;
pub const LoadedStereoPair = cameraio.LoadedStereoPair;
