const std = @import("std");
const gl = @import("zgl");

//const App = @import("app.zig");
const Engine = @import("engine.zig");

pub fn main() !void {
    var alloc = std.heap.DebugAllocator(.{}).init;
    var engine = try Engine.init(alloc.allocator());
    defer engine.deinit();
    try engine.run();
}
