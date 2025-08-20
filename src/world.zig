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
    chunks: [32*32*32]ChunkPtr,
    data: std.ArrayList(Chunk),
};

pub const ChunkPtr = packed struct {
    sparse: bool,
    ptr: u15, // sparse ? index into data : material
};

// 16*16*16 bricks
pub const Chunk = struct {
    alloc: std.mem.Allocator,
    bricks: []BrickPtr,
    data: std.ArrayList(Brick),
    mesh: Mesh,

    pub fn init(alloc: std.mem.Allocator) !Chunk {
        var self: Chunk = undefined;

        self.alloc = alloc;
        self.bricks = try alloc.alloc(BrickPtr, 4096);
        self.data = std.ArrayList(Brick).init(alloc);
        self.mesh = Mesh.init(alloc);

        for (0..4095) |i| {
            self.bricks[i] = .{
                .loaded = false,
                .requested = false,
                .sparse = false,
                .ptr = 0,
            };
        }

        return self;
    }

    pub fn deinit(self: Chunk) void {
        self.alloc.free(self.bricks);
        self.data.deinit();
        self.mesh.deinit();
    }

    pub fn get(self: *Chunk, x: usize, y: usize, z: usize) BrickPtr {
        return self.bricks[x + y * 16 + z * 256];
    }

    pub fn set(self: *Chunk, x: usize, y: usize, z: usize) void {
        var brickp = &self.bricks[x + y * 16 + z * 256];
        brickp.sparse = false;
        brickp.ptr = 1;
    }

    pub fn unset(self: *Chunk, x: usize, y: usize, z: usize) void {
        var brickp = &self.bricks[x + y * 16 + z * 256];
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

// note that a brick that's completely filled but made of two separate materials is nonetheless considered 'sparse'. maybe this could be optimized in the future to just be rasterized with some kind of texture lookup instead of spending one raymarching step
pub const BrickPtr = packed struct {
    loaded: bool,
    requested: bool,
    sparse: bool,
    ptr: u12,
};

pub const Brick = struct {
    voxels: [8*8*8]Voxel,
};

pub const Voxel = packed struct {
    material: u12, // 4096 possible materials
    padding: u4, // can this be used for something?
};

pub const Mesh = struct {
    items: std.ArrayList(PackedFace),

    pub fn init(alloc: std.mem.Allocator) Mesh {
        var self: Mesh = undefined;
        self.items = std.ArrayList(PackedFace).init(alloc);
        return self;
    }

    pub fn deinit(self: Mesh) void {
        self.items.deinit();
    }

    pub fn data(self: *Mesh) [*]const u32 {
        return @ptrCast(self.items.items.ptr);
    }

    pub fn size(self: *Mesh) usize {
        return self.items.items.len;
    }

    fn add_face(self: *Mesh, x: usize, y: usize, z: usize, face: Face) !void {
        try self.items.append(.{
            .x = @as(u8, @intCast(x)),
            .y = @as(u8, @intCast(y)),
            .z = @as(u8, @intCast(z)),
            .face = face,
        });
    }

    pub fn generate(self: *Mesh, chunk: *Chunk) !void {
        self.items.clearRetainingCapacity();

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

                        try self.add_face(x, y, z, face);
                    }
                }
            }
        }

        // TODO: investigate why a mesh of two non-adjacent cubes contains 18 faces instead of 12
        log.print(.debug, "mesh", "faces: {}", .{ self.size() });
    }
};

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
