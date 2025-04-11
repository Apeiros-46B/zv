const std = @import("std");

const App = @import("app.zig");

pub fn main() !void {
    var alloc = std.heap.DebugAllocator(.{}).init;
    var app = try App.init(alloc.allocator());
    defer app.deinit();
    try app.run();
}
