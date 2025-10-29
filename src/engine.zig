const Extensions = struct {
    VK_KHR_swapchain: bool,
    VK_KHR_synchronization2: bool,
};

const Layers = struct {
    VK_LAYER_KHRONOS_validation: bool,
};

const Frame = struct {
    command_pool: c.VkCommandPool,
    command_buffer: c.VkCommandBuffer,

    sw_semaphore: c.VkSemaphore,
    render_semaphore: c.VkSemaphore,
	render_fence: c.VkFence,

    pub fn init(device: c.VkDevice, queue_family_index: u32) !Frame {
        // create the command pool
        const command_pool_create_info = c.VkCommandPoolCreateInfo {
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = queue_family_index,
        };

        var command_pool: c.VkCommandPool = undefined;
        vk.createCommandPool(device, &command_pool_create_info, null, &command_pool) catch |err| {
            std.log.err("Failed to create a command pool : {any}", .{err});
            return err;
        };
        errdefer c.vkDestroyCommandPool(device, command_pool, null);

        // create the command buffer
        const command_buffer_info = c.VkCommandBufferAllocateInfo {
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = command_pool,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1
        };

        var command_buffer: c.VkCommandBuffer = undefined;
        vk.allocateCommandBuffer(device, &command_buffer_info, &command_buffer) catch |err| {
            std.log.err("Failed to allocate frame command buffer : {any}", .{ err });
            return err;
        };

        const semaphore_create_info = c.VkSemaphoreCreateInfo {
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
            .flags = 0
        };

        var sw_semaphore: c.VkSemaphore = undefined;
        vk.createSemaphore(device, &semaphore_create_info, null, &sw_semaphore) catch |err| {
            std.log.err("Failed to allocate swapchain semaphore : {any}", .{ err });
            return err;
        };
        errdefer c.vkDestroySemaphore(device, sw_semaphore, null);

        var render_semaphore: c.VkSemaphore = undefined;
        vk.createSemaphore(device, &semaphore_create_info, null, &render_semaphore) catch |err| {
            std.log.err("Failed to create render semaphore : {any}", .{ err });
            return err;
        };
        errdefer c.vkDestroySemaphore(device, render_semaphore, null);

        const fence_create_info = c.VkFenceCreateInfo {
            .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
        };

        var render_fence: c.VkFence = undefined;
        vk.createFence(device, &fence_create_info, null, &render_fence) catch |err| {
            std.log.err("Failed to create render fence : {any}", .{err});
            return err;
        };

        return .{
            .command_pool = command_pool,
            .command_buffer = command_buffer,
            .sw_semaphore = sw_semaphore,
            .render_semaphore = render_semaphore,
            .render_fence = render_fence
        };
    }

    pub fn deinit(self: *const Frame, device: c.VkDevice) void {
        c.vkDestroyFence(device, self.render_fence, null);
        c.vkDestroySemaphore(device, self.render_semaphore, null);
        c.vkDestroySemaphore(device, self.sw_semaphore, null);
        c.vkDestroyCommandPool(device, self.command_pool, null);
    }
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

const Swapchain = struct {
    allocator: std.mem.Allocator,

    extent: c.VkExtent2D,
    format: c.VkSurfaceFormatKHR,
    swapchain: c.VkSwapchainKHR,
    images: []c.VkImage,
    image_views: []c.VkImageView,

    pub fn init(allocator: std.mem.Allocator, device: c.VkDevice, gpu: c.VkPhysicalDevice, surface: c.VkSurfaceKHR, window_extent: c.VkExtent2D) !Swapchain {
        var surface_support: c.VkSurfaceCapabilitiesKHR = undefined;
        vk.getPhysicalDeviceSurfaceCapabilitiesKHR(gpu, surface, &surface_support) catch |err| {
            std.log.err("Failed to get surface capabilities : {any}", .{err});
            return err;
        };

        // pick optimal extent
        var sw_extent = window_extent;
        if (surface_support.currentExtent.width != std.math.maxInt(u32)) {
            sw_extent = surface_support.currentExtent;
        }
        else {
            sw_extent = .{
                .width = std.math.clamp(window_extent.width, surface_support.minImageExtent.width, surface_support.maxImageExtent.width),
                .height = std.math.clamp(window_extent.height, surface_support.minImageExtent.height, surface_support.maxImageExtent.height)
            };
        }

        // fetch available formats
        const surface_format_info = c.VkPhysicalDeviceSurfaceInfo2KHR {
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SURFACE_INFO_2_KHR,
            .surface = surface
        };

        var formats_count: u32 = 0;
        vk.getPhysicalDeviceSurfaceFormats2KHR(gpu, &surface_format_info, &formats_count, null) catch |err| {
            std.log.err("Failed to enumerates device supported formats: {any}", .{err});
            return err;
        };

        if (formats_count == 0) {
            std.log.warn("No format found", .{});
            return Error.NotFound;
        }

        const formats = allocator.alloc(c.VkSurfaceFormat2KHR, formats_count) catch |err| {
            std.log.err("Out of Memory", .{});
            return err;
        };
        defer allocator.free(formats);

        for (formats) |*f| {
            f.sType = c.VK_STRUCTURE_TYPE_SURFACE_FORMAT_2_KHR;
            f.pNext = null;
            f.surfaceFormat = c.VkSurfaceFormatKHR {};
        }

        vk.getPhysicalDeviceSurfaceFormats2KHR(gpu, &surface_format_info, &formats_count, formats.ptr) catch |err| {
            std.log.err("Failed to enumerates device supported formats: {any}", .{err});
            return err;
        };

        // pick optimal format
        var format: c.VkSurfaceFormatKHR = undefined;
        if (formats.len == 1 and formats[0].surfaceFormat.format == c.VK_FORMAT_UNDEFINED) {
            format = c.VkSurfaceFormatKHR {
                .format = c.VK_FORMAT_B8G8R8A8_UNORM,
                .colorSpace = c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
            };
        }
        else {
            for (formats) |f| {
                if (f.surfaceFormat.format == c.VK_FORMAT_B8G8R8A8_UNORM and f.surfaceFormat.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
                    format = f.surfaceFormat;
                }
            }
        }

        // fetch available present mode
        var present_mode_counts: u32 = 0;
        vk.getPhysicalDeviceSurfacePresentModesKHR(gpu, surface, &present_mode_counts, null) catch |err| {
            std.log.err("Failed to enumerates device supported formats: {any}", .{err});
            return err;
        };

        if (present_mode_counts == 0) {
            std.log.err("No present modes", .{});
            return Error.NotFound;
        }

        const present_modes = allocator.alloc(c.VkPresentModeKHR, present_mode_counts) catch |err| {
            std.log.err("Out of Memory", .{});
            return err;
        };
        defer allocator.free(present_modes);
        
        vk.getPhysicalDeviceSurfacePresentModesKHR(gpu, surface, &present_mode_counts, present_modes.ptr) catch |err| {
            std.log.err("Failed to enumerates device supported formats: {any}", .{err});
            return err;
        };

        // pick a present mode
        var sw_mode: c.VkPresentModeKHR = c.VK_PRESENT_MODE_FIFO_KHR; // par defaut
        for (present_modes) |mode| {
            if (mode == c.VK_PRESENT_MODE_MAILBOX_KHR) { // meilleur mode
                sw_mode = mode;
                break;
            }
            else if (mode == c.VK_PRESENT_MODE_IMMEDIATE_KHR) { // segond meilleur si disponible
                sw_mode = mode;
            }
        }

        // create the swapchain
        var image_count: u32 = surface_support.minImageCount + 1;
        if (surface_support.maxImageCount > 0 and image_count > surface_support.maxImageCount) {
            image_count = surface_support.maxImageCount;
        }

        // list queues info
        const swapchain_create_info = c.VkSwapchainCreateInfoKHR {
            .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .surface = surface,
            .minImageCount = image_count,
            .imageFormat = format.format,
            .imageColorSpace = format.colorSpace,
            .imageExtent = sw_extent,
            .imageArrayLayers = 1, // for mulitview/stereo
            .imageUsage = c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE, // if MODE_CONCURENT, define index count, and familiy index
            // .queueFamilyIndexCount = 1,
            // .pQueueFamilyIndices = &.{ queues.graphic_index },
            .preTransform = surface_support.currentTransform,
            .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .presentMode = sw_mode,
            .clipped = c.VK_TRUE,
            .oldSwapchain = @ptrCast(c.VK_NULL_HANDLE),
        };

        var swapchain: c.VkSwapchainKHR = undefined;
        vk.createSwapchainKHR(device, &swapchain_create_info, null, &swapchain) catch |err| {
            std.log.err("Failed to create the swapchain : {any}", .{err});
            return err;
        };
        errdefer c.vkDestroySwapchainKHR(device, swapchain, null);

        // get the swapchain images
        const images = try allocator.alloc(c.VkImage, image_count);
        errdefer allocator.free(images);

        vk.getSwapchainImagesKHR(device, swapchain, &image_count, images.ptr) catch |err| {
            std.log.err("Failed to fetch the swapchain images : {any}", .{err});
            return err;
        };

        // create image views
        const image_views = try allocator.alloc(c.VkImageView, image_count);
        errdefer allocator.free(image_views);

        for (images, 0..) |image, i| {
            const image_view_create_info = c.VkImageViewCreateInfo {
                .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                .image = image,
                .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
                .format = format.format,
                .subresourceRange = c.VkImageSubresourceRange {
                    .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                }
            };

            vk.createImageView(device, &image_view_create_info, null, &image_views[i]) catch |err| {
                std.log.err("Failed to create image view {d} for {any} : {any}", .{ i, image, err });
                return err;
            };
        }

        return .{
            .allocator = allocator,
            .extent = sw_extent,
            .format = format,
            .swapchain = swapchain,
            .images = images,
            .image_views = image_views
        };
    }

    pub fn deinit(self: *const Swapchain, device: c.VkDevice) void {
        for (self.image_views) |image_view| {
            c.vkDestroyImageView(device, image_view, null);
        }
        self.allocator.free(self.image_views);
        self.allocator.free(self.images); // on ne destroy pas les images car elles seront détruite par vkDestroySwapchainKHR
        c.vkDestroySwapchainKHR(device, self.swapchain, null);
    }
};

pub const Renderer = struct {
    instance: c.VkInstance,
    surface: c.VkSurfaceKHR,
    gpu: c.VkPhysicalDevice,
    device: c.VkDevice,
    queues: Queues,
    vma: c.VmaAllocator,
    swapchain: Swapchain,

    extensions: Extensions, // activated extensions list
    layers: Layers,

    frames: []Frame,

    pub fn init(allocator: std.mem.Allocator, app_name: []const u8, window: *c.SDL_Window) !Renderer {
        const layers = Layers {
            .VK_LAYER_KHRONOS_validation = true // when debug
        };
        
        const extensions = Extensions {
            .VK_KHR_swapchain = true,
            .VK_KHR_synchronization2 = true,
        };

        // initialize vulkan
        const instance = try create_instance(allocator, app_name, layers);
        errdefer c.vkDestroyInstance(instance, null);

        const surface = try create_surface(window, instance);
        errdefer c.vkDestroySurfaceKHR(instance, surface, null);

        const gpu = try select_physical_device(allocator, instance, surface, extensions);
        print_physical_device_info(gpu);

        const queue_indexes = fetch_queue_families(allocator, gpu, surface) catch |err| {
            std.log.err("Failed to fetch device queues", .{});
            return err;
        };

        const device = try create_device(allocator, gpu, queue_indexes.@"0", queue_indexes.@"1", layers, extensions);
        errdefer c.vkDestroyDevice(device, null);

        const queues = Queues.init(device, queue_indexes.@"0", queue_indexes.@"1");

        const vma = try create_vma(instance, gpu, device);
        errdefer c.vmaDestroyAllocator(vma);

        // initialize the swapchain
        const window_extent = current_window_extent(window) catch c.VkExtent2D { .width = 400, .height = 400 }; // try with min res
        const swapchain = try Swapchain.init(allocator, device, gpu, surface, window_extent);
        errdefer swapchain.deinit(device);

        // initialize the frames
        const frame_count = swapchain.images.len;

        var frames = try allocator.alloc(Frame, frame_count);
        errdefer allocator.free(frames);

        for (0..frame_count) |i| {
            frames[i] = try Frame.init(device, queues.graphic_index);
        }
        errdefer for (0..frame_count) |i| frames[i].deinit(device);

        return .{
            .instance = instance,
            .surface = surface,
            .gpu = gpu,
            .device = device,
            .queues = queues,
            .vma = vma,
            .swapchain = swapchain,

            .extensions = extensions,
            .layers = layers,

            .frames = frames,
        };
    }

    pub fn deinit(self: *const Renderer, allocator: std.mem.Allocator) void {
        vk.deviceWaitIdle(self.device) catch |err| {
            std.log.err("Failed to wait for device idle on renderer shutdown : {any}", .{err});
        };

        for (0..self.frames.len) |i| {
            self.frames[i].deinit(self.device);
        }
        allocator.free(self.frames);

        self.swapchain.deinit(self.device);

        c.vmaDestroyAllocator(self.vma);
        c.vkDestroyDevice(self.device, null);
        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyInstance(self.instance, null);
    }

    pub fn draw(self: *const Renderer, frame_index: u32) !void {
        const frame = &self.frames[frame_index];

        vk.waitForFences(self.device, 1, &frame.render_fence, c.VK_TRUE, std.math.maxInt(u64)) catch |err| {
            std.log.err("Failed to wait for frame {x} render fence : {any}\n", .{ frame_index, err });
            return Error.SkipImage;
        };

        const image_index = self.acquire_next_image(frame) catch {
            std.log.warn("Failed to acquire next image for frame {x}", .{frame_index});
            return Error.SkipImage;
        };

        // start recording draw command
        const cmd = self.begin_draw_command(frame) catch {
            std.log.warn("Failed to begin recording draw command for frame {x}...", .{frame_index});
            return Error.SkipImage;
        };

        // draw background

        // draw scene

        transition_image_layout(cmd, self.swapchain.images[image_index], c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);

        // copy draw image to swapchain image

        transition_image_layout(cmd, self.swapchain.images[image_index], c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);

        // draw engine GUI

        transition_image_layout(cmd, self.swapchain.images[image_index], c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR);

        // end recording
        // submit command buffer
        self.submit_draw_command(cmd, frame, image_index) catch {
            std.log.warn("Failed to submit draw command for frame {x}", .{frame_index});
            return Error.SkipImage;
        };
    }

    fn acquire_next_image(self: *const Renderer, frame: *const Frame) !u32 {
        const acquire_next_image_info = c.VkAcquireNextImageInfoKHR {
            .sType = c.VK_STRUCTURE_TYPE_ACQUIRE_NEXT_IMAGE_INFO_KHR,
            .swapchain = self.swapchain.swapchain,
            .timeout = std.math.maxInt(u64),
            .semaphore = frame.sw_semaphore,
            .fence = null,
            .deviceMask = 1,
        };

        var image_index: u32 = 0;
        vk.acquireNextImage2KHR(self.device, &acquire_next_image_info, &image_index) catch |err| {
            std.log.warn("TODO - handle errors : {any}", .{err});
            return err;
        };

        return image_index;
    }

    fn begin_draw_command(self: *const Renderer, frame: *const Frame) !c.VkCommandBuffer {
        vk.resetFences(self.device, 1, &frame.render_fence) catch |err| {
            std.log.warn("Failed to reset frame fence : {any}", .{err});
            return err;
        };

        vk.resetCommandBuffer(frame.command_buffer, 0) catch |err| {
            std.log.warn("Failed to reset command buffer : {any}", .{err});
            return err;
        };

        const begin_info = c.VkCommandBufferBeginInfo {
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        };
        vk.beginCommandBuffer(frame.command_buffer, &begin_info) catch |err| {
            std.log.warn("Failed to begin command buffer : {any}", .{err});
            return err;
        };

        return frame.command_buffer;
    }

    fn submit_draw_command(self: *const Renderer, cmd: c.VkCommandBuffer, frame: *const Frame, image_index: u32) !void {
        vk.endCommandBuffer(cmd) catch |err| {
            std.log.err("Failed to end command buffer : {any}", .{err});
            return err;
        };

        const command_buffer_submit_info = c.VkCommandBufferSubmitInfo {
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
            .commandBuffer = cmd,
            .deviceMask = 0
        };

        const wait_semaphore_info = c.VkSemaphoreSubmitInfo {
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
            .semaphore = frame.sw_semaphore,
            .stageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT_KHR,
            .deviceIndex = 0,
            .value = 1,
        };

        const signal_semaphore_info = c.VkSemaphoreSubmitInfo {
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
            .semaphore = frame.render_semaphore,
            .stageMask = c.VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
            .deviceIndex = 0,
            .value = 1,
        };

        const submit_info = c.VkSubmitInfo2 {
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
            .flags = 0,
            .commandBufferInfoCount = 1,
            .pCommandBufferInfos = &command_buffer_submit_info,
            .waitSemaphoreInfoCount = 1,
            .pWaitSemaphoreInfos = &wait_semaphore_info,
            .signalSemaphoreInfoCount = 1,
            .pSignalSemaphoreInfos = &signal_semaphore_info,
        };

        vk.queueSubmit2(self.queues.graphic, 1, &submit_info, frame.render_fence) catch |err| {
            std.log.err("Failed to submit command buffer : {any}", .{err});
            return err;
        };

        const present_info = c.VkPresentInfoKHR {
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &frame.render_semaphore,
            .swapchainCount = 1,
            .pSwapchains = &self.swapchain.swapchain,
            .pImageIndices = &image_index,
            .pResults = null,
        };

        vk.queuePresentKHR(self.queues.graphic, &present_info) catch |err| {
            std.log.err("Failed to present queue : {any}", .{err});
            return err;
        };
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

    var extensions = std.ArrayList([*c]const u8).empty;
    defer extensions.deinit(allocator);

    for (0..extension_count, required_extensions) |_, ext| {
        try extensions.append(allocator, ext);
    }
    try extensions.append(allocator, "VK_KHR_get_surface_capabilities2");

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
        
        .enabledExtensionCount = @intCast(extensions.items.len),
        .ppEnabledExtensionNames = extensions.items.ptr,
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

fn select_physical_device(allocator: std.mem.Allocator, instance: c.VkInstance, surface: c.VkSurfaceKHR, extensions: Extensions) !c.VkPhysicalDevice {
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
        const extensions_support = check_device_extensions(allocator, device, extensions);
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

fn check_device_extensions(allocator: std.mem.Allocator, device: c.VkPhysicalDevice, exts: Extensions) bool {
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

    var required_extensions = std.ArrayList([]const u8).empty;
    defer required_extensions.deinit(allocator);

    if (exts.VK_KHR_swapchain) {
        required_extensions.append(allocator, "VK_KHR_swapchain") catch {
            std.log.err("Memory Allocation failed", .{});
            return false;
        };
    }

    var match_extensions: u8 = 0;
    for (required_extensions.items) |required| {
        for (0..extension_count) |i| {
            const name: [*c]const u8 = @ptrCast(extensions[i].extensionName[0..]);
            if (std.mem.eql(u8, std.mem.span(name), required)) {
                match_extensions += 1;
            }
        }
    }

    return match_extensions == required_extensions.items.len;
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

fn create_device(allocator: std.mem.Allocator, physical_device: c.VkPhysicalDevice, graphic_index: u32, compute_index: ?u32, layers: Layers, extensions: Extensions) !c.VkDevice {
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
        .synchronization2 = if (extensions.VK_KHR_synchronization2) c.VK_TRUE else c.VK_FALSE,
    };

    // layers
    var layer_names = std.ArrayList([]const u8).empty;
    defer layer_names.deinit(allocator);

    if (layers.VK_LAYER_KHRONOS_validation) {
        try layer_names.append(allocator, "VK_LAYER_KHRONOS_validation");
    }

    // extensions
    var extensions_names = std.ArrayList([*c]const u8).empty;
    defer extensions_names.deinit(allocator);

    if (extensions.VK_KHR_swapchain) {
        try extensions_names.append(allocator, "VK_KHR_swapchain");
    }

    if (extensions.VK_KHR_synchronization2) {
        try extensions_names.append(allocator, "VK_KHR_synchronization2");
    }

    const device_create_info = c.VkDeviceCreateInfo {
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = &features_vulkan13,
        .queueCreateInfoCount = @intCast(queue_create_infos.items.len),
        .pQueueCreateInfos = queue_create_infos.items.ptr,

        .enabledExtensionCount = @intCast(extensions_names.items.len),
        .ppEnabledExtensionNames = @ptrCast(extensions_names.items.ptr),

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

fn current_window_extent(window: *c.SDL_Window) !c.VkExtent2D {
    var extent: c.VkExtent2D = .{ 
        .width = 0,
        .height = 0
    };
    const result = c.SDL_GetWindowSize(window, @ptrCast(&extent.width), @ptrCast(&extent.height));
    if (!result) {
        std.log.warn("Failed to get window size", .{});
        return Error.InvalidResult;
    }

    return extent;
}

fn transition_image_layout(cmd: c.VkCommandBuffer, image: c.VkImage, current_layout: c.VkImageLayout, new_layout: c.VkImageLayout) void {
    const aspect_mask: c.VkImageAspectFlags = if (new_layout == c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL) c.VK_IMAGE_ASPECT_DEPTH_BIT else c.VK_IMAGE_ASPECT_COLOR_BIT;

	const image_barrier = c.VkImageMemoryBarrier2 {
		.sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
		.pNext = null,

		.srcStageMask = c.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
		.srcAccessMask = c.VK_ACCESS_2_MEMORY_WRITE_BIT,
		.dstStageMask = c.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
		.dstAccessMask = c.VK_ACCESS_2_MEMORY_WRITE_BIT | c.VK_ACCESS_2_MEMORY_READ_BIT,

		.oldLayout = current_layout,
		.newLayout = new_layout,

		.image = image,
		.subresourceRange = c.VkImageSubresourceRange {
		    .aspectMask = aspect_mask,
		    .baseMipLevel = 0,
		    .levelCount = c.VK_REMAINING_MIP_LEVELS,
		    .baseArrayLayer = 0,
		    .layerCount = c.VK_REMAINING_ARRAY_LAYERS,
	    },
	};

	const dep_info = c.VkDependencyInfo {
		.sType = c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,

		.pNext = null,
		
		.dependencyFlags = 0,
		.memoryBarrierCount = 0,
		.pMemoryBarriers = null,
		.bufferMemoryBarrierCount = 0,
		.pBufferMemoryBarriers = null,
		
		.imageMemoryBarrierCount = 1,
		.pImageMemoryBarriers = &image_barrier,
	};

    c.vkCmdPipelineBarrier2(cmd, &dep_info);
}

const Error = error {
    SurfaceError,
    NoDevice,
    DeviceError,
    NotFound,
    InvalidResult,
    SkipImage,
};

const std = @import("std");
const c = @import("c.zig").c;
const vk = @import("vk.zig");
