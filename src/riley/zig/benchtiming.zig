//! Opt-in, caller-thread timing hooks. No clock reads when capture is disabled.
const std = @import("std");
pub const Capture = struct {
    io: std.Io,
    resource_ns: i96 = 0,
};
pub threadlocal var active: ?*Capture = null;
pub fn start() ?std.Io.Timestamp {
    return if (active) |capture| std.Io.Timestamp.now(capture.io, .awake) else null;
}
pub fn resourceEnd(begin: ?std.Io.Timestamp) void {
    if (active) |capture| {
        capture.resource_ns += begin.?.durationTo(std.Io.Timestamp.now(capture.io, .awake)).nanoseconds;
    }
}
