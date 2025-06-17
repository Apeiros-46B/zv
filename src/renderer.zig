const std = @import("std");
const sdl = @import("sdl2");
const vk = @import("vulkan");

const Vulkan = @import("vk.zig");
const Swapchain = @import("swapchain.zig");
const Pipelines = @import("pipelines.zig");
const Self = @This();

alloc: std.mem.Allocator,

vkc: Vulkan,
swapchain: Swapchain,
pipelines: Pipelines,

graphics_queue: Queue,
compute_queue: Queue,
present_queue: Queue,

pub fn init(alloc: std.mem.Allocator, window: *sdl.Window) !Self {
    var self: Self = undefined;

    self.vkc = try Vulkan.init(alloc, window);
    errdefer self.vkc.deinit();

    self.graphics_queue = Queue.init(&self.vkc, self.vkc.queue_config.graphics_family);
    self.compute_queue = Queue.init(&self.vkc, self.vkc.queue_config.compute_family);
    self.present_queue = Queue.init(&self.vkc, self.vkc.queue_config.present_family);

    self.swapchain = try Swapchain.init(&self.vkc, .{
        .height = @intCast(window.getSize().height),
        .width = @intCast(window.getSize().width),
    });
    errdefer self.swapchain.deinit();

    self.pipelines = try Pipelines.init(
        &self.vkc,
        self.swapchain.extent,
        self.swapchain.fmt.format,
    );
    errdefer self.pipelines.deinit();

    try self.swapchain.createFramebuffers(self.pipelines.render_pass);

    return self;
}

pub fn deinit(self: Self) void {
    self.vkc.dev.deviceWaitIdle() catch {};
    self.pipelines.deinit();
    self.swapchain.deinit();
    self.vkc.deinit();
}

const Queue = struct {
    handle: vk.Queue,
    family: u32,

    fn init(vkc: *const Vulkan, family: u32) Queue {
        return .{
            .handle = vkc.dev.getDeviceQueue(family, 0),
            .family = family,
        };
    }
};

pub fn draw(self: *Self) !void {
    try self.swapchain.getCurFrame().wait();
    try self.swapchain.getCurFrame().resetFence();
    const img_idx = try self.swapchain.acqNext();
    
    const frame = self.swapchain.getCurFrame();
    
    try frame.cmd_buf.resetCommandBuffer(.{});
    try frame.cmd_buf.beginCommandBuffer(&.{
        .flags = .{ .one_time_submit_bit = true },
    });
    
    frame.cmd_buf.beginRenderPass(&.{
        .render_pass = self.pipelines.render_pass,
        .framebuffer = self.swapchain.imgs[img_idx].framebuffer.?,
        .render_area = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.swapchain.extent,
        },
        .clear_value_count = 1,
        .p_clear_values = &[_]vk.ClearValue{
            .{ .color = .{ .float_32 = .{ 1.0, 1.0, 1.0, 1.0 } } },
        },
    }, .@"inline");
    frame.cmd_buf.endRenderPass();
    
    try frame.cmd_buf.endCommandBuffer();
    
    const submit_info = vk.SubmitInfo {
        .wait_semaphore_count = 1,
        .p_wait_semaphores = (&frame.img_acq)[0..1],
        .p_wait_dst_stage_mask = (&vk.PipelineStageFlags{ .color_attachment_output_bit = true })[0..1],
        .command_buffer_count = 1,
        .p_command_buffers = (&frame.cmd_buf.handle)[0..1],
        .signal_semaphore_count = 1,
        .p_signal_semaphores = (&frame.render_done)[0..1],
    };
    try self.vkc.dev.queueSubmit(self.graphics_queue.handle, 1, (&submit_info)[0..1], frame.fence);

    const present_info = vk.PresentInfoKHR{
        .wait_semaphore_count = 1,
        .p_wait_semaphores = (&frame.render_done)[0..1],
        .swapchain_count = 1,
        .p_swapchains = (&self.swapchain.handle)[0..1],
        .p_image_indices = (&img_idx)[0..1],
    };
    _ = try self.vkc.dev.queuePresentKHR(self.present_queue.handle, &present_info);
    
    self.swapchain.nextFrame();
}
