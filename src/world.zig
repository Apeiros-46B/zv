const std = @import("std");

const log = @import("log.zig");

const Self = @This();

regions: std.AutoHashMap(Coord, Region),

pub const Coord = struct {
    x: i64,
    y: i64,
    z: i64,
};

// 32*32*32 chunks
pub const Region = struct {
    chunks: [32 * 32 * 32]ChunkPtr,
    data: std.ArrayList(Chunk),
};

pub const ChunkPtr = packed struct {
    sparse: bool,
    ptr: u15, // sparse ? index into data : material
};

// 16*16*16 bricks
// TODO: figure out how to get/set individual voxels within bricks quickly without duplicating bricks
pub const Chunk = struct {
    alloc: std.mem.Allocator,
    brickps: []BrickPtr,
    bricks: std.ArrayList(Brick),
    mesh: Mesh,

    pub fn init(alloc: std.mem.Allocator) !Chunk {
        var self: Chunk = undefined;

        self.alloc = alloc;
        self.brickps = try alloc.alloc(BrickPtr, 4096);
        self.bricks = std.ArrayList(Brick).init(alloc);
        self.mesh = Mesh.init(alloc);

        for (0..4096) |i| {
            self.brickps[i] = .{
                .loaded = false,
                .requested = false,
                .sparse = false,
                .ptr = 0,
                .padding = false,
            };
        }

        return self;
    }

    pub fn deinit(self: Chunk) void {
        self.alloc.free(self.brickps);
        self.bricks.deinit();
        self.mesh.deinit();
    }

    // TODO: fix alignment issue and find out how to index from fsh
    // pub fn getBricks(self: *Chunk) [*]const u32 {
    //     return @ptrCast(self.bricks.items.ptr);
    // }

    pub fn numBricks(self: *Chunk) usize {
        return self.bricks.items.len;
    }

    pub fn get(self: *Chunk, x: usize, y: usize, z: usize) BrickPtr {
        return self.brickps[x + y * 16 + z * 256];
    }

    pub fn set(self: *Chunk, x: usize, y: usize, z: usize) void {
        var brickp = &self.brickps[x + y * 16 + z * 256];
        brickp.sparse = false;
        brickp.ptr = 1;
    }

    pub fn unset(self: *Chunk, x: usize, y: usize, z: usize) void {
        var brickp = &self.brickps[x + y * 16 + z * 256];
        brickp.sparse = false;
        brickp.ptr = 0;
    }

    pub fn isSet(self: *Chunk, x: usize, y: usize, z: usize) bool {
        const brickp = self.get(x, y, z);
        return brickp.sparse or brickp.ptr != 0; // sparse bricks can never be empty
    }

    pub fn isFull(self: *Chunk, x: usize, y: usize, z: usize) bool {
        const brickp = self.get(x, y, z);
        return !brickp.sparse and brickp.ptr != 0;
    }

    pub fn remesh(self: *Chunk) !void {
        try self.mesh.generate(self);
    }
};

// note that a brick that's completely filled but made of multiple separate materials is nonetheless considered 'sparse'. maybe this could be optimized in the future to just be rasterized with some kind of texture lookup instead of spending one raymarching step
pub const BrickPtr = packed struct {
    loaded: bool,
    requested: bool,
    sparse: bool,
    ptr: u12,
    padding: bool,
};

pub const Brick = struct {
    voxels: [8 * 8 * 8]Voxel,
};

pub const Voxel = packed struct {
    material: u12, // 4096 possible materials
    padding: u4, // can this be used for something?
};

pub const Mesh = struct {
    faces: std.ArrayList(PackedFace),

    pub fn init(alloc: std.mem.Allocator) Mesh {
        var self: Mesh = undefined;
        self.faces = std.ArrayList(PackedFace).init(alloc);
        return self;
    }

    pub fn deinit(self: Mesh) void {
        self.faces.deinit();
    }

    pub fn getFaces(self: *Mesh) [*]const u32 {
        return @ptrCast(self.faces.items.ptr);
    }

    pub fn numFaces(self: *Mesh) usize {
        return self.faces.items.len;
    }

    fn add_face(self: *Mesh, chunk: *Chunk, x: usize, y: usize, z: usize, face: Face) !void {
        try self.faces.append(.{
            .x = @as(u4, @intCast(x)),
            .y = @as(u4, @intCast(y)),
            .z = @as(u4, @intCast(z)),
            .face = face,
            .brickp = chunk.get(x, y, z),
        });
    }

    // basic culled mesher
    fn generate(self: *Mesh, chunk: *Chunk) !void {
        self.faces.clearRetainingCapacity();

        for (0..16) |x| {
            for (0..16) |y| {
                for (0..16) |z| {
                    if (!chunk.isSet(x, y, z)) continue;

                    for (0..6) |i| {
                        const face: Face = @enumFromInt(i);

                        const nx = @as(i32, @intCast(x)) + face.dx();
                        const ny = @as(i32, @intCast(y)) + face.dy();
                        const nz = @as(i32, @intCast(z)) + face.dz();

                        if (nx >= 0 and nx < 16 and ny >= 0 and ny < 16 and nz >= 0 and nz < 16) {
                            if (chunk.isFull(@intCast(nx), @intCast(ny), @intCast(nz))) {
                                continue;
                            }
                        }

                        try self.add_face(chunk, x, y, z, face);
                    }
                }
            }
        }
    }
};

pub const PackedFace = packed struct {
    x: u4,
    y: u4,
    z: u4,
    face: Face,
    brickp: BrickPtr,

    fn debugPrint(self: PackedFace) void {
        log.print(.debug, "mesh", "face: ({}, {}, {}) {s}", .{ self.x, self.y, self.z, @tagName(self.face) });
    }
};

pub const Face = enum(u4) {
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
