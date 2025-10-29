const Error = error {
    Incomplete,
    OutOfHostMemory,
    OutOfDeviceMemory,
    InitializationFailed,
    LayerNotPresent,
    ExtensionNotPresent,
    IncompatibleDriver,
    Unknown
};

pub fn createInstance(pCreateInfo: *const c.VkInstanceCreateInfo, pAllocator: ?*const c.VkAllocationCallbacks, pInstance: *c.VkInstance) Error!void {
    const result = c.vkCreateInstance(pCreateInfo, pAllocator, pInstance);
    try check_result(result);
}

pub fn enumeratePhysicalDevices(instance: c.VkInstance, pPhysicalDeviceCount: [*c]u32, pPhysicalDevices: [*c]c.VkPhysicalDevice) Error!void {
    const result = c.vkEnumeratePhysicalDevices(instance, pPhysicalDeviceCount, pPhysicalDevices);
    try check_result(result);
}

pub fn enumerateDeviceExtensionProperties(physicalDevice: c.VkPhysicalDevice, pLayerName: [*c]const u8, pPropertyCount: [*c]u32, pProperties: [*c]c.VkExtensionProperties) Error!void {
    const result = c.vkEnumerateDeviceExtensionProperties(physicalDevice, pLayerName, pPropertyCount, pProperties);
    try check_result(result);
}

pub fn getPhysicalDeviceSurfaceFormatsKHR(physicalDevice: c.VkPhysicalDevice, surface: c.VkSurfaceKHR, pSurfaceFormatCount: [*c]u32, pSurfaceFormats: [*c]c.VkSurfaceFormatKHR) Error!void {
    const result = c.vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, surface, pSurfaceFormatCount, pSurfaceFormats);
    try check_result(result);
}

pub fn getPhysicalDeviceSurfaceFormats2KHR(physicalDevice: c.VkPhysicalDevice, pSurfaceInfo: [*c]const c.VkPhysicalDeviceSurfaceInfo2KHR, pSurfaceFormatCount: [*c]u32, pSurfaceFormats: [*c]c.VkSurfaceFormat2KHR) Error!void {
    const result = c.vkGetPhysicalDeviceSurfaceFormats2KHR(physicalDevice, pSurfaceInfo, pSurfaceFormatCount, pSurfaceFormats);
    try check_result(result);
}

pub fn getPhysicalDeviceSurfacePresentModesKHR(physicalDevice: c.VkPhysicalDevice, surface: c.VkSurfaceKHR, pPresentModeCount: [*c]u32, pPresentModes: [*c]c.VkPresentModeKHR) Error!void {
    const result = c.vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice, surface, pPresentModeCount, pPresentModes);
    try check_result(result);
}

pub fn getPhysicalDeviceSurfaceSupportKHR(physicalDevice: c.VkPhysicalDevice, queueFamilyIndex: u32, surface: c.VkSurfaceKHR, pSupported: [*c]c.VkBool32) !void {
    const result = c.vkGetPhysicalDeviceSurfaceSupportKHR(physicalDevice, queueFamilyIndex, surface, pSupported);
    try check_result(result);
}

pub fn getPhysicalDeviceQueueFamilyProperties(physicalDevice: c.VkPhysicalDevice, pQueueFamilyPropertyCount: [*c]u32, pQueueFamilyProperties: [*c]c.VkQueueFamilyProperties) void {
    c.vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, pQueueFamilyPropertyCount, pQueueFamilyProperties);
}

pub fn getPhysicalDeviceQueueFamilyProperties2(physicalDevice: c.VkPhysicalDevice, pQueueFamilyPropertyCount: [*c]u32, pQueueFamilyProperties: [*c]c.VkQueueFamilyProperties2) void {
    c.vkGetPhysicalDeviceQueueFamilyProperties2(physicalDevice, pQueueFamilyPropertyCount, pQueueFamilyProperties);
}

pub fn createDevice(physicalDevice: c.VkPhysicalDevice, pCreateInfo: [*c]const c.VkDeviceCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pDevice: [*c]c.VkDevice) !void {
    const result = c.vkCreateDevice(physicalDevice, pCreateInfo, pAllocator, pDevice);
    try check_result(result);
}

pub fn vmaCreateAllocator(pCreateInfo: [*c]const c.VmaAllocatorCreateInfo, pAllocator: [*c]c.VmaAllocator) Error!void {
    const result = c.vmaCreateAllocator(pCreateInfo, pAllocator);
    try check_result(result);
}

pub fn getPhysicalDeviceSurfaceCapabilitiesKHR(physicalDevice: c.VkPhysicalDevice, surface: c.VkSurfaceKHR, pSurfaceCapabilities: [*c]c.VkSurfaceCapabilitiesKHR) Error!void {
    const result = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physicalDevice, surface, pSurfaceCapabilities);
    try check_result(result);
}

pub fn createSwapchainKHR(device: c.VkDevice, pCreateInfo: [*c]const c.VkSwapchainCreateInfoKHR, pAllocator: [*c]const c.VkAllocationCallbacks, pSwapchain: [*c]c.VkSwapchainKHR) Error!void {
    const result = c.vkCreateSwapchainKHR(device, pCreateInfo, pAllocator, pSwapchain);
    try check_result(result);
}

