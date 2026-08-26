pub const RenderGraph = struct {
    allocator: std.mem.Allocator,
    passes: std.ArrayList(RenderPass),
    
    pub fn init(allocator: std.mem.Allocator) RenderGraph {
        return .{
            .allocator = allocator,
            .passes = std.ArrayList(RenderPass).empty
        };
    }

    pub fn clear(self: *RenderGraph) void {
        for (self.passes.items) |*pass| {
            pass.deinit();
        }

        self.passes.clearRetainingCapacity();
    }

    pub fn deinit(self: *RenderGraph) void {
        for (self.passes.items) |*pass| {
            pass.deinit();
        }

        self.passes.deinit(self.allocator);
    }

    pub fn addPass(self: *RenderGraph, pass: RenderPass) !void {
        self.passes.append(self.allocator, pass) catch |err| {
            std.log.err("failed to allocate render pass. error : {any}", .{err});
            return err;
        };
    }

    pub fn exec(self: *RenderGraph, cmd: vk.CommandBuffer) void {
        for (self.passes.items) |pass| {
            pass.exec(cmd);
        }
    }
};

pub const RenderPass = struct {
    allocator: std.mem.Allocator,
    
    images: std.ArrayList(ImageResource),
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
    current_layout: vk.ImageLayout,
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
