const std = @import("std");
const sdl = @import("sdl2");

const Self = @This();

pressed: std.EnumSet(InputBtn),
just_pressed: std.EnumSet(InputBtn),
just_released: std.EnumSet(InputBtn),

pub fn init() Self {
    var self: Self = undefined;

    self.pressed = std.EnumSet.initEmpty();
    self.just_pressed = std.EnumSet.initEmpty();
    self.just_released = std.EnumSet.initEmpty();

    return self;
}

pub fn isPressed(self: *Self, btn: InputBtn) bool {
    return self.pressed.contains(btn);
}

pub fn isJustPressed(self: *Self, btn: InputBtn) bool {
    return self.just_pressed.contains(btn);
}

pub fn isJustReleased(self: *Self, btn: InputBtn) bool {
    return self.just_released.contains(btn);
}

pub fn processPost(self: *Self) void {
    self.just_pressed.clear();
    self.just_released.clear();
}

pub fn handleKeyDown(self: *Self, kev: sdl.KeyboardEvent) void {
    const btn = InputBtn.fromScancode(kev.scancode);
    self.pressed.insert(btn);
    self.just_pressed.insert(btn);
    self.just_released.remove(btn);
}

pub fn handleKeyUp(self: *Self, kev: sdl.KeyboardEvent) void {
    const btn = InputBtn.fromScancode(kev.scancode);
    self.pressed.remove(btn);
    self.just_pressed.remove(btn);
    self.just_released.insert(btn);
}

pub fn handleMouseBtnDown(self: *Self, mev: sdl.MouseButtonEvent) void {
    const btn = InputBtn.fromMouseButton(mev.button);
    self.pressed.insert(btn);
    self.just_pressed.insert(btn);
    self.just_released.remove(btn);
}

pub fn handleMouseBtnUp(self: *Self, mev: sdl.MouseButtonEvent) void {
    const btn = InputBtn.fromMouseButton(mev.button);
    self.pressed.remove(btn);
    self.just_pressed.remove(btn);
    self.just_released.insert(btn);
}

pub const InputBtn = enum {
    place_block,
    break_block,
    interact,
    move_fwd,
    move_left,
    move_back,
    move_right,
    move_up,
    move_down,
    reload_shaders,
    unrecognized,

    pub fn fromScancode(sc: sdl.Scancode) InputBtn {
        return switch (sc) {
            .e => .interact,
            .w => .move_fwd,
            .a => .move_left,
            .s => .move_back,
            .d => .move_right,
            .space => .move_up,
            .shift => .move_down,
            .r => .reload_shaders,
            else => .unrecognized,
        };
    }

    pub fn fromMouseButton(sc: sdl.MouseButton) InputBtn {
        return switch (sc) {
            .left => .break_block,
            .right => .place_block,
            else => .unrecognized,
        };
    }
};
