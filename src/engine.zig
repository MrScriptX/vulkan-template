pub const Renderer = struct {
    instance: c.VkInstance,
    surface: c.VkSurfaceKHR,
    gpu: c.VkPhysicalDevice,

    pub fn init(allocator: std.mem.Allocator, app_name: []const u8, window: *c.SDL_Window) !Renderer {
        const instance = try create_instance(app_name);
        errdefer c.vkDestroyInstance(instance, null);

        const surface = try create_surface(window, instance);
        errdefer c.vkDestroySurfaceKHR(instance, surface, null);

        const gpu = try select_physical_device(allocator, instance);
        print_physical_device_info(gpu);

        return .{
            .instance = instance,
            .surface = surface,
            .gpu = gpu,
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

    var extension_count: u32 = 0;
    const required_extensions = c.SDL_Vulkan_GetInstanceExtensions(&extension_count);

    // layers
    const layers = [_][]const u8 {
        "VK_LAYER_KHRONOS_validation"
    };

    const instance_info = c.VkInstanceCreateInfo {
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .enabledLayerCount = layers.len,
        .ppEnabledLayerNames = @ptrCast(&layers),
        .enabledExtensionCount = extension_count,
        .ppEnabledExtensionNames = required_extensions,
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

fn select_physical_device(allocator: std.mem.Allocator, instance: c.VkInstance) !c.VkPhysicalDevice {
    var device_count: u32 = 0;
    vk.enumeratePhysicalDevices(instance, &device_count, null) catch |err| {
        std.log.err("Failed to enumerate devices : {any}", .{err});
        return err;
    };

    if (device_count == 0) {
        std.log.warn("No device found", .{});
        return Error.NoDevice;
    }

    const devices = try allocator.alloc(c.VkPhysicalDevice, device_count);
    defer allocator.free(devices);

    vk.enumeratePhysicalDevices(instance, &device_count, devices.ptr) catch |err| {
        std.log.err("Failed to get devices list : {any}", .{err});
        return err;
    };

    for (devices) |device| {
        const compatibility = check_device_properties(device);
        const features = check_device_features(device);
        const extensions_support = check_device_extensions(allocator, device);

        if (compatibility and features and extensions_support) {
            return device;
        }
    }

    return Error.NoDevice;
}

fn check_device_properties(device: c.VkPhysicalDevice) bool {
    var properties: c.VkPhysicalDeviceProperties2 = .{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2,
    };
    c.vkGetPhysicalDeviceProperties2(device, &properties);

    if (properties.properties.deviceType != c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU and properties.properties.deviceType != c.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU) {
        std.log.warn("{s} is not a dedicated device", .{properties.properties.deviceName});
        return false;
    }

    return true;
}

fn check_device_features(device: c.VkPhysicalDevice) bool {
    var features: c.VkPhysicalDeviceFeatures2 = .{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
    };
    c.vkGetPhysicalDeviceFeatures2(device, &features);

    return true;
}

fn check_device_extensions(allocator: std.mem.Allocator, device: c.VkPhysicalDevice) bool {
    var extension_count: u32 = 0;
    vk.enumerateDeviceExtensionProperties(device, null, &extension_count, null) catch |err| {
        std.log.err("Failed to enumerate device extensions : {any}", .{err});
        return false;
    };

    if (extension_count == 0) {
        std.log.warn("No extensions found", .{});
        return false;
    }

    const extensions = allocator.alloc(c.VkExtensionProperties, extension_count) catch {
        std.log.err("Out of Memory", .{});
        return false;
    };
    defer allocator.free(extensions);

    vk.enumerateDeviceExtensionProperties(device, null, &extension_count, extensions.ptr) catch |err| {
        std.log.err("Failed to enumerate device extensions : {any}", .{err});
        return false;
    };

    const required_extensions = [_][]const u8 {
        "VK_KHR_synchronization2"
    };

    var match_extensions: u8 = 0;
    for (required_extensions) |required| {
        for (0..extension_count) |i| {
            const name: [*c]const u8 = @ptrCast(extensions[i].extensionName[0..]);
            if (std.mem.eql(u8, std.mem.span(name), required)) {
                match_extensions += 1;
            }
        }
    }

    return match_extensions == required_extensions.len;
}

fn print_physical_device_info(device: c.VkPhysicalDevice) void {
    var properties: c.VkPhysicalDeviceProperties2 = .{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2,
    };
    c.vkGetPhysicalDeviceProperties2(device, &properties);

    std.log.info("Device Info\nName: {s}\nVendor: {d}\nAPI Version: {d}\n", .{
        properties.properties.deviceName,
        properties.properties.vendorID,
        properties.properties.apiVersion
    }); 
}

const Error = error {
    SurfaceError,
    NoDevice,
};

const std = @import("std");
const c = @import("c.zig").c;
const vk = @import("vk.zig");
