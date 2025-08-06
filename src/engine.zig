const std = @import("std");
const sdl = @import("sdl2");
const gl = @import("zgl");

const log = @import("log.zig");

const Renderer = @import("renderer.zig");
const Self = @This();

alloc: std.mem.Allocator,
window: sdl.Window,

renderer: Renderer,
started: bool,
time: i128,

pub fn init(alloc: std.mem.Allocator, window: sdl.Window) !Self {
    var self: Self = undefined;

    self.alloc = alloc;
    self.window = window;

    self.renderer = try Renderer.init(alloc, window);
    errdefer self.renderer.deinit();

    self.started = false;
    self.time = std.time.nanoTimestamp();

    return self;
}

pub fn deinit(self: Self) void {
    self.renderer.deinit();
}

pub fn loop(self: *Self) !void {
    if (!self.started) {
        try self.start();
    }

    // const now = std.time.nanoTimestamp();
    // const dt = now - self.time;

    // try self.renderer.draw();   

    // self.time = now;
}

pub fn start(self: *Self) !void {
    self.started = true;

    const render_thread = try std.Thread.spawn(.{}, renderLoop, .{ self.alloc, self.window });
    render_thread.detach();
}

pub fn stop(self: *Self) !void {
    _ = self;
}

fn renderLoop(alloc: std.mem.Allocator, window: sdl.Window) !void {
    // var time = std.time.nanoTimestamp();
    var renderer = try Renderer.init(alloc, window);
    defer renderer.deinit();

    // TODO: fix segfault when closing the app. need to end this loop somehow, so we need a cross-thread communication mechanism like a channel or condvar
    while (true) {
        // const now = std.time.nanoTimestamp();
        // const dt = now - time;

        try renderer.draw();   
        // log.print(.debug, "render", "dt: {}", .{ dt });

        // time = now;
    }
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
