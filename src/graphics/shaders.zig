const std = @import("std");
const vk = @import("vk");

pub const Pipeline = struct {
    device: vk.Device,
    handle: vk.Pipeline,
    layout: vk.PipelineLayout,

    pub fn init(device: vk.Device, layout_info: vk.PipelineLayoutCreateInfo, module: vk.ShaderModule) !Pipeline {        
        var layout: vk.PipelineLayout = undefined;
        vk.createPipelineLayout(device, &layout_info, null, &layout) catch |err| {
            std.log.err("failed to create pipeline layout. error : {any}", .{ err });
            return err;
        };
        errdefer vk.destroyPipelineLayout(device, layout, null);

        const stage_info = vk.PipelineShaderStageCreateInfo {
            .sType = .pipeline_shader_stage_create_info,
            .module = module,
            .pName = "main",
            .stage = .{ .compute_bit = true },
        };

        const create_pipeline_info = vk.ComputePipelineCreateInfo {
            .sType = .compute_pipeline_create_info,
            .layout = layout,
            .stage = stage_info,
        };

        var pipeline: vk.Pipeline = undefined;
        vk.createComputePipelines(device, .null_handle, 1, &create_pipeline_info, null, &pipeline) catch |err| {
            std.log.err("failed to create pipeline. error : {any}", .{err});
            return err;
        }; 

        return .{
            .device = device,
            .layout = layout,
            .handle = pipeline
        };
    }

    pub fn deinit(self: *Pipeline) void {
        vk.destroyPipeline(self.device, self.handle, null);
        vk.destroyPipelineLayout(self.device, self.layout, null);
    }
};

pub fn load_shader_module(io: std.Io, allocator: std.mem.Allocator, path: []const u8, device: vk.Device) !vk.ShaderModule {
    const buffer = std.Io.Dir.readFileAlloc(std.Io.Dir.cwd(), io, path, allocator, .unlimited) catch |err| {
        std.log.err("failed to read shader file. error : {any}", .{err});
        return Error.LoadFailed;
    };
    defer allocator.free(buffer);

    const create_info = vk.ShaderModuleCreateInfo {
        .sType = .shader_module_create_info,
        .codeSize = buffer.len,
        .pCode = @alignCast(@ptrCast(buffer.ptr)),
    };
    
    var shader_module: vk.ShaderModule = undefined;
    vk.createShaderModule(device, &create_info, null, &shader_module) catch |err| {
        std.log.err("failed to create shader module. error : {any}", .{ err });
        return Error.LoadFailed;
    };

    return shader_module;
}

pub const Error = error {
    LoadFailed
};
