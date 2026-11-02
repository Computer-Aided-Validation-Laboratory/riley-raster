// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const riley = @import("riley");
const maths = riley.maths;
const datio = riley.dataio;
const ops = riley.ops;

test "public API surface is available through namespaces" {
    _ = riley.raster;
    _ = riley.rasterAdvanced;
    _ = riley.MeshInput;
    _ = riley.MeshType;
    _ = riley.Coords;
    _ = riley.Connect;
    _ = riley.Field;
    _ = riley.CameraInput;
    _ = riley.RasterConfig;
    _ = riley.DistortParams;
    _ = riley.BrownCon;
    _ = riley.BrownConExt;
    _ = riley.ShaderPipeInput;
    _ = riley.FuncShaderBuiltin;
    _ = riley.Resolver;

    _ = maths.F;
    _ = maths.Vec3F;
    _ = maths.MatSlice;
    _ = maths.Rotation;

    _ = datio.SimData;
    _ = datio.UVMap;
    _ = datio.ImageSaveOpts;

    _ = ops.boundsCenter;
    _ = ops.lookAtPoint;
    _ = ops.concreteTexture;
    _ = ops.calcElemNodeNormal;
}
