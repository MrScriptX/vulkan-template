pub const RenderGraph = struct {
    allocator: std.mem.Allocator,
    
    passes: std.ArrayList(RenderPass),

    images: std.ArrayList(ImageResource), // handle current state
    
    pub fn init(allocator: std.mem.Allocator) RenderGraph {
        return .{
            .allocator = allocator,
            .passes = std.ArrayList(RenderPass).empty,
            .images = std.ArrayList(ImageResource).empty
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
            }

            pass.exec(cmd);
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
    
    images: std.ArrayList(ImageResource), // handle to state, current state is given by render graph
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

const std = @import("std");
const vk = @import("vk");
const types = @import("graphics/types.zig");
const shaders = @import("graphics/shaders.zig");
const utils = @import("graphics/utils.zig");
