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
        self.passes.clearRetainingCapacity();
    }

    pub fn deinit(self: *RenderGraph) void {
        self.passes.deinit(self.allocator);
    }

    pub fn addPass(self: *RenderGraph, pass: RenderPass) !void {
        self.passes.append(self.allocator, pass) catch |err| {
            std.log.err("failed to allocate render pass. error : {any}", .{err});
            return err;
        };
    }

    pub fn exec(self: *RenderGraph, cmd: vk.CommandBuffer, ctx: *const Context) void {
        for (self.passes.items) |pass| {
            pass.exec(cmd, ctx);
        }
    }
};

pub const RenderPass = struct {
    allocator: std.mem.Allocator,
    images: std.ArrayList(ImageRessource),
    callback: FnRender,

    pub fn init(allocator: std.mem.Allocator, callback: FnRender) RenderPass {
        return .{
            .allocator = allocator,
            .callback = callback,
            .images = std.ArrayList(ImageRessource).empty
        };
    }

    pub fn clear(self: *RenderPass) void {
        self.images.clearRetainingCapacity();
    }

    pub fn deinit(self: *RenderPass) void {
        self.images.deinit(self.allocator);
    }

    pub fn addImageBuffer(self: *RenderPass, image: ImageRessource) !void {
        self.images.append(self.allocator, image) catch |err| {
            std.log.err("failed to allocate image buffer. error : {any}", .{err});
            return err;
        };
    }

    pub fn exec(self: *const RenderPass, cmd: vk.CommandBuffer, ctx: *const Context) void {
        self.callback(cmd, ctx);
    }
};

pub const ImageRessource = struct {
    image: *const types.Image,
    current_layout: vk.ImageLayout,
};

pub const Context = struct {

};

const FnRender = *const fn(cmd: vk.CommandBuffer, ctx: *const Context) void;

const std = @import("std");
const vk = @import("vk");
const types = @import("graphics/types.zig");
