// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------

// Public scene/camera operations and shader-input construction helpers.

// --------------------------------------------------------------------------------------
// Scene Operations
// --------------------------------------------------------------------------------------

pub const AxisAnchor = @import("../sceneops.zig").AxisAnchor;
pub const Bounds3D = @import("../sceneops.zig").Bounds3D;
pub const MeshGroupSpan = @import("../sceneops.zig").MeshGroupSpan;
pub const MeshGroup = @import("../sceneops.zig").MeshGroup;
pub const GridSpec = @import("../sceneops.zig").GridSpec;
pub const OverlapDirection = @import("../sceneops.zig").OverlapDirection;
pub const BoundsOverlapSpec = @import("../sceneops.zig").BoundsOverlapSpec;
pub const RadialAxis = @import("../sceneops.zig").RadialAxis;
pub const RadialSpec = @import("../sceneops.zig").RadialSpec;
pub const selectFirstLastFrameIndices = @import("../sceneops.zig").selectFirstLastFrameIndices;
pub const selectEvenlySpacedFrameIndices = @import("../sceneops.zig").selectEvenlySpacedFrameIndices;
pub const selectFieldFrames = @import("../sceneops.zig").selectFieldFrames;
pub const meshGroupSpan = @import("../sceneops.zig").meshGroupSpan;
pub const meshGroupSingle = @import("../sceneops.zig").meshGroupSingle;
pub const meshGroupLen = @import("../sceneops.zig").meshGroupLen;
pub const duplicateCoords = @import("../sceneops.zig").duplicateCoords;
pub const duplicateMeshInstance = @import("../sceneops.zig").duplicateMeshInstance;
pub const duplicateMeshInstances = @import("../sceneops.zig").duplicateMeshInstances;
pub const duplicateMeshGroup = @import("../sceneops.zig").duplicateMeshGroup;
pub const appendMeshGroupDuplicate = @import("../sceneops.zig").appendMeshGroupDuplicate;
pub const boundsForCoords = @import("../sceneops.zig").boundsForCoords;
pub const boundsForMeshes = @import("../sceneops.zig").boundsForMeshes;
pub const boundsForMeshGroup = @import("../sceneops.zig").boundsForMeshGroup;
pub const meanCenter = @import("../sceneops.zig").meanCenter;
pub const boundsCenter = @import("../sceneops.zig").boundsCenter;
pub const boundsCenterOverMeshes = @import("../sceneops.zig").boundsCenterOverMeshes;
pub const extentInRotatedFrame = @import("../sceneops.zig").extentInRotatedFrame;
pub const extentInRotatedFrameOverMeshes = @import("../sceneops.zig").extentInRotatedFrameOverMeshes;
pub const transformCoords = @import("../sceneops.zig").transformCoords;
pub const moveMesh = @import("../sceneops.zig").moveMesh;
pub const moveMeshGroup = @import("../sceneops.zig").moveMeshGroup;
pub const translateCoords = @import("../sceneops.zig").translateCoords;
pub const translateMesh = @import("../sceneops.zig").translateMesh;
pub const translateMeshes = @import("../sceneops.zig").translateMeshes;
pub const translateMeshGroup = @import("../sceneops.zig").translateMeshGroup;
pub const centerCoordsAt = @import("../sceneops.zig").centerCoordsAt;
pub const centerMeshAt = @import("../sceneops.zig").centerMeshAt;
pub const centerMeshGroupAt = @import("../sceneops.zig").centerMeshGroupAt;
pub const positionCoordsRelative = @import("../sceneops.zig").positionCoordsRelative;
pub const positionMeshRelative = @import("../sceneops.zig").positionMeshRelative;
pub const alignMeshGroupToMeshGroup = @import("../sceneops.zig").alignMeshGroupToMeshGroup;
pub const overlapMeshGroupBounds = @import("../sceneops.zig").overlapMeshGroupBounds;
pub const arrangeMeshesGrid = @import("../sceneops.zig").arrangeMeshesGrid;
pub const arrangeMeshGroupsGrid = @import("../sceneops.zig").arrangeMeshGroupsGrid;
pub const arrangeMeshesLine = @import("../sceneops.zig").arrangeMeshesLine;
pub const arrangeMeshGroupsLine = @import("../sceneops.zig").arrangeMeshGroupsLine;
pub const arrangeMeshesRadial = @import("../sceneops.zig").arrangeMeshesRadial;
pub const arrangeMeshGroupsRadial = @import("../sceneops.zig").arrangeMeshGroupsRadial;

