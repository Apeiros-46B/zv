const std = @import("std");

const log = @import("log.zig");

const Self = @This();

alloc: std.mem.Allocator,
regions: std.AutoHashMap(Coord, Region),

pub fn init(alloc: std.mem.Allocator) !Self {
    var self: Self = undefined;

    self.alloc = alloc;
    self.regions = std.AutoHashMap(Coord, Region).init(alloc);
    errdefer self.regions.deinit();

    const coord = Coord { .x = 0, .y = 0, .z = 0 };
    try self.regions.put(coord, try Region.init(alloc, coord));

    return self;
}

pub fn deinit(self: Self) void {
    var iter = self.regions.valueIterator();
    while (iter.next()) |region| {
        region.deinit();
    }
    @constCast(&self.regions).deinit();
}

pub const Coord = struct {
    x: i64,
    y: i64,
    z: i64,
};

// 32*32*32 chunks
pub const Region = struct {
    alloc: std.mem.Allocator,
    coord: Coord,
    chunkps: []ChunkPtr,
    data: std.ArrayList(Chunk),

    pub fn init(alloc: std.mem.Allocator, coord: Coord) !Region {
        var self: Region = undefined;

        self.alloc = alloc;
        self.coord = coord;
        self.chunkps = try alloc.alloc(ChunkPtr, 32*32*32);
        self.data = std.ArrayList(Chunk).init(alloc);

        try self.data.append(try Chunk.init(alloc));

        for (0..32*32*32) |i| {
            self.chunkps[i] = .{ .sparse = false, .ptr = 0 };
        }
        self.chunkps[0] = .{ .sparse = true, .ptr = 0 };
        self.chunkps[1] = .{ .sparse = true, .ptr = 0 };

        return self;
    }

    pub fn deinit(self: Region) void {
        for (self.data.items) |chunk| {
            chunk.deinit();
        }
        self.alloc.free(self.chunkps);
        self.data.deinit();
    }

    // returned coordinate is in brick lengths (coordinate system where brick is 1x1x1)
    pub fn chunkOfs(self: *const Region, i: usize) Coord {
        const x: i64 = @intCast(i % 32);
        const y: i64 = @intCast((i / 32) % 32);
        const z: i64 = @intCast(i / (32*32));
        return .{
            .x = x * 16 + self.coord.x * 512,
            .y = y * 16 + self.coord.y * 512,
            .z = z * 16 + self.coord.z * 512,
        };
    }
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
    bricks: std.ArrayListAligned(Brick, 4),
    mesh: Mesh,

    pub fn init(alloc: std.mem.Allocator) !Chunk {
        var self: Chunk = undefined;

        self.alloc = alloc;
        self.brickps = try alloc.alloc(BrickPtr, 16*16*16);
        self.bricks = std.ArrayListAligned(Brick, 4).init(alloc);
        self.mesh = Mesh.init(alloc);

        try self.bricks.append(Brick.initGrid(true));
        try self.bricks.append(Brick.initSphere());

        for (0..16) |x| {
            for (0..16) |y| {
                for (0..16) |z| {
                    var sparse: bool = true;
                    var ptr: u12 = undefined;

                    if (x % 2 == 0 and y % 2 == 0 and z % 2 == 0) {
                        ptr = 0;
                    } else if (x % 2 == 1 and y % 2 == 1 and z % 2 == 1 and x != 15 and y != 15 and z != 15) {
                        ptr = 1;
                    } else {
                        sparse = false;
                        ptr = 0;
                    }

                    self.brickps[Chunk.idx(x, y, z)] = .{
                        .loaded = false,
                        .requested = false,
                        .sparse = sparse,
                        .ptr = ptr,
                        .padding = false,
                    };
                }
            }
        }

        try self.remesh();

        return self;
    }

    pub fn deinit(self: Chunk) void {
        self.alloc.free(self.brickps);
        self.bricks.deinit();
        self.mesh.deinit();
    }

    // returns pointer to pairs of voxels
    pub fn getVoxels(self: *const Chunk) []align(1) const u32 {
        return @ptrCast(self.bricks.items.ptr[0..self.bricks.items.len]);
    }

    // pub fn numVoxels(self: *const Chunk) usize {
    //     return self.bricks.items.len * 512;
    // }

    pub fn get(self: *Chunk, x: usize, y: usize, z: usize) BrickPtr {
        return self.brickps[Chunk.idx(x, y, z)];
    }

    pub fn set(self: *Chunk, x: usize, y: usize, z: usize) void {
        var brickp = &self.brickps[Chunk.idx(x, y, z)];
        brickp.sparse = false;
        brickp.ptr = 1;
    }

    pub fn unset(self: *Chunk, x: usize, y: usize, z: usize) void {
        var brickp = &self.brickps[Chunk.idx(x, y, z)];
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

    pub fn debugPrint(self: *const Chunk) void {
        log.print(.debug, "Chunk", "#bricks={},#faces={}", .{ self.bricks.items.len, self.mesh.numFaces() });
    }

    fn idx(x: usize, y: usize, z: usize) usize {
        return x + 16 * y + 256 * z;
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

    fn initGrid(even: bool) Brick {
        var self: Brick = undefined;

        for (0..8) |x| {
            for (0..8) |y| {
                for (0..8) |z| {
                    var material: u12 = 0;
                    if (even) {
                        if (x % 2 == 0 and y % 2 == 0 and z % 2 == 0) {
                            material = 1;
                        }
                    } else {
                        if (x % 2 == 1 and y % 2 == 1 and z % 2 == 1) {
                            material = 1;
                        }
                    }
                    self.voxels[Brick.idx(x, y, z)] = .{
                        .material = material,
                        .padding = 0,
                    };
                }
            }
        }

        return self;
    }

    fn initSphere() Brick {
        var self: Brick = undefined;

        for (0..8) |x| {
            for (0..8) |y| {
                for (0..8) |z| {
                    const nx = @as(f32, @floatFromInt(x)) - 3.5;
                    const ny = @as(f32, @floatFromInt(y)) - 3.5;
                    const nz = @as(f32, @floatFromInt(z)) - 3.5;
                    var material: u12 = 0;
                    if (nx * nx + ny * ny + nz * nz < 16) {
                        material = 1;
                    }
                    self.voxels[Brick.idx(x, y, z)] = .{
                        .material = material,
                        .padding = 0,
                    };
                }
            }
        }

        return self;
    }

    fn init2x2() Brick {
        var self: Brick = undefined;

        for (0..8) |x| {
            for (0..8) |y| {
                for (0..8) |z| {
                    var material: u12 = 0;
                    if (x > 2 and x < 5 and y > 2 and y < 5 and z > 2 and z < 5) {
                        material = 1;
                    }
                    self.voxels[Brick.idx(x, y, z)] = .{
                        .material = material,
                        .padding = 0,
                    };
                }
            }
        }

        return self;
    }

    fn countVoxels(self: *const Brick) usize {
        var count: usize = 0;
        for (self.voxels) |v| {
            if (v.material != 0) {
                count += 1;
            }
        }
        return count;
    }

    fn idx(x: usize, y: usize, z: usize) usize {
        return x + 8 * y + 64 * z;
    }
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

    pub fn getFaces(self: *const Mesh) []align(1) const u32 {
        return @ptrCast(self.faces.items.ptr[0..self.faces.items.len]);
    }

    pub fn numFaces(self: *const Mesh) usize {
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

                        // const nx = @as(i32, @intCast(x)) + face.dx();
                        // const ny = @as(i32, @intCast(y)) + face.dy();
                        // const nz = @as(i32, @intCast(z)) + face.dz();
                        //
                        // if (nx >= 0 and nx < 16 and ny >= 0 and ny < 16 and nz >= 0 and nz < 16) {
                        //     if (chunk.isFull(@intCast(nx), @intCast(ny), @intCast(nz))) {
                        //         continue;
                        //     }
                        // }

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
        log.print(.debug, "Mesh", "face: ({}, {}, {}) {s}", .{ self.x, self.y, self.z, @tagName(self.face) });
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
