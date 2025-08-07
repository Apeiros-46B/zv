const std = @import("std");
const sdl = @import("sdl2");
const gl = @import("zgl");

const log = @import("log.zig");

const Self = @This();
const AtomicBool = std.atomic.Value(bool);

alloc: std.mem.Allocator,
window: sdl.Window,
should_resize: *AtomicBool,

gl_ctx: sdl.gl.Context,
vao: gl.VertexArray,
prg: gl.Program,


fn getProcAddressWrapper(comptime _: type, sym: [:0]const u8) ?*const anyopaque {
    return sdl.gl.getProcAddress(sym);
}

pub fn init(alloc: std.mem.Allocator, window: sdl.Window, should_resize: *AtomicBool) !Self {
    var self: Self = undefined;

    self.alloc = alloc;
    self.window = window;
    self.should_resize = should_resize;

    self.gl_ctx = try sdl.gl.createContext(window);
    errdefer self.gl_ctx.delete();
    try self.gl_ctx.makeCurrent(window);
    log.print(.debug, "GL", "context loaded", .{});

    try gl.loadExtensions(void, getProcAddressWrapper);
    log.print(.debug, "GL", "extensions loaded", .{});

    self.resize();

    self.vao = gl.VertexArray.create();
    errdefer self.vao.delete();
    self.vao.bind();
    log.print(.debug, "GL", "vao created", .{});

    try self.compileShaders();

    return self;
}

pub fn deinit(self: Self) void {
    self.prg.delete();
    self.vao.delete();
    self.gl_ctx.delete();
}

pub fn draw(self: *Self) !void {
    if (self.should_resize.load(.seq_cst)) {
        self.resize();
    }

    gl.clearColor(1.0, 1.0, 1.0, 1.0);
    gl.clear(.{ .color = true });

    self.prg.use();
    self.vao.bind();
    gl.drawArrays(.triangles, 0, 3);

    sdl.gl.swapWindow(self.window);
}

fn resize(self: *Self) void {
    const size = self.window.getSize();
    gl.viewport(0, 0, @intCast(size.width), @intCast(size.height));
}

pub fn reloadShaders(self: *Self) void {
    self.compileShaders() catch {
        log.print(.warn, "GL", "reloading shaders failed, using previous shaders", .{});
        return;
    };
    log.print(.info, "GL", "reloaded shaders", .{});
}

fn compileShaders(self: *Self) !void {
    const vsh = gl.Shader.create(.vertex);
    defer vsh.delete();
    try self.compileShader(vsh, "shader.vert");

    const fsh = gl.Shader.create(.fragment);
    defer fsh.delete();
    try self.compileShader(fsh, "shader.frag");

    self.prg = gl.Program.create();
    self.prg.attach(vsh);
    self.prg.attach(fsh);
    self.prg.link();

    log.print(.debug, "GL", "shader program created", .{});
}

fn compileShader(self: *Self, shader: gl.Shader, comptime name: []const u8) !void {
    const file = try std.fs.cwd().openFile("src/shaders/" ++ name, .{});
    defer file.close();

    const src = try file.readToEndAlloc(self.alloc, std.math.maxInt(usize));
    defer self.alloc.free(src);

    shader.source(1, &[1][]const u8 { src });
    shader.compile();

    if (shader.get(.compile_status) == 0) {
        var has_msg = true;
        const msg = shader.getCompileLog(self.alloc) catch ret: {
            has_msg = false;
            break :ret "unknown error\n";
        };
        log.print(.err, "shader", "'" ++ name ++ "' failed to compile: {s}", .{
            msg[0..msg.len - 2], // remove last newline character from compile logs
        });
        if (has_msg) {
            self.alloc.free(msg);
        }
        return error.ShaderCompilationFailed;
    } else {
        log.print(.debug, "shader", "'" ++ name ++ "' compiled successfully", .{});
    }
}
