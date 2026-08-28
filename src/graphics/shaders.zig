const std = @import("std");
const vk = @import("vk");

pub const Pipeline = struct {
    device: vk.Device,
    handle: vk.Pipeline,
    layout: vk.PipelineLayout,

    descriptor_set_layouts: []vk.DescriptorSetLayout,

    pub fn init(device: vk.Device, descriptor_set_layouts: []vk.DescriptorSetLayout) !Pipeline {        
        const pipeline_layout_info = vk.PipelineLayoutCreateInfo {
            .sType = .pipeline_layout_create_info,
            .setLayoutCount = @intCast(descriptor_set_layouts.len),
            .pSetLayouts = descriptor_set_layouts.ptr
        };

        var layout: vk.PipelineLayout = undefined;
        vk.createPipelineLayout(device, &pipeline_layout_info, null, &layout) catch |err| {
            std.log.err("failed to create pipeline layout. error : {any}", .{ err });
            return err;
        };
        errdefer vk.destroyPipelineLayout(device, layout, null);

        return .{
            .device = device,
            .layout = layout,
            .handle = .null_handle,
            .descriptor_set_layouts = descriptor_set_layouts
        };
    }

    /// Build a compute shader
    pub fn buildCompute(self: *Pipeline, device: vk.Device, module: vk.ShaderModule) !void {
        const stage_info = vk.PipelineShaderStageCreateInfo {
            .sType = .pipeline_shader_stage_create_info,
            .module = module,
            .pName = "main",
            .stage = .{ .compute_bit = true },
        };

        const create_pipeline_info = vk.ComputePipelineCreateInfo {
            .sType = .compute_pipeline_create_info,
            .layout = self.layout,
            .stage = stage_info,
        };

        if (self.handle != .null_handle) {
            std.log.warn("pipeline already exist.", .{});
            return;
        }

        vk.createComputePipelines(device, .null_handle, 1, &create_pipeline_info, null, &self.handle) catch |err| {
            std.log.err("failed to create pipeline. error : {any}", .{err});
            return err;
        };
    }

    /// Build a graphics pipeline (vertex + fragment) using dynamic rendering, no vertex input,
    /// a triangle-list topology and a dynamic viewport/scissor. No depth test.
    pub fn buildGraphics(self: *Pipeline, device: vk.Device, vertex_module: vk.ShaderModule, fragment_module: vk.ShaderModule, color_format: vk.Format) !void {
        const stages = [_]vk.PipelineShaderStageCreateInfo {
            .{
                .sType = .pipeline_shader_stage_create_info,
                .module = vertex_module,
                .pName = "main",
                .stage = .{ .vertex_bit = true },
            },
            .{
                .sType = .pipeline_shader_stage_create_info,
                .module = fragment_module,
                .pName = "main",
                .stage = .{ .fragment_bit = true },
            },
        };

        const vertex_input_state = vk.PipelineVertexInputStateCreateInfo {
            .sType = .pipeline_vertex_input_state_create_info,
        };

        const input_assembly_state = vk.PipelineInputAssemblyStateCreateInfo {
            .sType = .pipeline_input_assembly_state_create_info,
            .topology = .triangle_list,
            .primitiveRestartEnable = 0,
        };

        const viewport_state = vk.PipelineViewportStateCreateInfo {
            .sType = .pipeline_viewport_state_create_info,
            .viewportCount = 1,
            .scissorCount = 1,
        };

        const rasterization_state = vk.PipelineRasterizationStateCreateInfo {
            .sType = .pipeline_rasterization_state_create_info,
            .polygonMode = .fill,
            .cullMode = .{},
            .frontFace = .clockwise,
            .lineWidth = 1.0,
        };

        const multisample_state = vk.PipelineMultisampleStateCreateInfo {
            .sType = .pipeline_multisample_state_create_info,
            .rasterizationSamples = .{ .@"1_bit" = true },
            .sampleShadingEnable = 0,
            .minSampleShading = 1.0,
        };

        const color_blend_attachment = vk.PipelineColorBlendAttachmentState {
            .blendEnable = 1,
            .srcColorBlendFactor = .src_alpha,
            .dstColorBlendFactor = .one_minus_src_alpha,
            .colorBlendOp = .add,
            .srcAlphaBlendFactor = .one,
            .dstAlphaBlendFactor = .zero,
            .alphaBlendOp = .add,
            .colorWriteMask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
        };

        const color_blend_attachments = [_]vk.PipelineColorBlendAttachmentState { color_blend_attachment };
        const color_blend_state = vk.PipelineColorBlendStateCreateInfo {
            .sType = .pipeline_color_blend_state_create_info,
            .logicOpEnable = 0,
            .logicOp = .copy,
            .attachmentCount = 1,
            .pAttachments = &color_blend_attachments,
        };

        const dynamic_states = [_]vk.DynamicState { .viewport, .scissor };
        const dynamic_state = vk.PipelineDynamicStateCreateInfo {
            .sType = .pipeline_dynamic_state_create_info,
            .dynamicStateCount = dynamic_states.len,
            .pDynamicStates = &dynamic_states,
        };

        const color_formats = [_]vk.Format { color_format };
        const rendering_create_info = vk.PipelineRenderingCreateInfo {
            .sType = .pipeline_rendering_create_info,
            .colorAttachmentCount = 1,
            .pColorAttachmentFormats = &color_formats,
        };

        const create_pipeline_info = vk.GraphicsPipelineCreateInfo {
            .sType = .graphics_pipeline_create_info,
            .pNext = &rendering_create_info,
            .stageCount = stages.len,
            .pStages = &stages,
            .pVertexInputState = &vertex_input_state,
            .pInputAssemblyState = &input_assembly_state,
            .pViewportState = &viewport_state,
            .pRasterizationState = &rasterization_state,
            .pMultisampleState = &multisample_state,
            .pColorBlendState = &color_blend_state,
            .pDynamicState = &dynamic_state,
            .layout = self.layout,
            .renderPass = .null_handle,
            .subpass = 0,
            .basePipelineHandle = .null_handle,
            .basePipelineIndex = -1,
        };

        if (self.handle != .null_handle) {
            std.log.warn("pipeline already exist.", .{});
            return;
        }

        vk.createGraphicsPipelines(device, .null_handle, 1, &create_pipeline_info, null, &self.handle) catch |err| {
            std.log.err("failed to create graphics pipeline. error : {any}", .{err});
            return err;
        };
    }

    pub fn deinit(self: *Pipeline, allocator: std.mem.Allocator) void {
        vk.destroyPipeline(self.device, self.handle, null);
        vk.destroyPipelineLayout(self.device, self.layout, null);

        for (self.descriptor_set_layouts) |layout| {
            vk.destroyDescriptorSetLayout(self.device, layout, null);
        }
        allocator.free(self.descriptor_set_layouts);
    }
};

pub fn load_shader_module(io: std.Io, allocator: std.mem.Allocator, path: []const u8, device: vk.Device) !vk.ShaderModule {
    const buffer = std.Io.Dir.readFileAlloc(std.Io.Dir.cwd(), io, path, allocator, .unlimited) catch |err| {
        std.log.err("failed to read shader file. error : {any}", .{err});
        return Error.LoadFailed;
    };
    defer allocator.free(buffer);

    const create_info = vk.ShaderModuleCreateInfo {
        .sType = .shader_module_create_info,
        .codeSize = buffer.len,
        .pCode = @alignCast(@ptrCast(buffer.ptr)),
    };
    
    var shader_module: vk.ShaderModule = undefined;
    vk.createShaderModule(device, &create_info, null, &shader_module) catch |err| {
        std.log.err("failed to create shader module. error : {any}", .{ err });
        return Error.LoadFailed;
    };

    return shader_module;
}

pub const Error = error {
    LoadFailed
};

const descriptors = @import("descriptors.zig");
