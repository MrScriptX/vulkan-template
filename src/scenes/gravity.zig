pub const GravityScene = struct {
    allocator: std.mem.Allocator,
    state: State,

    render_graph: render.RenderGraph,

    gravity_shader: GravityShader,
    render_shader: RenderShader,
    buffer: types.Buffer,

    da: allocators.Descriptor,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, device: vk.Device, vma: c.VmaAllocator) !GravityScene {
        const render_graph = render.RenderGraph.init(allocator);

        // create initial state
        const initial_state = State {
            .objects = &.{
                .{
                    .pos = .{ 0, 0 },
                    .mass = 1,
                    .velocity = 0
                },
                .{
                    .pos = .{ 0, 100 },
                    .mass = 1 ,
                    .velocity = 0
                }
            },
            .delta_time = 0,
            .camera_pos = @splat(0),
            .world_size = .{ 800, 600 }
        };

        // allocate data buffer
        const buffer_usage = vk.BufferUsageFlags {
            .storage_buffer_bit = true
        };

        const buffer = try types.Buffer.init(vma, @sizeOf(Object) * initial_state.objects.len, buffer_usage, c.VMA_MEMORY_USAGE_AUTO);

        // upload intial state
        try utils.upload_data_array(Object, vma, buffer.allocation, initial_state.objects);

        const gravity_shader = try GravityShader.init(allocator, io, device);
        const render_shader = try RenderShader.init(allocator, io, device);

        // material
        const pool_sizes = [_]descriptors.PoolSizeRatio {
            .{
                .kind = .storage_buffer,
                .ratio = 1
            }
        };

        return .{
            .allocator = allocator,
            .state = initial_state,
            .render_graph = render_graph,
            .gravity_shader = gravity_shader,
            .render_shader = render_shader,
            .buffer = buffer,
            .da = try allocators.Descriptor.init(allocator, device, 2, &pool_sizes)
        };
    }

    pub fn deinit(self: *GravityScene, vma: c.VmaAllocator, device: vk.Device) void {
        self.da.deinit(device);
        self.render_graph.deinit();
        self.render_shader.deinit();
        self.gravity_shader.deinit();
        self.buffer.deinit(vma);
    }

    pub fn update(self: *GravityScene, dt: i96, draw_resource: *const render.DrawResource) !void {
        // update scene

        
        // update scene data
        const shader_data = GravityShader.Data {
            .object_buffer = self.buffer.handle,
            .object_offset = 0,
            .descriptor_set = try self.da.allocate(self.gravity_shader.layouts[0])
        };
        self.gravity_shader.write(shader_data);

        const render_shader_data = RenderShader.Data {
            .object_buffer = self.buffer.handle,
            .object_offset = 0,
            .descriptor_set = try self.da.allocate(self.render_shader.layouts[0])
        };
        self.render_shader.write(render_shader_data);

        // build render graph
        self.render_graph.clear();

        const compute_object_resource = render.BufferResource {
            .buffer = &self.buffer,
            .access = .{
                .shader_storage_read_bit = true,
                .shader_storage_write_bit = true,
            },
            .stage = .{
                .compute_shader_bit = true
            }
        };

        // gravity compute pass
        self.gravity_shader.push_constant = .{
            .delta_time = @divTrunc(@as(i32, @intCast(dt)), 100)
        };
        const gravity_pass_ctx = render.Context {
            .pipeline = &self.gravity_shader.pipeline,
            .descriptor_sets = &self.gravity_shader.bound_descriptor_sets,
            .push_constant = vk.PushConstantsInfo{
                .sType = .push_constants_info,
                .layout = self.gravity_shader.pipeline.layout,
                .stageFlags = .{
                    .compute_bit = true
                },
                .size = @sizeOf(GravityShader.PushConstant),
                .pValues = &self.gravity_shader.push_constant
            },
            .dispatch_size = .{ @intCast(self.state.objects.len), 1, 1 }
        };
        var gravity_pass = render.RenderPass.init(self.allocator, &compute_gravity, gravity_pass_ctx);
        try gravity_pass.addBuffer(compute_object_resource);
        try self.render_graph.addPass(gravity_pass);

        // render pass
        const render_resource = render.ImageResource {
            .image = &draw_resource.color_image,
            .layout = .color_attachment_optimal
        };

        const render_object_resource = render.BufferResource {
            .buffer = &self.buffer,
            .access = .{
                .shader_storage_read_bit = true,
            },
            .stage = .{
                .vertex_shader_bit = true
            }
        };

        self.render_shader.push_constant.world_size = @floatFromInt(self.state.world_size);
        self.render_shader.push_constant.camera_pos = @splat(0); // UPDATE camera with mouse
        const render_ctx = render.Context {
            .pipeline = &self.render_shader.pipeline,
            .descriptor_sets = &self.render_shader.bound_descriptor_sets,
            .dispatch_size = .{ 0, 0, 0 },
            .color_view = draw_resource.color_image.image_view,
            .extent = .{
                .width = draw_resource.color_image.extent.width,
                .height = draw_resource.color_image.extent.height,
            },
            .vertex_count = 6,
            .instance_count = @intCast(self.state.objects.len),
            .push_constant = vk.PushConstantsInfo {
                .sType = .push_constants_info,
                .layout = self.render_shader.pipeline.layout,
                .stageFlags = .{
                    .vertex_bit = true
                },
                .size = @sizeOf(RenderShader.PushConstant),
                .pValues = &self.render_shader.push_constant
            },
        };
        var render_pass = render.RenderPass.init(self.allocator, &render_objects, render_ctx);
        try render_pass.addImage(render_resource);
        try render_pass.addBuffer(render_object_resource);
        try self.render_graph.addPass(render_pass);

        try self.render_graph.setOutput(render_resource);
    }

    pub fn draw(ptr: *anyopaque, cmd: vk.CommandBuffer) void {
        const self: *GravityScene = @ptrCast(@alignCast(ptr));
        self.render_graph.exec(cmd);
    }

    const State = struct {
        objects: []const Object,
        delta_time: f32,
        world_size: @Vector(2, u32),
        camera_pos: @Vector(2, u32)
    };
};

