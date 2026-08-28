pub const GravityScene = struct {
    allocator: std.mem.Allocator,
    state: State,

    render_graph: render.RenderGraph,

    gravity_shader: GravityShader,
    buffer: types.Buffer,

    da: allocators.Descriptor,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, device: vk.Device, vma: c.VmaAllocator) !GravityScene {
        const render_graph = render.RenderGraph.init(allocator);

        const initial_state = State {
            .object = .{
                .pos = @splat(0),
            },
            .delta_time = 0
        };

        // allocate data buffer
        const buffer_usage = vk.BufferUsageFlags {
            .storage_buffer_bit = true
        };

        const buffer = try types.Buffer.init(vma, @sizeOf(Object), buffer_usage, c.VMA_MEMORY_USAGE_AUTO);

        // upload intial state
        try utils.upload_data(Object, vma, buffer.allocation, &initial_state.object);

        const gravity_shader = try GravityShader.init(allocator, io, device);

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
            .buffer = buffer,
            .da = try allocators.Descriptor.init(allocator, device, 1, &pool_sizes)
        };
    }

    pub fn deinit(self: *GravityScene, device: vk.Device) void {
        self.da.deinit(device);
        self.render_graph.deinit();
        self.gravity_shader.deinit();
    }

    pub fn update(self: *GravityScene, draw_resource: *const render.DrawResource) void {
        // update scene data
        const shader_data = GravityShader.Data {
            .object_buffer = self.buffer.handle,
            .object_offset = 0,
            .descriptor_set = try self.da.allocate(self.gravity_shader.layouts[0])
        };
        self.gravity_shader.write(shader_data);

        // TODO : add delta time as push constant
        // TODO : test upload position with a render of the object

        // build render graph
        self.render_graph.clear();

        const object_resource = render.BufferResource {
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
        const gravity_pass_ctx = render.Context {
            .pipeline = &self.gravity_shader.pipeline,
            .descriptor_sets = .{ shader_data.descriptor_set },
            .dispatch_size = .{ 1, 1, 1 }
        };
        var gravity_pass = render.RenderPass.init(self.allocator, &compute_gravity, gravity_pass_ctx);
        try gravity_pass.addBuffer(object_resource);

        // render pass
        // const render_ctx = render.Context {
        //     .pipeline = undefined,
        //     .descriptor_sets = .{},
        //     .dispatch_size = @splat(0)
        // };

        const render_resource = render.ImageResource {
            .image = &draw_resource.color_image,
            .layout = .color_attachment_optimal
        };
        // var render_pass = render.RenderPass.init(self.allocator, &render_objects, render_ctx);
        // try render_pass.addImageBuffer(render_resource);

        self.render_graph.setOutput(render_resource);
    }

    pub fn draw(self: *GravityScene, cmd: vk.CommandBuffer) void {
        self.render_graph.exec(cmd);
    }

    const State = struct {
        object: Object,
        delta_time: f32
    };
};

fn compute_gravity(cmd: vk.CommandBuffer, ctx: *const render.Context) void {
    vk.cmdBindPipeline(cmd, .compute, ctx.pipeline.handle);
    vk.cmdBindDescriptorSets(cmd, .compute, ctx.pipeline.layout, 0, @intCast(ctx.descriptor_sets.len), ctx.descriptor_sets.ptr, 0, null);
    vk.cmdDispatch(cmd, ctx.dispatch_size[0], ctx.dispatch_size[1], ctx.dispatch_size[2]);
}

fn render_objects(_: vk.CommandBuffer, _: *const render.Context) void {

}

const Object = struct {
    pos: @Vector(2, f32)
};

const GravityShader = struct {
    allocator: std.mem.Allocator,

    device: vk.Device,
    pipeline: shaders.Pipeline,
    layouts: []vk.DescriptorSetLayout,
    writer: descriptors.Writer,

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

        // create pipeline
        const exe_dir = try std.process.executableDirPathAlloc(io, allocator);
        defer allocator.free(exe_dir);

        const shader_path = try std.fmt.allocPrint(allocator, "{s}/shaders/gravity/gravity.spirv", .{ exe_dir });
        defer allocator.free(shader_path);

        const shader_module = try shaders.load_shader_module(io, allocator, shader_path, device);
        defer vk.destroyShaderModule(device, shader_module, null);

        var pipeline = try shaders.Pipeline.init(device, descriptor_set_layouts);
        try pipeline.buildCompute(device, shader_module);

        return .{
            .allocator = allocator,
            .device = device,
            .layouts = descriptor_set_layouts,
            .pipeline = pipeline,
            .writer = descriptors.Writer.init(allocator),
        };
    }

    pub fn write(self: *GravityShader, data: Data) void {
        self.writer.clear();
        self.writer.addBuffer(0, data.object_buffer, data.object_offset, @sizeOf(Object), .storage_buffer);

        self.writer.write(self.device, data.descriptor_set);
    }

    pub fn deinit(self: *GravityShader) void {
        self.pipeline.deinit(self.allocator);
        self.writer.deinit();
    }

    pub const Data = struct {
        object_buffer: vk.Buffer,
        object_offset: u32,
        descriptor_set: vk.DescriptorSet
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
