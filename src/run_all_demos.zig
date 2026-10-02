const std = @import("std");

const demo0_quickstart = @import("demo0_quickstart.zig");
const demo1_sphere = @import("demo1_sphere.zig");
const demo2a_rabbits_mono = @import("demo2a_rabbits_mono.zig");
const demo2b_rabbits_rgb = @import("demo2b_rabbits_rgb.zig");
const demo2c_rabbits_fields = @import("demo2c_rabbits_fields.zig");
const demo3_dicuq = @import("demo3_dicuq.zig");
const demo4_stereocal = @import("demo4_stereocal.zig");
const demo5_cameramodels = @import("demo5_cameramodels.zig");
const demo6_featurezoo = @import("demo6_featurezoo.zig");

pub fn main(init: std.process.Init) !void {
    try demo0_quickstart.main(init);
    try demo1_sphere.main(init);
    try demo2a_rabbits_mono.main(init);
    try demo2b_rabbits_rgb.main(init);
    try demo2c_rabbits_fields.main(init);
    try demo3_dicuq.main(init);
    try demo4_stereocal.main(init);
    try demo5_cameramodels.main(init);
    try demo6_featurezoo.main(init);
}
