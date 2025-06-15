const std = @import("std");
const vk = @import("vulkan");

const Vulkan = @import("vk.zig");
const Self = @This();

vkc: *const Vulkan,

pool: vk.CommandPool,
buf: vk.CommandBuffer,

pub fn init(vkc: *const Vulkan, queue_config: Vulkan.QueueConfiguration) !Self {
    var self: Self = undefined;

    self.vkc = vkc;

    self.pool = try vkc.dev.createCommandPool(&.{
        .flags = .{ .reset_command_buffer_bit = true },
        .queue_family_index = queue_config.graphics_family,
    }, null);
}
