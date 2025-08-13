const std = @import("std");
const sdl = @import("sdl2");
const zlm = @import("zlm");

const log = @import("log.zig");
const Self = @This();

const Inputs = std.EnumSet(InputBtn);

pressed: Inputs,
just_pressed: Inputs,
just_released: Inputs,
mouse_motion: zlm.Vec2,

pub fn init() Self {
    var self: Self = undefined;

    self.pressed = Inputs.initEmpty();
    self.just_pressed = Inputs.initEmpty();
    self.just_released = Inputs.initEmpty();
    self.mouse_motion = zlm.Vec2.zero;

    return self;
}

pub fn loopPost(self: *Self) void {
    self.just_pressed = Inputs.initEmpty();
    self.just_released = Inputs.initEmpty();
    self.mouse_motion = zlm.Vec2.zero;
}

pub fn handleEvent(self: *Self, ev: sdl.Event) void {
    switch (ev) {
        .key_down => |kev| self.handleKeyDown(kev),
        .key_up => |kev| self.handleKeyUp(kev),
        .mouse_button_down => |mev| self.handleMouseBtnDown(mev),
        .mouse_button_up => |mev| self.handleMouseBtnUp(mev),
        .mouse_motion => |mev| self.handleMouseMotion(mev),
        else => {},
    }
}

fn handleKeyDown(self: *Self, kev: sdl.KeyboardEvent) void {
    if (kev.is_repeat) {
        return;
    }
    const btn = InputBtn.fromScancode(kev.scancode);
    self.pressed.insert(btn);
    self.just_pressed.insert(btn);
    self.just_released.remove(btn);
}

fn handleKeyUp(self: *Self, kev: sdl.KeyboardEvent) void {
    const btn = InputBtn.fromScancode(kev.scancode);
    self.pressed.remove(btn);
    self.just_pressed.remove(btn);
    self.just_released.insert(btn);
}

fn handleMouseBtnDown(self: *Self, mev: sdl.MouseButtonEvent) void {
    const btn = InputBtn.fromMouseButton(mev.button);
    self.pressed.insert(btn);
    self.just_pressed.insert(btn);
    self.just_released.remove(btn);
}

fn handleMouseBtnUp(self: *Self, mev: sdl.MouseButtonEvent) void {
    const btn = InputBtn.fromMouseButton(mev.button);
    self.pressed.remove(btn);
    self.just_pressed.remove(btn);
    self.just_released.insert(btn);
}

fn handleMouseMotion(self: *Self, mev: sdl.MouseMotionEvent) void {
    self.mouse_motion.x = @floatFromInt(mev.delta_x);
    self.mouse_motion.y = @floatFromInt(mev.delta_y);
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
    capture_cursor,
    unrecognized,

    pub fn fromScancode(sc: sdl.Scancode) InputBtn {
        return switch (sc) {
            .e => .interact,
            .w => .move_fwd,
            .a => .move_left,
            .s => .move_back,
            .d => .move_right,
            .space => .move_up,
            .left_shift => .move_down,
            .r => .reload_shaders,
            else => .unrecognized,
        };
    }

    pub fn fromMouseButton(sc: sdl.MouseButton) InputBtn {
        return switch (sc) {
            .left => .break_block,
            .right => .place_block,
            .middle => .capture_cursor,
            else => .unrecognized,
        };
    }
};

pub fn isPressed(self: *const Self, btn: InputBtn) bool {
    return self.pressed.contains(btn);
}

pub fn isJustPressed(self: *const Self, btn: InputBtn) bool {
    return self.just_pressed.contains(btn);
}

pub fn isJustReleased(self: *const Self, btn: InputBtn) bool {
    return self.just_released.contains(btn);
}
