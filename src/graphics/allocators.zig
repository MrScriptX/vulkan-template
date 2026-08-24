pub const Descriptor = struct {
    allocator: std.mem.Allocator,
    device: vk.Device,

    pool_ratios: std.ArrayList(descriptors.PoolSizeRatio),
    full_pools: std.ArrayList(vk.DescriptorPool),
    ready_pools: std.ArrayList(vk.DescriptorPool),
    sets_per_pool: u32,

    pub fn init(allocator: std.mem.Allocator, device: vk.Device, max_sets: u32, ratios: []const descriptors.PoolSizeRatio) !Descriptor {
        var pool_ratios = std.ArrayList(descriptors.PoolSizeRatio).empty;
        pool_ratios.appendSlice(allocator, ratios) catch |err| {
            std.log.err("failed to allocate pool ratios. error : {any}", .{err});
            return err;
        };

        const pool = try create_descriptor_pool(allocator, device, max_sets, ratios);
        var ready_pools = std.ArrayList(vk.DescriptorPool).empty;
        ready_pools.append(allocator, pool) catch |err| {
            std.log.err("failed to insert new pool in ready pool. error : {any}", .{err});
            return err;
        };

        const sets_per_pool: u32 = @intFromFloat(@as(f32, @floatFromInt(max_sets)) * 1.5);

        return .{
            .allocator = allocator,
            .device = device,
            .full_pools = std.ArrayList(vk.DescriptorPool).empty,
            .ready_pools = ready_pools,
            .pool_ratios = pool_ratios,
            .sets_per_pool = sets_per_pool
        };
    }

    pub fn deinit(self: *Descriptor, device: vk.Device) void {
        for (self.ready_pools.items) |pool| {
            vk.destroyDescriptorPool(device, pool, null);
        }
        self.ready_pools.deinit(self.allocator);

        for (self.full_pools.items) |pool| {
            vk.destroyDescriptorPool(device, pool, null);
        }
        self.full_pools.deinit(self.allocator);

        self.pool_ratios.deinit(self.allocator);
    }

    pub fn getOrCreate(self: *Descriptor) !vk.DescriptorPool {
        const pool = self.ready_pools.pop();
        if (pool) |p| {
            return p;
        }

        const new_pool = create_descriptor_pool(self.allocator, self.device, self.sets_per_pool, self.pool_ratios.items) catch |err| {
            std.log.err("failed to create new descriptor pool. error : {any}", .{ err });
            return err;
        };

        self.sets_per_pool = @intFromFloat(@as(f32, @floatFromInt(self.sets_per_pool)) * 1.5);
        if (self.sets_per_pool > 4092) {
            self.sets_per_pool = 4092;
        }

        return new_pool;
    }

    pub fn allocate(self: *Descriptor, layout: vk.DescriptorSetLayout) !vk.DescriptorSet {
        const pool = self.getOrCreate() catch |err| {
            std.log.err("failed to fetch a descriptor pool. error : {any}", .{ err });
            return err;
        };

        const create_set_info = vk.DescriptorSetAllocateInfo {
            .sType = vk.StructureType.descriptor_set_allocate_info,
            .descriptorPool = pool,
            .descriptorSetCount = 1,
            .pSetLayouts = &layout
        };

        var descriptor_set: vk.DescriptorSet = undefined;
        vk.allocateDescriptorSets(self.device, &create_set_info, &descriptor_set) catch |err| {
            std.log.err("failed to allocate descriptor sets. error : {any}", .{ err });
            return err;
        };

        return descriptor_set;
    }
};

fn create_descriptor_pool(allocator: std.mem.Allocator, device: vk.Device, max_sets: u32, pool_ratios: []const descriptors.PoolSizeRatio) !vk.DescriptorPool {
    var pool_sizes = std.ArrayList(vk.DescriptorPoolSize).empty;
    defer pool_sizes.deinit(allocator);

    for (pool_ratios) |ratio| {
        const pool_size = vk.DescriptorPoolSize {
            .@"type" = ratio.kind,
            .descriptorCount =  @intFromFloat(ratio.ratio * @as(f32, @floatFromInt(max_sets)))
        };
        pool_sizes.append(allocator, pool_size) catch |err| {
            std.log.err("failed to allocate pool size. error : {any}", .{err});
            return err;
        };
    }
    
    const create_pool_info = vk.DescriptorPoolCreateInfo {
        .sType = vk.StructureType.descriptor_pool_create_info,
        .maxSets = max_sets,
        .poolSizeCount = @intCast(pool_sizes.items.len),
        .pPoolSizes = pool_sizes.items.ptr
    };
        
    var pool: vk.DescriptorPool = undefined;
    vk.createDescriptorPool(device, &create_pool_info, null, &pool) catch |err| {
        std.log.err("failed to create descriptor pool. error : {any}", .{err});
        return err;
    };

    return pool;
}

const std = @import("std");
const vk = @import("vk");
const descriptors = @import("descriptors.zig");