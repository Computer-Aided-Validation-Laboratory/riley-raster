const std = @import("std");
const riley = @import("riley/zig/riley.zig");
const meshio = @import("riley/zig/meshio.zig");
const meshpipe = @import("riley/zig/meshpipeline.zig");
const shaderops = @import("riley/zig/shaderops.zig");
const shaderpipe = @import("riley/zig/shaderpipe.zig");
const camera = @import("riley/zig/camera.zig");
const cameraops = @import("riley/zig/cameraops.zig");
const sceneops = @import("riley/zig/sceneops.zig");
const Rotation = @import("riley/zig/rotation.zig").Rotation;
const F = @import("riley/zig/buildconfig.zig").F;

pub fn main(init: std.process.Init) !void {
    var coord_values = [_]F{ -1, -1, 0, 1, -1, 0, 0, 1, 0 };
    var connect_values = [_]usize{ 0, 1, 2 };
    const coords = meshio.Coords.init(&coord_values, 3);
    const checker: shaderops.ShaderDirectInput = .{ .func = .{
        .coord_mode = .world_reference,
        .builtin = .checker,
        .params = .{ .coord_scale = .{ 4, 4 }, .settings = .{ .checker = .{} } },
        .scaling = .auto,
    } };
    const channel = shaderpipe.Slot{ .kind = .channel, .index = 0 };
    const parameter = shaderpipe.Slot{ .kind = .parameter, .index = 0 };
    const stages = [_]shaderops.ShaderPipeStageInput{
        .{ .source = .{ .shader = checker, .destination = channel } },
        .{
            .source = .{
                .shader = .{
                    .func = .{
                        .coord_mode = .world_reference,
                        .builtin = .linear,
                        // x in [-1,1]: illumination rises from 0.25 to 1.0.
                        .params = .{ .settings = .{ .linear = .{ .coeffs = .{ 0.625, 0.375, 0 } } } },
                        .bits = null,
                        .scaling = .none,
                    },
                },
                .destination = parameter,
            },
        },
    };
    const sources = [_]shaderpipe.Slot{channel};
    const mesh = meshpipe.MeshInput{
        .mesh_type = .tri3opt,
        .coords = coords,
        .connect = meshio.Connect.init(&connect_values, 1, 3),
        .disp = null,
        .shaders = .{
            .direct = checker,
            .mono = .{ .stages = &stages, .resolver = .{ .modulate = .{ .sources = &sources, .factor = parameter } } },
        },
    };
    const pixels_num = [2]u32{ 512, 512 };
    const pixels_size = [2]F{ 0.02, 0.02 };
    const target = sceneops.boundsCenter(&coords);
    const rotation = Rotation.init(0, 0, 0);
    const position = cameraops.posFillFrameFromRotAndTarg(&coords, target, pixels_num, pixels_size, 1, rotation, 1);
    const direct_camera = camera.CameraInput{
        .pixels_num = pixels_num,
        .pixels_size = pixels_size,
        .pos_world = position,
        .rot_world = rotation,
        .roi_cent_world = target,
        .focal_length = 1,
        .sub_sample = 4,
    };
    var lit_camera = direct_camera;
    lit_camera.shader_selection = .mono;
    const config = riley.RasterConfig{
        .save_strategy = .disk,
        .output_name_format = "demo7_cam{camera}_frame{frame}_field{field}",
        .output = .{ .image_save_mode = .grey, .image_save_opts = &.{.{ .format = .bmp, .bits = 8, .scaling = .none }} },
    };
    const images = try riley.raster(init.gpa, init.io, &.{ direct_camera, lit_camera }, &.{mesh}, config, "./out/demo7_shaderpipe_quickstart");
    if (images) |image| {
        init.gpa.free(image.slice);
        image.deinit(init.gpa);
    }
}
