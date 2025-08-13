const std = @import("std");
const sdl = @import("sdl2");
const zlm = @import("zlm");

const util = @import("util.zig");
const Self = @This();

movement: MovementState,

move_speed: f32,
rot_speed: f32,
fov: f32,

pos: zlm.Vec3,
dir: zlm.Vec3,
right: zlm.Vec3,

view: zlm.Mat4,
proj: zlm.Mat4,

const UP = zlm.vec3(0, 1, 0);

pub fn init() Self {
    var self: Self = undefined;

    self.movement = MovementState.initEmpty();

    self.move_speed = 0.5;
    self.rot_speed = 1.0;
    self.fov = zlm.toRadians(45.0);

    self.pos = zlm.vec3(0, 0, 2);
    self.dir = self.pos.normalize().neg();
    self.right = UP.cross(self.dir.neg()).normalize();

    return self;
}

pub fn resize(self: *Self, width: usize, height: usize) void {
    self.proj = zlm.Mat4.createPerspective(self.fov, util.ratio(width, height), 0.1, 100.0);
}

pub fn loop(self: *Self, dt: f32) void {
    self.movement.apply(&self.pos, self.dir, UP, self.right, self.move_speed * dt / 200.0);
    self.view = zlm.Mat4.createLook(self.pos, self.dir, UP);
}

pub fn handleKeyDown(self: *Self, kev: sdl.KeyboardEvent) void {
    switch (kev.scancode) {
        .w => self.movement.fwd = true,
        .a => self.movement.left = true,
        .s => self.movement.back = true,
        .d => self.movement.right = true,
        .space => self.movement.up = true,
        .left_shift => self.movement.down = true,
        else => {},
    }
}

pub fn handleKeyUp(self: *Self, kev: sdl.KeyboardEvent) void {
    switch (kev.scancode) {
        .w => self.movement.fwd = false,
        .a => self.movement.left = false,
        .s => self.movement.back = false,
        .d => self.movement.right = false,
        .space => self.movement.up = false,
        .left_shift => self.movement.down = false,
        else => {},
    }
}

const MovementState = packed struct {
    fwd: bool,
    left: bool,
    back: bool,
    right: bool,
    up: bool,
    down: bool,

    fn initEmpty() MovementState {
        return .{
            .fwd = false,
            .left = false,
            .back = false,
            .right = false,
            .up = false,
            .down = false,
        };
    }

    fn apply(self: MovementState, pos: *zlm.Vec3, fwd: zlm.Vec3, up: zlm.Vec3, right: zlm.Vec3, fac: f32) void {
        if (self.fwd) {
            pos.* = pos.add(fwd.scale(fac));
        }
        if (self.back) {
            pos.* = pos.sub(fwd.scale(fac));
        }

        if (self.left) {
            pos.* = pos.sub(right.scale(fac));
        }
        if (self.right) {
            pos.* = pos.add(right.scale(fac));
        }

        if (self.up) {
            pos.* = pos.add(up.scale(fac));
        }
        if (self.down) {
            pos.* = pos.sub(up.scale(fac));
        }
    }
};
