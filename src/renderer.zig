const std = @import("std");
const sdl = @import("sdl2");
const gl = @import("zgl");
const zlm = @import("zlm");

const log = @import("log.zig");

const Camera = @import("camera.zig");
const Self = @This();

alloc: std.mem.Allocator,
window: sdl.Window,
camera: Camera,

gl_ctx: sdl.gl.Context,
vao: gl.VertexArray,
vbo: gl.Buffer,

pass: ShaderPass,

fn getProcAddressWrapper(comptime _: type, sym: [:0]const u8) ?*const anyopaque {
    return sdl.gl.getProcAddress(sym);
}

pub fn init(alloc: std.mem.Allocator, window: sdl.Window) !Self {
    var self: Self = undefined;

    self.alloc = alloc;
    self.window = window;
    self.camera = Camera.init();

    self.gl_ctx = try sdl.gl.createContext(window);
    errdefer self.gl_ctx.delete();
    try self.gl_ctx.makeCurrent(window);
    log.print(.debug, "GL", "context loaded", .{});

    try gl.loadExtensions(void, getProcAddressWrapper);
    log.print(.debug, "GL", "extensions loaded", .{});

    self.resize();

    const verts = [_]f32{
        -0.5, -0.5, 0.0, 1.0, 0.0, 0.0,
        0.5,  -0.5, 0.0, 0.0, 1.0, 0.0,
        0.0,  0.5,  0.0, 0.0, 0.0, 1.0,
    };

    self.vao = gl.VertexArray.create();
    errdefer self.vao.delete();
    log.print(.debug, "GL", "vao created", .{});

    self.vbo = gl.Buffer.create();
    errdefer self.vbo.delete();
    log.print(.debug, "GL", "vbo created", .{});

    self.vao.bind();
    self.vbo.bind(.array_buffer);
    self.vbo.data(f32, &verts, .static_draw);
    gl.vertexAttribPointer(0, 3, .float, false, 6 * @sizeOf(f32), 0);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(1, 3, .float, false, 6 * @sizeOf(f32), 3 * @sizeOf(f32));
    gl.enableVertexAttribArray(1);

    self.pass = try ShaderPass.init(alloc);

    log.print(.debug, "renderer", "init complete", .{});

    return self;
}

pub fn deinit(self: Self) void {
    self.pass.deinit();
    self.vbo.delete();
    self.vao.delete();
    self.gl_ctx.delete();

    log.print(.debug, "renderer", "deinit complete", .{});
}

pub fn loop(self: *Self, dt: f32) !void {
    gl.clearColor(1.0, 1.0, 1.0, 1.0);
    gl.clear(.{ .color = true });

    self.camera.loop(dt);

    self.pass.use();
    self.vao.bind();

    const model = zlm.Mat4.identity;
    self.pass.setMat4("model", model);
    self.pass.setMat4("view", self.camera.view);
    self.pass.setMat4("proj", self.camera.proj);

    gl.drawArrays(.triangles, 0, 3);

    sdl.gl.swapWindow(self.window);
}

pub fn resize(self: *Self) void {
    const size = self.window.getSize();
    const width: usize = @intCast(size.width);
    const height: usize = @intCast(size.height);
    gl.viewport(0, 0, width, height);
    self.camera.resize(width, height);
}

pub fn handleKeyDown(self: *Self, kev: sdl.KeyboardEvent) void {
    self.camera.handleKeyDown(kev);
    switch (kev.keycode) {
        .r => self.reloadShaders(),
        else => {},
    }
}

pub fn handleKeyUp(self: *Self, kev: sdl.KeyboardEvent) void {
    self.camera.handleKeyUp(kev);
}

fn reloadShaders(self: *Self) void {
    self.pass.recompile();
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

        log.print(.debug, "GL", "shader program created", .{});
    }

    fn recompile(self: *ShaderPass) void {
        const old_prg = self.prg;
        self.compile() catch {
            self.prg = old_prg;
            log.print(.warn, "GL", "reloading shaders failed, using previous shaders", .{});
            return;
        };
        old_prg.delete();
        log.print(.info, "GL", "reloaded shaders", .{});
    }

    fn deinit(self: ShaderPass) void {
        self.prg.delete();
    }

    fn use(self: *ShaderPass) void {
        self.prg.use();
    }

    fn setMat4(self: *ShaderPass, name: [:0]const u8, value: zlm.Mat4) void {
        const location = gl.getUniformLocation(self.prg, name);
        if (location == null) {
            log.print(.warn, "GL", "uniform '{s}' not found", .{name});
            return;
        }
        self.prg.uniformMatrix4(location, false, &[_][4][4]f32{value.fields});
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
            log.print(.err, "shader", "'" ++ name ++ "' failed to compile: {s}", .{
                msg[0 .. msg.len - 2], // remove last newline character from compile logs
            });
            if (has_msg) {
                self.alloc.free(msg);
            }
            return error.ShaderCompilationFailed;
        } else {
            log.print(.debug, "shader", "'" ++ name ++ "' compiled successfully", .{});
        }

        self.prg.attach(shader);
    }
};
