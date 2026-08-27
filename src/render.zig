pub const RenderGraph = struct {
    allocator: std.mem.Allocator,
    
    passes: std.ArrayList(RenderPass),

    images: std.ArrayList(ImageResource), // handle current state
    output: ?ImageResource,
    
    pub fn init(allocator: std.mem.Allocator) RenderGraph {
        return .{
            .allocator = allocator,
            .passes = std.ArrayList(RenderPass).empty,
            .images = std.ArrayList(ImageResource).empty,
            .output = null
        };
    }

    pub fn clear(self: *RenderGraph) void {
        self.images.clearRetainingCapacity();

        for (self.passes.items) |*pass| {
            pass.deinit();
        }

        self.passes.clearRetainingCapacity();
    }

    pub fn deinit(self: *RenderGraph) void {
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
            for (pass.images.items) |res| {
                const current = self.findImage(res.image) catch {
                    std.log.err("image resource not found. This should never happen", .{});
                    continue;
                };

                const src_layout = current.layout;
                const dst_layout = res.layout;

                utils.transition_image_layout(cmd, res.image.image, src_layout, dst_layout);

                current.layout = dst_layout;
            }

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

    const Error = error {
        NotFound
    };
};

pub const RenderPass = struct {
    allocator: std.mem.Allocator,
    
    images: std.ArrayList(ImageResource), // handle wanted state
    ctx: Context,

    callback: FnRender,

    pub fn init(allocator: std.mem.Allocator, callback: FnRender, ctx: Context) RenderPass {
        return .{
            .allocator = allocator,
            .callback = callback,
            .images = std.ArrayList(ImageResource).empty,
            .ctx = ctx,
        };
    }

    pub fn clear(self: *RenderPass) void {
        self.images.clearRetainingCapacity();
    }

    pub fn deinit(self: *RenderPass) void {
        self.images.deinit(self.allocator);
    }

    pub fn addImageBuffer(self: *RenderPass, image: ImageResource) !void {
        self.images.append(self.allocator, image) catch |err| {
            std.log.err("failed to allocate image buffer. error : {any}", .{err});
            return err;
        };
    }

    pub fn exec(self: *const RenderPass, cmd: vk.CommandBuffer) void {
        self.callback(cmd, &self.ctx);
    }
};

pub const ImageResource = struct {
    image: *const types.Image,
    layout: vk.ImageLayout,
};

pub const Context = struct {
    pipeline: *const shaders.Pipeline,
    descriptor_sets: []vk.DescriptorSet,
    dispatch_size: [3]u32,
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

const std = @import("std");
const c = @import("c");
const vk = @import("vk");
const types = @import("graphics/types.zig");
const shaders = @import("graphics/shaders.zig");
const utils = @import("graphics/utils.zig");
