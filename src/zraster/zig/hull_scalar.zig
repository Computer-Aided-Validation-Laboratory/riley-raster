const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const cfg = buildconfig.config;
const tol = buildconfig.config.tolerance;
const rops = @import("rasterops.zig");
const common = @import("hull_common.zig");
const Camera = @import("camera.zig").Camera;
const NDArray = @import("ndarray.zig").NDArray;
const Vec3Slices = rops.Vec3Slices;

pub const TessTriangle = struct {
    x: [3]f64,
    y: [3]f64,
};

pub fn Tessellation(comptime NT: usize) type {
    return struct {
        triangles: [NT]TessTriangle,

        pub inline fn isInScalar(self: @This(), px: f64, py: f64) bool {
            const eps = tol.hull.scalar_inclusion;
            inline for (self.triangles) |tri| {
                const e0 = rops.edgeFun3(tri.x[0], tri.y[0], tri.x[1], tri.y[1], px, py);
                const e1 = rops.edgeFun3(tri.x[1], tri.y[1], tri.x[2], tri.y[2], px, py);
                const e2 = rops.edgeFun3(tri.x[2], tri.y[2], tri.x[0], tri.y[0], px, py);
                if (e0 >= -eps and e1 >= -eps and e2 >= -eps) return true;
            }
            return false;
        }
    };
}

pub fn getTessellation(
    comptime N: usize,
    comptime NH: usize,
    comptime NT: usize,
    hull_x: []const f64,
    hull_y: []const f64,
) Tessellation(NT) {
    var tess = Tessellation(NT){ .triangles = undefined };

    if (N == 4) {
        // Quad4 hull: C0, C1, C2, C3
        tess.triangles[0] = .{
            .x = .{ hull_x[0], hull_x[1], hull_x[2] },
            .y = .{ hull_y[0], hull_y[1], hull_y[2] },
        };
        tess.triangles[1] = .{
            .x = .{ hull_x[0], hull_x[2], hull_x[3] },
            .y = .{ hull_y[0], hull_y[2], hull_y[3] },
        };
    } else if (N == 6 or N == 8 or N == 9) {
        var cx: f64 = 0;
        var cy: f64 = 0;
        inline for (0..NH) |ii| {
            cx += hull_x[ii];
            cy += hull_y[ii];
        }
        cx /= @as(f64, @floatFromInt(NH));
        cy /= @as(f64, @floatFromInt(NH));

        inline for (0..NH) |ii| {
            const jj = (ii + 1) % NH;
            tess.triangles[ii] = .{
                .x = .{ cx, hull_x[ii], hull_x[jj] },
                .y = .{ cy, hull_y[ii], hull_y[jj] },
            };
        }
    }
    return tess;
}

pub const buildAdaptiveHulls = common.buildAdaptiveHulls;
