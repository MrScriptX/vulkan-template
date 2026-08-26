pub const GradiantScene = struct {
    render_graph: render.RenderGraph,
    render_ctx: render.Context,
    pipeline: shaders.ComputePipeline,

    pub fn init(allocator: std.mem.Allocator) GradiantScene {
        return .{
            .pipeline = undefined,
            .render_graph = render.RenderGraph.init(allocator),
            .render_ctx = render.Context{}
        };
    }

    pub fn draw(self: *GradiantScene, cmd: vk.CommandBuffer) void {
        self.render_graph.exec(cmd, &self.render_ctx);
    }

    pub fn deinit(self: *GradiantScene) void {
        self.render_graph.deinit();
        self.deinit();
    }
};

const std = @import("std");
const vk = @import("vk");
const shaders = @import("../graphics/shaders.zig");
const render = @import("../render.zig");
