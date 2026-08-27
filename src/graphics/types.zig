pub const Image = struct {
    allocation: c.VmaAllocation,
    image: vk.Image,
    image_view: vk.ImageView,
    extent: vk.Extent3D,

    pub fn init(allocator: c.VmaAllocator, device: vk.Device, format: vk.Format, extent: vk.Extent3D, usage: vk.ImageUsageFlags, aspect_mask: vk.ImageAspectFlags) !Image {
        const image_create_info = vk.ImageCreateInfo {
            .sType = .image_create_info,
            .imageType = .@"2d",
            .format = format,
            .extent = extent,
            .mipLevels = 1,
            .arrayLayers = 1,
            .samples = .{ .@"1_bit" = true }, //for MSAA. we will not be using it by default, so default it to 1 sample per pixel.
            .tiling = .optimal, // optimal tiling, which means the image is stored on the best gpu format
            .usage = usage,
        };

        const alloc_create_info = c.VmaAllocationCreateInfo {
            .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
            .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        };

        var allocation: c.VmaAllocation = undefined;
        var c_image: c.VkImage = undefined;
        vk_interop.vmaCreateImage(allocator, @ptrCast(&image_create_info), &alloc_create_info, &c_image, &allocation, null) catch |err| {
            std.log.err("Failed to create image : {any}", .{err});
            return err;
        };
        errdefer c.vmaDestroyImage(allocator, c_image, allocation);

        const image = vk_interop.imageFromC(c_image);

        const image_view_create_info = vk.ImageViewCreateInfo {
            .sType = .image_view_create_info,
            .viewType = .@"2d",
            .image = image,
            .format = format,
            .subresourceRange = vk.ImageSubresourceRange {
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
                .aspectMask = aspect_mask,
            }
        };

        var image_view: vk.ImageView = undefined;
        vk.createImageView(device, &image_view_create_info, null, &image_view) catch |err| {
            std.log.err("Failed to create image view : {any}", .{err});
            return err;
        };
        errdefer vk.destroyImageView(device, image_view, null);

        return .{
            .allocation = allocation,
            .image = image,
            .image_view = image_view,
            .extent = extent,
        };
    }

    pub fn deinit(self: *const Image, device: vk.Device, allocator: c.VmaAllocator) void {
        vk.destroyImageView(device, self.image_view, null);
        c.vmaDestroyImage(allocator, vk_interop.imageToC(self.image), self.allocation);
    }
};

pub const Buffer = struct {
    handle: vk.Buffer,
    allocation: c.VmaAllocation,
    info: c.VmaAllocationInfo,

    pub fn init(vma: c.VmaAllocator, size: usize, usage: vk.BufferUsageFlags, mem_usage: c.VmaMemoryUsage) Buffer {
        const buffer_create_info = vk.BufferCreateInfo {
            .sType = .buffer_create_info,
            .size = size,
            .usage = usage
        };

        const allocation_create_info = c.VmaAllocationCreateInfo {
            .usage = mem_usage,
            .flags = c.VMA_ALLOCATION_CREATE_MAPPED_BIT
        };

        const buffer: vk.Buffer = undefined;
        var allocation: c.VmaAllocation = undefined;
        var allocation_info: c.VmaAllocationInfo = undefined;
        vk_interop.vmaCreateBuffer(vma, @ptrCast(&buffer_create_info), &allocation_create_info, @ptrCast(buffer), &allocation, &allocation_info) catch |err| {
            std.log.err("failed to allocate new buffer. error : {any}", .{err});
            return err;
        };

        return .{
            .handle = buffer,
            .allocation = allocation,
            .info = allocation_info
        };
    }

    pub fn deinit(self: *Buffer, vma: c.VmaAllocator) void {
        c.vmaDestroyBuffer(vma, vk_interop.bufferToC(self.handle), self.allocation);
    }
};

const std = @import("std");
const vk = @import("vk");
const c = @import("c");
const vk_interop = @import("vk_interop.zig");
