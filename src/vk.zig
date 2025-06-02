const std = @import("std");
const sdl = @import("sdl2");
const vk = @import("vulkan");

const log = @import("log.zig");
const Swapchain = @import("swapchain.zig");
const Cstr = [*:0]const u8;
const Self = @This();

alloc: std.mem.Allocator,

loader: vk.PfnGetInstanceProcAddr,
vkb: vk.BaseWrapper,
vki: vk.InstanceWrapper,
vkd: vk.DeviceWrapper,

debug_msgr: vk.DebugUtilsMessengerEXT,
inst: vk.InstanceProxy,
surf: vk.SurfaceKHR,

pdev: vk.PhysicalDevice,
pdev_props: vk.PhysicalDeviceProperties,

dev: vk.DeviceProxy,
unique_families: u32,
graphics_q: Queue,
compute_q: Queue,
present_q: Queue,

swapchain: Swapchain,

const VALIDATION_ENABLED = @import("builtin").mode == .Debug;
const REQUIRED_VALIDATION_LAYERS = [_]Cstr { "VK_LAYER_KHRONOS_validation" };
const REQUIRED_DEVICE_EXTS = [_]Cstr { "VK_KHR_swapchain" };

// {{{ debug messenger
const DEBUG_MSGR_CREATE_INFO = vk.DebugUtilsMessengerCreateInfoEXT {
    .message_severity = .{
        .verbose_bit_ext = true,
        .info_bit_ext = true,
        .warning_bit_ext = true,
        .error_bit_ext = true,
    },
    .message_type = .{
        .general_bit_ext = true,
        .validation_bit_ext = true,
        .performance_bit_ext = true,
    },
    .pfn_user_callback = printDebugMsg,
};

// this is a vk.PfnDebugUtilsMessengerCallbackEXT
fn printDebugMsg(
    severity: vk.DebugUtilsMessageSeverityFlagsEXT,
    msg_type: vk.DebugUtilsMessageTypeFlagsEXT,
    p_callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
    _: ?*anyopaque,
) callconv(vk.vulkan_call_conv) vk.Bool32 {
    var scope: ?Cstr = null;
    if (msg_type.validation_bit_ext) {
        scope = "val";
    } else if (msg_type.performance_bit_ext) {
        scope = "perf";
    }
    const msg = p_callback_data.?.p_message.?;

    log.print(log.Severity.fromFlags(severity), scope, "{s}", .{ msg });

    return vk.FALSE;
}
// }}}

pub fn init(alloc: std.mem.Allocator, window: *sdl.Window) !Self {
    var self: Self = undefined;

    try sdl.vulkan.loadLibrary(null);
    errdefer sdl.vulkan.unloadLibrary();

    self.alloc = alloc;
    self.loader = try sdl.vulkan.getVkGetInstanceProcAddr();
    self.vkb = vk.BaseWrapper.load(self.loader);

    try self.createInstance(window);
    errdefer self.inst.destroyInstance(null);

    self.debug_msgr = try self.inst.createDebugUtilsMessengerEXT(
        &DEBUG_MSGR_CREATE_INFO,
        null,
    );
    errdefer self.inst.destroyDebugUtilsMessengerEXT(self.debug_msgr, null);

    self.surf = try sdl.vulkan.createSurface(window.*, self.inst.handle);
    errdefer self.inst.destroySurfaceKHR(self.surf, null);

    try self.createDevice(try self.pickPhysDevice());
    errdefer self.dev.destroyDevice(null);

    const extent: vk.Extent2D = .{
        .height = @intCast(window.getSize().height),
        .width = @intCast(window.getSize().width),
    };
    self.swapchain = try Swapchain.init(&self, self.alloc, extent);
    errdefer self.swapchain.deinit();

    return self;
}

pub fn deinit(self: Self) void {
    self.swapchain.deinit();
    self.dev.destroyDevice(null);
    self.inst.destroySurfaceKHR(self.surf, null);
    self.inst.destroyDebugUtilsMessengerEXT(self.debug_msgr, null);
    self.inst.destroyInstance(null);
    sdl.vulkan.unloadLibrary();
}

