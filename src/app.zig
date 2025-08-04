const std = @import("std");
const sdl = @import("sdl2");
const gl = @import("zgl");

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

    try sdl.gl.setAttribute(.{ .context_profile_mask = sdl.gl.Profile.core });
    try sdl.gl.setAttribute(.{ .context_major_version = 4 });
    try sdl.gl.setAttribute(.{ .context_minor_version = 1 });

    self.window = try sdl.createWindow(
        "Hello world!",
        .{ .centered = {} },
        .{ .centered = {} },
        640,
        480,
        .{ .vis = .shown, .resizable = true, .context = .opengl },
    );
    errdefer self.window.destroy();

    self.renderer = try Renderer.init(alloc, self.window);

    return self;
}

pub fn deinit(self: Self) void {
    self.renderer.deinit();
    self.window.destroy();
    sdl.quit();
}

pub fn run(self: *Self) !void {
    main: while (true) {
        while (sdl.pollEvent()) |ev| {
            switch (ev) {
                .quit => break :main,
                .window => |wev| switch (wev.type) {
                    .resized => self.renderer.resize(),
                    else => {},
                },
                else => {},
            }
        }
        try self.renderer.draw();
    }
}
