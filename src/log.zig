const std = @import("std");
const vk = @import("vulkan");

const cstr = [*:0]const u8;

const MAX_LEVEL = Severity.info;

pub const Severity = enum(u2) {
    err   = 0,
    warn  = 1,
    info  = 2,
    trace = 3,

    pub fn fromFlags(x: vk.DebugUtilsMessageSeverityFlagsEXT) Severity {
        if (x.error_bit_ext) {
            return .err;
        } else if (x.warning_bit_ext) {
            return .warn;
        } else if (x.verbose_bit_ext) {
            return .info;
        } else {
            return .trace;
        }
    }

    fn ignored(self: Severity) bool {
        return @intFromEnum(self) > @intFromEnum(MAX_LEVEL);
    }
};
const SEVERITY_STR = [_]cstr {
    "\x1b[1;31mEE\x1b[0m",
    "\x1b[1;33mWW\x1b[0m",
    "\x1b[34mII\x1b[0m",
    "\x1b[37m**",
};

pub fn print(
    severity: Severity,
    scope: ?cstr,
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
