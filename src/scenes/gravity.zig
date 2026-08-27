pub const GravityScene = struct {
    allocator: std.mem.Allocator,
    state: State,

    render_graph: render.RenderGraph,
    
    compute_gravity: shaders.Pipeline,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, device: vk.Device) !GravityScene {
        const render_graph = render.RenderGraph.init(allocator);

        const initial_state = State {
            .object = .{
                .pos = @splat(0)
            }
        };

        // create layouts
        var layout_builder = descriptors.LayoutBuilder.init(allocator);
        defer layout_builder.deinit();

        const shader_stages: vk.ShaderStageFlags = .{
            .compute_bit = true
        };
        try layout_builder.addBinding(0, .storage_buffer, shader_stages);

        const descriptor_set_layouts = try allocator.alloc(vk.DescriptorSetLayout, 1);
        errdefer allocator.free(descriptor_set_layouts);

        descriptor_set_layouts[0] = try layout_builder.build(device, .{});
        errdefer vk.destroyDescriptorSetLayout(device, descriptor_set_layouts[0], null);

        // create pipelines
        const exe_dir = try std.process.executableDirPathAlloc(io, allocator);
        defer allocator.free(exe_dir);

        const shader_path = try std.fmt.allocPrint(allocator, "{s}/shaders/gravity.spirv", .{ exe_dir });
        defer allocator.free(shader_path);

        const shader_module = try shaders.load_shader_module(io, allocator, shader_path, device);
        defer vk.destroyShaderModule(device, shader_module, null);

        var compute_gravity = try shaders.Pipeline.init(device, descriptor_set_layouts);
        try compute_gravity.buildCompute(device, shader_module);

        // allocate buffer for object
        
        return .{
            .allocator = allocator,
            .render_graph = render_graph,
            .state = initial_state,
            .compute_gravity = compute_gravity
        };
    }

    pub fn deinit(self: *GravityScene) void {
        self.render_graph.deinit();
        self.compute_gravity.deinit(self.allocator);
    }

    const State = struct {
        object: Object
    };
};

const Object = struct {
    pos: @Vector(2, f32)
};

const std = @import("std");
const vk = @import("vk");
const render = @import("../render.zig");
const shaders = @import("../graphics/shaders.zig");
const descriptors = @import("../graphics/descriptors.zig");
