pub fn main(proc: std.process.Init) !void {
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        const err = c.SDL_GetError();
        std.log.err("SDL initialization failed : {s}", .{err});
        return;
    }
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("Vulkan Template", 800, 600, c.SDL_WINDOW_VULKAN | c.SDL_WINDOW_RESIZABLE);
    if (window == null) {
        const err = c.SDL_GetError();
        std.log.err("Window creation failed : {s}", .{err});
        return;
    }
    defer c.SDL_DestroyWindow(window);

    var gpa = std.heap.DebugAllocator(.{}).init;
    const allocator = gpa.allocator();
    defer {
        const status = gpa.deinit();
        std.log.debug("Memory check : {any}\n", .{ status });
    }

    var renderer = engine.Renderer.init(allocator, "Vulkan Template", window.?) catch {
        std.log.err("Renderer initialization failed", .{});
        return;
    };
    defer renderer.deinit(allocator);

    var app = Engine.init(allocator, proc.io, &renderer) catch |e| {
        std.log.err("failed to init engine", .{});
        return e;
    };
    defer app.deinit();

    var quit = false;
    while (!quit) {
        var event: c.SDL_Event = undefined;
        while(c.SDL_PollEvent(&event)) {
            if (event.type == c.SDL_EVENT_QUIT) {
                quit = true;
            }
        }

        app.draw(allocator) catch |err| {
            switch (err) {
                engine.Error.SkipImage => {
                    std.log.warn("Skipping image...", .{});
                },
                engine.Error.RebuildSW => {
                    std.log.info("Rebuilding swapchain...", .{});
                    renderer.rebuild_swapchain(allocator, window.?) catch {
                        std.log.err("We are in deep...", .{});
                        quit = true;
                    };
                },
                else => {
                    std.log.err("Unhandle error. Should be shutting down : {any}", .{err});
                    // TODO : handle fatal errors
                }
            }
        };
    }

    return;
}

const Engine = struct {
    frame_count: u32 = 0,
    renderer: *const engine.Renderer,
    
    gradiant_scene: scenes.GradiantScene,
    gravity_scene: gravity.GravityScene,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, renderer: *const engine.Renderer) !Engine {
        const gradiant_scene = try scenes.GradiantScene.init(allocator, io, renderer.device);
        const gravity_scene = try gravity.GravityScene.init(allocator, io, renderer.device, renderer.vma);

        return .{
            .renderer = renderer,
            .gradiant_scene = gradiant_scene,
            .gravity_scene = gravity_scene
        };
    }

    pub fn draw(self: *Engine, allocator: std.mem.Allocator) !void {
        const frame_index = self.frame_count % @as(u32, @intCast(self.renderer.frames.len));

        try self.gradiant_scene.update(allocator, self.renderer.device, &self.renderer.draw_resource);

        try self.renderer.draw(frame_index, &self.gradiant_scene);
        self.frame_count += 1;
    }

    pub fn deinit(self: *Engine) void {
        self.renderer.stop();

        self.gravity_scene.deinit(self.renderer.device);
        self.gradiant_scene.deinit(self.renderer.device);
    }
};

const std = @import("std");
const c = @import("c");
const vk = @import("vk");
const engine = @import("engine.zig");
const scenes = @import("scenes/gradiant.zig");
const gravity = @import("scenes/gravity.zig");
const render = @import("render.zig");
