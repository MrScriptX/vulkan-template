pub const GradiantScene = struct {
    allocator: std.mem.Allocator,

    render_graph: render.RenderGraph,

    descriptor_allocator: allocators.Descriptor,
    descriptor_set_layout: vk.DescriptorSetLayout,
    descriptor_sets: []vk.DescriptorSet,

    pipeline: shaders.Pipeline,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, device: vk.Device, render_image: types.Image) !GradiantScene {
        // create descriptor allocator
        const pool_sizes = [_]descriptors.PoolSizeRatio {
            .{ .kind = vk.DescriptorType.storage_image, .ratio = 1 }
        };
        var da = allocators.Descriptor.init(allocator, device, 1, &pool_sizes) catch {
            std.log.err("failed to initialize descriptor allocator.", .{});
            return Error.initialization_failed;
        };
        errdefer da.deinit(device);

        // create descriptor layout
        var layout_builder = descriptors.LayoutBuilder.init(allocator);
        defer layout_builder.deinit();
        
        const shader_stages: vk.ShaderStageFlags = .{
            .compute_bit = true
        };
        try layout_builder.addBinding(0, .storage_image, shader_stages);
        const descriptor_set_layout = try layout_builder.build(device, .{});
        errdefer vk.destroyDescriptorSetLayout(device, descriptor_set_layout, null);

        // create pipeline
        const exe_dir = try std.process.executableDirPathAlloc(io, allocator);
        defer allocator.free(exe_dir);

        const shader_path = try std.fmt.allocPrint(allocator, "{s}/shaders/gradiant.spirv", .{ exe_dir });
        defer allocator.free(shader_path);

        const shader_module = try shaders.load_shader_module(io, allocator, shader_path, device);
        defer vk.destroyShaderModule(device, shader_module, null);

        const pipeline_layout_info = vk.PipelineLayoutCreateInfo {
            .sType = .pipeline_layout_create_info,
            .setLayoutCount = 1,
            .pSetLayouts = &descriptor_set_layout
        };
        const pipeline = try shaders.Pipeline.init(device, pipeline_layout_info, shader_module);

        // allocate descriptor set
        const descriptor_set = try da.allocate(descriptor_set_layout);

        var descriptor_writer = descriptors.Writer.init(allocator);
        defer descriptor_writer.deinit();

        try descriptor_writer.addImage(0, render_image.image_view, std.mem.zeroes(vk.Sampler), .general, .storage_image);
        descriptor_writer.write(device, descriptor_set);

        const descriptor_sets = allocator.alloc(vk.DescriptorSet, 1) catch {
            std.log.err("failed to allocate descriptor sets.", .{});
            return Error.initialization_failed;
        };
        descriptor_sets[0] = descriptor_set;

        return .{
            .allocator = allocator,

            .render_graph = render.RenderGraph.init(allocator),

            .pipeline = pipeline,
            .descriptor_allocator = da,
            .descriptor_set_layout = descriptor_set_layout,
            .descriptor_sets = descriptor_sets
        };
    }

    pub fn update(self: *GradiantScene, allocator: std.mem.Allocator, image: *const types.Image) !void {
        self.render_graph.clear();

        const ctx = render.Context {
            .pipeline = &self.pipeline,
            .descriptor_sets = self.descriptor_sets,
            .dispatch_size = .{
                image.extent.width / 16,
                image.extent.height / 16,
                1
            }
        };

        var render_pass = render.RenderPass.init(allocator, &render_gradiant, ctx);

        const render_image = render.ImageResource {
            .image = image,
            .layout = .general
        };
        render_pass.addImageBuffer(render_image) catch {
            std.log.err("failed to add render image resource.", .{});
        };

        self.render_graph.addPass(render_pass) catch |err| {
            std.log.err("failed to register render pass. error : {any}", .{err});
        };
    }

    pub fn draw(self: *GradiantScene, cmd: vk.CommandBuffer) void {
        self.render_graph.exec(cmd);
    }

    pub fn deinit(self: *GradiantScene, device: vk.Device) void {
        self.allocator.free(self.descriptor_sets);

        self.pipeline.deinit();

        self.descriptor_allocator.deinit(device);
        vk.destroyDescriptorSetLayout(device, self.descriptor_set_layout, null);
        
        self.render_graph.deinit();
    }

    const Error = error {
        initialization_failed
    };
};

fn render_gradiant(cmd: vk.CommandBuffer, ctx: *const render.Context) void {
    vk.cmdBindPipeline(cmd, .compute, ctx.pipeline.handle);
    vk.cmdBindDescriptorSets(cmd, .compute, ctx.pipeline.layout, 0, @intCast(ctx.descriptor_sets.len), ctx.descriptor_sets.ptr, 0, null);
    vk.cmdDispatch(cmd, ctx.dispatch_size[0], ctx.dispatch_size[1], ctx.dispatch_size[2]);
}

const std = @import("std");
const vk = @import("vk");
const shaders = @import("../graphics/shaders.zig");
const render = @import("../render.zig");
const types = @import("../graphics/types.zig");
const allocators = @import("../graphics/allocators.zig");
const descriptors = @import("../graphics/descriptors.zig");
