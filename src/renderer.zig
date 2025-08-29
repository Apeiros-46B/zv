const std = @import("std");
const sdl = @import("sdl2");
const gl = @import("zgl");
const zlm = @import("zlm");

const log = @import("log.zig");
const util = @import("util.zig");
const World = @import("world.zig");
const Camera = @import("camera.zig");
const InputState = @import("input.zig");
const Self = @This();

alloc: std.mem.Allocator,
window: sdl.Window,
chunk: World.Chunk,

gl_ctx: sdl.gl.Context,
vao: gl.VertexArray,
face_ssbo: gl.Buffer, // TODO: remove backfaces before vertex shader
brick_ssbo: gl.Buffer, // stores the brick data

// TODO: draw more than one chunk in one draw call. vsh needs to know what chunk a face belongs to, and fsh needs to know what chunk a brick belongs to

// index the face ssbo in the vertex shader to provide values to the fragment shader: whether or not to raymarch, the material/'ptr', etc
// in the fragment shader, if we are going to raymarch, index the brick ssbo by 'ptr' to get the brick data to raymarch through

scr_size: zlm.Vec2,
pass: ShaderPass,

fn getProcAddressWrapper(comptime _: type, sym: [:0]const u8) ?*const anyopaque {
    return sdl.gl.getProcAddress(sym);
}

pub fn init(alloc: std.mem.Allocator, window: sdl.Window) !Self {
    var self: Self = undefined;

    self.alloc = alloc;
    self.window = window;
    self.chunk = try World.Chunk.init(alloc);
    errdefer self.chunk.deinit();

    try self.chunk.remesh();

    self.gl_ctx = try sdl.gl.createContext(window);
    errdefer self.gl_ctx.delete();
    try self.gl_ctx.makeCurrent(window);
    log.print(.debug, "renderer", "context loaded", .{});

    try sdl.gl.setSwapInterval(.vsync);
    // try sdl.gl.setSwapInterval(.immediate);

    try gl.loadExtensions(void, getProcAddressWrapper);
    log.print(.debug, "renderer", "extensions loaded", .{});

    self.vao = gl.VertexArray.create();
    errdefer self.vao.delete();
    log.print(.debug, "renderer", "vao created", .{});

    self.face_ssbo = gl.Buffer.create();
    errdefer self.face_ssbo.delete();
    self.brick_ssbo = gl.Buffer.create();
    errdefer self.brick_ssbo.delete();
    log.print(.debug, "renderer", "ssbos created", .{});

    gl.enable(.depth_test);
    gl.depthFunc(.less);
    gl.enable(.cull_face);
    gl.cullFace(.back);

    self.pass = try ShaderPass.init(alloc);

    self.pass.use();
    self.face_ssbo.storage(u32, self.chunk.mesh.numFaces(), self.chunk.mesh.getFaces(), .{});
    gl.bindBufferBase(.shader_storage_buffer, 0, self.face_ssbo);
    self.brick_ssbo.storage(u32, self.chunk.numVoxels() / 2, self.chunk.getVoxels(), .{});
    gl.bindBufferBase(.shader_storage_buffer, 1, self.brick_ssbo);

    log.print(.debug, "renderer", "init complete", .{});

    return self;
}

pub fn deinit(self: Self) void {
    self.chunk.deinit();
    self.pass.deinit();
    self.face_ssbo.delete();
    self.vao.delete();
    self.gl_ctx.delete();

    log.print(.debug, "renderer", "deinit complete", .{});
}

pub fn draw(self: *Self, input: *const InputState, camera: *const Camera) !void {
    if (input.isJustPressed(.reload_shaders)) {
        self.pass.recompile();
    }

    gl.clearColor(1.0, 1.0, 1.0, 1.0);
    gl.clear(.{ .color = true, .depth = true });

    self.pass.use();
    self.vao.bind();
    self.face_ssbo.bind(.shader_storage_buffer);

    const model = zlm.Mat4.identity;
    self.pass.setMat4("model", model);
    self.pass.setMat4("view", camera.view);
    self.pass.setMat4("proj", camera.proj);

    self.pass.setVec2("scr_size", self.scr_size);
    self.pass.setMat4("inv_view", camera.inv_view);
    self.pass.setMat4("inv_proj", camera.inv_proj);

    gl.drawArrays(.triangles, 0, self.chunk.mesh.numFaces() * 3);

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

    fn setUint(self: *ShaderPass, name: [:0]const u8, value: anytype) void {
        const location = self.getLocation(name) orelse return;
        self.prg.uniform1ui(location, @intCast(value));
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
