const std = @import("std");
const sdl = @import("sdl2");
const vk = @import("vulkan");

const Vulkan = @import("vk.zig");
const Swapchain = @import("swapchain.zig");
const Pipelines = @import("pipelines.zig");
const Self = @This();

const FRAMES_IN_FLIGHT = 2;

alloc: std.mem.Allocator,

vkc: Vulkan,
swapchain: Swapchain,
pipelines: Pipelines,

graphics_queue: Queue,
compute_queue: Queue,
present_queue: Queue,

frames: [FRAMES_IN_FLIGHT]FrameData,
cur_frame: usize,

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

    try self.initFrames();
    errdefer self.deinitFrames();

    return self;
}

pub fn deinit(self: Self) void {
    @constCast(&self).deinitFrames();
    self.pipelines.deinit();
    self.swapchain.deinit();
    self.vkc.deinit();
}

fn initFrames(self: *Self) !void {
    const cmd_pool_info = vk.CommandPoolCreateInfo {
        .flags = .{ .reset_command_buffer_bit = true },
        .queue_family_index = self.vkc.queue_config.graphics_family,
    };
    var i: usize = 0;
    errdefer for (self.frames[0..i]) |frame| frame.deinit(&self.vkc);
    for (0..FRAMES_IN_FLIGHT) |_| {
        self.frames[i] = try FrameData.init(&self.vkc, &cmd_pool_info);
        i += 1;
    }
}

fn deinitFrames(self: *Self) void {
    for (self.frames) |frame| {
        frame.deinit(&self.vkc);
    }
}

fn getFrame(self: *Self) *FrameData {
    return self.frames[self.cur_frame % FRAMES_IN_FLIGHT];
}

const FrameData = struct {
    cmd_pool: vk.CommandPool,
    cmd_buf: vk.CommandBufferProxy,

    fn init(
        vkc: *const Vulkan,
        cmd_pool_info: *const vk.CommandPoolCreateInfo
    ) !FrameData {
        var self: FrameData = undefined;

        self.cmd_pool = try vkc.dev.createCommandPool(cmd_pool_info, null);
        errdefer vkc.dev.destroyCommandPool(self.cmd_pool, null);

        var cmd_buf = undefined;
        try vkc.dev.allocateCommandBuffers(&.{
            .command_pool = self.cmd_pool,
            .command_buffer_count = 1,
            .level = .primary,
        }, (&cmd_buf)[0..1]);
        self.cmd_buf = vk.CommandBufferProxy.init(cmd_buf, vkc.vkd);

        return self;
    }

    fn deinit(self: FrameData, vkc: *const Vulkan) void {
        vkc.dev.destroyCommandPool(self.cmd_pool, null);
    }
};

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
    const img = self.swapchain.getImg();
    _ = try self.vkc.dev.waitForFences(1, (&img.frame_fence)[0..1], vk.TRUE, 1_000_000_000);
    try self.vkc.dev.resetFences(1, (&img.frame_fence)[0..1]);
    try self.swapchain.acqNext();

    const cmd = self.getFrame().cmd_buf;
    cmd.resetCommandBuffer(.{});
    cmd.beginCommandBuffer(&.{
        .p_inheritance_info = null,
        .flags = .{ .one_time_submit_bit = true },
    });
}
