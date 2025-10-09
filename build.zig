const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // We will also create a module for our other entry point, 'main.zig'.
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "univers_simulation",
        .root_module = exe_mod
    });

    // Vulkan SDK
    const env_map = std.process.getEnvMap(b.allocator) catch {
        @panic("Out of Memory !");
    };
    const vk_sdk_path = env_map.get("VULKAN_SDK") orelse @panic("VULKAN_SDK missing !");

    exe.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/lib", .{ vk_sdk_path }) });
    exe.addIncludePath(.{ .cwd_relative = b.fmt("{s}/include", .{ vk_sdk_path }) });

    const vk_lib_name = if (target.result.os.tag == .windows) "vulkan-1" else "vulkan";
    exe.linkSystemLibrary(vk_lib_name);

    // SDL3
    const sdl = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
        .link_libc = true
    });
    exe.addIncludePath(sdl.path("include"));
    exe.addLibraryPath(sdl.path("lib/x64"));

    exe.linkSystemLibrary("SDL3");

    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.addPathDir(sdl.path("lib/x64").getPath(b));
    run_cmd.step.dependOn(b.getInstallStep());


    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