fn compute_gravity(cmd: vk.CommandBuffer, ctx: *const render.Context) void {
    vk.cmdBindPipeline(cmd, .compute, ctx.pipeline.handle);
    vk.cmdBindDescriptorSets(cmd, .compute, ctx.pipeline.layout, 0, @intCast(ctx.descriptor_sets.len), ctx.descriptor_sets.ptr, 0, null);
    
    vk.cmdPushConstants2(cmd, &ctx.push_constant);
    // vk.cmdPushConstants(cmd, ctx.push_constant.layout, ctx.push_constant.stageFlags, ctx.push_constant.offset, ctx.push_constant.size, ctx.push_constant.pValues);

    vk.cmdDispatch(cmd, ctx.dispatch_size[0], ctx.dispatch_size[1], ctx.dispatch_size[2]);
}

fn render_objects(cmd: vk.CommandBuffer, ctx: *const render.Context) void {
    const color_attachment = vk.RenderingAttachmentInfo {
        .sType = .rendering_attachment_info,
        .imageView = ctx.color_view,
        .imageLayout = .color_attachment_optimal,
        .resolveMode = .{},
        .resolveImageView = .null_handle,
        .resolveImageLayout = .@"undefined",
        .loadOp = .load,
        .storeOp = .store,
        .clearValue = std.mem.zeroes(vk.ClearValue),
    };

    const color_attachments = [_]vk.RenderingAttachmentInfo { color_attachment };
    const rendering_info = vk.RenderingInfo {
        .sType = .rendering_info,
        .renderArea = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = ctx.extent,
        },
        .layerCount = 1,
        .viewMask = 0,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_attachments,
        .pDepthAttachment = null,
        .pStencilAttachment = null,
    };

    vk.cmdBeginRendering(cmd, &rendering_info);

    const viewport = vk.Viewport {
        .x = 0,
        .y = 0,
        .width = @floatFromInt(ctx.extent.width),
        .height = @floatFromInt(ctx.extent.height),
        .minDepth = 0,
        .maxDepth = 1,
    };
    const viewports = [_]vk.Viewport { viewport };
    vk.cmdSetViewport(cmd, 0, 1, &viewports);

    const scissor = vk.Rect2D {
        .offset = .{ .x = 0, .y = 0 },
        .extent = ctx.extent,
    };
    const scissors = [_]vk.Rect2D { scissor };
    vk.cmdSetScissor(cmd, 0, 1, &scissors);

    vk.cmdBindPipeline(cmd, .graphics, ctx.pipeline.handle);
    vk.cmdBindDescriptorSets(cmd, .graphics, ctx.pipeline.layout, 0, @intCast(ctx.descriptor_sets.len), ctx.descriptor_sets.ptr, 0, null);
    vk.cmdPushConstants2(cmd, &ctx.push_constant);
    // vk.cmdPushConstants(cmd, ctx.push_constant.layout, ctx.push_constant.stageFlags, ctx.push_constant.offset, ctx.push_constant.size, ctx.push_constant.pValues);
    vk.cmdDraw(cmd, ctx.vertex_count, ctx.instance_count, 0, 0);

    vk.cmdEndRendering(cmd);
}

