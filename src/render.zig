pub const RenderGraph = struct {
    allocator: std.mem.Allocator,
    
    passes: std.ArrayList(RenderPass),

    images: std.ArrayList(ImageResource), // handle current state
    buffers: std.ArrayList(BufferResource),

    output: ?ImageResource,
    
    pub fn init(allocator: std.mem.Allocator) RenderGraph {
        return .{
            .allocator = allocator,
            .passes = std.ArrayList(RenderPass).empty,
            .images = std.ArrayList(ImageResource).empty,
            .buffers = std.ArrayList(BufferResource).empty,
            .output = null
        };
    }

    pub fn clear(self: *RenderGraph) void {
        self.buffers.clearRetainingCapacity();
        self.images.clearRetainingCapacity();

        for (self.passes.items) |*pass| {
            pass.deinit();
        }

        self.passes.clearRetainingCapacity();
    }

    pub fn deinit(self: *RenderGraph) void {
        self.buffers.deinit(self.allocator);
        self.images.deinit(self.allocator);

        for (self.passes.items) |*pass| {
            pass.deinit();
        }

        self.passes.deinit(self.allocator);
    }

    pub fn addPass(self: *RenderGraph, pass: RenderPass) !void {
        // scan ressources, if not exist, add them
        for (pass.images.items) |res| {
            _ = self.findImage(res.image) catch {
                const current_state: ImageResource = .{
                    .image = res.image,
                    .layout = .@"undefined"
                };

                self.images.append(self.allocator, current_state) catch |err| {
                    std.log.err("failed to add image resource to list. error : {any}", .{err});
                    return err;
                };
            };
        }

        for (pass.buffers.items) |res| {
            _ = self.findBuffer(res.buffer) catch {
                const current_state: BufferResource = .{
                    .buffer = res.buffer,
                    .stage = .{},
                    .access = .{}
                };

                self.buffers.append(self.allocator, current_state) catch |err| {
                    std.log.err("failed to add image resource to list. error : {any}", .{err});
                    return err;
                };
            };
        }

        self.passes.append(self.allocator, pass) catch |err| {
            std.log.err("failed to allocate render pass. error : {any}", .{err});
            return err;
        };
    }

    pub fn setOutput(self: *RenderGraph, image: ImageResource) !void {
        _ = self.findImage(image.image) catch {
            const current_state: ImageResource = .{
                .image = image.image,
                .layout = .@"undefined"
            };

            self.images.append(self.allocator, current_state) catch |err| {
                std.log.err("failed to add image resource to list. error : {any}", .{err});
                return err;
            };
        };

        self.output = image;
    }

    pub fn exec(self: *RenderGraph, cmd: vk.CommandBuffer) void {
        for (self.passes.items) |pass| {
            // image barriers            
            var image_barriers = std.ArrayList(vk.ImageMemoryBarrier2).empty;
            defer image_barriers.deinit(self.allocator);
            
            for (pass.images.items) |res| {
                const current = self.findImage(res.image) catch {
                    std.log.err("image resource not found. This should never happen", .{});
                    continue;
                };

                const src_layout = current.layout;
                const dst_layout = res.layout;

                const aspect_mask: vk.ImageAspectFlags = if (src_layout == .depth_attachment_optimal) .{ .depth_bit = true } else .{ .color_bit = true };

                const image_barrier = vk.ImageMemoryBarrier2 {
		            .sType = .image_memory_barrier_2,

		            .srcStageMask = .{ .all_commands_bit = true },
		            .srcAccessMask = .{ .memory_write_bit = true },
		            .dstStageMask = .{ .all_commands_bit = true },
		            .dstAccessMask = .{ .memory_write_bit = true, .memory_read_bit = true },

		            .oldLayout = src_layout,
		            .newLayout = dst_layout,

		            .image = res.image.image,
		            .subresourceRange = vk.ImageSubresourceRange {
		                .aspectMask = aspect_mask,
		                .baseMipLevel = 0,
		                .levelCount = c.VK_REMAINING_MIP_LEVELS,
		                .baseArrayLayer = 0,
		                .layerCount = c.VK_REMAINING_ARRAY_LAYERS,
	                },
	            };

                image_barriers.append(self.allocator, image_barrier) catch {
                    std.log.err("failed to allocate barrier.", .{});
                    continue;
                };

                current.layout = dst_layout;
            }

            const dep_info = vk.DependencyInfo {
		        .sType = .dependency_info,

		        .imageMemoryBarrierCount = @intCast(image_barriers.items.len),
		        .pImageMemoryBarriers = image_barriers.items.ptr,
	        };

            vk.cmdPipelineBarrier2(cmd, &dep_info);

            // buffer barriers
            var barriers = std.ArrayList(vk.BufferMemoryBarrier2).empty;
            defer barriers.deinit(self.allocator);

            for (pass.buffers.items) |res| {
                const current = self.findBuffer(res.buffer) catch {
                    std.log.err("buffer resource not found. This should never happen", .{});
                    continue;
                };

                const barrier = vk.BufferMemoryBarrier2 {
                    .sType = .buffer_memory_barrier_2,
                    .srcStageMask = current.stage,
                    .srcAccessMask = current.access,
                    
                    .dstStageMask = res.stage,
                    .dstAccessMask = res.access,
                    
                    .srcQueueFamilyIndex = 0,
                    .dstQueueFamilyIndex = 0,
                    
                    .buffer = res.buffer.handle,
                    .offset = 0,
                    .size = vk_whole_size,
                };

                barriers.append(self.allocator, barrier) catch {
                    std.log.err("failed to allocate barrier.", .{});
                    continue;
                };
            }

            const dependency = vk.DependencyInfo {
                .sType = .dependency_info,
                .bufferMemoryBarrierCount = @intCast(barriers.items.len),
                .pBufferMemoryBarriers = barriers.items.ptr,
            };

            vk.cmdPipelineBarrier2(cmd, &dependency);

            pass.exec(cmd);
        }

        if (self.output) |output| {
            const current = self.findImage(output.image) catch {
                std.log.err("image output not found. This should never happen", .{});
                return;
            };

            utils.transition_image_layout(cmd, output.image.image, current.layout, .transfer_src_optimal);
        }
        else {
            std.log.err("no output defined. call setOuput.", .{});
        }
    }

    fn findImage(self: *const RenderGraph, image: *const types.Image) !*ImageResource {
        for (self.images.items) |*i| {
            if (i.image == image) {
                return i;
            }
        }

        return Error.NotFound;
    }

    fn findBuffer(self: *const RenderGraph, buffer: *const types.Buffer) !*BufferResource {
        for (self.buffers.items) |*i| {
            if (i.buffer == buffer) {
                return i;
            }
        }

        return Error.NotFound;
    }

    const Error = error {
        NotFound
    };
};

