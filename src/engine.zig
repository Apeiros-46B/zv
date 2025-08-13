const std = @import("std");
const sdl = @import("sdl2");
const zlm = @import("zlm");

const log = @import("log.zig");
const util = @import("util.zig");
const Renderer = @import("renderer.zig");
const Self = @This();

alloc: std.mem.Allocator,
window: sdl.Window,
renderer: Renderer,

time: i128, // nanoseconds

pub fn init(alloc: std.mem.Allocator, window: sdl.Window) !Self {
    var self: Self = undefined;

    self.alloc = alloc;
    self.window = window;
    self.renderer = try Renderer.init(alloc, window);
    errdefer self.renderer.deinit();

    self.time = std.time.nanoTimestamp();

    log.print(.debug, "engine", "init complete", .{});

    return self;
}

pub fn deinit(self: Self) void {
    self.renderer.deinit();

    log.print(.debug, "engine", "deinit complete", .{});
}

pub fn loop(self: *Self) !void {
    const time = std.time.nanoTimestamp();
    const dt: f32 = util.ratio(time - self.time, 1_000_000);

    try self.renderer.loop(dt);

    self.time = time;
}

pub fn handleEvent(self: *Self, ev: sdl.Event) !void {
    switch (ev) {
        .window => |wev| switch (wev.type) {
            .resized => self.renderer.resize(),
            else => {},
        },
        .key_down => |kev| try self.handleKeyDown(kev),
        .key_up => |kev| try self.handleKeyUp(kev),
        else => {},
    }
}

fn handleKeyDown(self: *Self, kev: sdl.KeyboardEvent) !void {
    if (kev.is_repeat) {
        return;
    }
    self.renderer.handleKeyDown(kev);
}

fn handleKeyUp(self: *Self, kev: sdl.KeyboardEvent) !void {
    self.renderer.handleKeyUp(kev);
}