// {{{ instance
fn createInstance(self: *Self, window: *sdl.Window) !void {
    if (VALIDATION_ENABLED and !try self.checkValidationSupport()) {
        return error.ValidationLayersUnavailable;
    }

    const num_exts = sdl.vulkan.getInstanceExtensionsCount(window.*);
    var exts = try std.ArrayList(Cstr).initCapacity(self.alloc, num_exts + 1);
    defer exts.deinit();

    const buf = try self.alloc.alloc(Cstr, num_exts);
    defer self.alloc.free(buf);
    _ = try sdl.vulkan.getInstanceExtensions(window.*, buf);
    try exts.appendSlice(buf);

    if (VALIDATION_ENABLED) {
        try exts.append(vk.extensions.ext_debug_utils.name);
    }

    const app_name = "Hello world!";
    var create_info = vk.InstanceCreateInfo {
        .p_application_info = &.{
            .p_application_name = app_name,
            .application_version = @bitCast(vk.makeApiVersion(0, 0, 1, 0)),
            .p_engine_name = app_name,
            .engine_version = @bitCast(vk.makeApiVersion(0, 0, 1, 0)),
            .api_version = @bitCast(vk.API_VERSION_1_3),
        },
        .enabled_extension_count = @intCast(exts.items.len),
        .pp_enabled_extension_names = @ptrCast(exts.items.ptr),
    };

    if (VALIDATION_ENABLED) {
        create_info.enabled_layer_count = REQUIRED_VALIDATION_LAYERS.len;
        create_info.pp_enabled_layer_names = &REQUIRED_VALIDATION_LAYERS;
        create_info.p_next = &DEBUG_MSGR_CREATE_INFO;
    } else {
        create_info.enabled_layer_count = 0;
        create_info.pp_enabled_layer_names = null;
        create_info.p_next = null;
    }

    const inst = try self.vkb.createInstance(&create_info, null);
    self.vki = vk.InstanceWrapper.load(inst, self.loader);
    self.inst = vk.InstanceProxy.init(inst, &self.vki);
}

fn checkValidationSupport(self: *const Self) !bool {
    const layers = try self.vkb.enumerateInstanceLayerPropertiesAlloc(self.alloc);
    defer self.alloc.free(layers);

    for (REQUIRED_VALIDATION_LAYERS) |layer| {
        var found = false;
        for (layers) |props| {
            // Needed in order to change the length of the layer name from 256 to
            // however long it actually is, so that eql returns true
            const rhs = std.mem.sliceTo(&props.layer_name, 0);
            if (std.mem.eql(u8, std.mem.span(layer), rhs)) {
                found = true;
                break;
            }
        }
        if (!found) {
            return false;
        }
    }
    return true;
}
// }}}

// {{{ physical device
const PdevCandidate = struct {
    score: u32,
    pdev: vk.PhysicalDevice,
    props: vk.PhysicalDeviceProperties,
    queues: QueueConfiguration,
};

const QueueConfiguration = struct {
    graphics_family: u32,
    compute_family: u32,
    present_family: u32,

    fn countUnique(self: *const QueueConfiguration) u32 {
        var seen = [_]?u32 {null} ** 3;
        var n: u32 = 0;

        const families = [_]u32 {
            self.graphics_family,
            self.compute_family,
            self.present_family
        };
        for (families) |family| {
            const already_seen = for (seen) |seen_family| {
                if (seen_family != null and family == seen_family.?) {
                    break true;
                }
            } else false;

            if (!already_seen) {
                seen[n] = family;
                n += 1;
            }
        }
        return n;
    }
};

fn pickPhysDevice(self: *Self) !PdevCandidate {
    const pdevs = try self.inst.enumeratePhysicalDevicesAlloc(self.alloc);
    defer self.alloc.free(pdevs);

    if (pdevs.len == 0) {
        return error.NoSupportedGPU;
    }

    var best_score: u32 = 0;
    var best_candidate: ?PdevCandidate = null;

    for (pdevs) |pdev| {
        const candidate = scorePhysDevice(self.alloc, self.inst, self.surf, pdev)
            orelse continue;
        if (candidate.score > best_score) {
            best_score = candidate.score;
            best_candidate = candidate;
        }
    }
    if (best_candidate == null) {
        return error.NoSupportedGPU;
    }

    self.pdev = best_candidate.?.pdev;
    self.pdev_props = best_candidate.?.props;
    return best_candidate.?;
}

// TODO: improve this metric
fn scorePhysDevice(
    alloc: std.mem.Allocator,
    inst: vk.InstanceProxy,
    surf: vk.SurfaceKHR,
    pdev: vk.PhysicalDevice,
) ?PdevCandidate {
    const ext_supported = checkExtSupport(alloc, inst, pdev) catch false;
    if (!ext_supported) {
        return null;
    }

    const surf_supported = checkSurfSupport(inst, surf, pdev) catch false;
    if (!surf_supported) {
        return null;
    }

    const queues = findQueues(alloc, inst, surf, pdev) catch null;
    if (queues) |config| {
        var score: u32 = 0;
        const props = inst.getPhysicalDeviceProperties(pdev);

        if (props.device_type == .discrete_gpu) {
            score += 1_000_000;
        }
        score += props.limits.max_compute_shared_memory_size;

        return PdevCandidate {
            .score = score,
            .pdev = pdev,
            .props = props,
            .queues = config,
        };
    }

    return null;
}

