pub inline fn instanceToC(handle: vk.Instance) c.VkInstance {
    return @ptrFromInt(@intFromEnum(handle));
}

pub inline fn physicalDeviceToC(handle: vk.PhysicalDevice) c.VkPhysicalDevice {
    return @ptrFromInt(@intFromEnum(handle));
}

pub inline fn deviceToC(handle: vk.Device) c.VkDevice {
    return @ptrFromInt(@intFromEnum(handle));
}

pub inline fn surfaceFromC(handle: c.VkSurfaceKHR) vk.SurfaceKHR {
    return @enumFromInt(@intFromPtr(handle));
}

pub inline fn imageToC(handle: vk.Image) c.VkImage {
    return @ptrFromInt(@intFromEnum(handle));
}

pub inline fn imageFromC(handle: c.VkImage) vk.Image {
    return @enumFromInt(@intFromPtr(handle));
}

pub inline fn bufferToC(handle: vk.Buffer) c.VkBuffer {
    return @ptrFromInt(@intFromEnum(handle));
}

pub inline fn bufferFromC(handle: c.VkBuffer) vk.Buffer {
    return @enumFromInt(@intFromPtr(handle));
}

pub fn vmaCreateAllocator(p_create_info: *const c.VmaAllocatorCreateInfo, p_allocator: *c.VmaAllocator) vk.Error!void {
    try vk.check_result(@enumFromInt(c.vmaCreateAllocator(p_create_info, p_allocator)));
}

pub fn vmaCreateImage(
    allocator: c.VmaAllocator,
    p_image_create_info: *const c.VkImageCreateInfo,
    p_alloc_create_info: *const c.VmaAllocationCreateInfo,
    p_image: *c.VkImage,
    p_allocation: *c.VmaAllocation,
    p_allocation_info: ?*c.VmaAllocationInfo,
) vk.Error!void {
    try vk.check_result(@enumFromInt(c.vmaCreateImage(
        allocator, p_image_create_info, p_alloc_create_info, p_image, p_allocation, p_allocation_info
    )));
}

pub fn vmaCreateBuffer(
    allocator: c.VmaAllocator,
    p_buffer_create_info: *const c.VkBufferCreateInfo,
    p_alloc_create_info: *const c.VmaAllocationCreateInfo,
    p_buffer: *c.VkBuffer,
    p_allocation: *c.VmaAllocation,
    p_allocation_info: ?*c.VmaAllocationInfo,
) vk.Error!void {
    try vk.check_result(@enumFromInt(c.vmaCreateBuffer(
        allocator, p_buffer_create_info, p_alloc_create_info, p_buffer, p_allocation, p_allocation_info
    )));
}

pub fn vmaMapMemory(allocator: c.VmaAllocator, allocation: c.VmaAllocation, pp_data: [*c]?*anyopaque) vk.Error!void {
    const result = c.vmaMapMemory(allocator, allocation, pp_data);
    try vk.check_result(@enumFromInt(result));
}

const c = @import("c");
const vk = @import("vk");
