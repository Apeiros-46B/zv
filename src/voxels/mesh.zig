// The world is rendered with parallax raymarching, where one brick (8^3 voxels) has its faces meshed.
// Bricks are part of chunks, which are 16 bricks in each dimension. Therefore, only four bits are needed to store
// each dimension of the vertex position.

const std = @import("std");

const util = @import("../util.zig");
const Self = @This();

items: std.ArrayList(PackedFace),

pub fn init(alloc: std.mem.Allocator) Self {
    var self: Self = undefined;
    self.items = std.ArrayList(PackedFace).init(alloc);
    return self;
}

pub fn deinit(self: Self) void {
    self.items.deinit();
}

pub fn data(self: *Self) [*]const u32 {
    return @ptrCast(self.items.items.ptr);
}

pub fn size(self: *Self) usize {
    return self.items.items.len;
}

fn add_face(self: *Self, x: usize, y: usize, z: usize, face: Face) !void {
    try self.items.append(.{
        .x = @as(u8, @intCast(x)),
        .y = @as(u8, @intCast(y)),
        .z = @as(u8, @intCast(z)),
        .face = face,
    });
}

pub const PackedFace = packed struct {
    x: u8,
    y: u8,
    z: u8,
    face: Face,
};

pub const Face = enum(u8) {
    xp = 0,
    xn = 1,
    yp = 2,
    yn = 3,
    zp = 4,
    zn = 5,

    fn dx(self: Face) i32 {
        return switch (self) {
            .xp => 1,
            .xn => -1,
            .yp => 0,
            .yn => 0,
            .zp => 0,
            .zn => 0,
        };
    }

    fn dy(self: Face) i32 {
        return switch (self) {
            .xp => 0,
            .xn => 0,
            .yp => 1,
            .yn => -1,
            .zp => 0,
            .zn => 0,
        };
    }

    fn dz(self: Face) i32 {
        return switch (self) {
            .xp => 0,
            .xn => 0,
            .yp => 0,
            .yn => 0,
            .zp => 1,
            .zn => -1,
        };
    }
};

pub fn generate(self: *Self, chunk: u4096) !void {
    self.items.clearRetainingCapacity();

    for (0..16) |x| {
        for (0..16) |y| {
            for (0..16) |z| {
                if (!isVoxelSet(chunk, x, y, z)) continue;

                for (0..6) |i| {
                    const face: Face = @enumFromInt(i);

                    // TODO: don't cull adjacent faces when they are adjacent to a sparse brick
                    // const nx = @as(i32, @intCast(x)) + face.dx();
                    // const ny = @as(i32, @intCast(y)) + face.dy();
                    // const nz = @as(i32, @intCast(z)) + face.dz();

                    // if (nx >= 0 and nx < 16 and ny >= 0 and ny < 16 and nz >= 0 and nz < 16) {
                    //     if (isVoxelSet(chunk, @intCast(nx), @intCast(ny), @intCast(nz))) {
                    //         continue;
                    //     }
                    // }

                    try self.add_face(x, y, z, face);
                }
            }
        }
    }
}

fn isVoxelSet(mask: u4096, x: usize, y: usize, z: usize) bool {
    const idx: usize = x + y * 16 + z * 256;
    return (mask >> @intCast(idx)) & 1 != 0;
}
