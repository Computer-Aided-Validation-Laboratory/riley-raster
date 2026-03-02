const std = @import("std");
const print = std.debug.print;

pub const MeshType = enum {
    lin_tri,
    quad_tri,
};
