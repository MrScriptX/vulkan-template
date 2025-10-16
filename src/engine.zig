const Extensions = struct {
    
};

const Layers = struct {
    VK_LAYER_KHRONOS_validation: bool,
};

const Queues = struct {
    graphic: c.VkQueue,
    graphic_index: u32,

    compute: ?c.VkQueue = null,
    compute_index: ?u32 = null,

    pub fn init(device: c.VkDevice, graphic_index: u32, compute_index: ?u32) Queues {
        const graphic_queue: c.VkQueue = create_queue(device, graphic_index);

        var compute_queue: ?c.VkQueue = null;
        if (compute_index) |index| {
            const queue: c.VkQueue = create_queue(device, index);
            compute_queue = queue;
        }

        return .{
            .graphic_index = graphic_index,
            .graphic = graphic_queue,

            .compute_index = compute_index,
            .compute = compute_queue,
        };
    }
};

pub const Renderer = struct {
    instance: c.VkInstance,
    surface: c.VkSurfaceKHR,
    gpu: c.VkPhysicalDevice,
    device: c.VkDevice,
    queues: Queues,
    vma: c.VmaAllocator,

    extensions: Extensions = .{}, // activated extensions list
    layers: Layers,

    pub fn init(allocator: std.mem.Allocator, app_name: []const u8, window: *c.SDL_Window) !Renderer {
        const layers = Layers {
            .VK_LAYER_KHRONOS_validation = true // when debug
        };
        
        // initialize vulkan
        const instance = try create_instance(allocator, app_name, layers);
        errdefer c.vkDestroyInstance(instance, null);

        const surface = try create_surface(window, instance);
        errdefer c.vkDestroySurfaceKHR(instance, surface, null);

        const gpu = try select_physical_device(allocator, instance, surface);
        print_physical_device_info(gpu);

        const queue_indexes = fetch_queue_families(allocator, gpu, surface) catch |err| {
            std.log.err("Failed to fetch device queues", .{});
            return err;
        };

        const device = try create_device(allocator, gpu, queue_indexes.@"0", queue_indexes.@"1", layers);
        errdefer c.vkDestroyDevice(device, null);

        const queues = Queues.init(device, queue_indexes.@"0", queue_indexes.@"1");

        const vma = try create_vma(instance, gpu, device);
        errdefer c.vmaDestroyAllocator(vma);

        // initialize the swapchain
        

        return .{
            .instance = instance,
            .surface = surface,
            .gpu = gpu,
            .device = device,
            .queues = queues,
            .vma = vma,

            .layers = layers
        };
    }

    pub fn deinit(self: *const Renderer) void {
        c.vmaDestroyAllocator(self.vma);
        c.vkDestroyDevice(self.device, null);
        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyInstance(self.instance, null);
    }
};

