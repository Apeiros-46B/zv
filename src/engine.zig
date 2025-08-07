const std = @import("std");
const sdl = @import("sdl2");
const gl = @import("zgl");

const log = @import("log.zig");

const Renderer = @import("renderer.zig");
const Self = @This();
const Thread = std.Thread;
const AtomicBool = std.atomic.Value(bool);

alloc: std.mem.Allocator,
window: sdl.Window,

should_resize: AtomicBool,
render_thread: ?Thread,
renderer: Renderer,

running: AtomicBool,
started: bool,

pub fn init(alloc: std.mem.Allocator, window: sdl.Window) !Self {
    var self: Self = undefined;

    self.alloc = alloc;
    self.window = window;

    self.should_resize = AtomicBool.init(false);
    self.render_thread = null;
    self.renderer = try Renderer.init(alloc, window, &self.should_resize);
    errdefer self.renderer.deinit();

    self.running = AtomicBool.init(true);
    self.started = false;

    return self;
}

pub fn deinit(self: Self) void {
    self.renderer.deinit();
}

pub fn loop(self: *Self) !void {
    if (!self.started) {
        try self.start();
    }
}

pub fn start(self: *Self) !void {
    self.started = true;
    self.render_thread = try std.Thread.spawn(.{}, renderLoop, .{
        self.alloc,
        self.window,
        &self.should_resize,
        &self.running,
    });

    log.print(.debug, "engine", "startup complete", .{});
}

pub fn stop(self: *Self) !void {
    self.running.store(false, .seq_cst);
    self.render_thread.?.join();

    log.print(.debug, "engine", "shutdown complete", .{});
}

fn renderLoop(
    alloc: std.mem.Allocator,
    window: sdl.Window,
    should_resize: *AtomicBool,
    running: *AtomicBool
) !void {
    var renderer = try Renderer.init(alloc, window, should_resize);
    defer renderer.deinit();

    log.print(.debug, "render", "startup complete", .{});

    while (running.load(.seq_cst)) {
        try renderer.draw();   
    }

    log.print(.debug, "render", "shutdown complete", .{});
}

pub fn handleEvent(self: *Self, ev: sdl.Event) !void {
    switch (ev) {
        .window => |wev| switch (wev.type) {
            .resized => self.should_resize.store(true, .seq_cst),
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
