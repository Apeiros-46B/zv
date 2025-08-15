// The world is rendered with parallax raymarching, where one brick (8^3 voxels) has its faces meshed.
// Bricks are part of chunks, which are 16 bricks in each dimension. Therefore, only four bits are needed to store
// each dimension of the vertex position.

const std = @import("std");

const Mesh = packed struct {
    vertices: std.ArrayList(Vertex),
    indices: [12]u4,
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
