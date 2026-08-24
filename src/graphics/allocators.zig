pub const PoolSizeRatio = struct {
    kind: vk.DescriptorType,
    ratio: f16
};

pub const Descriptor = struct {
    allocator: std.mem.Allocator,

    pool_ratios: std.ArrayList(PoolSizeRatio),
    full_pools: std.ArrayList(vk.DescriptorPool),
    ready_pools: std.ArrayList(vk.DescriptorPool),
    sets_per_pool: u32,

    pub fn init(allocator: std.mem.Allocator, device: vk.Device, max_sets: u32, ratios: []const PoolSizeRatio) !Descriptor {
        var pool_ratios = std.ArrayList(PoolSizeRatio).empty;
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
};

fn create_descriptor_pool(allocator: std.mem.Allocator, device: vk.Device, max_sets: u32, pool_ratios: []const PoolSizeRatio) !vk.DescriptorPool {
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