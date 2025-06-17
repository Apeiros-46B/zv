const std = @import("std");
const vk = @import("vulkan");

const Vulkan = @import("vk.zig");
const Self = @This();

const FRAMES_IN_FLIGHT = 2;

pub const PresentState = enum {
    optimal,
    suboptimal,
};

pub const AcquireResult = struct {
    state: PresentState,
    img_idx: u32,
};

vkc: *const Vulkan,
alloc: std.mem.Allocator,

fmt: vk.SurfaceFormatKHR,
mode: vk.PresentModeKHR,
extent: vk.Extent2D,
handle: vk.SwapchainKHR,

imgs: []SwapImage,
img_idx: u32,
cur_frame: usize,
frames: [FRAMES_IN_FLIGHT]Frame,

pub fn init(vkc: *const Vulkan, extent: vk.Extent2D) !Self {
    return try initRecycle(vkc, extent, .null_handle);
}

// secondary initialization step which can only be done after the Pipelines
// (which depends on the swapchain extent and format)'s render pass is created
pub fn createFramebuffers(self: *Self, render_pass: vk.RenderPass) !void {
    var i: usize = 0;
    errdefer for (self.imgs[0..i]) |img| self.vkc.dev.destroyFramebuffer(
        img.framebuffer.?,
        null
    );
    for (self.imgs) |_| {
        try self.imgs[i].createFramebuffer(self.extent, render_pass);
        i += 1;
    }
}

pub fn initRecycle(vkc: *const Vulkan, extent: vk.Extent2D, prev: vk.SwapchainKHR) !Self {
    var self: Self = undefined;

    self.vkc = vkc;
    self.alloc = vkc.alloc;

    const caps = try vkc.inst.getPhysicalDeviceSurfaceCapabilitiesKHR(
        vkc.pdev,
        vkc.surf
    );

    try self.findFmt();
    try self.findMode();

    self.findActualExtent(caps, extent);
    if (self.extent.width == 0 or self.extent.height == 0) {
        return error.InvalidSurfaceDimensions;
    }

    var img_count = caps.min_image_count + 1;
    if (caps.max_image_count > 0) {
        img_count = @min(img_count, caps.max_image_count);
    }

    const families = vkc.queue_config.families();
    const sharing_mode: vk.SharingMode = if (vkc.queue_config.unique > 1)
        .concurrent
    else
        .exclusive;

    self.handle = try vkc.dev.createSwapchainKHR(&.{
        .surface = vkc.surf,
        .min_image_count = img_count,
        .image_format = self.fmt.format,
        .image_color_space = self.fmt.color_space,
        .image_extent = self.extent,
        .image_array_layers = 1,
        .image_usage = .{
            .color_attachment_bit = true,
            .transfer_dst_bit = true,
        },
        .image_sharing_mode = sharing_mode,
        .queue_family_index_count = families.len,
        .p_queue_family_indices = &families,
        .pre_transform = caps.current_transform,
        .composite_alpha = .{ .opaque_bit_khr = true },
        .present_mode = self.mode,
        .clipped = vk.TRUE,
        .old_swapchain = prev,
    }, null);
    errdefer vkc.dev.destroySwapchainKHR(self.handle, null);

    if (prev != .null_handle) {
        vkc.dev.destroySwapchainKHR(prev, null);
    }

    self.img_idx = 0;
    try self.initImgs();
    errdefer self.deinitImgs();

    self.cur_frame = 0;
    try self.initFrames();
    errdefer self.deinitFrames();

    return self;
}

pub fn recreate(self: *Self, new_extent: vk.Extent2D) !void {
    const vkc = self.vkc;
    const prev = self.handle;
    self.deinitImgs();
    self.deinitFrames();
    self.* = try initRecycle(vkc, new_extent, prev);
}

pub fn deinit(self: Self) void {
    if (self.handle == .null_handle) return;
    self.deinitImgs();
    self.deinitFrames();
    self.vkc.dev.destroySwapchainKHR(self.handle, null);
}

pub fn acqNext(self: *Self) !AcquireResult {
    const res = try self.vkc.dev.acquireNextImageKHR(
        self.handle,
        std.math.maxInt(u64),
        self.getCurFrame().img_acq,
        .null_handle
    );
    if (res.result == .not_ready or res.result == .timeout) {
        return error.ImageAcquireFailed;
    }
    return .{
        .state = switch (res.result) {
            .success => .optimal,
            .suboptimal_khr => .suboptimal,
            else => unreachable,
        },
        .img_idx = res.image_index,
    };
}

// {{{ settings (fmt, mode, extent)
fn findFmt(self: *Self) !void {
    const preferred = vk.SurfaceFormatKHR {
        .format = .b8g8r8a8_srgb,
        .color_space = .srgb_nonlinear_khr,
    };

    const fmts = try self.vkc.inst.getPhysicalDeviceSurfaceFormatsAllocKHR(
        self.vkc.pdev,
        self.vkc.surf,
        self.alloc
    );
    for (fmts) |fmt| {
        if (std.meta.eql(fmt, preferred)) {
            self.fmt = preferred;
            return;
        }
    }

    // there must always be at least one supported format
    self.fmt = fmts[0];
}

fn findMode(self: *Self) !void {
    const modes = try self.vkc.inst.getPhysicalDeviceSurfacePresentModesAllocKHR(
        self.vkc.pdev,
        self.vkc.surf,
        self.alloc
    );
    defer self.alloc.free(modes);

    const preferred = [_]vk.PresentModeKHR { .mailbox_khr, .immediate_khr };
    for (preferred) |mode| {
        if (std.mem.indexOfScalar(vk.PresentModeKHR, modes, mode) != null) {
            self.mode = mode;
            return;
        }
    }

    self.mode = .fifo_khr;
}

