pub const GradiantScene = struct {
    allocator: std.mem.Allocator,

    state: State,
    render_graph: render.RenderGraph,

    descriptor_allocator: allocators.Descriptor,
    descriptor_sets: []vk.DescriptorSet,

    pipeline: shaders.Pipeline,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, device: vk.Device) !GradiantScene {
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

        const descriptor_set_layouts = try allocator.alloc(vk.DescriptorSetLayout, 1);
        errdefer allocator.free(descriptor_set_layouts);

        descriptor_set_layouts[0] = descriptor_set_layout;

        // create pipeline
        var pipeline = try shaders.Pipeline.init(device, descriptor_set_layouts);

        const exe_dir = try std.process.executableDirPathAlloc(io, allocator);
        defer allocator.free(exe_dir);

        const shader_path = try std.fmt.allocPrint(allocator, "{s}/shaders/gradiant.spirv", .{ exe_dir });
        defer allocator.free(shader_path);

        const shader_module = try shaders.load_shader_module(io, allocator, shader_path, device);
        defer vk.destroyShaderModule(device, shader_module, null);
        
        try pipeline.buildCompute(device, shader_module);

        // allocate descriptor set
        const descriptor_set = try da.allocate(descriptor_set_layout);

        const descriptor_sets = allocator.alloc(vk.DescriptorSet, 1) catch {
            std.log.err("failed to allocate descriptor sets.", .{});
            return Error.initialization_failed;
        };
        descriptor_sets[0] = descriptor_set;

        return .{
            .allocator = allocator,

            .state = .{},
            .render_graph = render.RenderGraph.init(allocator),

            .pipeline = pipeline,
            .descriptor_allocator = da,
            .descriptor_sets = descriptor_sets
        };
    }

    pub fn update(self: *GradiantScene, allocator: std.mem.Allocator, device: vk.Device, draw_resource: *const render.DrawResource) !void {
        self.render_graph.clear();

        // check if needs update
        if (draw_resource.color_image.extent.width != self.state.x_view or  draw_resource.color_image.extent.height != self.state.y_view) {
            self.state.x_view = draw_resource.color_image.extent.width;
            self.state.y_view = draw_resource.color_image.extent.height;

            var descriptor_writer = descriptors.Writer.init(allocator);
            defer descriptor_writer.deinit();

            try descriptor_writer.addImage(0, draw_resource.color_image.image_view, std.mem.zeroes(vk.Sampler), .general, .storage_image);
            descriptor_writer.write(device, self.descriptor_sets[0]);
        }

        // prepare render graph
        var render_resource = render.ImageResource {
            .image = &draw_resource.color_image,
            .layout = .general
        };

        const depth_resource = render.ImageResource {
            .image = &draw_resource.depth_image,
            .layout = .depth_attachment_optimal
        };

        // create draw grandiant pass
        const ctx = render.Context {
            .pipeline = &self.pipeline,
            .descriptor_sets = self.descriptor_sets,
            .dispatch_size = .{
                draw_resource.color_image.extent.width / 16,
                draw_resource.color_image.extent.height / 16,
                1
            }
        };

        var draw_gradiant_pass = render.RenderPass.init(allocator, &render_gradiant, ctx);
        draw_gradiant_pass.addImageBuffer(render_resource) catch {
            std.log.err("failed to add render image resource.", .{});
        };

        self.render_graph.addPass(draw_gradiant_pass) catch |err| {
            std.log.err("failed to register render pass. error : {any}", .{err});
        };

        // create empty draw color pass
        var empty_color_pass = render.RenderPass.init(allocator, &render_color, ctx);

        render_resource.layout = .color_attachment_optimal;
        empty_color_pass.addImageBuffer(render_resource) catch {
            std.log.err("failed to add render image resource.", .{});
        };

        empty_color_pass.addImageBuffer(depth_resource) catch {
            std.log.err("failed to add depth image resource.", .{});
        };

        self.render_graph.addPass(empty_color_pass) catch |err| {
            std.log.err("failed to register empty pass. error : {any}", .{err});
        };

        self.render_graph.setOutput(render_resource) catch {
            std.log.err("failed to set output.", .{});
        };
    }

    pub fn draw(self: *GradiantScene, cmd: vk.CommandBuffer) void {
        self.render_graph.exec(cmd);
    }

    pub fn deinit(self: *GradiantScene, device: vk.Device) void {
        self.allocator.free(self.descriptor_sets);

        self.pipeline.deinit(self.allocator);

        self.descriptor_allocator.deinit(device);
        
        self.render_graph.deinit();
    }

    /// scene state
    const State = struct {
        x_view: u32 = 0,
        y_view: u32 = 0
    };

    const Error = error {
        initialization_failed
    };
};

fn render_gradiant(cmd: vk.CommandBuffer, ctx: *const render.Context) void {
    vk.cmdBindPipeline(cmd, .compute, ctx.pipeline.handle);
    vk.cmdBindDescriptorSets(cmd, .compute, ctx.pipeline.layout, 0, @intCast(ctx.descriptor_sets.len), ctx.descriptor_sets.ptr, 0, null);
    vk.cmdDispatch(cmd, ctx.dispatch_size[0], ctx.dispatch_size[1], ctx.dispatch_size[2]);
}

fn render_color(_: vk.CommandBuffer, _: *const render.Context) void {

}

const std = @import("std");
const vk = @import("vk");
const shaders = @import("../graphics/shaders.zig");
const render = @import("../render.zig");
const types = @import("../graphics/types.zig");
const allocators = @import("../graphics/allocators.zig");
const descriptors = @import("../graphics/descriptors.zig");
