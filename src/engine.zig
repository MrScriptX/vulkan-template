const Extensions = struct {
    VK_KHR_swapchain: bool,
    VK_KHR_synchronization2: bool,
};

const Layers = struct {
    VK_LAYER_KHRONOS_validation: bool,
};

const Frame = struct {
    command_pool: vk.CommandPool,
    command_buffer: vk.CommandBuffer,

    sw_semaphore: vk.Semaphore,
    render_semaphore: vk.Semaphore,
	render_fence: vk.Fence,

    pub fn init(device: vk.Device, queue_family_index: u32) !Frame {
        // create the command pool
        const command_pool_create_info = vk.CommandPoolCreateInfo {
            .sType = .command_pool_create_info,
            .flags = .{ .reset_command_buffer_bit = true },
            .queueFamilyIndex = queue_family_index,
        };

        var command_pool: vk.CommandPool = undefined;
        vk.createCommandPool(device, &command_pool_create_info, null, &command_pool) catch |err| {
            std.log.err("Failed to create a command pool : {any}", .{err});
            return err;
        };
        errdefer vk.destroyCommandPool(device, command_pool, null);

        // create the command buffer
        const command_buffer_info = vk.CommandBufferAllocateInfo {
            .sType = .command_buffer_allocate_info,
            .commandPool = command_pool,
            .level = .primary,
            .commandBufferCount = 1
        };

        var command_buffer: vk.CommandBuffer = undefined;
        vk.allocateCommandBuffers(device, &command_buffer_info, &command_buffer) catch |err| {
            std.log.err("Failed to allocate frame command buffer : {any}", .{ err });
            return err;
        };

        const semaphore_create_info = vk.SemaphoreCreateInfo {
            .sType = .semaphore_create_info,
        };

        var sw_semaphore: vk.Semaphore = undefined;
        vk.createSemaphore(device, &semaphore_create_info, null, &sw_semaphore) catch |err| {
            std.log.err("Failed to allocate swapchain semaphore : {any}", .{ err });
            return err;
        };
        errdefer vk.destroySemaphore(device, sw_semaphore, null);

        var render_semaphore: vk.Semaphore = undefined;
        vk.createSemaphore(device, &semaphore_create_info, null, &render_semaphore) catch |err| {
            std.log.err("Failed to create render semaphore : {any}", .{ err });
            return err;
        };
        errdefer vk.destroySemaphore(device, render_semaphore, null);

        const fence_create_info = vk.FenceCreateInfo {
            .sType = .fence_create_info,
            .flags = .{ .signaled_bit = true },
        };

        var render_fence: vk.Fence = undefined;
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

    pub fn deinit(self: *const Frame, device: vk.Device) void {
        vk.destroyFence(device, self.render_fence, null);
        vk.destroySemaphore(device, self.render_semaphore, null);
        vk.destroySemaphore(device, self.sw_semaphore, null);
        vk.destroyCommandPool(device, self.command_pool, null);
    }

    pub fn reset_sw_semaphore(self: *Frame, device: vk.Device) !void {
        vk.destroySemaphore(device, self.sw_semaphore, null);

        const semaphore_create_info = vk.SemaphoreCreateInfo {
            .sType = .semaphore_create_info,
        };

        var sw_semaphore: vk.Semaphore = undefined;
        vk.createSemaphore(device, &semaphore_create_info, null, &sw_semaphore) catch |err| {
            std.log.err("Failed to create swapchain semaphore : {any}", .{ err });
            return err;
        };

        self.sw_semaphore = sw_semaphore;
    }
};

const Queues = struct {
    graphic: vk.Queue,
    graphic_index: u32,

    compute: ?vk.Queue = null,
    compute_index: ?u32 = null,

    pub fn init(device: vk.Device, graphic_index: u32, compute_index: ?u32) Queues {
        const graphic_queue: vk.Queue = create_queue(device, graphic_index);

        var compute_queue: ?vk.Queue = null;
        if (compute_index) |index| {
            const queue: vk.Queue = create_queue(device, index);
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

    extent: vk.Extent2D,
    format: vk.SurfaceFormatKHR,
    swapchain: vk.SwapchainKHR,
    images: []vk.Image,
    image_views: []vk.ImageView,

    pub fn init(allocator: std.mem.Allocator, device: vk.Device, gpu: vk.PhysicalDevice, surface: vk.SurfaceKHR, window_extent: vk.Extent2D) !Swapchain {
        var surface_support: vk.SurfaceCapabilitiesKHR = undefined;
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
        const surface_format_info = vk.PhysicalDeviceSurfaceInfo2KHR {
            .sType = .physical_device_surface_info_2_khr,
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

        const formats = allocator.alloc(vk.SurfaceFormat2KHR, formats_count) catch |err| {
            std.log.err("Out of Memory", .{});
            return err;
        };
        defer allocator.free(formats);

        for (formats) |*f| {
            f.sType = .surface_format_2_khr;
            f.pNext = null;
            f.surfaceFormat = vk.SurfaceFormatKHR {};
        }

        vk.getPhysicalDeviceSurfaceFormats2KHR(gpu, &surface_format_info, &formats_count, formats.ptr) catch |err| {
            std.log.err("Failed to enumerates device supported formats: {any}", .{err});
            return err;
        };

        // pick optimal format
        var format: vk.SurfaceFormatKHR = undefined;
        if (formats.len == 1 and formats[0].surfaceFormat.format == .@"undefined") {
            format = vk.SurfaceFormatKHR {
                .format = .b8g8r8a8_unorm,
                .colorSpace = .srgb_nonlinear,
            };
        }
        else {
            for (formats) |f| {
                if (f.surfaceFormat.format == .b8g8r8a8_unorm and f.surfaceFormat.colorSpace == .srgb_nonlinear) {
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

        const present_modes = allocator.alloc(vk.PresentModeKHR, present_mode_counts) catch |err| {
            std.log.err("Out of Memory", .{});
            return err;
        };
        defer allocator.free(present_modes);

        vk.getPhysicalDeviceSurfacePresentModesKHR(gpu, surface, &present_mode_counts, present_modes.ptr) catch |err| {
            std.log.err("Failed to enumerates device supported formats: {any}", .{err});
            return err;
        };

        // pick a present mode
        var sw_mode: vk.PresentModeKHR = .fifo; // par defaut
        for (present_modes) |mode| {
            if (mode == .mailbox) { // meilleur mode
                sw_mode = mode;
                break;
            }
            else if (mode == .immediate) { // segond meilleur si disponible
                sw_mode = mode;
            }
        }

        // create the swapchain
        var image_count: u32 = surface_support.minImageCount + 1;
        if (surface_support.maxImageCount > 0 and image_count > surface_support.maxImageCount) {
            image_count = surface_support.maxImageCount;
        }

        // list queues info
        const swapchain_create_info = vk.SwapchainCreateInfoKHR {
            .sType = .swapchain_create_info_khr,
            .surface = surface,
            .minImageCount = image_count,
            .imageFormat = format.format,
            .imageColorSpace = format.colorSpace,
            .imageExtent = sw_extent,
            .imageArrayLayers = 1, // for mulitview/stereo
            .imageUsage = .{ .transfer_dst_bit = true, .color_attachment_bit = true },
            .imageSharingMode = .exclusive, // if MODE_CONCURENT, define index count, and familiy index
            // .queueFamilyIndexCount = 1,
            // .pQueueFamilyIndices = &.{ queues.graphic_index },
            .preTransform = surface_support.currentTransform,
            .compositeAlpha = .{ .opaque_bit = true },
            .presentMode = sw_mode,
            .clipped = c.VK_TRUE,
            .oldSwapchain = .null_handle,
        };

        var swapchain: vk.SwapchainKHR = undefined;
        vk.createSwapchainKHR(device, &swapchain_create_info, null, &swapchain) catch |err| {
            std.log.err("Failed to create the swapchain : {any}", .{err});
            return err;
        };
        errdefer vk.destroySwapchainKHR(device, swapchain, null);

        // get the swapchain images
        const images = try allocator.alloc(vk.Image, image_count);
        errdefer allocator.free(images);

        vk.getSwapchainImagesKHR(device, swapchain, &image_count, images.ptr) catch |err| {
            std.log.err("Failed to fetch the swapchain images : {any}", .{err});
            return err;
        };

        // create image views
        const image_views = try allocator.alloc(vk.ImageView, image_count);
        errdefer allocator.free(image_views);

        for (images, 0..) |image, i| {
            const image_view_create_info = vk.ImageViewCreateInfo {
                .sType = .image_view_create_info,
                .image = image,
                .viewType = .@"2d",
                .format = format.format,
                .subresourceRange = vk.ImageSubresourceRange {
                    .aspectMask = .{ .color_bit = true },
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

    pub fn deinit(self: *const Swapchain, device: vk.Device) void {
        for (self.image_views) |image_view| {
            vk.destroyImageView(device, image_view, null);
        }
        self.allocator.free(self.image_views);
        self.allocator.free(self.images); // on ne destroy pas les images car elles seront détruite par vkDestroySwapchainKHR
        vk.destroySwapchainKHR(device, self.swapchain, null);
    }
};

pub const Renderer = struct {
    instance: vk.Instance,
    surface: vk.SurfaceKHR,
    gpu: vk.PhysicalDevice,
    device: vk.Device,
    queues: Queues,
    vma: c.VmaAllocator,
    swapchain: Swapchain,

    extensions: Extensions, // activated extensions list
    layers: Layers,

    frames: []Frame,

    draw_resource: render.DrawResource,
    // render_image: types.Image, // image use to record scene command
    // depth_image: types.Image,

    pub fn init(allocator: std.mem.Allocator, app_name: [:0]const u8, window: *c.SDL_Window) !Renderer {
        const layers = Layers {
            .VK_LAYER_KHRONOS_validation = true // when debug
        };

        const extensions = Extensions {
            .VK_KHR_swapchain = true,
            .VK_KHR_synchronization2 = true,
        };

        // initialize vulkan
        const instance = try create_instance(allocator, app_name, layers);
        errdefer vk.destroyInstance(instance, null);

        vk.loadInstanceCommands(instance);

        const surface = try create_surface(window, instance);
        errdefer vk.destroySurfaceKHR(instance, surface, null);

        const gpu = try select_physical_device(allocator, instance, surface, extensions);
        print_physical_device_info(gpu);

        const queue_indexes = fetch_queue_families(allocator, gpu, surface) catch |err| {
            std.log.err("Failed to fetch device queues", .{});
            return err;
        };

        const device = try create_device(allocator, gpu, queue_indexes.@"0", queue_indexes.@"1", layers, extensions);
        errdefer vk.destroyDevice(device, null);

        vk.loadDeviceCommands(device);

        const queues = Queues.init(device, queue_indexes.@"0", queue_indexes.@"1");

        const vma = try create_vma(instance, gpu, device);
        errdefer c.vmaDestroyAllocator(vma);

        // initialize the swapchain
        const window_extent = current_window_extent(window) catch vk.Extent2D { .width = 400, .height = 400 }; // try with min res
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

        // initialize draw resource
        const draw_resource = try render.DrawResource.init(vma, device, window_extent.width, window_extent.height);
        errdefer draw_resource.deinit(vma, device);

        // create the render images
        // const render_extent = vk.Extent3D {
        //     .width = swapchain.extent.width,
        //     .height = swapchain.extent.height,
        //     .depth = 1
        // };

        // const render_image_usage: vk.ImageUsageFlags = .{ .transfer_src_bit = true, .storage_bit = true, .color_attachment_bit = true };

        // const render_image = types.Image.init(vma, device, .r16g16b16a16_sfloat, render_extent, render_image_usage, .{ .color_bit = true }) catch |err| {
        //     std.log.err("failed to create render image", .{});
        //     return err;
        // };
        // errdefer render_image.deinit(device, vma);

        // const depth_image = try types.Image.init(vma, device, .d32_sfloat, render_extent, .{ .depth_stencil_attachment_bit = true }, .{ .depth_bit = true });
        // errdefer depth_image.deinit(device, vma);

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
            .draw_resource = draw_resource
            // .render_image = render_image,
            // .depth_image = depth_image,
        };
    }

    pub fn deinit(self: *Renderer, allocator: std.mem.Allocator) void {
        self.stop();

        // self.depth_image.deinit(self.device, self.vma);
        // self.render_image.deinit(self.device, self.vma);
        self.draw_resource.deinit(self.vma, self.device);

        for (0..self.frames.len) |i| {
            self.frames[i].deinit(self.device);
        }
        allocator.free(self.frames);

        self.swapchain.deinit(self.device);

        c.vmaDestroyAllocator(self.vma);
        vk.destroyDevice(self.device, null);
        vk.destroySurfaceKHR(self.instance, self.surface, null);
        vk.destroyInstance(self.instance, null);
    }

    /// Wait for the renderer to complete all tasks
    pub fn stop(self: *const Renderer) void {
        vk.deviceWaitIdle(self.device) catch |err| {
            std.log.err("Failed to wait for device idle on renderer shutdown : {any}", .{err});
        };
    }

    pub fn draw(self: *const Renderer, frame_index: u32, scenes: anytype) !void {
        const frame = &self.frames[frame_index];

        vk.waitForFences(self.device, 1, &frame.render_fence, c.VK_TRUE, std.math.maxInt(u64)) catch |err| {
            std.log.err("Failed to wait for frame {x} render fence : {any}\n", .{ frame_index, err });
            return Error.SkipImage;
        };

        const image_index = self.acquire_next_image(frame) catch |err| {
            std.log.warn("Failed to acquire next image for frame {x}", .{frame_index});

            self.frames[frame_index].reset_sw_semaphore(self.device) catch {
                std.log.err("Failed to reset swapchain semaphore", .{});
                return Error.RendererError;
            };

            return err;
        };

        // start recording draw command
        const cmd = self.begin_draw_command(frame) catch {
            std.log.warn("Failed to begin recording draw command for frame {x}...", .{frame_index});
            return Error.SkipImage;
        };

        inline for (scenes) |scene| {
            scene.draw(cmd);
        }

        // copy draw image to swapchain image
        utils.transition_image_layout(cmd, self.swapchain.images[image_index], .@"undefined", .transfer_dst_optimal);

        const render_image_extent = vk.Extent2D {
            .width = self.draw_resource.color_image.extent.width,
            .height = self.draw_resource.color_image.extent.height,
        };
        blit_image(cmd, self.draw_resource.color_image.image, self.swapchain.images[image_index], render_image_extent, self.swapchain.extent);

        utils.transition_image_layout(cmd, self.swapchain.images[image_index], .transfer_dst_optimal, .color_attachment_optimal);

        // draw engine GUI

        utils.transition_image_layout(cmd, self.swapchain.images[image_index], .color_attachment_optimal, .present_src_khr);

        // end recording
        // submit command buffer
        self.submit_draw_command(cmd, frame, image_index) catch {
            std.log.warn("Failed to submit draw command for frame {x}", .{frame_index});
            return Error.SkipImage;
        };
    }

    fn acquire_next_image(self: *const Renderer, frame: *const Frame) !u32 {
        const acquire_next_image_info = vk.AcquireNextImageInfoKHR {
            .sType = .acquire_next_image_info_khr,
            .swapchain = self.swapchain.swapchain,
            .timeout = std.math.maxInt(u64),
            .semaphore = frame.sw_semaphore,
            .fence = .null_handle,
            .deviceMask = 1,
        };

        var image_index: u32 = 0;
        vk.acquireNextImage2KHR(self.device, &acquire_next_image_info, &image_index) catch |err| {
            switch (err) {
                vk.Error.NotReady => return Error.SkipImage,
                vk.Error.SuboptimalKHR => return Error.RebuildSW,
                vk.Error.Timeout => return Error.SkipImage,
                vk.Error.OutOfDateKHR => return Error.RebuildSW,
                else => return err
            }
        };

        return image_index;
    }

    fn begin_draw_command(self: *const Renderer, frame: *const Frame) !vk.CommandBuffer {
        vk.resetFences(self.device, 1, &frame.render_fence) catch |err| {
            std.log.warn("Failed to reset frame fence : {any}", .{err});
            return err;
        };

        vk.resetCommandBuffer(frame.command_buffer, .{}) catch |err| {
            std.log.warn("Failed to reset command buffer : {any}", .{err});
            return err;
        };

        const begin_info = vk.CommandBufferBeginInfo {
            .sType = .command_buffer_begin_info,
            .flags = .{ .one_time_submit_bit = true },
        };
        vk.beginCommandBuffer(frame.command_buffer, &begin_info) catch |err| {
            std.log.warn("Failed to begin command buffer : {any}", .{err});
            return err;
        };

        return frame.command_buffer;
    }

    fn submit_draw_command(self: *const Renderer, cmd: vk.CommandBuffer, frame: *const Frame, image_index: u32) !void {
        vk.endCommandBuffer(cmd) catch |err| {
            std.log.err("Failed to end command buffer : {any}", .{err});
            return err;
        };

        const command_buffer_submit_info = vk.CommandBufferSubmitInfo {
            .sType = .command_buffer_submit_info,
            .commandBuffer = cmd,
            .deviceMask = 0
        };

        const wait_semaphore_info = vk.SemaphoreSubmitInfo {
            .sType = .semaphore_submit_info,
            .semaphore = frame.sw_semaphore,
            .stageMask = .{ .color_attachment_output_bit = true },
            .deviceIndex = 0,
            .value = 1,
        };

        const signal_semaphore_info = vk.SemaphoreSubmitInfo {
            .sType = .semaphore_submit_info,
            .semaphore = frame.render_semaphore,
            .stageMask = .{ .all_graphics_bit = true },
            .deviceIndex = 0,
            .value = 1,
        };

        const submit_info = vk.SubmitInfo2 {
            .sType = .submit_info_2,
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

        const present_info = vk.PresentInfoKHR {
            .sType = .present_info_khr,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &frame.render_semaphore,
            .swapchainCount = 1,
            .pSwapchains = &self.swapchain.swapchain,
            .pImageIndices = &image_index,
        };

        vk.queuePresentKHR(self.queues.graphic, &present_info) catch |err| {
            std.log.err("Failed to present queue : {any}", .{err});
            return err;
        };
    }

    pub fn rebuild_swapchain(self: *Renderer, allocator: std.mem.Allocator, window: *c.SDL_Window) !void {
        self.stop();

        // self.depth_image.deinit(self.device, self.vma);
        // self.render_image.deinit(self.device, self.vma);
        self.draw_resource.deinit(self.vma, self.device);
        
        // clean up swapchain & resources
        self.swapchain.deinit(self.device);

        // build swapchain
        const window_extent = current_window_extent(window) catch vk.Extent2D { .width = 400, .height = 400 }; // try with min res
        self.swapchain = try Swapchain.init(allocator, self.device, self.gpu, self.surface, window_extent);
        errdefer self.swapchain.deinit(self.device);

        self.draw_resource = try render.DrawResource.init(self.vma, self.device, window_extent.width, window_extent.height);
    }
};

fn create_instance(allocator: std.mem.Allocator, app_name: [:0]const u8, layers: Layers) !vk.Instance {
    const app_info: vk.ApplicationInfo = .{
        .sType = .application_info,
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

    const instance_info = vk.InstanceCreateInfo {
        .sType = .instance_create_info,
        .pApplicationInfo = &app_info,

        .enabledLayerCount = @intCast(layer_names.items.len),
        .ppEnabledLayerNames = @ptrCast(layer_names.items.ptr),

        .enabledExtensionCount = @intCast(extensions.items.len),
        .ppEnabledExtensionNames = extensions.items.ptr,
    };

    var instance: vk.Instance = undefined;
    vk.createInstance(&instance_info, null, &instance) catch |err| {
        std.log.err("Vulkan instance creation failed : {any}", .{err});
        return err;
    };

    return instance;
}

fn create_surface(window: *c.SDL_Window, instance: vk.Instance) !vk.SurfaceKHR {
    var surface: c.VkSurfaceKHR = undefined;
    const result = c.SDL_Vulkan_CreateSurface(window, vk_interop.instanceToC(instance), null, &surface);
    if (result == false) {
        std.log.err("Unable to create Vulkan surface: {s}", .{ c.SDL_GetError() });
        return Error.SurfaceError;
    }

    return vk_interop.surfaceFromC(surface);
}

fn select_physical_device(allocator: std.mem.Allocator, instance: vk.Instance, surface: vk.SurfaceKHR, extensions: Extensions) !vk.PhysicalDevice {
    var device_count: u32 = 0;
    vk.enumeratePhysicalDevices(instance, &device_count, null) catch |err| {
        std.log.err("Failed to enumerate devices : {any}", .{err});
        return err;
    };

    if (device_count == 0) {
        std.log.warn("No device found", .{});
        return Error.NoDevice;
    }

    const devices = try allocator.alloc(vk.PhysicalDevice, device_count);
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

fn check_device_properties(device: vk.PhysicalDevice) bool {
    var properties: vk.PhysicalDeviceProperties2 = .{
        .sType = .physical_device_properties_2,
    };
    vk.getPhysicalDeviceProperties2(device, &properties);

    if (properties.properties.deviceType != .discrete_gpu and properties.properties.deviceType != .integrated_gpu) {
        std.log.warn("{s} is not a dedicated device", .{properties.properties.deviceName});
        return false;
    }

    return true;
}

fn check_device_features(device: vk.PhysicalDevice) bool {
    var features: vk.PhysicalDeviceFeatures2 = .{
        .sType = .physical_device_features_2,
    };
    vk.getPhysicalDeviceFeatures2(device, &features);

    return true;
}

fn check_device_extensions(allocator: std.mem.Allocator, device: vk.PhysicalDevice, exts: Extensions) bool {
    var extension_count: u32 = 0;
    vk.enumerateDeviceExtensionProperties(device, null, &extension_count, null) catch |err| {
        std.log.err("Failed to enumerate device extensions : {any}", .{err});
        return false;
    };

    if (extension_count == 0) {
        std.log.warn("No extensions found", .{});
        return false;
    }

    const extensions = allocator.alloc(vk.ExtensionProperties, extension_count) catch {
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

fn check_device_swapchain_support(allocator: std.mem.Allocator, device: vk.PhysicalDevice, surface: vk.SurfaceKHR) bool {
    var formats_count: u32 = 0;
    vk.getPhysicalDeviceSurfaceFormatsKHR(device, surface, &formats_count, null) catch |err| {
        std.log.err("Failed to enumerates device supported formats: {any}", .{err});
        return false;
    };

    if (formats_count == 0) {
        std.log.warn("No format found", .{});
        return false;
    }

    const formats = allocator.alloc(vk.SurfaceFormatKHR, formats_count) catch {
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

    const present_modes = allocator.alloc(vk.PresentModeKHR, present_mode_count) catch {
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

fn fetch_queue_families(allocator: std.mem.Allocator, device: vk.PhysicalDevice, surface: vk.SurfaceKHR) !struct { u32, ?u32 } {
    var family_count: u32 = 0;
    vk.getPhysicalDeviceQueueFamilyProperties(device, &family_count, null);

    if (family_count == 0) {
        std.log.err("No queue family found !", .{});
        return Error.DeviceError;
    }

    const queue_families = try allocator.alloc(vk.QueueFamilyProperties, family_count);
    defer allocator.free(queue_families);

    vk.getPhysicalDeviceQueueFamilyProperties(device, &family_count, queue_families.ptr);

    var graphic_queue_index: u32 = 0;
    var compute_queue_index: ?u32 = null;

    for (queue_families, 0..) |queue_family, index| {
        if (queue_family.queueCount > 0) {
            if (queue_family.queueFlags.graphics_bit) {
                // check presentation support
                var present_support: u32 = 0;
                vk.getPhysicalDeviceSurfaceSupportKHR(device, @as(u32, @intCast(index)), surface, &present_support) catch |err| {
                    std.log.warn("An error was raised while checking presentation support : {any}", .{err});
                    continue;
                };

                if (present_support == c.VK_TRUE) {
                    graphic_queue_index = @intCast(index);
                    continue;
                }
            }
            else if (queue_family.queueFlags.compute_bit) {
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

fn create_device(allocator: std.mem.Allocator, physical_device: vk.PhysicalDevice, graphic_index: u32, compute_index: ?u32, layers: Layers, extensions: Extensions) !vk.Device {
    // queues info
    var queue_create_infos = std.ArrayList(vk.DeviceQueueCreateInfo).empty;
    defer queue_create_infos.deinit(allocator);

    var queue_priority: f32 = 0.0;
    const graphic_graphic_queue_create_info = vk.DeviceQueueCreateInfo {
        .sType = .device_queue_create_info,
        .queueFamilyIndex = graphic_index,
        .queueCount = 1,
        .pQueuePriorities = &queue_priority
    };

    try queue_create_infos.append(allocator, graphic_graphic_queue_create_info);

    if (compute_index) |index| {
        const compute_queue_create_info = vk.DeviceQueueCreateInfo {
            .sType = .device_queue_create_info,
            .queueFamilyIndex = index,
            .queueCount = 1,
            .pQueuePriorities = &queue_priority
        };

        try queue_create_infos.append(allocator, compute_queue_create_info);
    }

    // device features
    const device_features = vk.PhysicalDeviceFeatures {
        .fillModeNonSolid = c.VK_TRUE,
    };

    const features_vulkan11 = vk.PhysicalDeviceVulkan11Features {
        .sType = .physical_device_vulkan_1_1_features,
        .shaderDrawParameters = c.VK_TRUE,
    };

    const features_vulkan12 = vk.PhysicalDeviceVulkan12Features {
        .sType = .physical_device_vulkan_1_2_features,
        .pNext = @constCast(@ptrCast(&features_vulkan11)),
        .bufferDeviceAddress = c.VK_TRUE,
    };

    const features_vulkan13 = vk.PhysicalDeviceVulkan13Features {
        .sType = .physical_device_vulkan_1_3_features,
        .pNext = @constCast(@ptrCast(&features_vulkan12)),
        .synchronization2 = if (extensions.VK_KHR_synchronization2) c.VK_TRUE else c.VK_FALSE,
        .dynamicRendering = c.VK_TRUE,
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

    const device_create_info = vk.DeviceCreateInfo {
        .sType = .device_create_info,
        .pNext = @ptrCast(&features_vulkan13),
        .queueCreateInfoCount = @intCast(queue_create_infos.items.len),
        .pQueueCreateInfos = queue_create_infos.items.ptr,

        .enabledExtensionCount = @intCast(extensions_names.items.len),
        .ppEnabledExtensionNames = @ptrCast(extensions_names.items.ptr),

        .enabledLayerCount = @intCast(layer_names.items.len),
        .ppEnabledLayerNames = @ptrCast(layer_names.items.ptr),

        .pEnabledFeatures = &device_features
    };

    var device: vk.Device = undefined;
    vk.createDevice(physical_device, &device_create_info, null, &device) catch |err| {
        std.log.err("Failed to create device : {any}", .{err});
        return err;
    };

    return device;
}

fn create_queue(device: vk.Device, family_index: u32) vk.Queue {
    const queue_info = vk.DeviceQueueInfo2 {
        .sType = .device_queue_info_2,
        .queueFamilyIndex = family_index,
        .queueIndex = 0
    };

    var queue: vk.Queue = undefined;
    vk.getDeviceQueue2(device, &queue_info, &queue);

    return queue;
}

fn create_vma(instance: vk.Instance, physical_device: vk.PhysicalDevice, device: vk.Device) !c.VmaAllocator {
    const create_allocator_info = c.VmaAllocatorCreateInfo {
        .instance = vk_interop.instanceToC(instance),
        .physicalDevice = vk_interop.physicalDeviceToC(physical_device),
        .device = vk_interop.deviceToC(device),
        .vulkanApiVersion = c.VK_API_VERSION_1_4,
        .flags = c.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT
    };

    var allocator: c.VmaAllocator = undefined;
    vk_interop.vmaCreateAllocator(&create_allocator_info, &allocator) catch |err| {
        std.log.err("Failed to create vulkan memory allocator : {any}", .{err});
        return err;
    };

    return allocator;
}

fn print_physical_device_info(device: vk.PhysicalDevice) void {
    var properties: vk.PhysicalDeviceProperties2 = .{
        .sType = .physical_device_properties_2,
    };
    vk.getPhysicalDeviceProperties2(device, &properties);

    std.log.info("Device Info", .{});
    std.log.info("Name: {s}", .{ properties.properties.deviceName });
    std.log.info("Vendor: {d}", .{ properties.properties.vendorID });
    std.log.info("API Version: {d}", .{ properties.properties.apiVersion });
    std.log.info("Driver: {d}", .{ properties.properties.driverVersion });
}

fn current_window_extent(window: *c.SDL_Window) !vk.Extent2D {
    var extent: vk.Extent2D = .{
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

fn blit_image(cmd: vk.CommandBuffer, source: vk.Image, destination: vk.Image, srcSize: vk.Extent2D, dstSize: vk.Extent2D) void {
    const empty_offset = vk.Offset3D {
        .x = 0,
        .y = 0,
        .z = 0,
    };

    const src_offset = vk.Offset3D {
        .x = @intCast(srcSize.width),
        .y = @intCast(srcSize.height),
        .z = 1,
    };

    const dst_offset = vk.Offset3D {
        .x = @intCast(dstSize.width),
        .y = @intCast(dstSize.height),
        .z = 1,
    };

    const blit_region = vk.ImageBlit2 {
        .sType = .image_blit_2,

        .srcOffsets = [_]vk.Offset3D{ empty_offset, src_offset },
        .dstOffsets = [_]vk.Offset3D{ empty_offset, dst_offset },

        .srcSubresource = vk.ImageSubresourceLayers {
            .aspectMask = .{ .color_bit = true },
            .baseArrayLayer = 0,
            .layerCount = 1,
            .mipLevel = 0,
        },

        .dstSubresource = vk.ImageSubresourceLayers {
            .aspectMask = .{ .color_bit = true },
            .baseArrayLayer = 0,
            .layerCount = 1,
            .mipLevel = 0,
        },
    };

	const blit_image_info = vk.BlitImageInfo2 {
        .sType = .blit_image_info_2,

        .dstImage = destination,
	    .dstImageLayout = .transfer_dst_optimal,
	    .srcImage = source,
	    .srcImageLayout = .transfer_src_optimal,
	    .filter = .linear,
	    .regionCount = 1,
	    .pRegions = &blit_region,
    };


	vk.cmdBlitImage2(cmd, &blit_image_info);
}

pub const Error = error {
    SurfaceError,
    NoDevice,
    DeviceError,
    NotFound,
    InvalidResult,
    SkipImage,
    RebuildSW,
    RendererError,
};

const std = @import("std");
const c = @import("c");
const vk = @import("vk");
const vk_interop = @import("graphics/vk_interop.zig");
const allocators = @import("graphics/allocators.zig");
const descriptors = @import("graphics/descriptors.zig");
const shaders = @import("graphics/shaders.zig");
const types = @import("graphics/types.zig");
const utils = @import("graphics/utils.zig");
const render = @import("render.zig");
