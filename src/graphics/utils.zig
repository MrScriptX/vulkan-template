pub fn transition_image_layout(cmd: vk.CommandBuffer, image: vk.Image, current_layout: vk.ImageLayout, new_layout: vk.ImageLayout) void {
    const aspect_mask: vk.ImageAspectFlags = if (new_layout == .depth_attachment_optimal) .{ .depth_bit = true } else .{ .color_bit = true };

	const image_barrier = vk.ImageMemoryBarrier2 {
		.sType = .image_memory_barrier_2,

		.srcStageMask = .{ .all_commands_bit = true },
		.srcAccessMask = .{ .memory_write_bit = true },
		.dstStageMask = .{ .all_commands_bit = true },
		.dstAccessMask = .{ .memory_write_bit = true, .memory_read_bit = true },

		.oldLayout = current_layout,
		.newLayout = new_layout,

		.image = image,
		.subresourceRange = vk.ImageSubresourceRange {
		    .aspectMask = aspect_mask,
		    .baseMipLevel = 0,
		    .levelCount = c.VK_REMAINING_MIP_LEVELS,
		    .baseArrayLayer = 0,
		    .layerCount = c.VK_REMAINING_ARRAY_LAYERS,
	    },
	};

	const dep_info = vk.DependencyInfo {
		.sType = .dependency_info,

		.imageMemoryBarrierCount = 1,
		.pImageMemoryBarriers = &image_barrier,
	};

    vk.cmdPipelineBarrier2(cmd, &dep_info);
}

pub fn upload_data(comptime T: type, vma: c.VmaAllocator, allocation: c.VmaAllocation, data: *const T) !void {
	var ptr: *T = undefined;
    vk_interop.vmaMapMemory(vma, allocation, @ptrCast(&ptr)) catch |err| {
		std.log.err("failed to map memory. error : {any}", .{err});
		return err;
	};
    ptr.* = data.*;
    c.vmaUnmapMemory(vma, allocation);
}

pub fn upload_data_array(comptime T: type, vma: c.VmaAllocator, allocation: c.VmaAllocation, data: []const T) !void {
	var ptr: []T = undefined;
    vk_interop.vmaMapMemory(vma, allocation, @ptrCast(&ptr)) catch |err| {
		std.log.err("failed to map memory. error : {any}", .{err});
		return err;
	};
	@memcpy(ptr[0..data.len], data);
    c.vmaUnmapMemory(vma, allocation);
}

const std = @import("std");
const c = @import("c");
const vk = @import("vk");
const vk_interop = @import("vk_interop.zig");
