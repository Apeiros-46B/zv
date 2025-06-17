const std = @import("std");
const sdl = @import("sdl2");

const Renderer = @import("renderer.zig");
const Self = @This();

window: sdl.Window,
renderer: Renderer,

pub fn init(alloc: std.mem.Allocator) !Self {
    var self: Self = undefined;

    try sdl.init(.{
        .video = true,
        .audio = true,
        .events = true,
    });
    errdefer sdl.quit();

    self.window = try sdl.createWindow(
        "Hello world!",
        .{ .centered = {} },
        .{ .centered = {} },
        640,
        480,
        .{ .vis = .shown, .resizable = true, .context = .vulkan },
    );
    errdefer self.window.destroy();

    self.renderer = try Renderer.init(alloc, &self.window);

    return self;
}

pub fn deinit(self: *Self) void {
    self.renderer.deinit();
    self.window.destroy();
    sdl.quit();
    self.* = undefined;
}

pub fn run(self: *Self) !void {
    var resize_requested = false;

    main: while (true) {
        while (sdl.pollEvent()) |ev| {
            switch (ev) {
                .quit => break :main,
                .window => |window_ev| {
                    if (window_ev.type == .resized) {
                        resize_requested = true;
                    }
                },
                else => {},
            }
        }
        if (resize_requested) {
           try self.renderer.resizeSwapchain();
           resize_requested = false;
        }
        try self.renderer.draw();
    }
}
