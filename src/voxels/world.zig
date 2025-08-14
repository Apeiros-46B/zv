const std = @import("std");
const Self = @This();

regions: std.AutoHashMap(Coord, Region),

const Coord = struct {
    x: i64,
    y: i64,
    z: i64,
};

const Region = struct {
    chunks: [32*32*32]ChunkPtr,
    data: std.ArrayList(Chunk),
};

const ChunkPtr = packed struct {
    homogenous: bool,
    ptr: u15, // homogenous ? material : index into data
};

const Chunk = struct {
    bricks: [16*16*16]BrickPtr,
    data: std.ArrayList(Brick),
};

const BrickPtr = packed struct {
    loaded: bool,
    requested: bool,
    homogenous: bool,
    ptr: u12,
};

const Brick = struct {
    voxels: [8*8*8]Voxel,
};

const Voxel = packed struct {
    material: u12, // 4096 possible materials
    padding: u4, // can this be used for something?
};
