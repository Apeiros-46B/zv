const gl = @import("zgl");

pub fn drawArraysInstancedBaseInstance(mode: gl.PrimitiveType, first: GLint, count: GLsizei, instancecount: GLsizei, baseinstance: GLuint) void {
    gl.drawArraysInstancedBaseInstance(mode, first, count, instancecount, baseinstance);
}
