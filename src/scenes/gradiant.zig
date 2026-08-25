pub const GradiantScene = struct {
    pipeline: shaders.ComputePipeline,

    pub fn init() GradiantScene {
        return .{
            .pipeline = undefined
        };
    }

    pub fn draw(_: *GradiantScene, _: vk.CommandBuffer) void {
        
    }

    pub fn deinit(self: *GradiantScene) void {
        self.deinit();
    }
};

const vk = @import("vk");
const shaders = @import("../graphics/shaders.zig");
