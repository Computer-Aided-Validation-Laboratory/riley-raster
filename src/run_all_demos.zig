const std = @import("std");

const demo00_quickstart = @import("demo00_quickstart.zig");
const demo01_sphere = @import("demo01_sphere.zig");
const demo02a_rabbits_mono = @import("demo02a_rabbits_mono.zig");
const demo02b_rabbits_rgb = @import("demo02b_rabbits_rgb.zig");
const demo02c_rabbits_fields = @import("demo02c_rabbits_fields.zig");
const demo03_dicuq = @import("demo03_dicuq.zig");
const demo04_stereocal = @import("demo04_stereocal.zig");
const demo05_cameramodels = @import("demo05_cameramodels.zig");
const demo06_featurezoo = @import("demo06_featurezoo.zig");
const demo07_shaderpipe_quickstart = @import("demo07_shaderpipe_quickstart.zig");

const demo08_shaderpipe_gallery = @import("demo08_shaderpipe_gallery.zig");
const demo09_diciruq = @import("demo09_diciruq.zig");
const demo10_sphere_lit = @import("demo10_sphere_lit.zig");

pub fn main(init: std.process.Init) !void {
    try demo00_quickstart.main(init);
    try demo01_sphere.main(init);
    try demo02a_rabbits_mono.main(init);
    try demo02b_rabbits_rgb.main(init);
    try demo02c_rabbits_fields.main(init);
    try demo03_dicuq.main(init);
    try demo04_stereocal.main(init);
    try demo05_cameramodels.main(init);
    try demo06_featurezoo.main(init);
    try demo07_shaderpipe_quickstart.main(init);
    try demo08_shaderpipe_gallery.main(init);
    try demo09_diciruq.main(init);
    try demo10_sphere_lit.main(init);
}
