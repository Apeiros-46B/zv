// The world is rendered with parallax raymarching, where one brick (8^3 voxels) has its faces meshed.
// Bricks are part of chunks, which are 16 bricks in each dimension. Therefore, only four bits are needed to store
// each dimension of the vertex position.

const std = @import("std");

const Mesh = packed struct {
    verts: std.ArrayList(Vertex),
    idxs: [12]u4,
};

const Vertex = packed struct {
    x: u4,
    y: u4,
    z: u4,
    face: Face,
};

const Face = enum(u3) {
    up,
    down,
    north,
    east,
    south,
    west,
};

fn isVoxelSet(bitmask: [64]u64, x: usize, y: usize, z: usize) bool {
    const index: usize = x + y * 16 + z * 256;
    const u64_index = index >> 6;
    const bit_index = @as(u6, @truncate(index));
    return (bitmask[u64_index] >> bit_index) & 1 != 0;
}

pub fn generateVoxelMesh(list: *std.ArrayList(f32), bitmask: [64]u64) !void {
    const FaceDef = struct {
        dx: i32,
        dy: i32,
        dz: i32,
        corners: [4][3]f32,
    };

    const faces = [6]FaceDef{
        .{ // -X (left)
            .dx = -1,
            .dy = 0,
            .dz = 0,
            .corners = [4][3]f32{
                .{ 0.0, 0.0, 0.0 },
                .{ 0.0, 0.0, 1.0 },
                .{ 0.0, 1.0, 1.0 },
                .{ 0.0, 1.0, 0.0 },
            },
        },
        .{ // +X (right)
            .dx = 1,
            .dy = 0,
            .dz = 0,
            .corners = [4][3]f32{
                .{ 1.0, 0.0, 0.0 },
                .{ 1.0, 0.0, 1.0 },
                .{ 1.0, 1.0, 1.0 },
                .{ 1.0, 1.0, 0.0 },
            },
        },
        .{ // -Y (bottom)
            .dx = 0,
            .dy = -1,
            .dz = 0,
            .corners = [4][3]f32{
                .{ 0.0, 0.0, 0.0 },
                .{ 0.0, 0.0, 1.0 },
                .{ 1.0, 0.0, 1.0 },
                .{ 1.0, 0.0, 0.0 },
            },
        },
        .{ // +Y (top)
            .dx = 0,
            .dy = 1,
            .dz = 0,
            .corners = [4][3]f32{
                .{ 0.0, 1.0, 0.0 },
                .{ 0.0, 1.0, 1.0 },
                .{ 1.0, 1.0, 1.0 },
                .{ 1.0, 1.0, 0.0 },
            },
        },
        .{ // -Z (back)
            .dx = 0,
            .dy = 0,
            .dz = -1,
            .corners = [4][3]f32{
                .{ 0.0, 0.0, 0.0 },
                .{ 1.0, 0.0, 0.0 },
                .{ 1.0, 1.0, 0.0 },
                .{ 0.0, 1.0, 0.0 },
            },
        },
        .{ // +Z (front)
            .dx = 0,
            .dy = 0,
            .dz = 1,
            .corners = [4][3]f32{
                .{ 0.0, 0.0, 1.0 },
                .{ 0.0, 1.0, 1.0 },
                .{ 1.0, 1.0, 1.0 },
                .{ 1.0, 0.0, 1.0 },
            },
        },
    };

    for (0..16) |x| {
        for (0..16) |y| {
            for (0..16) |z| {
                if (!isVoxelSet(bitmask, x, y, z)) continue;

                for (faces) |face| {
                    const nx = @as(i32, @intCast(x)) + face.dx;
                    const ny = @as(i32, @intCast(y)) + face.dy;
                    const nz = @as(i32, @intCast(z)) + face.dz;

                    if (nx >= 0 and nx < 16 and ny >= 0 and ny < 16 and nz >= 0 and nz < 16) {
                        if (isVoxelSet(bitmask, @as(usize, @intCast(nx)), @as(usize, @intCast(ny)), @as(usize, @intCast(nz)))) {
                            continue;
                        }
                    }

                    const corners = face.corners;
                    const v0 = .{
                        @as(f32, @floatFromInt(x)) + corners[0][0],
                        @as(f32, @floatFromInt(y)) + corners[0][1],
                        @as(f32, @floatFromInt(z)) + corners[0][2],
                    };
                    const v1 = .{
                        @as(f32, @floatFromInt(x)) + corners[1][0],
                        @as(f32, @floatFromInt(y)) + corners[1][1],
                        @as(f32, @floatFromInt(z)) + corners[1][2],
                    };
                    const v2 = .{
                        @as(f32, @floatFromInt(x)) + corners[2][0],
                        @as(f32, @floatFromInt(y)) + corners[2][1],
                        @as(f32, @floatFromInt(z)) + corners[2][2],
                    };
                    const v3 = .{
                        @as(f32, @floatFromInt(x)) + corners[3][0],
                        @as(f32, @floatFromInt(y)) + corners[3][1],
                        @as(f32, @floatFromInt(z)) + corners[3][2],
                    };

                    try list.appendSlice(&v0);
                    try list.appendSlice(&v1);
                    try list.appendSlice(&v2);

                    try list.appendSlice(&v0);
                    try list.appendSlice(&v2);
                    try list.appendSlice(&v3);
                }
            }
        }
    }
}
