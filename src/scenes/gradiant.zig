pub const GradiantScene = struct {
    render_graph: render.RenderGraph,
    pipeline: shaders.Pipeline,

    pub fn init(allocator: std.mem.Allocator) GradiantScene {
        return .{
            .pipeline = undefined,
            .render_graph = render.RenderGraph.init(allocator)
        };
    }

    pub fn update(self: *GradiantScene, allocator: std.mem.Allocator, ctx: render.Context) void {
        self.render_graph.clear();

        const render_pass = render.RenderPass.init(allocator, &render_gradiant, ctx);
        // defer render_pass.deinit();

        // const input_image = render.ImageResource {
        //     .image = image,
        //     .current_layout = .undefined
        // };
        // try render_pass.addImageBuffer(input_image);

        self.render_graph.addPass(render_pass) catch |err| {
            std.log.err("failed to register render pass. error : {any}", .{err});
        };
    }

    pub fn draw(self: *GradiantScene, cmd: vk.CommandBuffer) void {
        self.render_graph.exec(cmd);
    }

    pub fn deinit(self: *GradiantScene) void {
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
