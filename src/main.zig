pub fn main() !void {
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        const err = c.SDL_GetError();
        std.log.err("SDL initialization failed : {s}", .{err});
        return;
    }
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("Physics Simulation", 800, 600, c.SDL_WINDOW_VULKAN | c.SDL_WINDOW_RESIZABLE);
    if (window == null) {
        const err = c.SDL_GetError();
        std.log.err("Window creation failed : {s}", .{err});
        return;
    }
    defer c.SDL_DestroyWindow(window);
    
    var quit = false;
    while (!quit) {
        var event: c.SDL_Event = undefined;
        while(c.SDL_PollEvent(&event)) {
            if (event.type == c.SDL_EVENT_QUIT) {
                quit = true;
            }
        }
    }

    return;
}

const std = @import("std");
const c = @cImport({
    @cInclude("SDL3/SDL.h");
});
