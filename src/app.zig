const std = @import("std");
const sdl = @import("sdl2");

const VulkanCtx = @import("vk.zig");
const Self = @This();

window: sdl.Window,
vk: VulkanCtx,

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
        .{ .vis = .shown, .context = .vulkan },
    );
    errdefer self.window.destroy();

    self.vk = try VulkanCtx.init(alloc, &self.window);

    return self;
}

pub fn deinit(self: *Self) void {
    self.vk.deinit();
    self.window.destroy();
    sdl.quit();
    self.* = undefined;
}

pub fn run(self: *Self) !void {
    main: while (true) {
        while (sdl.pollEvent()) |ev| {
            switch (ev) {
                .quit => break :main,
                else => {},
            }
        }

        try self.vk.presentFrame();
    }
}
