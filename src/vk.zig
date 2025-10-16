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