const Object = struct {
    /// Position in km
    pos: @Vector(2, f32),
    /// Mass in kg
    mass: f32,
    /// Velocity in km/h
    velocity: f32
};

const GravityShader = struct {
    allocator: std.mem.Allocator,

    device: vk.Device,
    pipeline: shaders.Pipeline,
    layouts: []vk.DescriptorSetLayout,
    writer: descriptors.Writer,

    bound_descriptor_sets: [1]vk.DescriptorSet = .{ .null_handle },
    push_constant: PushConstant,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, device: vk.Device) !GravityShader {
        // create layout
        var layout_builder = descriptors.LayoutBuilder.init(allocator);
        defer layout_builder.deinit();

        const shader_stages: vk.ShaderStageFlags = .{
            .compute_bit = true
        };
        try layout_builder.addBinding(0, .storage_buffer, shader_stages);

        const descriptor_set_layouts = try allocator.alloc(vk.DescriptorSetLayout, 1);
        errdefer allocator.free(descriptor_set_layouts);

        descriptor_set_layouts[0] = try layout_builder.build(device, .{});
        errdefer vk.destroyDescriptorSetLayout(device, descriptor_set_layouts[0], null);

        const push_constant_range = vk.PushConstantRange {
            .size = @sizeOf(PushConstant),
            .offset = 0,
            .stageFlags = .{
                .compute_bit = true
            }
        };

        // create pipeline
        const exe_dir = try std.process.executableDirPathAlloc(io, allocator);
        defer allocator.free(exe_dir);

        const shader_path = try std.fmt.allocPrint(allocator, "{s}/shaders/gravity/gravity.spirv", .{ exe_dir });
        defer allocator.free(shader_path);

        const shader_module = try shaders.load_shader_module(io, allocator, shader_path, device);
        defer vk.destroyShaderModule(device, shader_module, null);

        var pipeline = try shaders.Pipeline.init(device, descriptor_set_layouts);
        try pipeline.addPushConstant(allocator, push_constant_range);
        try pipeline.buildCompute(device, shader_module);

        return .{
            .allocator = allocator,
            .device = device,
            .layouts = descriptor_set_layouts,
            .pipeline = pipeline,
            .writer = descriptors.Writer.init(allocator),
            .push_constant = .{
                .delta_time = 0
            }
        };
    }

    pub fn write(self: *GravityShader, data: Data) void {
        self.bound_descriptor_sets[0] = data.descriptor_set;

        self.writer.clear();
        self.writer.addBuffer(0, data.object_buffer, data.object_offset, @sizeOf(Object), .storage_buffer) catch {
            std.log.warn("failed to write data.", .{});
        };

        self.writer.write(self.device, data.descriptor_set);
    }

    pub fn deinit(self: *GravityShader) void {
        for (self.layouts) |layout| {
            vk.destroyDescriptorSetLayout(self.device, layout, null);
        }
        self.allocator.free(self.layouts);

        self.pipeline.deinit(self.allocator);
        self.writer.deinit();
    }

    pub const Data = struct {
        object_buffer: vk.Buffer,
        object_offset: u32,
        descriptor_set: vk.DescriptorSet
    };

    pub const PushConstant = struct {
        delta_time: i32
    };
};

