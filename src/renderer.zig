const std = @import("std");
const sdl = @import("sdl2");
const gl = @import("zgl");
const zlm = @import("zlm");

const log = @import("log.zig");
const util = @import("util.zig");
const meshing = @import("voxels/mesh.zig");
const Camera = @import("camera.zig");
const InputState = @import("input.zig");
const Self = @This();

alloc: std.mem.Allocator,
window: sdl.Window,
mesh: std.ArrayList(f32),

gl_ctx: sdl.gl.Context,
vao: gl.VertexArray,
vbo: gl.Buffer,

scr_size: zlm.Vec2,
pass: ShaderPass,

fn createSingleVoxelBitmask(x: usize, y: usize, z: usize) [64]u64 {
    const index = x + y * 16 + z * 256;
    const u64_index = index >> 6;
    const bit_index = @as(u6, @truncate(index));
    var bitmask = [_]u64{0} ** 64;
    bitmask[u64_index] = @as(u64, 1) << bit_index;
    return bitmask;
}

fn coordsToBitmask(coords: []const [3]usize) [64]u64 {
    var bitmask = [_]u64{0} ** 64;
    for (coords) |pos| {
        const x = pos[0];
        const y = pos[1];
        const z = pos[2];
        const index = x + y * 16 + z * 256;
        const u64_index = index >> 6;
        const bit_index = @as(u6, @truncate(index));
        bitmask[u64_index] |= @as(u64, 1) << bit_index;
    }
    return bitmask;
}

fn getProcAddressWrapper(comptime _: type, sym: [:0]const u8) ?*const anyopaque {
    return sdl.gl.getProcAddress(sym);
}

pub fn init(alloc: std.mem.Allocator, window: sdl.Window) !Self {
    var self: Self = undefined;

    self.alloc = alloc;
    self.window = window;
    self.mesh = std.ArrayList(f32).init(alloc);
    errdefer self.mesh.deinit();

    var list = std.ArrayList([3]usize).init(alloc);
    defer list.deinit();
    for (0..5) |x| {
        for (0..5) |z| {
            try list.append(.{ x * 2, 0, z * 2 });
        }
    }
    try meshing.generateVoxelMesh(
        &self.mesh,
        coordsToBitmask(list.items),
    );
    // log.print(.debug, "renderer", "mesh: {any}", .{self.mesh.items});

    self.gl_ctx = try sdl.gl.createContext(window);
    errdefer self.gl_ctx.delete();
    try self.gl_ctx.makeCurrent(window);
    log.print(.debug, "renderer", "context loaded", .{});

    try sdl.gl.setSwapInterval(.immediate);

    try gl.loadExtensions(void, getProcAddressWrapper);
    log.print(.debug, "renderer", "extensions loaded", .{});

    self.vao = gl.VertexArray.create();
    errdefer self.vao.delete();
    log.print(.debug, "renderer", "vao created", .{});

    self.vbo = gl.Buffer.create();
    errdefer self.vbo.delete();
    log.print(.debug, "renderer", "vbo created", .{});

    self.vao.bind();
    self.vbo.bind(.array_buffer);
    self.vbo.data(f32, self.mesh.items, .static_draw);
    gl.vertexAttribPointer(0, 3, .float, false, 3 * @sizeOf(f32), 0);
    gl.enableVertexAttribArray(0);

    gl.enable(.depth_test);
    gl.depthFunc(.less);

    self.pass = try ShaderPass.init(alloc);

    log.print(.debug, "renderer", "init complete", .{});

    return self;
}

pub fn deinit(self: Self) void {
    self.mesh.deinit();
    self.pass.deinit();
    self.vbo.delete();
    self.vao.delete();
    self.gl_ctx.delete();

    log.print(.debug, "renderer", "deinit complete", .{});
}

