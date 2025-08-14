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

last_dt: f32,

const UP = zlm.vec3(0, 1, 0);

pub fn init(window: sdl.Window) Self {
    var self: Self = undefined;

    self.window = window;

    self.move_speed = 2.5;
    self.rot_speed = 5;
    self.fov = zlm.toRadians(45.0);

    self.pos = zlm.vec3(0, 0, 2);
    self.pitch = 0.0;
    self.yaw = 0.0;

    self.dir = zlm.Vec3.zero;
    self.right = zlm.Vec3.zero;
    self.view = zlm.Mat4.identity;
    self.proj = zlm.Mat4.identity;

    self.last_dt = 0.0;

    return self;
}

pub fn loop(self: *Self, dt: f32, input: *const InputState) void {
    const move_fac = self.move_speed * dt;

    if (input.isPressed(.move_fwd)) {
        self.pos = self.pos.add(self.dir.scale(move_fac));
    }
    if (input.isPressed(.move_back)) {
        self.pos = self.pos.sub(self.dir.scale(move_fac));
    }
    if (input.isPressed(.move_left)) {
        self.pos = self.pos.sub(self.right.scale(move_fac));
    }
    if (input.isPressed(.move_right)) {
        self.pos = self.pos.add(self.right.scale(move_fac));
    }
    if (input.isPressed(.move_up)) {
        self.pos = self.pos.add(UP.scale(move_fac));
    }
    if (input.isPressed(.move_down)) {
        self.pos = self.pos.sub(UP.scale(move_fac));
    }
    if (input.isJustPressed(.capture_cursor)) {
        self.toggleCaptureCursor();
    }

    self.view = zlm.Mat4.createLook(self.pos, self.dir, UP);
    self.last_dt = dt;
}

// we must use a handler for camera movement instead of using the centralized input system because
// SDL can send multiple mouse movements per frame (?) so using the centralized input system makes
// rotation stuttery and have high latency
pub fn onMouseMotion(self: *Self, dx: i32, dy: i32) void {
    if (!self.capture_cursor) {
        return;
    }

    self.yaw += zlm.toRadians(util.i2f(dx) * self.rot_speed * self.last_dt);
    self.pitch -= zlm.toRadians(util.i2f(dy) * self.rot_speed * self.last_dt);
    self.pitch = std.math.clamp(self.pitch, -std.math.pi / 2.0, std.math.pi / 2.0);

    self.dir.x = std.math.cos(self.yaw) * std.math.cos(self.pitch);
    self.dir.y = std.math.sin(self.pitch);
    self.dir.z = std.math.sin(self.yaw) * std.math.cos(self.pitch);
    self.right = UP.cross(self.dir.neg()).normalize();
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