pub const RenderPass = struct {
    allocator: std.mem.Allocator,
    
    images: std.ArrayList(ImageResource), // handle wanted state
    buffers: std.ArrayList(BufferResource),
    ctx: Context,

    callback: FnRender,

    pub fn init(allocator: std.mem.Allocator, callback: FnRender, ctx: Context) RenderPass {
        return .{
            .allocator = allocator,
            .callback = callback,
            .images = std.ArrayList(ImageResource).empty,
            .buffers = std.ArrayList(BufferResource).empty,
            .ctx = ctx,
        };
    }

    pub fn clear(self: *RenderPass) void {
        self.buffers.clearRetainingCapacity();
        self.images.clearRetainingCapacity();
    }

    pub fn deinit(self: *RenderPass) void {
        self.buffers.deinit(self.allocator);
        self.images.deinit(self.allocator);
    }

    pub fn addBuffer(self: *RenderPass, buffer: BufferResource) !void {
        self.buffers.append(self.allocator, buffer) catch |err| {
            std.log.err("failed to allocate buffer. error : {any}", .{err});
            return err;
        };
    }

    pub fn addImage(self: *RenderPass, image: ImageResource) !void {
        self.images.append(self.allocator, image) catch |err| {
            std.log.err("failed to allocate image buffer. error : {any}", .{err});
            return err;
        };
    }

    pub fn exec(self: *const RenderPass, cmd: vk.CommandBuffer) void {
        self.callback(cmd, &self.ctx);
    }
};

pub const BufferResource = struct {
    buffer: *const types.Buffer,
    stage: vk.PipelineStageFlags2,
    access: vk.AccessFlags2
};

pub const ImageResource = struct {
    image: *const types.Image,
    layout: vk.ImageLayout,
};

pub const Context = struct {
    pipeline: *const shaders.Pipeline,
    descriptor_sets: []const vk.DescriptorSet,
    push_constant: vk.PushConstantsInfo = .{},

    // compute parameters
    dispatch_size: [3]u32,

    // graphics draw parameters
    color_view: vk.ImageView = .null_handle,
    extent: vk.Extent2D = .{ .width = 0, .height = 0 },
    vertex_count: u32 = 0,
    instance_count: u32 = 0
};

pub const FnRender = *const fn(cmd: vk.CommandBuffer, ctx: *const Context) void;

/// Base Resource  for drawing
pub const DrawResource = struct {
    color_image: types.Image,
    depth_image: types.Image,

    pub fn init(vma: c.VmaAllocator, device: vk.Device, width: u32, height: u32) !DrawResource {
        const draw_image_usage: vk.ImageUsageFlags = .{ 
            .transfer_src_bit = true,
            .storage_bit = true,
            .color_attachment_bit = true
        };

        const extent = vk.Extent3D {
            .width = width,
            .height = height,
            .depth = 1
        };
        const draw_image = types.Image.init(vma, device, .r16g16b16a16_sfloat, extent, draw_image_usage, .{ .color_bit = true }) catch |err| {
            std.log.err("failed to create draw image", .{});
            return err;
        };
        errdefer draw_image.deinit(device, vma);

        const depth_image = types.Image.init(vma, device, .d32_sfloat, extent, .{ .depth_stencil_attachment_bit = true }, .{ .depth_bit = true }) catch |err| {
            std.log.err("failed to create depth image", .{});
            return err;
        };
        errdefer depth_image.deinit(device, vma);

        return .{
            .color_image = draw_image,
            .depth_image = depth_image
        };
    }

    pub fn deinit(self: *DrawResource, vma: c.VmaAllocator, device: vk.Device) void {
        self.color_image.deinit(device, vma);
        self.depth_image.deinit(device, vma);
    }
};

const vk_whole_size: u64 = ~@as(u64, 0);

const std = @import("std");
const c = @import("c");
const vk = @import("vk");
const types = @import("graphics/types.zig");
const shaders = @import("graphics/shaders.zig");
const utils = @import("graphics/utils.zig");
