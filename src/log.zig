const std = @import("std");

const Cstr = [*:0]const u8;

const MAX_LEVEL = Severity.debug;

pub const Severity = enum(u2) {
    err   = 0,
    warn  = 1,
    info  = 2,
    debug = 3,

    fn ignored(self: Severity) bool {
        return @intFromEnum(self) > @intFromEnum(MAX_LEVEL);
    }
};
const SEVERITY_STR = [_]Cstr {
    "\x1b[1;31mERR\x1b[0m",
    "\x1b[1;33mWARN\x1b[0m",
    "\x1b[34mINFO\x1b[0m",
    "\x1b[37mDEBUG",
};

// modified version of std.log.defaultLog function that supports non-comptime
// severity level and scope
pub fn print(
    severity: Severity,
    scope: ?Cstr,
    comptime format: []const u8,
    args: anytype,
) void {
    if (severity.ignored()) return;

    const stderr = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stderr);
    const writer = bw.writer();

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    nosuspend {
        writer.print("{s}", .{ SEVERITY_STR[@intFromEnum(severity)] }) catch return;
        if (scope) |name| {
            writer.print("({s})", .{ name }) catch return;
        }
        writer.print(" " ++ format ++ "\x1b[0m\n", args) catch return;
        bw.flush() catch return;
    }
}
