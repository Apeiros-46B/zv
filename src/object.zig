const std = @import("std");

const Self = @This();

ptr: *anyopaque,
processFn: fn (*anyopaque, f32) void,

// loop(self, dt, inputState)
// loopPost
