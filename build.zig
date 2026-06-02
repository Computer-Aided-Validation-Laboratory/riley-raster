const std = @import("std");

const riley_version = std.SemanticVersion{
    .major = 2026,
    .minor = 5,
    .patch = 0,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("riley", .{
        .root_source_file = b.path("src/riley/zig/riley.zig"),
        .target = target,
        .optimize = optimize,
    });

    const shared_lib = addRileySharedLibrary(
        b,
        target,
        optimize,
    );
    b.installArtifact(shared_lib);
    _ = b.addInstallHeaderFile(
        b.path("src/riley/cyth/riley.h"),
        "riley.h",
    );

    const test_min_step = b.step("test-min", "Run the MIN test suite");
    test_min_step.dependOn(&addMinTestRunStep(
        b,
        target,
        optimize,
    ).step);
}

fn addRileySharedLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const shared_lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "riley",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/riley/zig/c-riley.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
        .version = riley_version,
    });
    return shared_lib;
}

fn addMinTestRunStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Run {
    const test_min = b.addTest(.{
        .name = "test-min",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_min.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    return b.addRunArtifact(test_min);
}
