pub const Renderer = struct {
    instance: c.VkInstance,
    surface: c.VkSurfaceKHR,

    pub fn init(app_name: []const u8, window: *c.SDL_Window) !Renderer {
        const instance = try create_instance(app_name);
        errdefer c.vkDestroyInstance(instance, null);

        const surface = try create_surface(window, instance);
        errdefer c.vkDestroySurfaceKHR(instance, surface, null);

        return .{
            .instance = instance,
            .surface = surface,
        };
    }

    pub fn deinit(self: *const Renderer) void {
        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyInstance(self.instance, null);
    }
};

fn create_instance(app_name: []const u8) !c.VkInstance {
    const app_info: c.VkApplicationInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .apiVersion = c.VK_MAKE_API_VERSION(0, 1, 4, 0),
        .pApplicationName = app_name.ptr,
        .applicationVersion = c.VK_MAKE_VERSION(0, 0, 1),
        .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
        .pEngineName = "R3D"
    };

    const instance_info = c.VkInstanceCreateInfo {
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
    };

    var instance: c.VkInstance = undefined;
    vk.createInstance(&instance_info, null, &instance) catch |err| {
        std.log.err("Vulkan instance creation failed : {any}", .{err});
        return err;
    };

    return instance;
}

fn create_surface(window: *c.SDL_Window, instance: c.VkInstance) !c.VkSurfaceKHR {
    var surface: c.VkSurfaceKHR = undefined;
    const result = c.SDL_Vulkan_CreateSurface(window, @ptrCast(instance), null, &surface);
    if (result == false) {
        std.log.err("Unable to create Vulkan surface: {s}", .{ c.SDL_GetError() });
        return Error.SurfaceError;
    }

    return surface;
}

const Error = error {
    SurfaceError,
};

const std = @import("std");
const c = @import("c.zig").c;
const vk = @import("vk.zig");
