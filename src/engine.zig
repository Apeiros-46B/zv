const std = @import("std");
const sdl = @import("sdl2");
const zlm = @import("zlm");

const log = @import("log.zig");
const util = @import("util.zig");
const InputState = @import("input.zig");
const Camera = @import("camera.zig");
const Renderer = @import("renderer.zig");
const Self = @This();

alloc: std.mem.Allocator,
window: sdl.Window,
input: InputState,
camera: Camera,
renderer: Renderer,

time: i128, // nanoseconds

pub fn init(alloc: std.mem.Allocator, window: sdl.Window) !Self {
    var self: Self = undefined;

    self.alloc = alloc;
    self.window = window;
    self.input = InputState.init();
    self.camera = Camera.init(window);
    self.renderer = try Renderer.init(alloc, window);

    self.resize();
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

    self.camera.loop(dt, &self.input);
    try self.renderer.draw(&self.input, &self.camera);

    self.time = time;
    self.input.loopPost();
}

pub fn handleEvent(self: *Self, ev: sdl.Event) !void {
    switch (ev) {
        .window => |wev| switch (wev.type) {
            .resized => self.resize(),
            else => {},
        },
        .mouse_button_down => |mev| self.input.handleMouseBtnDown(mev),
        .mouse_button_up => |mev| self.input.handleMouseBtnUp(mev),
        //.mouse_motion => |mev| self.input.handleMouseMotion(mev),
        .key_down => |kev| self.input.handleKeyDown(kev),
        .key_up => |kev| self.input.handleKeyUp(kev),
        else => {},
    }
}

fn resize(self: *Self) void {
    self.renderer.resize();
    self.camera.resize();
}