// --------------------------------------------------------------------------------------
// Camera Framing Operations
// --------------------------------------------------------------------------------------

pub const toOpenGLInput = @import("../cameraframeops.zig").toOpenGLInput;
pub const calcPlaneMetrics = @import("../cameraframeops.zig").calcPlaneMetrics;
pub const coverageToFovScale = @import("../cameraframeops.zig").coverageToFovScale;
pub const fovScaleToCoverage = @import("../cameraframeops.zig").fovScaleToCoverage;
pub const fovFromCamRot = @import("../cameraframeops.zig").fovFromCamRot;
pub const fovFromCamRotOverMeshes = @import("../cameraframeops.zig").fovFromCamRotOverMeshes;
pub const calcSensorSize = @import("../cameraframeops.zig").calcSensorSize;
pub const imageDistFromFov = @import("../cameraframeops.zig").imageDistFromFov;
pub const calcFOVScaling = @import("../cameraframeops.zig").calcFOVScaling;
pub const calcCamPos = @import("../cameraframeops.zig").calcCamPos;
pub const lookAtPoint = @import("../cameraframeops.zig").lookAtPoint;
pub const imageDistFrameCoords = @import("../cameraframeops.zig").imageDistFrameCoords;
pub const imageDistFrameCoordsTarg = @import("../cameraframeops.zig").imageDistFrameCoordsTarg;
pub const imageDistFrameMeshes = @import("../cameraframeops.zig").imageDistFrameMeshes;
pub const imageDistFrameMeshesTarg = @import("../cameraframeops.zig").imageDistFrameMeshesTarg;
pub const posFrameCoords = @import("../cameraframeops.zig").posFrameCoords;
pub const posFrameCoordsTarg = @import("../cameraframeops.zig").posFrameCoordsTarg;
pub const posFrameMesh = @import("../cameraframeops.zig").posFrameMesh;
pub const posFrameMeshes = @import("../cameraframeops.zig").posFrameMeshes;
pub const posFrameMeshesTarg = @import("../cameraframeops.zig").posFrameMeshesTarg;
pub const posOrbitCam = @import("../cameraframeops.zig").posOrbitCam;
pub const posStereoPair = @import("../cameraframeops.zig").posStereoPair;
pub const calcPixelResolution = @import("../cameraframeops.zig").calcPixelResolution;
pub const imageDistFillFrameFromRot = @import("../cameraframeops.zig").imageDistFillFrameFromRot;
pub const posFillFrameFromRot = @import("../cameraframeops.zig").posFillFrameFromRot;
pub const posFillFrameFromRotAndTarg = @import("../cameraframeops.zig").posFillFrameFromRotAndTarg;
pub const posFillFrameFromRotOverMeshes = @import("../cameraframeops.zig").posFillFrameFromRotOverMeshes;
pub const posFillFrameFromRotOverMeshesAndTarg = @import("../cameraframeops.zig").posFillFrameFromRotOverMeshesAndTarg;

// --------------------------------------------------------------------------------------
// Shader Input Construction
// --------------------------------------------------------------------------------------

pub const stageSource = @import("../shaderops.zig").stageSource;
pub const identityRGB = @import("../shaderops.zig").identityRGB;
pub const identityMulti = @import("../shaderops.zig").identityMulti;
pub const monoToPipeSource = @import("../shaderops.zig").monoToPipeSource;
pub const resolverIdentity = @import("../shaderops.zig").resolverIdentity;
pub const getScaleMax = @import("../imageops.zig").getScaleMax;