pub fn getSwapchainImagesKHR(device: c.VkDevice, swapchain: c.VkSwapchainKHR, pSwapchainImageCount: [*c]u32, pSwapchainImages: [*c]c.VkImage) Error!void {
    const result = c.vkGetSwapchainImagesKHR(device, swapchain, pSwapchainImageCount, pSwapchainImages);
    try check_result(result);
}

pub fn createImageView(device: c.VkDevice, pCreateInfo: [*c]const c.VkImageViewCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pView: [*c]c.VkImageView) Error!void {
    const result = c.vkCreateImageView(device, pCreateInfo, pAllocator, pView);
    try check_result(result);
}

pub fn createCommandPool(device: c.VkDevice, pCreateInfo: [*c]const c.VkCommandPoolCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pCommandPool: [*c]c.VkCommandPool) Error!void {
    const result = c.vkCreateCommandPool(device, pCreateInfo, pAllocator, pCommandPool);
    try check_result(result);
}

pub fn allocateCommandBuffer(device: c.VkDevice, pAllocateInfo: [*c]const c.VkCommandBufferAllocateInfo, pCommandBuffers: [*c]c.VkCommandBuffer) Error!void {
    const result = c.vkAllocateCommandBuffers(device, pAllocateInfo, pCommandBuffers);
    try check_result(result);
}

pub fn createSemaphore(device: c.VkDevice, pCreateInfo: [*c]const c.VkSemaphoreCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pSemaphore: [*c]c.VkSemaphore) Error!void {
    const result = c.vkCreateSemaphore(device, pCreateInfo, pAllocator, pSemaphore);
    try check_result(result);
}

pub fn createFence(device: c.VkDevice, pCreateInfo: [*c]const c.VkFenceCreateInfo, pAllocator: [*c]const c.VkAllocationCallbacks, pFence: [*c]c.VkFence) Error!void {
    const result = c.vkCreateFence(device, pCreateInfo, pAllocator, pFence);
    try check_result(result);
}

pub fn resetFences(device: c.VkDevice, fenceCount: u32, pFences: [*c]const c.VkFence) Error!void {
    const result = c.vkResetFences(device, fenceCount, pFences);
    try check_result(result);
}

pub fn resetCommandBuffer(commandBuffer: c.VkCommandBuffer, flags: c.VkCommandBufferResetFlags) Error!void {
    const result = c.vkResetCommandBuffer(commandBuffer, flags);
    try check_result(result);
}

pub fn beginCommandBuffer(commandBuffer: c.VkCommandBuffer, pBeginInfo: [*c]const c.VkCommandBufferBeginInfo) Error!void {
    const result = c.vkBeginCommandBuffer(commandBuffer, pBeginInfo);
    try check_result(result);
}

pub fn endCommandBuffer(commandBuffer: c.VkCommandBuffer) Error!void {
    const result = c.vkEndCommandBuffer(commandBuffer);
    try check_result(result);
}

pub fn queueSubmit2(queue: c.VkQueue, submitCount: u32, pSubmits: [*c]const c.VkSubmitInfo2, fence: c.VkFence) Error!void {
    const result = c.vkQueueSubmit2(queue, submitCount, pSubmits, fence);
    try check_result(result);
}

pub fn acquireNextImage2KHR(device: c.VkDevice, pAcquireInfo: [*c]const c.VkAcquireNextImageInfoKHR, pImageIndex: [*c]u32) Error!void {
    const result = c.vkAcquireNextImage2KHR(device, pAcquireInfo, pImageIndex);
    try check_result(result);
}

pub fn queuePresentKHR(queue: c.VkQueue, pPresentInfo: [*c]const c.VkPresentInfoKHR) Error!void {
    const result = c.vkQueuePresentKHR(queue, pPresentInfo);
    try check_result(result);
}

pub fn waitForFences(device: c.VkDevice, fenceCount: u32, pFences: [*c]const c.VkFence, waitAll: c.VkBool32, timeout: u64) Error!void {
    const result = c.vkWaitForFences(device, fenceCount, pFences, waitAll, timeout);
    try check_result(result);
}

pub fn check_result(result: c.VkResult) Error!void {
    switch (result) {
        c.VK_SUCCESS => return,
        c.VK_INCOMPLETE => return Error.Incomplete,
        c.VK_ERROR_OUT_OF_HOST_MEMORY => return Error.OutOfHostMemory,
        c.VK_ERROR_OUT_OF_DEVICE_MEMORY => return Error.OutOfDeviceMemory,
        c.VK_ERROR_INITIALIZATION_FAILED => return Error.InitializationFailed,
        c.VK_ERROR_LAYER_NOT_PRESENT => return Error.LayerNotPresent,
        c.VK_ERROR_EXTENSION_NOT_PRESENT => return Error.ExtensionNotPresent,
        c.VK_ERROR_INCOMPATIBLE_DRIVER => return Error.IncompatibleDriver,
        else => return Error.Unknown
    }
}

const c = @import("c.zig").c;
