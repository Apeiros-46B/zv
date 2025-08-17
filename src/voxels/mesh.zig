// The world is rendered with parallax raymarching, where one brick (8^3 voxels) has its faces meshed.
// Bricks are part of chunks, which are 16 bricks in each dimension. Therefore, only four bits are needed to store
// each dimension of the vertex position.

const std = @import("std");

const util = @import("../util.zig");
const Self = @This();

positions: std.ArrayList(f32),
faces: std.ArrayList(Face),

pub fn init(alloc: std.mem.Allocator) Self {
    var self: Self = undefined;
    self.positions = std.ArrayList(f32).init(alloc);
    self.faces = std.ArrayList(Face).init(alloc);
    return self;
}

pub fn deinit(self: Self) void {
    self.positions.deinit();
    self.faces.deinit();
}

pub fn get_face_positions(self: *Self) []const f32 {
    return self.positions.items;
}

pub fn get_face_normals(self: *Self) []const u32 {
    return @ptrCast(self.faces.items);
}

pub fn size(self: *Self) usize {
    return self.faces.items.len;
}

fn add_face(self: *Self, x: usize, y: usize, z: usize, face: Face) !void {
    try self.positions.append(util.i2f(x));
    try self.positions.append(util.i2f(y));
    try self.positions.append(util.i2f(z));
    try self.faces.append(face);
}

pub const Face = enum(u32) {
    xp = 0,
    xn = 1,
    yp = 2,
    yn = 3,
    zp = 4,
    zn = 5,
};

pub fn generate(self: *Self, chunk: u4096) !void {
    const FaceDef = struct {
        dx: i32,
        dy: i32,
        dz: i32,
        face: Face,
    };

    const faces = [6]FaceDef{
        .{
            .dx = 1,
            .dy = 0,
            .dz = 0,
            .face = .xp,
        },
        .{
            .dx = -1,
            .dy = 0,
            .dz = 0,
            .face = .xn,
        },
        .{
            .dx = 0,
            .dy = 1,
            .dz = 0,
            .face = .yp,
        },
        .{
            .dx = 0,
            .dy = -1,
            .dz = 0,
            .face = .yn,
        },
        .{
            .dx = 0,
            .dy = 0,
            .dz = 1,
            .face = .zp,
        },
        .{
            .dx = 0,
            .dy = 0,
            .dz = -1,
            .face = .zn,
        },
    };

    for (0..16) |x| {
        for (0..16) |y| {
            for (0..16) |z| {
                if (!isVoxelSet(chunk, x, y, z)) continue;

                for (faces) |face| {
                    const nx = @as(i32, @intCast(x)) + face.dx;
                    const ny = @as(i32, @intCast(y)) + face.dy;
                    const nz = @as(i32, @intCast(z)) + face.dz;

                    if (nx >= 0 and nx < 16 and ny >= 0 and ny < 16 and nz >= 0 and nz < 16) {
                        if (isVoxelSet(chunk, @as(usize, @intCast(nx)), @as(usize, @intCast(ny)), @as(usize, @intCast(nz)))) {
                            continue;
                        }
                    }

                    try self.add_face(x, y, z, face.face);
                }
            }
        }
    }
}

fn isVoxelSet(mask: u4096, x: usize, y: usize, z: usize) bool {
    const idx: usize = x + y * 16 + z * 256;
    return (mask >> @intCast(idx)) & 1 != 0;
}
