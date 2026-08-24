const c = @import("c");

pub const Error = error {
    Incomplete,
    OutOfHostMemory,
    OutOfDeviceMemory,
    InitializationFailed,
    LayerNotPresent,
    ExtensionNotPresent,
    IncompatibleDriver,
    SurfaceLostKHR,
    ValidationFailed,
    OutOfDateKHR,
    FullScreenExclusiveModeLostExt,
    DeviceLost,
    NotReady,
    SuboptimalKHR,
    Timeout,
    Unknown
};

pub fn check_result(result: c.VkResult) Error!void {
    switch (result) {
        c.VK_SUCCESS => return,
        c.VK_INCOMPLETE => return Error.Incomplete,
        c.VK_SUBOPTIMAL_KHR => return Error.SuboptimalKHR,
        c.VK_TIMEOUT => return Error.Timeout,
        c.VK_NOT_READY => return Error.NotReady,
        c.VK_ERROR_OUT_OF_HOST_MEMORY => return Error.OutOfHostMemory,
        c.VK_ERROR_OUT_OF_DEVICE_MEMORY => return Error.OutOfDeviceMemory,
        c.VK_ERROR_INITIALIZATION_FAILED => return Error.InitializationFailed,
        c.VK_ERROR_LAYER_NOT_PRESENT => return Error.LayerNotPresent,
        c.VK_ERROR_EXTENSION_NOT_PRESENT => return Error.ExtensionNotPresent,
        c.VK_ERROR_INCOMPATIBLE_DRIVER => return Error.IncompatibleDriver,
        c.VK_ERROR_DEVICE_LOST => return Error.DeviceLost,
        c.VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT => return Error.FullScreenExclusiveModeLostExt,
        c.VK_ERROR_OUT_OF_DATE_KHR => return Error.OutOfDateKHR,
        c.VK_ERROR_SURFACE_LOST_KHR => return Error.SurfaceLostKHR,
        c.VK_ERROR_VALIDATION_FAILED => return Error.ValidationFailed,
        else => return Error.Unknown
    }
}

pub fn vmaCreateAllocator(pCreateInfo: [*c]const c.VmaAllocatorCreateInfo, pAllocator: [*c]c.VmaAllocator) Error!void {
    const result = c.vmaCreateAllocator(pCreateInfo, pAllocator);
    try check_result(result);
}

pub fn vmaCreateImage(allocator: c.VmaAllocator, pImageCreateInfo: [*c]const c.VkImageCreateInfo, pAllocationCreateInfo: [*c]const c.VmaAllocationCreateInfo, pImage: [*c]c.VkImage, pAllocation: [*c]c.VmaAllocation, pAllocationInfo: [*c]c.VmaAllocationInfo) Error!void {
    const result = c.vmaCreateImage(allocator, pImageCreateInfo, pAllocationCreateInfo, pImage, pAllocation, pAllocationInfo);
    try check_result(result);
}

pub fn getPhysicalDeviceQueueFamilyProperties(physicalDevice: c.VkPhysicalDevice, pQueueFamilyPropertyCount: [*c]u32, pQueueFamilyProperties: [*c]c.VkQueueFamilyProperties) void {
    c.vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, pQueueFamilyPropertyCount, pQueueFamilyProperties);
}

pub fn getPhysicalDeviceQueueFamilyProperties2(physicalDevice: c.VkPhysicalDevice, pQueueFamilyPropertyCount: [*c]u32, pQueueFamilyProperties: [*c]c.VkQueueFamilyProperties2) void {
    c.vkGetPhysicalDeviceQueueFamilyProperties2(physicalDevice, pQueueFamilyPropertyCount, pQueueFamilyProperties);
}
