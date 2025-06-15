const std = @import("std");
const vk = @import("vulkan");

const Vulkan = @import("vk.zig");
const Self = @This();

const frag_spv align(@alignOf(u32)) = @embedFile("fragment_shader").*;
const vert_spv align(@alignOf(u32)) = @embedFile("vertex_shader").*;

vkc: *const Vulkan,

render_pass: vk.RenderPass,
pipeline_layout: vk.PipelineLayout,
graphics_pipeline: vk.Pipeline,

pub fn init(vkc: *const Vulkan, extent: vk.Extent2D, fmt: vk.Format) !Self {
    var self: Self = undefined;

    self.vkc = vkc;

    const frag_mod = try createModule(vkc, @ptrCast(&frag_spv));
    defer self.vkc.dev.destroyShaderModule(frag_mod, null);
    const vert_mod = try createModule(vkc, @ptrCast(&vert_spv));
    defer self.vkc.dev.destroyShaderModule(vert_mod, null);

    const shader_stages = [_]vk.PipelineShaderStageCreateInfo {
        .{
            .stage = .{ .fragment_bit = true },
            .module = frag_mod,
            .p_name = "main",
        },
        .{
            .stage = .{ .vertex_bit = true },
            .module = vert_mod,
            .p_name = "main",
        },
    };

    const dyn_states = [_]vk.DynamicState { .viewport, .scissor };
    const dyn_state_info = vk.PipelineDynamicStateCreateInfo {
        .dynamic_state_count = @intCast(dyn_states.len),
        .p_dynamic_states = @ptrCast(&dyn_states),
    };
    const vert_input_info = vk.PipelineVertexInputStateCreateInfo {
        .vertex_binding_description_count = 0,
        .p_vertex_binding_descriptions = null,
        .vertex_attribute_description_count = 0,
        .p_vertex_attribute_descriptions = null,
    };
    const input_assembly_info = vk.PipelineInputAssemblyStateCreateInfo {
        .topology = .triangle_list,
        .primitive_restart_enable = vk.FALSE,
    };

    const viewport = vk.Viewport {
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(extent.width),
        .height = @floatFromInt(extent.height),
        .min_depth = 0.0,
        .max_depth = 1.0,
    };
    const scissor = vk.Rect2D {
        .offset = .{ .x = 0, .y = 0 },
        .extent = extent,
    };
    const viewport_state_info = vk.PipelineViewportStateCreateInfo {
        .viewport_count = 1,
        .p_viewports = (&viewport)[0..1],
        .scissor_count = 1,
        .p_scissors = (&scissor)[0..1],
    };

    const rasterizer_info = vk.PipelineRasterizationStateCreateInfo {
        .depth_bias_enable = vk.FALSE,
        .depth_bias_clamp = 0.0,
        .depth_bias_slope_factor = 0.0,
        .depth_bias_constant_factor = 0.0,
        .depth_clamp_enable = vk.FALSE,
        .rasterizer_discard_enable = vk.FALSE,
        .polygon_mode = .fill,
        .front_face = .clockwise,
        .cull_mode = .{ .back_bit = true },
        .line_width = 1.0,
    };
    const multisample_info = vk.PipelineMultisampleStateCreateInfo {
        .sample_shading_enable = vk.FALSE,
        .rasterization_samples = .{ .@"1_bit" = true },
        .min_sample_shading = 1.0,
        .p_sample_mask = null,
        .alpha_to_coverage_enable = vk.FALSE,
        .alpha_to_one_enable = vk.FALSE,
    };
    const color_blend_attachment = vk.PipelineColorBlendAttachmentState {
        .blend_enable = vk.FALSE,
        .color_write_mask = .{
            .r_bit = true,
            .g_bit = true,
            .b_bit = true,
            .a_bit = true,
        },
        .src_color_blend_factor = .src_alpha,
        .dst_color_blend_factor = .one_minus_src_alpha,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .one,
        .dst_alpha_blend_factor = .zero,
        .alpha_blend_op = .add,
    };
    const color_blend_info = vk.PipelineColorBlendStateCreateInfo {
        .logic_op_enable = vk.FALSE,
        .logic_op = .copy,
        .attachment_count = 1,
        .p_attachments = (&color_blend_attachment)[0..1],
        .blend_constants = [_]f32 { 0.0, 0.0, 0.0, 0.0 },
    };

    self.pipeline_layout = try vkc.dev.createPipelineLayout(&.{
        .set_layout_count = 0,
        .p_set_layouts = null,
        .push_constant_range_count = 0,
        .p_push_constant_ranges = null,
    }, null);
    errdefer vkc.dev.destroyPipelineLayout(self.pipeline_layout, null);

    const color_attachment = vk.AttachmentDescription {
        .format = fmt,
        .samples = .{ .@"1_bit" = true },
        .load_op = .clear,
        .store_op = .store,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        .initial_layout = .undefined,
        .final_layout = .present_src_khr,
    };
    const color_attachment_ref = vk.AttachmentReference {
        .attachment = 0,
        .layout = .color_attachment_optimal,
    };

    const subpass = vk.SubpassDescription {
        .pipeline_bind_point = .graphics,
        .color_attachment_count = 1,
        .p_color_attachments = (&color_attachment_ref)[0..1],
    };

    self.render_pass = try vkc.dev.createRenderPass(&.{
        .attachment_count = 1,
        .p_attachments = (&color_attachment)[0..1],
        .subpass_count = 1,
        .p_subpasses = (&subpass)[0..1],
    }, null);
    errdefer vkc.dev.destroyRenderPass(self.render_pass, null);

    const pipeline_info = vk.GraphicsPipelineCreateInfo {
        .stage_count = 2,
        .p_stages = &shader_stages,
        .p_vertex_input_state = &vert_input_info,
        .p_input_assembly_state = &input_assembly_info,
        .p_viewport_state = &viewport_state_info,
        .p_rasterization_state = &rasterizer_info,
        .p_multisample_state = &multisample_info,
        .p_color_blend_state = &color_blend_info,
        .p_dynamic_state = &dyn_state_info,
        .layout = self.pipeline_layout,
        .render_pass = self.render_pass,
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    };
    _ = try vkc.dev.createGraphicsPipelines(
        .null_handle,
        1,
        (&pipeline_info)[0..1],
        null,
        (&self.graphics_pipeline)[0..1],
    );

    return self;
}

pub fn deinit(self: Self) void {
    self.vkc.dev.destroyPipeline(self.graphics_pipeline, null);
    self.vkc.dev.destroyPipelineLayout(self.pipeline_layout, null);
    self.vkc.dev.destroyRenderPass(self.render_pass, null);
}

fn createModule(vkc: *const Vulkan, spv: []const u32) !vk.ShaderModule {
    return try vkc.dev.createShaderModule(&.{
        .code_size = spv.len * @sizeOf(u32),
        .p_code = spv.ptr,
    }, null);
}