fn create_instance(allocator: std.mem.Allocator, app_name: []const u8, layers: Layers) !c.VkInstance {
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
    var layer_names = std.ArrayList([]const u8).empty;
    defer layer_names.deinit(allocator);

    if (layers.VK_LAYER_KHRONOS_validation) {
        try layer_names.append(allocator, "VK_LAYER_KHRONOS_validation");
    }

    const instance_info = c.VkInstanceCreateInfo {
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        
        .enabledLayerCount = @intCast(layer_names.items.len),
        .ppEnabledLayerNames = @ptrCast(layer_names.items.ptr),
        
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

fn select_physical_device(allocator: std.mem.Allocator, instance: c.VkInstance, surface: c.VkSurfaceKHR) !c.VkPhysicalDevice {
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
        const swapchain_support = check_device_swapchain_support(allocator, device, surface);

        if (compatibility and features and extensions_support and swapchain_support) {
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

fn check_device_swapchain_support(allocator: std.mem.Allocator, device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) bool {
    var formats_count: u32 = 0;
    vk.getPhysicalDeviceSurfaceFormatsKHR(device, surface, &formats_count, null) catch |err| {
        std.log.err("Failed to enumerates device supported formats: {any}", .{err});
        return false;
    };

    if (formats_count == 0) {
        std.log.warn("No format found", .{});
        return false;
    }

    const formats = allocator.alloc(c.VkSurfaceFormatKHR, formats_count) catch {
        std.log.err("Out of Memory", .{});
        return false;
    };
    defer allocator.free(formats);

    vk.getPhysicalDeviceSurfaceFormatsKHR(device, surface, &formats_count, formats.ptr) catch |err| {
        std.log.err("Failed to enumerates device supported formats: {any}", .{err});
        return false;
    };

    var present_mode_count: u32 = 0;
    vk.getPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_mode_count, null) catch |err| {
        std.log.err("Failed to enumerate surface present modes : {any}", .{ err });
        return false;
    };

    if (present_mode_count == 0) {
        std.log.warn("No present mode found", .{});
        return false;
    }

    const present_modes = allocator.alloc(c.VkPresentModeKHR, present_mode_count) catch {
        std.log.err("Out of Memory", .{});
        return false;
    };
    defer allocator.free(present_modes);

    vk.getPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_mode_count, present_modes.ptr) catch |err| {
        std.log.err("Failed to enumerate surface present modes : {any}", .{ err });
        return false;
    };

    return true;
}

fn fetch_queue_families(allocator: std.mem.Allocator, device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) !struct { u32, ?u32 } {
    var family_count: u32 = 0;
    vk.getPhysicalDeviceQueueFamilyProperties(device, &family_count, null);

    if (family_count == 0) {
        std.log.err("No queue family found !", .{});
        return Error.DeviceError;
    }

    const queue_families = try allocator.alloc(c.VkQueueFamilyProperties, family_count);
    defer allocator.free(queue_families);

    vk.getPhysicalDeviceQueueFamilyProperties(device, &family_count, queue_families.ptr);

    var graphic_queue_index: u32 = 0;
    var compute_queue_index: ?u32 = null;

    for (queue_families, 0..) |queue_family, index| {
        if (queue_family.queueCount > 0) {
            if (queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
                // check presentation support
                var present_support: c.VkBool32 = c.VK_FALSE;
                vk.getPhysicalDeviceSurfaceSupportKHR(device, @intCast(index), surface, &present_support) catch |err| {
                    std.log.warn("An error was raised while checking presentation support : {any}", .{err});
                    continue;
                };

                if (present_support == c.VK_TRUE) {
                    graphic_queue_index = @intCast(index);
                    continue;
                }
            }
            else if (queue_family.queueFlags & c.VK_QUEUE_COMPUTE_BIT != 0) {
                // get compute queue
                compute_queue_index = @intCast(index);
                continue;
            }
        }
    }

    if (graphic_queue_index == compute_queue_index) { // graphic queue should not be the same
        compute_queue_index = null;
    }

    return .{
        graphic_queue_index,
        compute_queue_index,
    };
}

fn create_device(allocator: std.mem.Allocator, physical_device: c.VkPhysicalDevice, graphic_index: u32, compute_index: ?u32, layers: Layers) !c.VkDevice {
    // queues info
    var queue_create_infos = std.ArrayList(c.VkDeviceQueueCreateInfo).empty;
    defer queue_create_infos.deinit(allocator);

    var queue_priority: f32 = 0.0;
    const graphic_graphic_queue_create_info = c.VkDeviceQueueCreateInfo {
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = graphic_index,
        .queueCount = 1,
        .pQueuePriorities = &queue_priority
    };

    try queue_create_infos.append(allocator, graphic_graphic_queue_create_info);

    if (compute_index) |index| {
        const compute_queue_create_info = c.VkDeviceQueueCreateInfo {
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = index,
            .queueCount = 1,
            .pQueuePriorities = &queue_priority
        };

        try queue_create_infos.append(allocator, compute_queue_create_info);
    }

    // device features
    const device_features = c.VkPhysicalDeviceFeatures {
        .fillModeNonSolid = c.VK_TRUE,
    };

    const features_vulkan13 = c.VkPhysicalDeviceVulkan13Features {
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
    };

    // layers
    var layer_names = std.ArrayList([]const u8).empty;
    defer layer_names.deinit(allocator);

    if (layers.VK_LAYER_KHRONOS_validation) {
        try layer_names.append(allocator, "VK_LAYER_KHRONOS_validation");
    }

    const device_create_info = c.VkDeviceCreateInfo {
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = &features_vulkan13,
        .queueCreateInfoCount = @intCast(queue_create_infos.items.len),
        .pQueueCreateInfos = queue_create_infos.items.ptr,

        .enabledExtensionCount = 0,
        .ppEnabledExtensionNames = null,

        .enabledLayerCount = @intCast(layer_names.items.len),
        .ppEnabledLayerNames = @ptrCast(layer_names.items.ptr),

        .pEnabledFeatures = &device_features
    };

    var device: c.VkDevice = undefined;
    vk.createDevice(physical_device, &device_create_info, null, &device) catch |err| {
        std.log.err("Failed to create device : {any}", .{err});
        return err;
    };

    return device;
}

fn create_queue(device: c.VkDevice, family_index: u32) c.VkQueue {
    const queue_info = c.VkDeviceQueueInfo2 {
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_INFO_2,
        .queueFamilyIndex = family_index,
        .queueIndex = 0
    };

    var queue: c.VkQueue = undefined;
    c.vkGetDeviceQueue2(device, &queue_info, &queue);

    return queue;
}

fn create_vma(instance: c.VkInstance, physical_device: c.VkPhysicalDevice, device: c.VkDevice) !c.VmaAllocator {
    const create_allocator_info = c.VmaAllocatorCreateInfo {
        .instance = instance,
        .physicalDevice = physical_device,
        .device = device,
        .vulkanApiVersion = c.VK_API_VERSION_1_4,
        .flags = c.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT
    };

    var allocator: c.VmaAllocator = undefined;
    vk.vmaCreateAllocator(&create_allocator_info, &allocator) catch |err| {
        std.log.err("Failed to create vulkan memory allocator : {any}", .{err});
        return err;
    };

    return allocator;
}

fn print_physical_device_info(device: c.VkPhysicalDevice) void {
    var properties: c.VkPhysicalDeviceProperties2 = .{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2,
    };
    c.vkGetPhysicalDeviceProperties2(device, &properties);

    std.log.info("Device Info", .{});
    std.log.info("Name: {s}", .{ properties.properties.deviceName });
    std.log.info("Vendor: {d}", .{ properties.properties.vendorID });
    std.log.info("API Version: {d}", .{ properties.properties.apiVersion });
    std.log.info("Driver: {d}", .{ properties.properties.driverVersion });
}

const Error = error {
    SurfaceError,
    NoDevice,
    DeviceError,
};

const std = @import("std");
const c = @import("c.zig").c;
const vk = @import("vk.zig");