const RenderShader = struct {
    allocator: std.mem.Allocator,

    device: vk.Device,
    pipeline: shaders.Pipeline,
    layouts: []vk.DescriptorSetLayout,
    writer: descriptors.Writer,

    bound_descriptor_sets: [1]vk.DescriptorSet = .{ .null_handle },
    push_constant: PushConstant,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, device: vk.Device) !RenderShader {
        // create layout
        var layout_builder = descriptors.LayoutBuilder.init(allocator);
        defer layout_builder.deinit();

        const shader_stages: vk.ShaderStageFlags = .{
            .vertex_bit = true
        };
        try layout_builder.addBinding(0, .storage_buffer, shader_stages);

        const descriptor_set_layouts = try allocator.alloc(vk.DescriptorSetLayout, 1);
        errdefer allocator.free(descriptor_set_layouts);

        descriptor_set_layouts[0] = try layout_builder.build(device, .{});
        errdefer vk.destroyDescriptorSetLayout(device, descriptor_set_layouts[0], null);

        // create pipeline
        const exe_dir = try std.process.executableDirPathAlloc(io, allocator);
        defer allocator.free(exe_dir);

        const vertex_path = try std.fmt.allocPrint(allocator, "{s}/shaders/gravity/vertex.spirv", .{ exe_dir });
        defer allocator.free(vertex_path);

        const fragment_path = try std.fmt.allocPrint(allocator, "{s}/shaders/gravity/fragment.spirv", .{ exe_dir });
        defer allocator.free(fragment_path);

        const vertex_module = try shaders.load_shader_module(io, allocator, vertex_path, device);
        defer vk.destroyShaderModule(device, vertex_module, null);

        const fragment_module = try shaders.load_shader_module(io, allocator, fragment_path, device);
        defer vk.destroyShaderModule(device, fragment_module, null);

        const push_constant_range = vk.PushConstantRange {
            .size = @sizeOf(PushConstant),
            .offset = 0,
            .stageFlags = .{
                .vertex_bit = true
            }
        };

        var pipeline = try shaders.Pipeline.init(device, descriptor_set_layouts);
        try pipeline.addPushConstant(allocator, push_constant_range);
        try pipeline.buildGraphics(device, vertex_module, fragment_module, .r16g16b16a16_sfloat);

        return .{
            .allocator = allocator,
            .device = device,
            .layouts = descriptor_set_layouts,
            .pipeline = pipeline,
            .writer = descriptors.Writer.init(allocator),
            .push_constant = .{
                .world_size = @splat(0),
                .camera_pos = @splat(0)
            }
        };
    }

    pub fn write(self: *RenderShader, data: Data) void {
        self.bound_descriptor_sets[0] = data.descriptor_set;

        self.writer.clear();
        self.writer.addBuffer(0, data.object_buffer, data.object_offset, @sizeOf(Object), .storage_buffer) catch {
            std.log.warn("failed to write data.", .{});
        };

        self.writer.write(self.device, data.descriptor_set);
    }

    pub fn deinit(self: *RenderShader) void {
        for (self.layouts) |layout| {
            vk.destroyDescriptorSetLayout(self.device, layout, null);
        }
        self.allocator.free(self.layouts);

        self.pipeline.deinit(self.allocator);
        self.writer.deinit();
    }

    pub const Data = struct {
        object_buffer: vk.Buffer,
        object_offset: u32,
        descriptor_set: vk.DescriptorSet
    };

    pub const PushConstant = struct {
        world_size: @Vector(2, f32),
        camera_pos: @Vector(2, f32)
    };
};

const std = @import("std");
const vk = @import("vk");
const c = @import("c");
const utils = @import("../graphics/utils.zig");
const render = @import("../render.zig");
const shaders = @import("../graphics/shaders.zig");
const descriptors = @import("../graphics/descriptors.zig");
const types = @import("../graphics/types.zig");
const allocators = @import("../graphics/allocators.zig");
