// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

/// Removes previous demo output, creates missing parents, and opens the empty
/// output directory. The caller must close the returned directory with `io`.
/// Only relative paths without parent traversal are accepted. This resets the
/// named directory, not its parent or neighbouring demos' output.
pub fn resetOutputDir(io: std.Io, out_dir_root: []const u8) !std.Io.Dir {
    return resetOutputDirAt(std.Io.Dir.cwd(), io, out_dir_root);
}

fn resetOutputDirAt(parent: std.Io.Dir, io: std.Io, sub_path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(sub_path)) return error.InvalidOutputPath;
    var components = std.mem.tokenizeAny(u8, sub_path, "/\\");
    var has_name = false;
    while (components.next()) |component| {
        if (std.mem.eql(u8, component, "..")) return error.InvalidOutputPath;
        if (!std.mem.eql(u8, component, ".")) has_name = true;
    }
    if (!has_name) return error.InvalidOutputPath;

    parent.deleteTree(io, sub_path) catch |err| {
        if (err != error.FileNotFound) return err;
    };
    return parent.createDirPathOpen(io, sub_path, .{});
}

test "output reset creates nested parents and returns a usable directory" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var output = try resetOutputDirAt(tmp.dir, io, "out/demo");
    defer output.close(io);
    try output.writeFile(io, .{ .sub_path = "cameradata.csv", .data = "new output" });
    _ = try tmp.dir.statFile(io, "out/demo/cameradata.csv", .{});
}

test "output reset removes stale nested files and preserves siblings" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "out/demo/nested");
    try tmp.dir.writeFile(io, .{ .sub_path = "out/demo/nested/stale.bmp", .data = "stale" });
    try tmp.dir.writeFile(io, .{ .sub_path = "out/keep.csv", .data = "keep" });

    var output = try resetOutputDirAt(tmp.dir, io, "./out/demo");
    defer output.close(io);
    try std.testing.expectError(error.FileNotFound, output.statFile(io, "nested", .{}));
    _ = try tmp.dir.statFile(io, "out/keep.csv", .{});
}

test "output reset rejects unsafe paths before changing any files" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "keep.csv", .data = "keep" });

    const invalid_paths = [_][]const u8{ "", ".", "./", "/", "..", "out/..", "../demo" };
    for (invalid_paths) |path| {
        try std.testing.expectError(error.InvalidOutputPath, resetOutputDirAt(tmp.dir, io, path));
    }
    _ = try tmp.dir.statFile(io, "keep.csv", .{});
}

test "output reset propagates parent path errors" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "file", .data = "not a directory" });
    try std.testing.expectError(error.NotDir, resetOutputDirAt(tmp.dir, io, "file/demo"));
}
