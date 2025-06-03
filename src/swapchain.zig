const std = @import("std");
const vk = @import("vulkan");

const VulkanCtx = @import("vk.zig");
const Self = @This();

pub const PresentState = enum {
    optimal,
    suboptimal,
};

vkc: *const VulkanCtx,
alloc: std.mem.Allocator,

fmt: vk.SurfaceFormatKHR,
mode: vk.PresentModeKHR,
extent: vk.Extent2D,
handle: vk.SwapchainKHR,

imgs: []SwapImage,
img_idx: u32,
next_img_acq: vk.Semaphore,

pub fn init(
    vkc: *const VulkanCtx,
    extent: vk.Extent2D,
) !Self {
    return try initRecycle(vkc, extent, .null_handle);
}

pub fn initRecycle(
    vkc: *const VulkanCtx,
    extent: vk.Extent2D,
    prev: vk.SwapchainKHR,
) !Self {
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

    const families = [_]u32 {
        vkc.graphics_q.family,
        vkc.compute_q.family,
        vkc.present_q.family
    };
    const sharing_mode: vk.SharingMode = if (vkc.unique_families > 1)
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

    try self.initImgs();
    errdefer self.deinitImgs();

    self.next_img_acq = try vkc.dev.createSemaphore(&.{}, null);
    errdefer vkc.dev.destroySemaphore(self.next_img_acq, null);

    const res = try vkc.dev.acquireNextImageKHR(
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
    img_acq: vk.Semaphore,
    render_finished: vk.Semaphore,
    frame_fence: vk.Fence,

    fn init(vkc: *const VulkanCtx, fmt: vk.Format, img: vk.Image) !SwapImage {
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

    fn deinit(self: SwapImage, vkc: *const VulkanCtx) void {
        self.wait(vkc) catch return;
        vkc.dev.destroyFence(self.frame_fence, null);
        vkc.dev.destroySemaphore(self.img_acq, null);
        vkc.dev.destroySemaphore(self.render_finished, null);
        vkc.dev.destroyImageView(self.view, null);
    }

    fn wait(self: SwapImage, vkc: *const VulkanCtx) !void {
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
