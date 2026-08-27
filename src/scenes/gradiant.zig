pub const GradiantScene = struct {
    render_graph: render.RenderGraph,
    pipeline: shaders.Pipeline,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, device: vk.Device, descriptor_set_layout: vk.DescriptorSetLayout) !GradiantScene {
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

        return .{
            .pipeline = pipeline,
            .render_graph = render.RenderGraph.init(allocator)
        };
    }

    pub fn update(self: *GradiantScene, allocator: std.mem.Allocator, ctx: render.Context, image: *const types.Image) void {
        self.render_graph.clear();

        const context = render.Context {
            .pipeline = &self.pipeline,
            .descriptor_sets = ctx.descriptor_sets,
            .dispatch_size = ctx.dispatch_size
        };

        var render_pass = render.RenderPass.init(allocator, &render_gradiant, context);

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

    pub fn deinit(self: *GradiantScene) void {
        self.pipeline.deinit();
        self.render_graph.deinit();
    }
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
