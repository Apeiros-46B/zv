const sdl = @import("sdl");
const zlm = @import("zlm");

/// Utility function for converting integers into f32s
pub fn i2f(x: anytype) f32 {
    return @as(f32, @floatFromInt(x));
}

/// Utility function for calculating f32 ratios between integers
pub fn ratio(x: anytype, y: anytype) f32 {
    return i2f(x) / i2f(y);
}
