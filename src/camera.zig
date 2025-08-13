const std = @import("std");
const zlm = @import("zlm");

const Self = @This();

pos: zlm.Vec3,
idir: zlm.Vec3,

view: zlm.Mat4,
proj: zlm.Mat4,

time_start: i64,

const UP = zlm.vec3(0, 1, 0);
const CTR = zlm.vec3(0, 0, 0);

pub fn init() Self {
    var self: Self = undefined;

    self.pos = zlm.vec3(0, 0, 2);
    self.idir = self.pos.normalize();
    //const right = UP.cross(self.idir).normalize();

    self.time_start = std.time.milliTimestamp();

    return self;
}

pub fn resize(self: *Self, width: usize, height: usize) void {
    self.proj = zlm.Mat4.createPerspective(zlm.toRadians(45.0), @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height)), 0.1, 100.0);
}

pub fn update(self: *Self) void {
    var time: f32 = @floatFromInt(std.time.milliTimestamp() - self.time_start);
    time /= 500.0;

    const radius = 2.0;
    const x = std.math.sin(time) * radius;
    const y = std.math.cos(time) * radius;
    self.view = zlm.Mat4.createLookAt(zlm.vec3(x, 0.0, y), CTR, UP);
}
