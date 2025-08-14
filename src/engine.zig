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

pub fn init(alloc: std.mem.Allocator) !Self {
    var self: Self = undefined;

    self.alloc = alloc;

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

    self.input = InputState.init();
    self.camera = Camera.init(self.window);
    self.renderer = try Renderer.init(alloc, self.window);
    errdefer self.renderer.deinit();

    self.resize();
    self.time = std.time.nanoTimestamp();

    log.print(.debug, "engine", "init complete", .{});

    return self;
}

pub fn deinit(self: Self) void {
    self.renderer.deinit();
    self.window.destroy();
    sdl.quit();

    log.print(.debug, "engine", "deinit complete", .{});
}

pub fn run(self: *Self) !void {
    main: while (true) {
        while (sdl.pollEvent()) |ev| {
            switch (ev) {
                .quit => break :main,
                .window => |wev| switch (wev.type) {
                    .resized => self.resize(),
                    else => {},
                },
                .mouse_motion => |mev| self.camera.onMouseMotion(mev.delta_x, mev.delta_y),
                else => {},
            }
            self.input.handleEvent(ev);
        }

        const time = std.time.nanoTimestamp();
        const dt: f32 = util.ratio(time - self.time, 1_000_000_000); // in seconds

        self.camera.loop(dt, &self.input);
        try self.renderer.draw(&self.input, &self.camera);

        self.time = time;
        self.input.loopPost();
    }
}

fn resize(self: *Self) void {
    self.renderer.resize();
    self.camera.resize();
}
