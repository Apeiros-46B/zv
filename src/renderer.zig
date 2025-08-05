const std = @import("std");
const sdl = @import("sdl2");
const gl = @import("zgl");

const log = @import("log.zig");

const Self = @This();

const Cstr = [*:0]const u8;

alloc: std.mem.Allocator,
window: sdl.Window,
gl_ctx: sdl.gl.Context,

vao: gl.VertexArray,
vbo: gl.Buffer,

prg: gl.Program,

pub fn init(alloc: std.mem.Allocator, window: sdl.Window) !Self {
    var self: Self = undefined;

    self.alloc = alloc;
    self.window = window;

    self.gl_ctx = try sdl.gl.createContext(window);
    errdefer self.gl_ctx.delete();
    try self.gl_ctx.makeCurrent(window);
    log.print(.debug, "GL", "context loaded", .{});

    try gl.loadExtensions(void, getProcAddressWrapper);
    log.print(.debug, "GL", "extensions loaded", .{});

    self.resize();

    self.vao = gl.VertexArray.create();
    errdefer self.vao.delete();

    const verts = [_]f32 {
        // pos            // color
         0.5, -0.5, 0.0,  1.0, 0.0, 0.0,
        -0.5, -0.5, 0.0,  0.0, 1.0, 0.0,
         0.0,  0.5, 0.0,  0.0, 0.0, 1.0,
    };
    self.vbo = gl.Buffer.create();
    errdefer self.vbo.delete();

    self.vao.bind();
    self.vbo.bind(.array_buffer);
    self.vbo.data(f32, &verts, .static_draw);
    gl.vertexAttribPointer(0, 3, .float, false, 6 * @sizeOf(f32), 0);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(1, 3, .float, false, 6 * @sizeOf(f32), 3 * @sizeOf(f32));
    gl.enableVertexAttribArray(1);
    log.print(.debug, "GL", "vao+vbo created", .{});

    const vsh = gl.Shader.create(.vertex);
    defer vsh.delete();
    try self.compileShader(vsh, "shader.vert");

    const fsh = gl.Shader.create(.fragment);
    defer fsh.delete();
    try self.compileShader(fsh, "shader.frag");

    self.prg = gl.Program.create();
    errdefer self.prg.delete();

    self.prg.attach(vsh);
    self.prg.attach(fsh);
    self.prg.link();
    log.print(.debug, "GL", "shader program created", .{});

    return self;
}

pub fn deinit(self: Self) void {
    self.prg.delete();
    self.vbo.delete();
    self.vao.delete();
    self.gl_ctx.delete();
}

pub fn resize(self: Self) void {
    const size = self.window.getSize();
    gl.viewport(0, 0, @intCast(size.width), @intCast(size.height));
}

pub fn draw(self: *Self) !void {
    gl.clearColor(1.0, 1.0, 1.0, 1.0);
    gl.clear(.{ .color = true });

    self.prg.use();
    self.vao.bind();
    gl.drawArrays(.triangles, 0, 3);

    sdl.gl.swapWindow(self.window);
}

fn getProcAddressWrapper(comptime _: type, sym: [:0]const u8) ?*const anyopaque {
    return sdl.gl.getProcAddress(sym);
}

fn compileShader(self: *Self, shader: gl.Shader, comptime name: []const u8) !void {
    const src: Cstr = @embedFile("shaders/" ++ name);
    shader.source(1, &[1][]const u8 { std.mem.span(src) });
    shader.compile();
    if (shader.get(.compile_status) == 0) {
        var has_msg = true;
        const msg = shader.getCompileLog(self.alloc) catch ret: {
            has_msg = false;
            break :ret "unknown error";
        };
        log.print(.err, "GL", "compilation of shader '" ++ name ++ "' failed: {s}", .{ msg });
        if (has_msg) {
            self.alloc.free(msg);
        }
        return error.ShaderCompilationFailed;
    }
    log.print(.info, "GL", "shader '" ++ name ++ "' compiled successfully", .{});
}
