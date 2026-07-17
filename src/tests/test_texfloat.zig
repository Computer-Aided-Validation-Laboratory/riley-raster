// --------------------------------------------------------------------------
// Float texture shader regression coverage for the all suite.
// --------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("../riley/zig/buildconfig.zig");
const ndarray = @import("../riley/zig/ndarray.zig");
const shaderops = @import("../riley/zig/shaderops.zig");
const texops = @import("../riley/zig/textureops.zig");

const F = buildconfig.F;

test "float texture shader variants preserve fractional texels" {
    const allocator = std.testing.allocator;

    var grey = try texops.Tex(F, 1).init(allocator, 2, 2);
    defer grey.deinit(allocator);
    grey.setVal(0, 0, 0, 0.125);
    grey.setVal(0, 0, 1, 0.375);
    grey.setVal(0, 1, 0, 0.625);
    grey.setVal(0, 1, 1, 0.875);

    var rgb = try texops.Tex(F, 3).init(allocator, 1, 1);
    defer rgb.deinit(allocator);
    rgb.setVal(0, 0, 0, 0.125);
    rgb.setVal(1, 0, 0, 0.5);
    rgb.setVal(2, 0, 0, 0.875);

    const sampled = texops.sampScal(1, .{ .sample = .linear }, grey, 0.5, 0.5);
    try std.testing.expectEqual(@as(F, 0.5), sampled[0]);

    var uvs = try ndarray.NDArray(F).initFlat(allocator, &.{ 3, 2 });
    defer uvs.deinit(allocator);

    const grey_shader: shaderops.ShaderInput = .{ .tex_f = .{
        .uvs = uvs,
        .tex = grey,
        .samp_cfg = .{ .sample = .linear },
    } };
    const rgb_shader: shaderops.ShaderInput = .{ .tex_rgb_f = .{
        .uvs = uvs,
        .tex = rgb,
        .samp_cfg = .{ .sample = .nearest },
    } };

    switch (grey_shader) {
        .tex_f => |shader| try std.testing.expectEqual(@as(F, 0.125), shader.tex.getVal(0, 0, 0)),
        else => unreachable,
    }
    switch (rgb_shader) {
        .tex_rgb_f => |shader| try std.testing.expectEqual(@as(F, 0.875), shader.tex.getVal(2, 0, 0)),
        else => unreachable,
    }
}
