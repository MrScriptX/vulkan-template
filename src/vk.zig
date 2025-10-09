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
