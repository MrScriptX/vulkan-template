pub const PoolSizeRatio = struct {
    kind: vk.DescriptorType,
    ratio: f16
};

pub const LayoutBuilder = struct {
    allocator: std.mem.Allocator,
    bindings: std.ArrayList(vk.DescriptorSetLayoutBinding),

    pub fn init(allocator: std.mem.Allocator) LayoutBuilder {
        return .{
            .allocator = allocator,
            .bindings = std.ArrayList(vk.DescriptorSetLayoutBinding).empty
        };
    }

    pub fn deinit(self: *LayoutBuilder) void {
        self.bindings.deinit(self.allocator);
    }

    pub fn addBinding(self: *LayoutBuilder, binding: u32, descriptor: vk.DescriptorType, stages: vk.ShaderStageFlags) !void {
        const layout_binding = vk.DescriptorSetLayoutBinding {
            .binding = binding,
            .descriptorType = descriptor,
            .descriptorCount = 1,
            .stageFlags = stages
        };

        self.bindings.append(self.allocator, layout_binding) catch |err| {
            std.log.err("failed to add binding. error : {any}", .{err});
            return err;
        };
    }

    pub fn build(self: *LayoutBuilder, device: vk.Device, flags: vk.DescriptorSetLayoutCreateFlags) !vk.DescriptorSetLayout {        
        const create_set_layout_info = vk.DescriptorSetLayoutCreateInfo {
            .sType = vk.StructureType.descriptor_set_layout_create_info,
            .flags = flags,
            .bindingCount = @intCast(self.bindings.items.len),
            .pBindings = self.bindings.items.ptr
        };

        var descriptor_set_layout: vk.DescriptorSetLayout = undefined;
        vk.createDescriptorSetLayout(device, &create_set_layout_info, null, &descriptor_set_layout) catch |err| {
            std.log.err("failed to create descriptor set layout. error : {any}", .{ err });
            return err;
        };

        return descriptor_set_layout;
    }
};

/// Writer can be probably improve to batch even more writes
/// Example would be to use a struct to store info for WriteDescriptorSet
/// along side DescriptorImageInfo.
pub const Writer = struct {
    allocator: std.mem.Allocator,

    writes: std.ArrayList(vk.WriteDescriptorSet),
    images_info: std.ArrayList(*vk.DescriptorImageInfo),

    pub fn init(allocator: std.mem.Allocator) Writer {
        return .{
            .allocator = allocator,
            .writes = std.ArrayList(vk.WriteDescriptorSet).empty,
            .images_info = std.ArrayList(*vk.DescriptorImageInfo).empty
        };
    }

    pub fn deinit(self: *Writer) void {
        for (self.images_info.items) |info| {
            self.allocator.destroy(info);
        }
        self.images_info.deinit(self.allocator);

        self.writes.deinit(self.allocator);
    }

    pub fn clear(self: *Writer) void {
        for (self.images_info.items) |info| {
            self.allocator.free(info);
        }
        self.images_info.clearRetainingCapacity();
    }

    pub fn addImage(self: *Writer, binding: u32, image_view: vk.ImageView, sampler: vk.Sampler, image_layout: vk.ImageLayout, kind: vk.DescriptorType) !void {
        const image_descriptor_info = self.allocator.create(vk.DescriptorImageInfo) catch |err| {
            std.log.err("failed to allocate DescriptorImageInfo. error : {any}", .{ err });
            return err;
        };

        image_descriptor_info.* = vk.DescriptorImageInfo {
            .sampler = sampler,
            .imageView = image_view,
            .imageLayout = image_layout
        };

        self.images_info.append(self.allocator, image_descriptor_info) catch |err| {
            std.log.err("failed to append descriptor image. error : {any}", .{ err });
            return err;
        };

        const image_write = vk.WriteDescriptorSet {
            .sType = .write_descriptor_set,
            .pImageInfo = image_descriptor_info,
            .dstBinding = binding,
            .descriptorCount = 1,
            .descriptorType = kind,
        };

        self.writes.append(self.allocator, image_write) catch |err| {
            std.log.err("failed to append descriptor set write. error : {any}", .{ err });
            return err;
        };
    }

    pub fn write(self: *Writer, device: vk.Device, set: vk.DescriptorSet) void {
        for (self.writes.items) |*w| {
            w.dstSet = set;
        }

        vk.updateDescriptorSets(device, @intCast(self.writes.items.len), self.writes.items.ptr, 0, null);
    }
};

const std = @import("std");
const vk = @import("vk");