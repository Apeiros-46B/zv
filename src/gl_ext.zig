const gl = @import("zgl");

pub const DrawCommand = extern struct {
    count: u32,
    instance_count: u32,
    first: u32,
    base_instance: u32,
};

pub fn multiDrawArraysIndirect(
    mode: gl.PrimitiveType,
    indirect: ?*const DrawCommand,
    count: gl.SizeI,
    stride: gl.SizeI,
) void {
    gl.binding.multiDrawArraysIndirect(@intFromEnum(mode), indirect, count, stride);
}
