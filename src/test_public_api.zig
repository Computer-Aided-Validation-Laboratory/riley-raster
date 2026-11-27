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
    _ = riley.rasterInto;
    _ = riley.MeshInput;
    _ = riley.MeshType;
    _ = riley.Coords;
    _ = riley.Connect;
    _ = riley.Field;
    _ = riley.CameraInput;
    _ = riley.RasterConfig;
    _ = riley.DistortParams;
    _ = riley.BrownConParams;
    _ = riley.BrownConExtParams;
    _ = riley.ShaderPipeInput;
    _ = riley.FuncShaderBuiltin;
    _ = riley.ResolverInput;

    _ = maths.F;
    _ = maths.Vec3F;
    _ = maths.MatSlice;
    _ = maths.Rotation;

    _ = datio.SimData;
    _ = datio.UVMap;
    _ = datio.ImageSaveOpts;

    _ = ops.boundsCenter;
    _ = ops.lookAtPoint;
    _ = ops.stageSource;
    _ = ops.resolverIdentity;
}

test "public speckle variants use pattern-specific parameters" {
    const std = @import("std");
    const disk: riley.SpeckleParams = .{ .disk = riley.Disk2DParams{ .coverage = 0.5, .radius = 1, .edge_softness = 0.1 } };
    const gaussian: riley.SpeckleParams = .{ .gaussian = riley.Gaussian2DParams{ .coverage = 0.5, .radius = 1 } };
    try disk.validate();
    try gaussian.validate();
    try std.testing.expect(!@hasField(riley.Gaussian2DParams, "edge_softness"));
    try std.testing.expect(!@hasDecl(riley, "Dot2DParams"));
}

test "public 3D speckles use the same UV-free input for direct and pipe shaders" {
    const std = @import("std");
    const perlin: riley.Perlin3DParams = .{ .cell_size = 0.25 };
    const params: riley.Speckle3DParams = .{ .perlin = perlin };
    try params.validate();
    const input: riley.Speckle3DInput = .{ .params = params };
    const direct: riley.ShaderMonoInput = .{ .speckle3d = input };
    const source: riley.PipeSourceInput = .{ .speckle3d = input };
    try std.testing.expectEqualDeep(direct.speckle3d, source.speckle3d);
    try std.testing.expect(!@hasField(riley.Speckle3DInput, "uvs"));
}

test "public API excludes render implementation details" {
    const std = @import("std");
    try std.testing.expect(!@hasDecl(riley, "MeshStatic"));
    try std.testing.expect(!@hasDecl(riley, "rasterAdvanced"));
    try std.testing.expect(!@hasDecl(ops, "prepMeshFrame"));
    try std.testing.expect(!@hasDecl(ops, "sampLanes"));
    try std.testing.expect(!@hasDecl(ops, "selectShader"));
}

test "all maths types remain public" {
    const std = @import("std");
    inline for (.{ "F", "Vec2F", "Vec3F", "Vec2T", "Vec3T", "Vec2Ops", "Vec3Ops", "Mat22F", "Mat33F", "Mat44F", "MatSlice", "NDArray", "MappedNDArray", "Rotation" }) |name| {
        try std.testing.expect(@hasDecl(maths, name));
    }
}
