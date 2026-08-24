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

const std = @import("std");
const vk = @import("vk");