fn findActualExtent(
    self: *Self,
    caps: vk.SurfaceCapabilitiesKHR,
    extent: vk.Extent2D
) void {
    if (caps.current_extent.width != std.math.maxInt(u32)) {
        self.extent = caps.current_extent;
    } else {
        self.extent = .{
            .width = std.math.clamp(
                extent.width,
                caps.max_image_extent.width,
                caps.max_image_extent.width
            ),
            .height = std.math.clamp(
                extent.height,
                caps.max_image_extent.height,
                caps.max_image_extent.height
            ),
        };
    }
}
// }}}

// {{{ images
const SwapImage = struct {
    vkc: *const Vulkan,

    img: vk.Image,
    view: vk.ImageView,
    framebuffer: ?vk.Framebuffer,
    render_done: vk.Semaphore,

    fn init(vkc: *const Vulkan, fmt: vk.Format, img: vk.Image) !SwapImage {
        var self: SwapImage = undefined;

        self.vkc = vkc;

        self.img = img;
        self.view = try vkc.dev.createImageView(&.{
            .image = img,
            .view_type = .@"2d",
            .format = fmt,
            .components = .{
                .r = .identity,
                .g = .identity,
                .b = .identity,
                .a = .identity,
            },
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }, null);
        errdefer vkc.dev.destroyImageView(self.view, null);

        // the framebuffer is overwritten later when we have created the render pass
        self.framebuffer = null;

        self.render_done = try vkc.dev.createSemaphore(&.{}, null);

        return self;
    }

    fn createFramebuffer(
        self: *SwapImage,
        extent: vk.Extent2D,
        render_pass: vk.RenderPass
    ) !void {
        self.framebuffer = try self.vkc.dev.createFramebuffer(&.{
            .render_pass = render_pass,
            .attachment_count = 1,
            .p_attachments = (&self.view)[0..1],
            .width = extent.width,
            .height = extent.height,
            .layers = 1,
        }, null);
    }

    fn deinit(self: SwapImage) void {
        self.vkc.dev.destroySemaphore(self.render_done, null);
        if (self.framebuffer) |fb| {
            self.vkc.dev.destroyFramebuffer(fb, null);
        }
        self.vkc.dev.destroyImageView(self.view, null);
    }
};

fn initImgs(self: *Self) !void {
    const imgs = try self.vkc.dev.getSwapchainImagesAllocKHR(
        self.handle,
        self.alloc
    );
    defer self.alloc.free(imgs);

    self.imgs = try self.alloc.alloc(SwapImage, imgs.len);
    errdefer self.alloc.free(self.imgs);

    var i: usize = 0;
    // when error occurs, only clean up images up to image i
    errdefer for (self.imgs[0..i]) |img| img.deinit();

    for (imgs) |img| {
        self.imgs[i] = try SwapImage.init(self.vkc, self.fmt.format, img);
        i += 1;
    }
}

fn deinitImgs(self: Self) void {
    for (self.imgs) |img| img.deinit();
    self.alloc.free(self.imgs);
}
// }}}

// {{{ frames
const Frame = struct {
    vkc: *const Vulkan,

    cmd_pool: vk.CommandPool,
    cmd_buf: vk.CommandBufferProxy,

    img_acq: vk.Semaphore,
    fence: vk.Fence,

    fn init(vkc: *const Vulkan) !Frame {
        var self: Frame = undefined;

        self.vkc = vkc;

        self.cmd_pool = try vkc.dev.createCommandPool(&.{
            .flags = .{ .reset_command_buffer_bit = true },
            .queue_family_index = self.vkc.queue_config.graphics_family,
        }, null);
        errdefer vkc.dev.destroyCommandPool(self.cmd_pool, null);

        var cmd_buf: vk.CommandBuffer = undefined;
        try vkc.dev.allocateCommandBuffers(&.{
            .command_pool = self.cmd_pool,
            .command_buffer_count = 1,
            .level = .primary,
        }, (&cmd_buf)[0..1]);
        self.cmd_buf = vk.CommandBufferProxy.init(cmd_buf, &vkc.vkd);

        self.img_acq = try vkc.dev.createSemaphore(&.{}, null);
        errdefer vkc.dev.destroySemaphore(self.img_acq, null);

        self.fence = try vkc.dev.createFence(&.{
            .flags = .{ .signaled_bit = true },
        }, null);

        return self;
    }

    fn deinit(self: Frame) void {
        self.wait() catch {};
        self.vkc.dev.destroyFence(self.fence, null);
        self.vkc.dev.destroySemaphore(self.img_acq, null);
        self.vkc.dev.destroyCommandPool(self.cmd_pool, null);
    }

    pub fn wait(self: *const Frame) !void {
        // TODO: the synchronization logic here is broken. when this timeout is set to std.math.maxInt(u64), the entire application freezes.
        _ = try self.vkc.dev.waitForFences(1, @ptrCast(&self.fence), vk.TRUE, 1_000_000_000);
    }

    pub fn resetFence(self: *const Frame) !void {
        try self.vkc.dev.resetFences(1, (&self.fence)[0..1]);
    }
};

fn initFrames(self: *Self) !void {
    var i: usize = 0;
    errdefer for (self.frames[0..i]) |frame| frame.deinit();

    for (0..FRAMES_IN_FLIGHT) |_| {
        self.frames[i] = try Frame.init(self.vkc);
        i += 1;
    }
}

fn deinitFrames(self: *const Self) void {
    for (self.frames) |frame| {
        frame.deinit();
    }
}

pub fn getCurFrame(self: *Self) *Frame {
    return &self.frames[self.cur_frame % FRAMES_IN_FLIGHT];
}

pub fn nextFrame(self: *Self) void {
    self.cur_frame +%= 1;
}
// }}}
