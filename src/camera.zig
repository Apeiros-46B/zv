const std = @import("std");
const sdl = @import("sdl2");
const zlm = @import("zlm");

const log = @import("log.zig");
const util = @import("util.zig");
const InputState = @import("input.zig");
const Self = @This();

window: sdl.Window,
capture_cursor: bool,

move_speed: f32,
rot_speed: f32,
fov: f32,

// modified by input
pos: zlm.Vec3,
pitch: f32, // radians
yaw: f32,

// computed
dir: zlm.Vec3,
right: zlm.Vec3,
view: zlm.Mat4,
proj: zlm.Mat4,

const UP = zlm.vec3(0, 1, 0);

pub fn init(window: sdl.Window) Self {
    var self: Self = undefined;

    self.window = window;

    self.move_speed = 0.5;
    self.rot_speed = 0.05;
    self.fov = zlm.toRadians(45.0);

    self.pos = zlm.vec3(0, 0, 2);
    self.pitch = 0.0;
    self.yaw = 0.0;

    self.dir = zlm.Vec3.zero;
    self.right = zlm.Vec3.zero;
    self.view = zlm.Mat4.identity;
    self.proj = zlm.Mat4.identity;

    return self;
}

pub fn loop(self: *Self, dt: f32, input: *const InputState) void {
    const fac = self.move_speed * dt / 200.0;

    if (input.isPressed(.move_fwd)) {
        self.pos = self.pos.add(self.dir.scale(fac));
    }
    if (input.isPressed(.move_back)) {
        self.pos = self.pos.sub(self.dir.scale(fac));
    }
    if (input.isPressed(.move_left)) {
        self.pos = self.pos.sub(self.right.scale(fac));
    }
    if (input.isPressed(.move_right)) {
        self.pos = self.pos.add(self.right.scale(fac));
    }
    if (input.isPressed(.move_up)) {
        self.pos = self.pos.add(UP.scale(fac));
    }
    if (input.isPressed(.move_down)) {
        self.pos = self.pos.sub(UP.scale(fac));
    }
    if (input.isJustPressed(.capture_cursor)) {
        self.toggleCaptureCursor();
    }
    if (self.capture_cursor) {
        self.yaw += zlm.toRadians(input.mouse_motion.x * self.rot_speed * dt);
        self.pitch -= zlm.toRadians(input.mouse_motion.y * self.rot_speed * dt);
        self.pitch = std.math.clamp(self.pitch, -std.math.pi / 2.0, std.math.pi / 2.0);
    }

    // TODO: fix stuttery rotation
    self.dir.x = std.math.cos(self.yaw) * std.math.cos(self.pitch);
    self.dir.y = std.math.sin(self.pitch);
    self.dir.z = std.math.sin(self.yaw) * std.math.cos(self.pitch);
    self.right = UP.cross(self.dir.neg()).normalize();
    self.view = zlm.Mat4.createLook(self.pos, self.dir, UP);
}

pub fn resize(self: *Self) void {
    const size = self.window.getSize();
    self.proj = zlm.Mat4.createPerspective(self.fov, util.ratio(size.width, size.height), 0.1, 100.0);
}

fn toggleCaptureCursor(self: *Self) void {
    self.capture_cursor = !self.capture_cursor;
    var status: c_int = undefined;
    if (self.capture_cursor) {
        status = sdl.c.SDL_SetRelativeMouseMode(sdl.c.SDL_TRUE);
    } else {
        status = sdl.c.SDL_SetRelativeMouseMode(sdl.c.SDL_FALSE);
    }
    if (status != 0) {
        log.print(.err, "camera", "failed to toggle cursor capture", .{});
    }
}
