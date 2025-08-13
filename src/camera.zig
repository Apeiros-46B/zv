const std = @import("std");
const sdl = @import("sdl2");
const zlm = @import("zlm");

const util = @import("util.zig");
const InputState = @import("input.zig");
const Self = @This();

window: sdl.Window,

move_speed: f32,
rot_speed: f32,
fov: f32,

pos: zlm.Vec3,
dir: zlm.Vec3,
right: zlm.Vec3,

view: zlm.Mat4,
proj: zlm.Mat4,

const UP = zlm.vec3(0, 1, 0);

pub fn init(window: sdl.Window) Self {
    var self: Self = undefined;

    self.window = window;

    self.move_speed = 0.5;
    self.rot_speed = 1.0;
    self.fov = zlm.toRadians(45.0);

    self.pos = zlm.vec3(0, 0, 2);
    self.dir = self.pos.normalize().neg();
    self.right = UP.cross(self.dir.neg()).normalize();

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

    self.view = zlm.Mat4.createLook(self.pos, self.dir, UP);
}

pub fn resize(self: *Self) void {
    const size = self.window.getSize();
    self.proj = zlm.Mat4.createPerspective(self.fov, util.ratio(size.width, size.height), 0.1, 100.0);
}