pub fn draw(self: *Self, input: *const InputState, camera: *const Camera) !void {
    if (input.isJustPressed(.reload_shaders)) {
        self.pass.recompile();
    }

    // gl.clearColor(1.0, 1.0, 1.0, 1.0);
    gl.clearColor(0.0, 0.0, 0.0, 1.0);
    gl.clear(.{ .color = true, .depth = true });

    self.pass.use();
    self.vao.bind();

    const model = zlm.Mat4.identity;
    self.pass.setMat4("model", model);
    self.pass.setMat4("view", camera.view);
    self.pass.setMat4("proj", camera.proj);

    self.pass.setVec2("scr_size", self.scr_size);
    self.pass.setMat4("inv_view", camera.inv_view);
    self.pass.setMat4("inv_proj", camera.inv_proj);

    gl.drawArrays(.triangles, 0, self.mesh.items.len);

    sdl.gl.swapWindow(self.window);
}

pub fn resize(self: *Self) void {
    const size = self.window.getSize();
    gl.viewport(0, 0, @intCast(size.width), @intCast(size.height));
    self.scr_size = zlm.vec2(util.i2f(size.width), util.i2f(size.height));
}

const ShaderPass = struct {
    alloc: std.mem.Allocator,
    prg: gl.Program,

    fn init(alloc: std.mem.Allocator) !ShaderPass {
        var self: ShaderPass = undefined;

        self.alloc = alloc;
        try self.compile();

        return self;
    }

    fn compile(self: *ShaderPass) !void {
        self.prg = gl.Program.create();
        errdefer self.prg.delete();

        try self.compileShader(.vertex, "shader.vert");
        try self.compileShader(.fragment, "shader.frag");
        self.prg.link();

        log.print(.debug, "renderer", "shader program created", .{});
    }

    fn recompile(self: *ShaderPass) void {
        const old_prg = self.prg;
        self.compile() catch {
            self.prg = old_prg;
            log.print(.warn, "renderer", "reloading shaders failed, using previous shaders", .{});
            return;
        };
        old_prg.delete();
        log.print(.info, "renderer", "reloaded shaders", .{});
    }

    fn deinit(self: ShaderPass) void {
        self.prg.delete();
    }

    fn use(self: *ShaderPass) void {
        self.prg.use();
    }

    fn setMat4(self: *ShaderPass, name: [:0]const u8, value: zlm.Mat4) void {
        const location = self.getLocation(name) orelse return;
        self.prg.uniformMatrix4(location, false, &[_][4][4]f32{value.fields});
    }

    fn setVec2(self: *ShaderPass, name: [:0]const u8, value: zlm.Vec2) void {
        const location = self.getLocation(name) orelse return;
        self.prg.uniform2f(location, value.x, value.y);
    }

    fn setVec3(self: *ShaderPass, name: [:0]const u8, value: zlm.Vec3) void {
        const location = self.getLocation(name) orelse return;
        self.prg.uniform3f(location, value.x, value.y, value.z);
    }

    fn getLocation(self: *ShaderPass, name: [:0]const u8) ?u32 {
        const location = gl.getUniformLocation(self.prg, name);
        if (location == null) {
            // log.print(.warn, "renderer", "uniform '{s}' not found", .{name});
        }
        return location;
    }

    fn compileShader(self: *ShaderPass, ty: gl.ShaderType, comptime name: []const u8) !void {
        const shader = gl.Shader.create(ty);
        defer shader.delete();

        const file = try std.fs.cwd().openFile("src/shaders/" ++ name, .{});
        defer file.close();

        const src = try file.readToEndAlloc(self.alloc, std.math.maxInt(usize));
        defer self.alloc.free(src);

        shader.source(1, &[1][]const u8{src});
        shader.compile();

        if (shader.get(.compile_status) == 0) {
            var has_msg = true;
            const msg = shader.getCompileLog(self.alloc) catch ret: {
                has_msg = false;
                break :ret "unknown error\n";
            };
            log.print(.err, "renderer", "'" ++ name ++ "' failed to compile: {s}", .{
                msg[0 .. msg.len - 2], // remove last newline character from compile logs
            });
            if (has_msg) {
                self.alloc.free(msg);
            }
            return error.ShaderCompilationFailed;
        } else {
            log.print(.debug, "renderer", "'" ++ name ++ "' compiled successfully", .{});
        }

        self.prg.attach(shader);
    }
};