fn checkSurfSupport(
    inst: vk.InstanceProxy,
    surf: vk.SurfaceKHR,
    pdev: vk.PhysicalDevice,
) !bool {
    var num_fmts: u32 = undefined;
    _ = try inst.getPhysicalDeviceSurfaceFormatsKHR(
        pdev, surf, &num_fmts, null
    );

    var num_modes: u32 = undefined;
    _ = try inst.getPhysicalDeviceSurfacePresentModesKHR(
        pdev, surf, &num_modes, null
    );

    return num_fmts > 0 and num_modes > 0;
}

fn checkExtSupport(
    alloc: std.mem.Allocator,
    inst: vk.InstanceProxy,
    pdev: vk.PhysicalDevice,
) !bool {
    const exts = try inst.enumerateDeviceExtensionPropertiesAlloc(
        pdev, null, alloc
    );
    defer alloc.free(exts);

    for (REQUIRED_DEVICE_EXTS) |ext| {
        var found = false;
        for (exts) |props| {
            const rhs = std.mem.sliceTo(&props.extension_name, 0);
            if (std.mem.eql(u8, std.mem.span(ext), rhs)) {
                found = true;
                break;
            }
        }
        if (!found) {
            return false;
        }
    }
    return true;
}

fn findQueues(
    alloc: std.mem.Allocator,
    inst: vk.InstanceProxy,
    surf: vk.SurfaceKHR,
    pdev: vk.PhysicalDevice,
) !?QueueConfiguration {
    const families = try inst.getPhysicalDeviceQueueFamilyPropertiesAlloc(
        pdev,
        alloc
    );
    defer alloc.free(families);

    var graphics_family: ?u32 = null;
    var compute_family: ?u32 = null;
    var present_family: ?u32 = null;

    for (families, 0..) |properties, i| {
        const family: u32 = @intCast(i);

        if (graphics_family == null and properties.queue_flags.graphics_bit) {
            graphics_family = family;
        }
        if (compute_family == null and properties.queue_flags.compute_bit) {
            compute_family = family;
        }

        const supported = try inst.getPhysicalDeviceSurfaceSupportKHR(
            pdev,
            family,
            surf
        );
        if (present_family == null and supported == vk.TRUE) {
            present_family = family;
        }
    }

    if (graphics_family != null and present_family != null) {
        return .{
            .graphics_family = graphics_family.?,
            .compute_family = compute_family.?,
            .present_family = present_family.?,
        };
    }

    return null;
}
// }}}

// {{{ logical device and queues
pub const Queue = struct {
    handle: vk.Queue,
    family: u32,

    fn init(dev: vk.DeviceProxy, family: u32) Queue {
        return .{
            .handle = dev.getDeviceQueue(family, 0),
            .family = family,
        };
    }
};

fn createDevice(self: *Self, candidate: PdevCandidate) !void {
    self.unique_families = candidate.queues.countUnique();

    const priority = [_]f32 {1};
    const dev = try self.inst.createDevice(self.pdev, &.{
        .queue_create_info_count = self.unique_families,
        .p_queue_create_infos = &.{
            .{
                .queue_family_index = candidate.queues.graphics_family,
                .queue_count = 1,
                .p_queue_priorities = &priority,
            },
            .{
                .queue_family_index = candidate.queues.compute_family,
                .queue_count = 1,
                .p_queue_priorities = &priority,
            },
            .{
                .queue_family_index = candidate.queues.present_family,
                .queue_count = 1,
                .p_queue_priorities = &priority,
            },
        },
        .enabled_extension_count = @intCast(REQUIRED_DEVICE_EXTS.len),
        .pp_enabled_extension_names = @ptrCast(&REQUIRED_DEVICE_EXTS),
    }, null);

    self.vkd = vk.DeviceWrapper.load(dev, self.vki.dispatch.vkGetDeviceProcAddr.?);
    self.dev = vk.DeviceProxy.init(dev, &self.vkd);

    // retrieve queues
    self.graphics_q = Queue.init(self.dev, candidate.queues.graphics_family);
    self.compute_q = Queue.init(self.dev, candidate.queues.compute_family);
    self.present_q = Queue.init(self.dev, candidate.queues.present_family);
}
// }}}

pub fn presentFrame(_: *Self) !void {}
