const std = @import("std");

const benchcommon = @import("common/benchcommon.zig");
const orch = @import("common/orchestration.zig");
const testcommon = @import("common/tests.zig");
const tcfg = @import("common/testconfig.zig");
const buildconfig = @import("zraster/zig/buildconfig.zig");
const meshio = @import("zraster/zig/meshio.zig");
const mo = @import("zraster/zig/meshops.zig");
const zraster = @import("zraster/zig/zraster.zig");

const simd_on = buildconfig.config.simd == .on;
const gold_root = if (simd_on)
    "gold/return_modes-simd"
else
    "gold/return_modes";

fn runCase(
    comptime T: type,
    allocator: std.mem.Allocator,
    io: std.Io,
    file_name: []const u8,
    abs_tol: f64,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const data_dir = "data/bench/tri3_sphere200";
    const coord_path = try std.fs.path.join(
        aa,
        &[_][]const u8{ data_dir, "coords.csv" },
    );
    const connect_path = try std.fs.path.join(
        aa,
        &[_][]const u8{ data_dir, "connect.csv" },
    );
    const field_path = try std.fs.path.join(
        aa,
        &[_][]const u8{ data_dir, "field.csv" },
    );

    const sim_data = try meshio.loadSimData(
        aa,
        io,
        coord_path,
        connect_path,
        null,
        null,
    );
    const field_raw = try benchcommon.loadNDArrayFromCSV(
        aa,
        io,
        field_path,
        1,
        true,
    );
    const camera = try orch.initCameraForCoords(
        aa,
        &sim_data.coords,
        .{ 320, 200 },
        1.0,
    );
    defer camera.deinit(aa);

    const mesh_input = mo.MeshInput{
        .mesh_type = .tri3,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = null,
        .shader = .{
            .nodal = .{
                .field = .{
                    .array = field_raw,
                    .array_mem = field_raw.slice,
                },
                .scaling = .auto,
            },
        },
    };

    var config = tcfg.getRasterConfig(.gold);
    config.save_strategy = .memory;
    config.report = .off;
    config.memory_image_scaling = .auto;

    const result = (try zraster.rasterAllFrames(
        T,
        aa,
        io,
        &[_]@TypeOf(camera.toInput()){camera.toInput()},
        &[_]mo.MeshInput{mesh_input},
        config,
        null,
        null,
    )) orelse return error.NoResult;
    defer {
        aa.free(result.slice);
        var result_mut = result;
        result_mut.deinit(aa);
    }

    const gold_path = try std.fs.path.join(
        aa,
        &[_][]const u8{ gold_root, file_name },
    );
    try testcommon.compareNDArrayToGoldTyped(
        T,
        aa,
        io,
        &result,
        0,
        0,
        0,
        1,
        gold_path,
        0.0,
        abs_tol,
    );
}

test "Return mode f64 gold matches" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    try runCase(f64, gpa.allocator(), std.testing.io, "tri3_sphere200_f64.fimg", 1e-11);
}

test "Return mode u8 gold matches" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    try runCase(u8, gpa.allocator(), std.testing.io, "tri3_sphere200_u8.csv", 0.0);
}

test "Return mode u16 gold matches" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    try runCase(u16, gpa.allocator(), std.testing.io, "tri3_sphere200_u16.csv", 0.0);
}
