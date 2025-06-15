const std = @import("std");
const vk = @import("vulkan");

const Vulkan = @import("vk.zig");
const Self = @This();

pub const PresentState = enum {
    optimal,
    suboptimal,
};

vkc: *const Vulkan,
alloc: std.mem.Allocator,

fmt: vk.SurfaceFormatKHR,
mode: vk.PresentModeKHR,
extent: vk.Extent2D,
handle: vk.SwapchainKHR,

imgs: []SwapImage,
img_idx: u32,
next_img_acq: vk.Semaphore,

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
    for (self.imgs) |img| {
        self.imgs[i].framebuffer = try self.vkc.dev.createFramebuffer(&.{
            .render_pass = render_pass,
            .attachment_count = 1,
            .p_attachments = (&img.view)[0..1],
            .width = self.extent.width,
            .height = self.extent.height,
            .layers = 1,
        }, null);
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

    self.next_img_acq = try vkc.dev.createSemaphore(&.{}, null);
    errdefer vkc.dev.destroySemaphore(self.next_img_acq, null);

    try self.acqNext();

    return self;
}

pub fn recreate(self: *Self, new_extent: vk.Extent2D) !void {
    const vkc = self.vkc;
    const alloc = self.alloc;
    const prev = self.handle;
    self.deinitPartial();
    self.* = try initRecycle(vkc, alloc, new_extent, prev);
}

pub fn deinit(self: Self) void {
    self.deinitPartial();
    self.vkc.dev.destroySwapchainKHR(self.handle, null);
}

fn deinitPartial(self: Self) void {
    self.deinitImgs();
    self.vkc.dev.destroySemaphore(self.next_img_acq, null);
}

pub fn getImg(self: *Self) SwapImage {
    return self.imgs[self.img_idx];
}

pub fn acqNext(self: *Self) !void {
    const res = try self.vkc.dev.acquireNextImageKHR(
        self.handle,
        std.math.maxInt(u64),
        self.next_img_acq,
        .null_handle
    );
    if (res.result != .success) {
        return error.ImageAcquireFailed;
    }
    std.mem.swap(vk.Semaphore,
        &self.imgs[res.image_index].img_acq,
        &self.next_img_acq
    );
}

pub fn waitAll(self: Self) !void {
    for (self.imgs) |si| si.wait(self.vkc) catch {};
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
    img: vk.Image,
    view: vk.ImageView,
    framebuffer: ?vk.Framebuffer,

    img_acq: vk.Semaphore,
    render_finished: vk.Semaphore,
    frame_fence: vk.Fence,

    fn init(vkc: *const Vulkan, fmt: vk.Format, img: vk.Image) !SwapImage {
        var self: SwapImage = undefined;

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

        self.img_acq = try vkc.dev.createSemaphore(&.{}, null);
        errdefer vkc.dev.destroySemaphore(self.img_acq, null);

        self.render_finished = try vkc.dev.createSemaphore(&.{}, null);
        errdefer vkc.dev.destroySemaphore(self.render_finished, null);

        self.frame_fence = try vkc.dev.createFence(&.{
            .flags = .{ .signaled_bit = true },
        }, null);
        errdefer vkc.dev.destroyFence(self.frame_fence, null);

        return self;
    }

    fn deinit(self: SwapImage, vkc: *const Vulkan) void {
        self.wait(vkc) catch return;
        vkc.dev.destroyFence(self.frame_fence, null);
        vkc.dev.destroySemaphore(self.img_acq, null);
        vkc.dev.destroySemaphore(self.render_finished, null);
        if (self.framebuffer) |fb| {
            vkc.dev.destroyFramebuffer(fb, null);
        }
        vkc.dev.destroyImageView(self.view, null);
    }

    fn wait(self: SwapImage, vkc: *const Vulkan) !void {
        _ = try vkc.dev.waitForFences(1,
            @ptrCast(&self.frame_fence),
            vk.TRUE,
            std.math.maxInt(u64)
        );
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
    errdefer for (self.imgs[0..i]) |si| si.deinit(self.vkc);

    for (imgs) |img| {
        self.imgs[i] = try SwapImage.init(self.vkc, self.fmt.format, img);
        i += 1;
    }
}

fn deinitImgs(self: Self) void {
    for (self.imgs) |img| img.deinit(self.vkc);
    self.alloc.free(self.imgs);
}
// }}}
