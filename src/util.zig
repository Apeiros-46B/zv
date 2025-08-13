/// Utility function for calculating f32 ratios between integers
pub fn ratio(x: anytype, y: anytype) f32 {
    return @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(y));
}
