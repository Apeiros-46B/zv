const std = @import("std");
const sdl = @import("sdl2");
const zlm = @import("zlm");

const log = @import("log.zig");

const Renderer = @import("renderer.zig");
const Self = @This();
const Thread = std.Thread;
const AtomicBool = std.atomic.Value(bool);

alloc: std.mem.Allocator,
window: sdl.Window,
renderer: Renderer,

pub fn init(alloc: std.mem.Allocator, window: sdl.Window) !Self {
    var self: Self = undefined;

    self.alloc = alloc;
    self.window = window;
    self.renderer = try Renderer.init(alloc, window);
    errdefer self.renderer.deinit();

    log.print(.debug, "engine", "init complete", .{});

    return self;
}

pub fn deinit(self: Self) void {
    self.renderer.deinit();

    log.print(.debug, "engine", "deinit complete", .{});
}

pub fn loop(self: *Self) !void {
    try self.renderer.draw();
}

pub fn handleEvent(self: *Self, ev: sdl.Event) !void {
    switch (ev) {
        .window => |wev| switch (wev.type) {
            .resized => self.renderer.resize(),
            else => {},
        },
        .key_down => |kev| try self.handleKeyDown(kev),
        else => {},
    }
}

fn handleKeyDown(self: *Self, kev: sdl.KeyboardEvent) !void {
    if (kev.is_repeat) {
        return;
    }
    switch (kev.keycode) {
        .r => self.renderer.reloadShaders(),
        else => {},
    }
}
